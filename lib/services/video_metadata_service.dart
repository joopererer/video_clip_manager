import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

// A simple service dedicated to one task: getting video duration.
class VideoMetadataService {
  /// Public method to get video duration.
  /// Runs directly on the main thread since media_kit requires UI thread.
  Future<Duration?> getVideoDuration(String videoPath) async {
    try {
      if (!await File(videoPath).exists()) {
        debugPrint('[VideoMetadataService] File does not exist: $videoPath');
        return null;
      }

      // Create a temporary player for duration extraction
      final player = Player();
      await player.open(Media(videoPath), play: false);

      // Wait for the duration to become available.
      final duration = await player.stream.duration
          .firstWhere((d) => d > Duration.zero)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              debugPrint(
                '[VideoMetadataService] Timeout getting duration for: $videoPath',
              );
              return Duration.zero;
            },
          );

      await player.dispose();
      return duration == Duration.zero ? null : duration;
    } catch (e) {
      debugPrint(
        '[VideoMetadataService] Error getting duration for $videoPath: $e',
      );
      return null;
    }
  }
}
