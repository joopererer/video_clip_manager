import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import 'path_service.dart';

class ThumbnailService {
  final PathService pathService;

  final Player _player = Player();
  late final VideoController _videoController;

  VideoController get videoController => _videoController;

  String? _currentlyOpenVideoPath;
  Future<void> _processingFuture = Future.value();

  ThumbnailService({required this.pathService}) {
    _videoController = VideoController(_player);
  }

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
    final previousFuture = _processingFuture;
    final completer = Completer<String?>();
    _processingFuture = completer.future.then(
      (_) => null,
      onError: (_) => null,
    );

    await previousFuture;

    try {
      final thumbDir = getThumbnailDirForDatabase(dbPath);
      final thumbFile = File(p.join(thumbDir, getThumbnailFileName(entityId)));

      await Directory(thumbDir).create(recursive: true);

      if (_currentlyOpenVideoPath != videoPath) {
        debugPrint(
          'ThumbnailService: Switching to video $videoPath for entity $entityId',
        );
        await _player.open(Media(videoPath), play: false);
        _currentlyOpenVideoPath = videoPath;
        await _player.stream.buffer
            .firstWhere((e) => e > Duration.zero)
            .timeout(const Duration(seconds: 15));
        await Future.delayed(const Duration(milliseconds: 500));
      }

      debugPrint(
        'ThumbnailService: Seeking to time $time for entity $entityId',
      );
      await _player.seek(time);
      await Future.delayed(const Duration(milliseconds: 500));

      debugPrint('ThumbnailService: Taking screenshot for entity $entityId');
      final data = await _player.screenshot();

      if (data != null) {
        await thumbFile.writeAsBytes(data);
        final fileName = getThumbnailFileName(entityId);
        debugPrint(
          'ThumbnailService: Generated thumbnail at ${thumbFile.path}',
        );
        completer.complete(fileName);
        return fileName;
      } else {
        throw Exception('Screenshot failed: returned null data.');
      }
    } catch (e) {
      debugPrint('Error generating thumbnail for $entityId: $e');
      _currentlyOpenVideoPath = null;
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

  void dispose() {
    _player.dispose();
  }
}
