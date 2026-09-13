import 'dart:async';
import 'dart:io';

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'path_service.dart';
import 'screenshot_service.dart';

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
      final data = await ScreenshotService().takeScreenshot(videoPath, time).timeout(const Duration(seconds: 15), onTimeout: () => null);

      if (data != null) {
        await thumbFile.writeAsBytes(data);
        debugPrint('ThumbnailService: Generated thumbnail at ${thumbFile.path}');
        completer.complete(fileName);
        return fileName;
      }

      debugPrint('ThumbnailService: Screenshot returned null for $entityId');
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

  void dispose() {
    // no-op: each generation delegated to ScreenshotService which is long-lived.
  }
}
