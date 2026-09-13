import 'dart:async';
import 'dart:io';

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'path_service.dart';
import 'screenshot_service.dart';
import '../data/app_state.dart';
import 'package:media_kit/media_kit.dart';

class ThumbnailService {
  final PathService pathService;

  Future<void> _processingFuture = Future.value();

  ThumbnailService({required this.pathService});

  String getThumbnailDirForDatabase(String dbPath) {
    final dbDir = p.dirname(dbPath);
    return p.join(dbDir, 'Thumbnails');
  }

  String getThumbnailPathForDatabase(String dbPath, String clipId) {
    final thumbDir = getThumbnailDirForDatabase(dbPath);
    return p.join(thumbDir, '$clipId.jpg');
  }

  String getThumbnailFileName(String clipId) {
    return '$clipId.jpg';
  }

  String getTempThumbnailFileName(String clipId) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${clipId}_temp_$timestamp.jpg';
  }

  String buildThumbnailPath(String dbPath, String thumbnailFileName) {
    final thumbDir = getThumbnailDirForDatabase(dbPath);
    return p.join(thumbDir, thumbnailFileName);
  }

  Future<String?> generateThumbnail(
    String videoPath,
    Duration time,
    String entityId, {
    required String dbPath,
  }) async {
    return _generateThumbnailInternal(videoPath, time, entityId, dbPath, false);
  }

  Future<String?> generateTempThumbnail(
    String videoPath,
    Duration time,
    String entityId, {
    required String dbPath,
  }) async {
    return _generateThumbnailInternal(videoPath, time, entityId, dbPath, true);
  }

  /// Public API: generate thumbnail using legacy per-Player approach.
  /// Writes file into thumbnail directory and returns filename on success.
  Future<String?> generateThumbnailLegacy(
    String videoPath,
    Duration time,
    String entityId, {
    required String dbPath,
  }) async {
    final thumbDir = getThumbnailDirForDatabase(dbPath);
    final fileName = getThumbnailFileName(entityId);
    final thumbFile = File(p.join(thumbDir, fileName));
    await Directory(thumbDir).create(recursive: true);

    final data = await _generateWithTempPlayer(videoPath, time);
    if (data != null) {
      try {
        await thumbFile.writeAsBytes(data);
        debugPrint('ThumbnailService: Generated thumbnail (legacy) at ${thumbFile.path}');
        return fileName;
      } catch (e) {
        debugPrint('ThumbnailService: Failed to write legacy thumbnail file ${thumbFile.path}: $e');
        return null;
      }
    }
    return null;
  }

  Future<String?> _generateThumbnailInternal(
    String videoPath,
    Duration time,
    String entityId,
    String dbPath,
    bool isTemp,
  ) async {
    final previousFuture = _processingFuture;
    final completer = Completer<String?>();
    _processingFuture = completer.future.then(
      (_) => null,
      onError: (_) => null,
    );

    await previousFuture;

    try {
      final thumbDir = getThumbnailDirForDatabase(dbPath);
      final fileName = isTemp
          ? getTempThumbnailFileName(entityId)
          : getThumbnailFileName(entityId);
      final thumbFile = File(p.join(thumbDir, fileName));

      await Directory(thumbDir).create(recursive: true);

      debugPrint('ThumbnailService: Requesting screenshot for entity $entityId at $time');
      // Ensure the off-screen host is ready before attempting screenshots.
      try {
       ScreenshotService().markReady();
       // Wait the configured markReady delay + small cushion so texture is registered.
       final delayMs = AppState.instance?.markReadyDelayMs ?? 300;
       await Future.delayed(Duration(milliseconds: delayMs + 100));
      } catch (_) {}

      var data = await ScreenshotService()
         .takeScreenshot(videoPath, time)
         .timeout(Duration(seconds: AppState.instance?.screenshotTimeoutSeconds ?? 15), onTimeout: () => null);

      // Retry once if the first attempt returned null. This helps transient host/setup races.
      if (data == null) {
       debugPrint('ThumbnailService: First screenshot attempt returned null for $entityId, retrying once');
       try {
         ScreenshotService().markReady();
         final delayMs = AppState.instance?.markReadyDelayMs ?? 300;
         await Future.delayed(Duration(milliseconds: delayMs + 150));
       } catch (_) {}
       data = await ScreenshotService()
           .takeScreenshot(videoPath, time)
           .timeout(Duration(seconds: AppState.instance?.screenshotTimeoutSeconds ?? 15), onTimeout: () => null);
      }
 
      if (data != null) {
       try {
         await thumbFile.writeAsBytes(data);
         debugPrint('ThumbnailService: Generated thumbnail at ${thumbFile.path}');
         completer.complete(fileName);
         return fileName;
       } catch (e) {
         debugPrint('ThumbnailService: Failed to write thumbnail file ${thumbFile.path}: $e');
         completer.complete(null);
         return null;
       }
      }
 
      debugPrint('ThumbnailService: Screenshot returned null for $entityId after retry');
      // Fallback: try legacy temporary Player approach for refresh-all and critical flows
      try {
        debugPrint('ThumbnailService: Falling back to temporary Player for $entityId');
        final legacyData = await _generateWithTempPlayer(videoPath, time);
        if (legacyData != null) {
          try {
            await thumbFile.writeAsBytes(legacyData);
            debugPrint('ThumbnailService: Generated thumbnail (legacy) at ${thumbFile.path}');
            completer.complete(fileName);
            return fileName;
          } catch (e) {
            debugPrint('ThumbnailService: Failed to write legacy thumbnail file ${thumbFile.path}: $e');
            completer.complete(null);
            return null;
          }
        }
      } catch (e) {
        debugPrint('ThumbnailService: Legacy fallback failed for $entityId: $e');
      }
 
      completer.complete(null);
      return null;
    } catch (e) {
      debugPrint('Error generating thumbnail for $entityId: $e');
      completer.complete(null);
      return null;
    }
  }

  bool deleteThumbnail(String dbPath, String clipId) {
    String thumbnailFile = getThumbnailPathForDatabase(dbPath, clipId);
    if (File(thumbnailFile).existsSync()) {
      File(thumbnailFile).deleteSync();
      return true;
    }
    return false;
  }

  void cleanupTempThumbnails(String dbPath, String clipId) {
    final thumbDir = getThumbnailDirForDatabase(dbPath);
    final dir = Directory(thumbDir);
    if (dir.existsSync()) {
      final files = dir.listSync();
      for (final file in files) {
        if (file is File) {
          final fileName = p.basename(file.path);
          if (fileName.startsWith('${clipId}_temp_') && fileName.endsWith('.jpg')) {
            try {
              file.deleteSync();
              debugPrint('ThumbnailService: Cleaned up temp file $fileName');
            } catch (e) {
              debugPrint('ThumbnailService: Failed to delete temp file $fileName: $e');
            }
          }
        }
      }
    }
  }

  /// Legacy fallback: create a temporary Player, open/seek/screenshot and dispose.
  /// Only used when centralized ScreenshotService fails. Guarded by timeouts.
  Future<Uint8List?> _generateWithTempPlayer(String videoPath, Duration time) async {
    try {
      final file = File(videoPath);
      if (!await file.exists()) {
        debugPrint('ThumbnailService: Legacy fallback - file not found: $videoPath');
        return null;
      }

      final player = Player();
      try {
        final openTimeout = Duration(seconds: AppState.instance?.openTimeoutSeconds ?? 10);
        await player.open(Media(videoPath), play: false).timeout(openTimeout);
        // wait for first buffer/frame
        try {
          await player.stream.buffer.firstWhere((d) => d > Duration.zero).timeout(const Duration(seconds: 10));
        } catch (_) {}

        final seekTimeout = Duration(seconds: AppState.instance?.seekTimeoutSeconds ?? 10);
        try {
          await player.seek(time).timeout(seekTimeout);
        } catch (_) {
          // seek failed/time out
        }

        await Future.delayed(const Duration(milliseconds: 300));
        final data = await player.screenshot();
        debugPrint('ThumbnailService: Legacy screenshot size: ${data != null ? data.length : 0}');
        return data;
      } finally {
        try {
          await player.dispose();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('ThumbnailService: Legacy fallback error: $e');
      return null;
    }
  }

  void dispose() {
    // no-op: each generation delegated to ScreenshotService which is long-lived.
  }
}
