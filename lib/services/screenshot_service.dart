import 'dart:async';
import 'dart:typed_data';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// A single, long-lived Player+VideoController used only for screenshots.
/// Serializes access so screenshot/open/seek are never run concurrently.
class ScreenshotService {
  static final ScreenshotService _instance = ScreenshotService._internal();
  factory ScreenshotService() => _instance;

  late final Player _player;
  late final VideoController _controller;
  String? _openPath;

  // serialization queue
  Future<void> _queue = Future.value();
  bool _disposed = false;

  // Completer that is completed when the off-screen Video widget has been
  // inserted into the widget tree and the texture host is (likely) ready.
  final Completer<void> _readyCompleter = Completer<void>();

  ScreenshotService._internal() {
    _player = Player();
    _controller = VideoController(_player);
  }

  VideoController get videoController => _controller;

  /// Notify the service that the off-screen Video widget has been attached.
  /// Call this from the UI after the widget has been built (e.g. in
  /// addPostFrameCallback). This reduces the chance of taking screenshots
  /// before Flutter has registered the texture.
  void markReady() {
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.complete();
    }
  }

  /// Returns a future that completes when the internal queue is idle.
  Future<void> whenIdle() => _disposed ? Future.value() : _queue;

  Future<void> dispose() async {
    _disposed = true;
    try {
      await _player.dispose();
    } catch (_) {}
  }

  /// Ensure the internal player has opened [videoPath]. Serialized.
  Future<Duration?> _ensureOpened(String videoPath) {
    _queue = _queue.then((_) async {
      if (_disposed) throw StateError('ScreenshotService disposed');
      // Wait for the off-screen Video to be ready (registered) before opening
      try {
        await _readyCompleter.future.timeout(const Duration(seconds: 5));
      } catch (_) {
        // ignore timeout, proceed anyway
      }

      if (_openPath == videoPath) return;
      try {
        await _player.open(Media(videoPath), play: false);
        // wait for buffer/first frame
        await _player.stream.buffer.firstWhere((d) => d > Duration.zero).timeout(const Duration(seconds: 15));
        await Future.delayed(const Duration(milliseconds: 200));
        _openPath = videoPath;
      } catch (e) {
        // propagate
        rethrow;
      }
    });
    return _queue.then((_) => _player.state.duration);
  }

  /// Take a screenshot at [time] for [videoPath]. Serialized.
  Future<Uint8List?> takeScreenshot(String videoPath, Duration time) {
    if (_disposed) return Future.value(null);
    final completer = Completer<Uint8List?>();
    _queue = _queue.then((_) async {
      if (_disposed) {
        completer.complete(null);
        return;
      }
      try {
        // Ensure the off-screen Video has been attached before screenshotting.
        try {
          await _readyCompleter.future.timeout(const Duration(seconds: 5));
        } catch (_) {
          // if not ready in time, continue but this increases risk
        }

        await _ensureOpened(videoPath);
        await _player.seek(time);
        await Future.delayed(const Duration(milliseconds: 200));
        final data = await _player.screenshot();
        completer.complete(data);
      } catch (e) {
        // Return null on error to avoid crashing callers
        completer.complete(null);
      }
    });
    return completer.future;
  }

  /// Convenience to get duration (serialized open if needed)
  Future<Duration?> getDuration(String videoPath) async {
    try {
      final duration = await _ensureOpened(videoPath);
      return duration;
    } catch (e) {
      return null;
    }
  }
}
