import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import '../data/models.dart';
import 'thumbnail_service.dart';

class VideoMetadataService {
  final ThumbnailService _thumbnailService;
  final Player _player = Player();

  VideoMetadataService({required ThumbnailService thumbnailService})
      : _thumbnailService = thumbnailService;

  /// 获取视频的完整元数据
  Future<VideoMetadata> getVideoMetadata(String videoPath) async {
    try {
      final media = Media(videoPath);
      await _player.open(media, play: false);
      
      // 等待播放器准备好
      await _player.stream.buffer.firstWhere((e) => e > Duration.zero);
      await Future.delayed(const Duration(milliseconds: 200));

      final duration = _player.state.duration;

      await _player.stop();

      return VideoMetadata(
        duration: duration,
        metadata: {}, // 暂时跳过元数据提取，只获取时长
      );
    } catch (e) {
      debugPrint('Error getting video metadata for $videoPath: $e');
      return VideoMetadata(duration: null, metadata: {});
    }
  }

  /// 为视频生成中间帧作为封面
  Future<String?> generateVideoThumbnail(String videoPath, String videoId) async {
    try {
      // 获取视频时长
      final media = Media(videoPath);
      await _player.open(media, play: false);
      
      // 等待播放器准备好
      await _player.stream.buffer.firstWhere((e) => e > Duration.zero);
      await Future.delayed(const Duration(milliseconds: 200));

      final duration = _player.state.duration;
      
      if (duration == null || duration.inMilliseconds == 0) {
        await _player.stop();
        return null;
      }

      // 在视频中间时间点截图
      final middleTime = Duration(milliseconds: duration.inMilliseconds ~/ 2);
      
      // 使用 ThumbnailService 的 generateThumbnail 方法
      final thumbnailPath = await _thumbnailService.generateThumbnail(
        videoPath,
        middleTime,
        videoId, // 直接使用 videoId 作为 clipId
      );
      
      // 返回相对路径（只保留文件名）
      if (thumbnailPath != null) {
        final fileName = _thumbnailService.getThumbnailFileName(videoId);
        debugPrint('VideoMetadataService: Generated thumbnail file name: $fileName');
        return fileName;
      }
      
      await _player.stop();
      return null;
    } catch (e) {
      debugPrint('Error generating video thumbnail for $videoPath: $e');
    }
    return null;
  }

  /// 批量处理视频元数据
  Future<void> processVideoMetadata(
    List<OriginalVideo> videos,
    Function(int index, OriginalVideo updatedVideo) onUpdate,
  ) async {
    debugPrint('VideoMetadataService: Starting processVideoMetadata with ${videos.length} videos');
    
    for (int i = 0; i < videos.length; i++) {
      final video = videos[i];
      debugPrint('VideoMetadataService: Processing video ${i + 1}/${videos.length}: ${video.name}');
      debugPrint('VideoMetadataService: Current duration: ${video.duration}, thumbnailPath: ${video.thumbnailPath}');
      
      // 如果已经有元数据，跳过
      if (video.duration != null && video.thumbnailPath != null) {
        debugPrint('VideoMetadataService: Skipping ${video.name} - already has metadata');
        continue;
      }

      try {
        debugPrint('VideoMetadataService: Getting metadata for ${video.name}');
        final metadata = await getVideoMetadata(video.path);
        debugPrint('VideoMetadataService: Got metadata for ${video.name} - duration: ${metadata.duration}');
        
        String? thumbnailPath;
        
        // 如果没有封面，生成一个
        if (video.thumbnailPath == null) {
          debugPrint('VideoMetadataService: Generating thumbnail for ${video.name}');
          thumbnailPath = await generateVideoThumbnail(video.path, video.id);
          debugPrint('VideoMetadataService: Generated thumbnail for ${video.name}: $thumbnailPath');
        }

        final updatedVideo = video.copyWith(
          duration: metadata.duration,
          thumbnailPath: thumbnailPath ?? video.thumbnailPath,
          metadata: metadata.metadata,
        );

        debugPrint('VideoMetadataService: Calling onUpdate for ${video.name} with thumbnailPath: ${updatedVideo.thumbnailPath}');
        onUpdate(i, updatedVideo);
      } catch (e) {
        debugPrint('Error processing metadata for video ${video.name}: $e');
      }
    }
    
    debugPrint('VideoMetadataService: Finished processVideoMetadata');
  }

  void dispose() {
    _player.dispose();
  }
}

/// 视频元数据类
class VideoMetadata {
  final Duration? duration;
  final Map<String, dynamic> metadata;

  VideoMetadata({
    this.duration,
    this.metadata = const {},
  });

  /// 从元数据中提取演员信息
  List<String> get actors {
    final actorData = metadata['artist'] ?? metadata['actors'] ?? metadata['performer'];
    if (actorData is String) {
      return actorData.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
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