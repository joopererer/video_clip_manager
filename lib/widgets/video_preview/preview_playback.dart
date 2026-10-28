import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// The small slice of a media_kit player the original-video preview needs.
///
/// One instance owns exactly one `Player` and one `VideoController`. The
/// preview dialog creates it once and calls [dispose] once; tests replace it
/// with a fake so Player creation and release can be counted without native
/// libraries.
abstract class PreviewPlayback {
  Stream<bool> get playingStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<String> get errorStream;
  Stream<int?> get widthStream;
  Stream<int?> get heightStream;

  bool get isPlaying;
  Duration get position;
  Duration get duration;

  /// 0 to 100, as in media_kit.
  double get volume;
  int? get width;
  int? get height;

  Future<void> open(String source, {Map<String, String>? httpHeaders});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);

  /// The video surface. Safe to build under different parents (dialog and
  /// fullscreen); it always shows the same controller.
  Widget buildVideo();

  /// Stops audio and releases the native player. Safe to call once.
  Future<void> dispose();
}

typedef PreviewPlaybackFactory = PreviewPlayback Function();

/// Production implementation on top of media_kit.
class MediaKitPreviewPlayback implements PreviewPlayback {
  MediaKitPreviewPlayback() : _player = Player() {
    _controller = VideoController(_player);
  }

  final Player _player;
  late final VideoController _controller;

  @override
  Stream<bool> get playingStream => _player.stream.playing;
  @override
  Stream<Duration> get positionStream => _player.stream.position;
  @override
  Stream<Duration> get durationStream => _player.stream.duration;
  @override
  Stream<String> get errorStream => _player.stream.error;
  @override
  Stream<int?> get widthStream => _player.stream.width;
  @override
  Stream<int?> get heightStream => _player.stream.height;

  @override
  bool get isPlaying => _player.state.playing;
  @override
  Duration get position => _player.state.position;
  @override
  Duration get duration => _player.state.duration;
  @override
  double get volume => _player.state.volume;
  @override
  int? get width => _player.state.width;
  @override
  int? get height => _player.state.height;

  @override
  Future<void> open(String source, {Map<String, String>? httpHeaders}) {
    final headers = (httpHeaders == null || httpHeaders.isEmpty)
        ? null
        : httpHeaders;
    return _player.open(Media(source, httpHeaders: headers), play: true);
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Widget buildVideo() => Video(
    controller: _controller,
    // The dialog draws its own controls.
    controls: NoVideoControls,
    // Keeps landscape and portrait sources at their original aspect ratio.
    fit: BoxFit.contain,
    fill: Colors.black,
  );

  @override
  Future<void> dispose() async {
    try {
      if (_player.state.playing) await _player.pause();
    } catch (_) {
      // Pausing is best effort; dispose below still releases the audio.
    }
    await _player.dispose();
  }
}
