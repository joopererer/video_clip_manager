import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'ai_failure.dart';

/// 视频关键帧嵌入记录（绝对时间戳锚定）
class VideoFrameEmbeddingRecord {
  /// 绝对时间戳（毫秒，相对于母视频开始时刻 0ms）
  final int tMs;

  /// Embedding 向量 (例如 EmbeddingGemma 2 的 768 或 256 维)
  final List<double> vector;

  /// 对应抽出的关键帧图片路径（可选）
  final String? frameImagePath;

  /// 记录创建时间戳
  final int createdAtMs;

  const VideoFrameEmbeddingRecord({
    required this.tMs,
    required this.vector,
    this.frameImagePath,
    required this.createdAtMs,
  });

  /// 余弦相似度计算
  double cosineSimilarity(List<double> other) {
    if (vector.isEmpty || other.isEmpty || vector.length != other.length) {
      return 0.0;
    }
    double dot = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    for (int i = 0; i < vector.length; i++) {
      final a = vector[i];
      final b = other[i];
      dot += a * b;
      normA += a * a;
      normB += b * b;
    }
    if (normA <= 0.0 || normB <= 0.0) return 0.0;
    return dot / (sqrt(normA) * sqrt(normB));
  }

  Map<String, dynamic> toJson() => {
    't_ms': tMs,
    'vector': vector,
    'frame_image_path': frameImagePath,
    'created_at_ms': createdAtMs,
  };

  factory VideoFrameEmbeddingRecord.fromJson(Map<String, dynamic> json) {
    final rawVec = (json['vector'] as List<dynamic>?) ?? [];
    return VideoFrameEmbeddingRecord(
      tMs: json['t_ms'] as int? ?? 0,
      vector: rawVec.map((v) => (v as num).toDouble()).toList(),
      frameImagePath: json['frame_image_path'] as String?,
      createdAtMs: json['created_at_ms'] as int? ?? 0,
    );
  }
}

/// 母视频级别的帧嵌入池 (Frame Embedding Pool)
/// 保证视频帧按母视频绝对时间轴组织与缓存，Clip 切分与调整仅作为区间检索
class FrameEmbeddingPool {
  /// 内存中缓存：videoKey -> (tMs -> Record)
  final Map<String, Map<int, VideoFrameEmbeddingRecord>> _pool = {};

  /// 计算视频唯一标识（MD5）
  String computeVideoKey(String videoPathOrUrl) {
    final normalized = videoPathOrUrl.trim().replaceAll(r'\', '/');
    return md5.convert(utf8.encode(normalized)).toString();
  }

  /// 获取存储目录
  Future<Directory> _getStorageDir({String? customDir}) async {
    if (customDir != null && customDir.isNotEmpty) {
      final dir = Directory(customDir);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return dir;
    }
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(appDir.path, 'frame_embeddings'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// 获取视频缓存文件
  Future<File> _getFile(String videoPathOrUrl, {String? customDir}) async {
    final dir = await _getStorageDir(customDir: customDir);
    final key = computeVideoKey(videoPathOrUrl);
    return File(p.join(dir.path, '$key.json'));
  }

  /// 从磁盘加载缓存
  Future<int> loadFromDisk(
    String videoPathOrUrl, {
    String? customStorageDir,
  }) async {
    try {
      final file = await _getFile(videoPathOrUrl, customDir: customStorageDir);
      if (!await file.exists()) return 0;

      final content = await file.readAsString();
      if (content.isEmpty) return 0;

      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('cache root is not a JSON object');
      }
      final rawFrames = decoded['frames'];
      if (rawFrames != null && rawFrames is! List) {
        throw const FormatException('"frames" is not a list');
      }
      final framesJson = (rawFrames as List<dynamic>?) ?? [];

      final key = computeVideoKey(videoPathOrUrl);
      _unreadable.remove(key);
      final map = _pool.putIfAbsent(key, () => {});

      int count = 0;
      for (final item in framesJson) {
        if (item is Map<String, dynamic>) {
          final record = VideoFrameEmbeddingRecord.fromJson(item);
          map[record.tMs] = record;
          count++;
        }
      }
      return count;
    } on FormatException catch (e) {
      // Unreadable JSON: keep the file for inspection instead of letting the
      // next save silently replace whatever was recoverable in it.
      debugPrint('[FrameEmbeddingPool] cache file is not valid JSON: $e');
      await _quarantine(videoPathOrUrl, customDir: customStorageDir);
      return 0;
    } catch (e) {
      // The file may exist but could not be read (locked, I/O error). Mark it
      // so saveToDisk does not replace it with a partial in-memory view.
      debugPrint('[FrameEmbeddingPool] loadFromDisk error: $e');
      _unreadable.add(computeVideoKey(videoPathOrUrl));
      return 0;
    }
  }

  /// Videos whose cache file exists but could not be read this session.
  final Set<String> _unreadable = {};

  Future<void> _quarantine(String videoPathOrUrl, {String? customDir}) async {
    try {
      final file = await _getFile(videoPathOrUrl, customDir: customDir);
      if (!await file.exists()) return;
      final stamp = DateTime.now().millisecondsSinceEpoch;
      await file.rename('${file.path}.corrupt-$stamp');
    } catch (e) {
      debugPrint('[FrameEmbeddingPool] could not set aside bad cache: $e');
    }
  }

  /// 保存当前视频的所有帧嵌入到磁盘。
  ///
  /// Writes `<key>.json.tmp` and renames it over the cache, so an interrupted
  /// or failed write leaves the previous cache intact. Throws
  /// [AiStageException] (stage `storage`) when the write fails, instead of the
  /// earlier silent swallow that made lost caches invisible.
  Future<void> saveToDisk(
    String videoPathOrUrl, {
    String? customStorageDir,
  }) async {
    final key = computeVideoKey(videoPathOrUrl);
    final map = _pool[key];
    if (map == null || map.isEmpty) return;

    if (_unreadable.contains(key)) {
      throw AiStageException(
        stage: AiStage.storage,
        kind: AiFailureKind.storageFailed,
        message:
            '该视频已有的向量缓存无法读取，为避免覆盖已有数据，本次不写入。'
            '请关闭占用该文件的程序后重试。',
        videoPath: videoPathOrUrl,
      );
    }

    File? tmp;
    try {
      final file = await _getFile(videoPathOrUrl, customDir: customStorageDir);
      final list = map.values.toList()..sort((a, b) => a.tMs.compareTo(b.tMs));

      final data = {
        'video_path_or_url': videoPathOrUrl,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'frames': list.map((r) => r.toJson()).toList(),
      };

      tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(data), flush: true);
      await tmp.rename(file.path);
    } on FileSystemException catch (e) {
      try {
        if (tmp != null && await tmp.exists()) await tmp.delete();
      } catch (_) {}
      throw AiStageException(
        stage: AiStage.storage,
        kind: AiFailureKind.storageFailed,
        message: describeAiFailure(
          AiStage.storage,
          AiFailureKind.storageFailed,
        ),
        detail: tailForLog(
          '${e.message} | ${e.osError?.message ?? ''} '
          '(errno ${e.osError?.errorCode}) | ${e.path ?? ''}',
        ),
        videoPath: videoPathOrUrl,
      );
    }
  }

  /// 获取指定时间范围 [startMs, endMs] 内的所有已缓存帧记录
  List<VideoFrameEmbeddingRecord> getFramesInRange(
    String videoPathOrUrl,
    int startMs,
    int endMs,
  ) {
    final key = computeVideoKey(videoPathOrUrl);
    final map = _pool[key];
    if (map == null || map.isEmpty) return const [];

    final result = <VideoFrameEmbeddingRecord>[];
    for (final record in map.values) {
      if (record.tMs >= startMs && record.tMs <= endMs) {
        result.add(record);
      }
    }
    result.sort((a, b) => a.tMs.compareTo(b.tMs));
    return result;
  }

  /// 获取该视频目前在内存中已有的所有时间戳集合
  Set<int> getCachedTimestamps(String videoPathOrUrl) {
    final key = computeVideoKey(videoPathOrUrl);
    final map = _pool[key];
    if (map == null) return const {};
    return map.keys.toSet();
  }

  /// 插入或合并新的帧记录
  void putFrames(
    String videoPathOrUrl,
    List<VideoFrameEmbeddingRecord> frames,
  ) {
    final key = computeVideoKey(videoPathOrUrl);
    final map = _pool.putIfAbsent(key, () => {});
    for (final frame in frames) {
      map[frame.tMs] = frame;
    }
  }

  /// 清空内存缓存
  void clearMemoryCache({String? videoPathOrUrl}) {
    if (videoPathOrUrl != null) {
      final key = computeVideoKey(videoPathOrUrl);
      _pool.remove(key);
    } else {
      _pool.clear();
    }
  }
}
