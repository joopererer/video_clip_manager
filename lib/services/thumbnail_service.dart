import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'path_service.dart';
import '../data/models.dart';

class ThumbnailService {
  final PathService pathService;
  late final String _thumbnailDir;

  final Player player = Player();
  late final VideoController videoController;
  String? _currentlyOpenVideoPath;

  ThumbnailService({required this.pathService}) {
    _thumbnailDir = pathService.getThumbnailDir();
    videoController = VideoController(player);
  }

  String getThumbnailPath(String clipId) {
    return p.join(_thumbnailDir, '$clipId.jpg');
  }

  /// 根据数据库文件路径获取对应的缩略图目录
  String getThumbnailDirForDatabase(String dbPath) {
    final dbDir = p.dirname(dbPath);
    return p.join(dbDir, 'Thumbnails');
  }

  /// 根据数据库文件路径和clipId获取缩略图路径
  String getThumbnailPathForDatabase(String dbPath, String clipId) {
    final thumbDir = getThumbnailDirForDatabase(dbPath);
    return p.join(thumbDir, '$clipId.jpg');
  }

  /// 将完整路径转换为相对路径（只保留文件名）
  String getThumbnailFileName(String clipId) {
    return '$clipId.jpg';
  }

  /// 从相对路径构建完整路径
  String buildThumbnailPath(String dbPath, String thumbnailFileName) {
    final thumbDir = getThumbnailDirForDatabase(dbPath);
    return p.join(thumbDir, thumbnailFileName);
  }

  Future<void> clearCache() async {
    // 确保播放器已停止并释放了可能锁定的文件资源
    await player.stop();
    _currentlyOpenVideoPath = null;

    final dir = Directory(_thumbnailDir);
    try {
      if (await dir.exists()) {
        // 不删除目录本身，而是删除目录下的所有文件
        final files = dir.list();
        await for (final file in files) {
          try {
            await file.delete();
          } catch (e) {
            debugPrint('Failed to delete file ${file.path}: $e');
          }
        }
      } else {
        // 如果目录不存在，则创建它
        await dir.create(recursive: true);
      }
    } catch (e) {
      debugPrint('Error clearing thumbnail cache: $e');
      // 如果发生错误，尝试重新创建目录以确保其存在
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }
  }

  Future<String?> generateThumbnail(
    String videoPath,
    Duration time,
    String clipId,
  ) async {
    final thumbPath = getThumbnailPath(clipId);
    final thumbFile = File(thumbPath);
    
    // 确保缩略图目录存在
    final thumbDir = p.dirname(thumbPath);
    await Directory(thumbDir).create(recursive: true);

    try {
      if (_currentlyOpenVideoPath != videoPath) {
        await player.open(Media(videoPath), play: false);
        _currentlyOpenVideoPath = videoPath;
        // 等待播放器准备好，对于快速连续操作很重要
        await player.stream.buffer.firstWhere((e) => e > Duration.zero);
        await Future.delayed(const Duration(milliseconds: 200));
      }

      await player.seek(time);
      await Future.delayed(const Duration(milliseconds: 200)); // 给 seek 一点时间
      final data = await player.screenshot();

      if (data != null) {
        await thumbFile.writeAsBytes(data);
        return thumbPath;
      }
    } catch (e) {
      debugPrint('Error generating thumbnail for $clipId: $e');
    }
    return null;
  }

  Future<void> generateThumbnailsInBatch(
    List<VideoClip> clips,
    VoidCallback onUpdate,
  ) async {
    final clipsByVideo = <String, List<VideoClip>>{};
    for (final clip in clips) {
      (clipsByVideo[clip.videoPath] ??= []).add(clip);
    }

    for (final entry in clipsByVideo.entries) {
      final videoPath = entry.key;
      final clipsForVideo = entry.value;

      try {
        await player.open(Media(videoPath), play: false);
        _currentlyOpenVideoPath = videoPath;
        // 等待播放器准备好，对于快速连续操作很重要
        await player.stream.buffer.firstWhere((e) => e > Duration.zero);
        await Future.delayed(const Duration(milliseconds: 200));

        for (final clip in clipsForVideo) {
          // 直接在此处实现截图逻辑，而不是调用另一个方法
          try {
            await player.seek(clip.coverFrameTime);
            await Future.delayed(
              const Duration(milliseconds: 200),
            ); // 给 seek 一点时间
            final data = await player.screenshot();

            if (data != null) {
              final thumbPath = getThumbnailPath(clip.id);
              await File(thumbPath).writeAsBytes(data);
              // Trouvez l'index du clip dans votre liste `_clips`
              final index = clipsForVideo.indexWhere((c) => c.id == clip.id);
              if (index != -1) {
                // Créez une nouvelle instance avec le thumbnailPath mis à jour
                final updatedClip = clipsForVideo[index].copyWith(thumbnailPath: thumbPath);
                // Remplacez l'ancien clip par le nouveau dans la liste
                clipsForVideo[index] = updatedClip;
              }
              onUpdate();
            }
          } catch (e) {
            debugPrint(
              'Error generating thumbnail for clip ${clip.id} in batch: $e',
            );
          }
        }
      } catch (e) {
        debugPrint("Error in batch generation for $videoPath: $e");
      }
    }
    _currentlyOpenVideoPath = null;
    // 任务结束后可以考虑停止播放器以释放资源
    await player.stop();
  }

  void dispose() {
    player.dispose();
  }
}
