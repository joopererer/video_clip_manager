import 'dart:io';

import 'package:flutter/foundation.dart';
import 'screenshot_service.dart';
import '../data/app_state.dart';

class VideoMetadataService {
  /// Public method to get video duration using centralized ScreenshotService
  Future<Duration?> getVideoDuration(String videoPath) async {
    try {
      final isNetwork = videoPath.startsWith('http://') || videoPath.startsWith('https://');
      if (!isNetwork && !await File(videoPath).exists()) {
        debugPrint('[VideoMetadataService] File does not exist: $videoPath');
        return null;
      }

      final duration = await ScreenshotService().getDuration(videoPath).timeout(Duration(seconds: AppState.instance?.screenshotTimeoutSeconds ?? 15), onTimeout: () {
        debugPrint('[VideoMetadataService] Timeout getting duration for: $videoPath');
        return Duration.zero;
      });

      return duration == Duration.zero ? null : duration;
    } catch (error, stackTrace) {
      debugPrint('[VideoMetadataService] Error getting duration for $videoPath: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }
}
