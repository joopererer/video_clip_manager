import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../data/app_state.dart';

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

  // Timeouts are read from AppState if available, otherwise use defaults.
  Duration get _openTimeout => Duration(seconds: AppState.instance?.openTimeoutSeconds ?? 10);
  Duration get _seekTimeout => Duration(seconds: AppState.instance?.seekTimeoutSeconds ?? 10);
  int get _markReadyDelayMs => AppState.instance?.markReadyDelayMs ?? 300;

  // Completer that is completed when the off-screen Video widget has been
  // inserted into the widget tree and the texture host is (likely) ready.
  final Completer<void> _readyCompleter = Completer<void>();
  bool _hostEnabled = false;

  // markReady scheduling
  Timer? _markReadyTimer;
  bool _markReadyPending = false;

  bool get isHostAvailable => _hostEnabled && !_disposed;

  ScreenshotService._internal() {
    print('ScreenshotService: initialized');
    _player = Player();
    _controller = VideoController(_player);
  }

  VideoController get videoController => _controller;

  /// Notify the service that the off-screen Video widget has been attached.
  /// Call this from the UI after the widget has been built (e.g. in
  /// addPostFrameCallback). This reduces the chance of taking screenshots
  /// before Flutter has registered the texture.
  void markReady() {
    // Cancel any previously scheduled markReady and reschedule with the
    // configured delay. Using a Timer lets us cancel/reschedule when the
    // user changes the delay in settings.
    final int delayMs = _markReadyDelayMs;
    print('ScreenshotService: scheduling markReady in ${delayMs}ms (cancel existing)');
    _markReadyTimer?.cancel();
    _markReadyPending = true;

    _markReadyTimer = Timer(Duration(milliseconds: delayMs), () {
      _markReadyTimer = null;
      _markReadyPending = false;
      if (_disposed) return;
      _hostEnabled = true;
      if (!_readyCompleter.isCompleted) {
        print('ScreenshotService: marked ready (delayed)');
        _readyCompleter.complete();
      }
    });
  }

  /// Called when AppState markReady delay changed. If a markReady was pending,
  /// cancel and reschedule using the new delay so the updated value takes
  /// effect immediately.
  void updateMarkReadyDelay() {
    if (_markReadyPending) {
      final int delayMs = _markReadyDelayMs;
      print('ScreenshotService: markReady delay updated, rescheduling pending in ${delayMs}ms');
      _markReadyTimer?.cancel();
      _markReadyTimer = Timer(Duration(milliseconds: delayMs), () {
        _markReadyTimer = null;
        _markReadyPending = false;
        if (_disposed) return;
        _hostEnabled = true;
        if (!_readyCompleter.isCompleted) {
          print('ScreenshotService: marked ready (rescheduled)');
          _readyCompleter.complete();
        }
      });
    }
  }

  void disableHost() {
    _hostEnabled = false;
    print('ScreenshotService: host disabled for playback stability');
  }

  /// Returns a future that completes when the internal queue is idle.
  Future<void> whenIdle() async {
    if (_disposed) {
      print('ScreenshotService: whenIdle called after dispose');
      return;
    }
    await _queue;
  }

  Future<void> dispose() async {
    _disposed = true;
    _hostEnabled = false;
    _markReadyTimer?.cancel();
    print('ScreenshotService: disposing');
    try {
      await _player.dispose();
    } catch (_) {}
  }

  /// Ensure the internal player has opened [videoPath]. Serialized.
  Future<Duration?> _ensureOpened(String videoPath) {
    _queue = _queue.then((_) async {
      if (_disposed || !_hostEnabled) {
        print('ScreenshotService: host disabled, skip open for $videoPath');
        return null;
      }
      print('ScreenshotService: ensureOpen -> $videoPath');
      // Wait for the off-screen Video to be ready (registered) before opening
      try {
        await _readyCompleter.future.timeout(const Duration(seconds: 5));
        print('ScreenshotService: host ready before open');
      } catch (_) {
        print('ScreenshotService: host not ready before open, continuing');
      }

      if (_openPath == videoPath) {
        print('ScreenshotService: already opened for $videoPath');
        return;
      }
      try {
        // Check file existence to avoid opening invalid paths
        final file = File(videoPath);
        final exists = await file.exists();
        if (!exists) {
          print('ScreenshotService: file not found: $videoPath, skipping open');
          return;
        }

        try {
          // Attempt open with timeout to avoid indefinite blocking from native plugin
          await _player.open(Media(videoPath), play: false).timeout(_openTimeout);

          // wait for buffer/first frame
          await _player.stream.buffer.firstWhere((d) => d > Duration.zero).timeout(const Duration(seconds: 15));
          await Future.delayed(const Duration(milliseconds: 200));
          _openPath = videoPath;
          print('ScreenshotService: opened $videoPath');
        } on TimeoutException catch (te) {
          print('ScreenshotService: open timed out for $videoPath: $te');
          return;
        }
      } catch (e) {
        print('ScreenshotService: open failed for $videoPath: $e');
        rethrow;
      }
    });
    return _queue.then((_) => _player.state.duration);
  }

  /// Take a screenshot at [time] for [videoPath]. Serialized.
  Future<Uint8List?> takeScreenshot(String videoPath, Duration time) {
    if (_disposed || !_hostEnabled) {
      print('ScreenshotService: host disabled, skip screenshot for $videoPath @ ${time.inSeconds}s');
      return Future.value(null);
    }
    final completer = Completer<Uint8List?>();
    _queue = _queue.then((_) async {
      if (_disposed) {
        completer.complete(null);
        return;
      }
      print('ScreenshotService: takeScreenshot start -> $videoPath @ ${time.inSeconds}s');
      try {
        // Ensure the off-screen Video has been attached before screenshotting.
        try {
          await _readyCompleter.future.timeout(const Duration(seconds: 5));
          print('ScreenshotService: host ready before screenshot');
        } catch (_) {
          print('ScreenshotService: host not ready before screenshot, continuing');
        }

        await _ensureOpened(videoPath);
        try {
          await _player.seek(time).timeout(_seekTimeout);
        } on TimeoutException catch (te) {
          print('ScreenshotService: seek timed out for $videoPath @ ${time.inSeconds}s: $te');
          completer.complete(null);
          return;
        }

        await Future.delayed(const Duration(milliseconds: 200));
        final data = await _player.screenshot();
        print('ScreenshotService: screenshot result for $videoPath @ ${time.inSeconds}s: ${data != null ? data.length : 0} bytes');
        completer.complete(data);
      } catch (e) {
        print('ScreenshotService: screenshot failed for $videoPath @ ${time.inSeconds}s: $e');
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
