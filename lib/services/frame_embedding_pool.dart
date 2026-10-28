import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

      final json = jsonDecode(content) as Map<String, dynamic>;
      final framesJson = (json['frames'] as List<dynamic>?) ?? [];

      final key = computeVideoKey(videoPathOrUrl);
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
    } catch (e) {
      debugPrint('[FrameEmbeddingPool] loadFromDisk error: ');
      return 0;
    }
  }

  /// 保存当前视频的所有帧嵌入到磁盘
  Future<void> saveToDisk(
    String videoPathOrUrl, {
    String? customStorageDir,
  }) async {
    try {
      final key = computeVideoKey(videoPathOrUrl);
      final map = _pool[key];
      if (map == null || map.isEmpty) return;

      final file = await _getFile(videoPathOrUrl, customDir: customStorageDir);
      final list = map.values.toList()..sort((a, b) => a.tMs.compareTo(b.tMs));

      final data = {
        'video_path_or_url': videoPathOrUrl,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'frames': list.map((r) => r.toJson()).toList(),
      };

      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('[FrameEmbeddingPool] saveToDisk error: ');
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
