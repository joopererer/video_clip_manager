import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import '../data/models.dart';
import 'thumbnail_service.dart';
import 'video_metadata_cache.dart';
import 'path_service.dart';

class VideoMetadataService {
  final ThumbnailService _thumbnailService;
  final VideoMetadataCache _cache = VideoMetadataCache();

  VideoMetadataService({required ThumbnailService thumbnailService})
    : _thumbnailService = thumbnailService;

  /// 后台处理单个视频的元数据
  static Future<VideoMetadataResult> _processVideoMetadataInBackground(
    VideoMetadataTask task,
  ) async {
    // 创建一个临时的PathService用于后台处理
    final pathService = PathService();
    await pathService.init();
    final service = VideoMetadataService(
      thumbnailService: ThumbnailService(pathService: pathService),
    );
    
    try {
      debugPrint('VideoMetadataService: Background processing ${task.videoPath}');
      
      // 获取元数据
      final metadata = await service._getVideoMetadataInternal(task.videoPath);
      
      // 生成缩略图
      String? thumbnailPath;
      if (metadata.duration != null) {
        thumbnailPath = await service._generateVideoThumbnailInternal(
          task.videoPath,
          task.videoId,
          metadata.duration!,
        );
      }
      
      return VideoMetadataResult(
        videoId: task.videoId,
        success: true,
        duration: metadata.duration,
        thumbnailPath: thumbnailPath,
        error: null,
      );
    } catch (e) {
      debugPrint('VideoMetadataService: Background processing failed for ${task.videoPath}: $e');
      return VideoMetadataResult(
        videoId: task.videoId,
        success: false,
        duration: null,
        thumbnailPath: null,
        error: e.toString(),
      );
    }
  }

  /// 获取视频的完整元数据（内部方法，不包含缓存逻辑）
  Future<VideoMetadata> _getVideoMetadataInternal(String videoPath) async {
    Player? player;
    try {
      debugPrint('VideoMetadataService: Getting metadata for $videoPath');

      // 检查文件是否存在
      final file = File(videoPath);
      if (!await file.exists()) {
        debugPrint('VideoMetadataService: File does not exist: $videoPath');
        return VideoMetadata(duration: null, metadata: {});
      }

      // 检查文件扩展名，对AVI文件使用不同的处理策略
      final isAviFile = videoPath.toLowerCase().endsWith('.avi');
      
      if (isAviFile) {
        debugPrint('VideoMetadataService: AVI file detected, using fallback strategy');
        return await _getMetadataForAviFile(videoPath);
      }

      // 为每个操作创建独立的播放器实例
      player = Player();
      final media = Media(videoPath);
      debugPrint('VideoMetadataService: Opening media for $videoPath');
      await player.open(media, play: false)
          .timeout(const Duration(seconds: 10), onTimeout: () {
        throw Exception('Timeout opening video');
      });

      // 等待播放器准备好
      debugPrint('VideoMetadataService: Waiting for player to be ready...');
      await player.stream.buffer.firstWhere((e) => e > Duration.zero)
          .timeout(const Duration(seconds: 15), onTimeout: () {
        throw Exception('Timeout waiting for video buffer');
      });
      await Future.delayed(const Duration(milliseconds: 200));

      final duration = player.state.duration;
      debugPrint(
        'VideoMetadataService: Got duration: $duration for $videoPath',
      );

      await player.stop();
      debugPrint('VideoMetadataService: Player stopped for $videoPath');

      return VideoMetadata(
        duration: duration,
        metadata: {}, // 暂时跳过元数据提取，只获取时长
      );
    } catch (e) {
      debugPrint('Error getting video metadata for $videoPath: $e');
      debugPrint('Error stack trace: ${StackTrace.current}');
      return VideoMetadata(duration: null, metadata: {});
    } finally {
      // 确保播放器被正确释放
      if (player != null) {
        try {
          await player.stop();
          player.dispose();
          debugPrint('VideoMetadataService: Player disposed for $videoPath');
        } catch (e) {
          debugPrint('Error disposing player for $videoPath: $e');
        }
      }
    }
  }

  /// 为AVI文件获取元数据的降级策略
  Future<VideoMetadata> _getMetadataForAviFile(String videoPath) async {
    try {
      debugPrint('VideoMetadataService: Using fallback strategy for AVI file: $videoPath');
      
      // 对于AVI文件，我们暂时跳过元数据获取，只返回null
      // 这样可以避免media_kit的超时问题，但仍然可以生成缩略图
      return VideoMetadata(duration: null, metadata: {});
    } catch (e) {
      debugPrint('Error in AVI fallback strategy for $videoPath: $e');
      return VideoMetadata(duration: null, metadata: {});
    }
  }

  /// 为视频生成中间帧作为封面（内部方法）
  Future<String?> _generateVideoThumbnailInternal(
    String videoPath,
    String videoId,
    Duration duration,
  ) async {
    Player? player;
    try {
      debugPrint(
        'VideoMetadataService: Generating thumbnail for $videoPath (ID: $videoId)',
      );

      // 检查文件是否存在
      final file = File(videoPath);
      if (!await file.exists()) {
        debugPrint(
          'VideoMetadataService: File does not exist for thumbnail generation: $videoPath',
        );
        return null;
      }

      // 检查文件扩展名
      final isAviFile = videoPath.toLowerCase().endsWith('.avi');
      
      if (isAviFile) {
        debugPrint('VideoMetadataService: AVI file detected for thumbnail, using fallback');
        return await _generateThumbnailForAviFile(videoPath, videoId);
      }

      // 为每个操作创建独立的播放器实例
      player = Player();
      final media = Media(videoPath);
      debugPrint(
        'VideoMetadataService: Opening media for thumbnail generation: $videoPath',
      );
      await player.open(media, play: false)
          .timeout(const Duration(seconds: 10), onTimeout: () {
        throw Exception('Timeout opening video');
      });

      // 等待播放器准备好
      debugPrint(
        'VideoMetadataService: Waiting for player to be ready for thumbnail...',
      );
      await player.stream.buffer.firstWhere((e) => e > Duration.zero)
          .timeout(const Duration(seconds: 15), onTimeout: () {
        throw Exception('Timeout waiting for video buffer');
      });
      await Future.delayed(const Duration(milliseconds: 200));

      final playerDuration = player.state.duration;
      debugPrint('VideoMetadataService: Got duration for thumbnail: $playerDuration');

      if (playerDuration.inMilliseconds == 0) {
        debugPrint(
          'VideoMetadataService: Invalid duration for thumbnail generation: $playerDuration',
        );
        await player.stop();
        return null;
      }

      // 在视频中间时间点截图
      final middleTime = Duration(milliseconds: playerDuration.inMilliseconds ~/ 2);
      debugPrint(
        'VideoMetadataService: Middle time for thumbnail: $middleTime',
      );

      // 使用 ThumbnailService 的 generateThumbnail 方法
      debugPrint(
        'VideoMetadataService: Calling ThumbnailService.generateThumbnail...',
      );
      final thumbnailPath = await _thumbnailService.generateThumbnail(
        videoPath,
        middleTime,
        videoId, // 直接使用 videoId 作为 clipId
      );

      debugPrint(
        'VideoMetadataService: ThumbnailService returned: $thumbnailPath',
      );

      // 返回相对路径（只保留文件名）
      if (thumbnailPath != null) {
        final fileName = _thumbnailService.getThumbnailFileName(videoId);
        debugPrint(
          'VideoMetadataService: Generated thumbnail file name: $fileName',
        );
        return fileName;
      }

      await player.stop();
      debugPrint(
        'VideoMetadataService: No thumbnail generated, stopping player',
      );
      return null;
    } catch (e) {
      debugPrint('Error generating video thumbnail for $videoPath: $e');
      debugPrint('Error stack trace: ${StackTrace.current}');
    } finally {
      // 确保播放器被正确释放
      if (player != null) {
        try {
          await player.stop();
          player.dispose();
          debugPrint('VideoMetadataService: Player disposed for thumbnail generation of $videoPath');
        } catch (e) {
          debugPrint('Error disposing player for thumbnail generation of $videoPath: $e');
        }
      }
    }
    return null;
  }

  /// 为AVI文件生成缩略图的降级策略
  Future<String?> _generateThumbnailForAviFile(String videoPath, String videoId) async {
    try {
      debugPrint('VideoMetadataService: Using fallback thumbnail strategy for AVI file: $videoPath');
      
      // 对于AVI文件，我们尝试在视频开始处截图
      final thumbnailPath = await _thumbnailService.generateThumbnail(
        videoPath,
        Duration.zero, // 在视频开始处截图
        videoId,
      );

      if (thumbnailPath != null) {
        final fileName = _thumbnailService.getThumbnailFileName(videoId);
        debugPrint('VideoMetadataService: Generated AVI thumbnail: $fileName');
        return fileName;
      }
      
      return null;
    } catch (e) {
      debugPrint('Error generating AVI thumbnail for $videoPath: $e');
      return null;
    }
  }

  /// 处理单个视频的元数据（公开方法）
  Future<void> processVideoMetadata(
    String videoId,
    String videoPath,
    Function(VideoMetadataResult) onResult,
  ) async {
    // 检查是否需要处理
    if (!_cache.shouldProcessVideo(videoId, videoPath)) {
      debugPrint('VideoMetadataService: Skipping $videoId - not ready for processing');
      return;
    }

    debugPrint('VideoMetadataService: Processing metadata for $videoId');

    // 在后台处理
    final task = VideoMetadataTask(videoId: videoId, videoPath: videoPath);
    final result = await compute(_processVideoMetadataInBackground, task);

    // 记录结果到缓存
    await _cache.recordResult(
      videoId,
      result.success,
      error: result.error,
      duration: result.duration,
      thumbnailPath: result.thumbnailPath,
    );

    // 通知结果
    onResult(result);
  }

  /// 批量处理视频元数据（非阻塞）
  Future<void> processVideoMetadataBatch(
    List<OriginalVideo> videos,
    Function(VideoMetadataResult) onResult,
  ) async {
    debugPrint(
      'VideoMetadataService: Starting batch processing with ${videos.length} videos',
    );

    for (final video in videos) {
      // 检查是否需要处理
      if (!_cache.shouldProcessVideo(video.id, video.path)) {
        debugPrint('VideoMetadataService: Skipping ${video.name} - not ready for processing');
        continue;
      }

      // 异步处理每个视频
      processVideoMetadata(video.id, video.path, onResult);
    }

    debugPrint('VideoMetadataService: Batch processing initiated');
  }

  /// 强制重新处理所有视频
  Future<void> forceReprocessAll() async {
    await _cache.forceReprocessAll();
    debugPrint('VideoMetadataService: Force reprocess all videos');
  }

  /// 强制重新处理失败的视频
  Future<void> forceReprocessFailed() async {
    await _cache.forceReprocessFailed();
    debugPrint('VideoMetadataService: Force reprocess failed videos');
  }

  /// 获取视频的处理状态
  VideoMetadataStatus? getVideoStatus(String videoId) {
    return _cache.getStatus(videoId);
  }

  /// 获取需要重试的视频列表
  List<String> getVideosToRetry() {
    return _cache.getVideosToRetry();
  }

  /// 获取失败次数过多的视频列表
  List<String> getFailedVideos() {
    return _cache.getFailedVideos();
  }

  void dispose() {
    // 不再需要dispose方法，因为每个操作都使用独立的播放器实例
  }
}

/// 视频元数据处理任务
class VideoMetadataTask {
  final String videoId;
  final String videoPath;

  VideoMetadataTask({
    required this.videoId,
    required this.videoPath,
  });
}

/// 视频元数据处理结果
class VideoMetadataResult {
  final String videoId;
  final bool success;
  final Duration? duration;
  final String? thumbnailPath;
  final String? error;

  VideoMetadataResult({
    required this.videoId,
    required this.success,
    this.duration,
    this.thumbnailPath,
    this.error,
  });
}

/// 视频元数据类
class VideoMetadata {
  final Duration? duration;
  final Map<String, dynamic> metadata;

  VideoMetadata({this.duration, this.metadata = const {}});

  /// 从元数据中提取演员信息
  List<String> get actors {
    final actorData =
        metadata['artist'] ?? metadata['actors'] ?? metadata['performer'];
    if (actorData is String) {
      return actorData
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return [];
  }

  /// 从元数据中提取年份
  int? get year {
    final yearData = metadata['date'] ?? metadata['year'];
    if (yearData is String) {
      final yearMatch = RegExp(r'(\d{4})').firstMatch(yearData);
      if (yearMatch != null) {
        return int.tryParse(yearMatch.group(1)!);
      }
    }
    return null;
  }

  /// 从元数据中提取系列信息
  String? get series {
    return metadata['album'] ?? metadata['series'] ?? metadata['show'];
  }

  /// 从元数据中提取标题
  String? get title {
    return metadata['title'];
  }

  /// 从元数据中提取描述
  String? get description {
    return metadata['description'] ?? metadata['comment'];
  }
}
