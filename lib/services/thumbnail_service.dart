import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:video_thumbnail/video_thumbnail.dart';

class ThumbnailService {
  late final String _thumbnailDir;

  Future<void> init() async {
    final tempDir = await getTemporaryDirectory();
    _thumbnailDir = p.join(tempDir.path, 'VideoClipManagerThumbs');
    final dir = Directory(_thumbnailDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  Future<String?> getThumbnail(
    String videoPath,
    Duration time,
    String clipId,
  ) async {
    final thumbPath = p.join(_thumbnailDir, '$clipId.jpg');
    final thumbFile = File(thumbPath);

    // Always regenerate for simplicity, can be optimized later if needed
    if (await thumbFile.exists()) {
      await thumbFile.delete();
    }

    try {
      final generatedPath = await VideoThumbnail.thumbnailFile(
        video: videoPath,
        thumbnailPath: _thumbnailDir,
        imageFormat: ImageFormat.JPEG,
        timeMs: time.inMilliseconds,
        quality: 50,
      );
      if (generatedPath != null) {
        final finalFile = File(thumbPath);
        if (await File(generatedPath).exists()) {
          await File(generatedPath).rename(finalFile.path);
          return finalFile.path;
        }
      }
    } catch (e) {
      debugPrint('Error generating thumbnail for $clipId: $e');
    }
    return null;
  }
}
