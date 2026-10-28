import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart'
    show defaultEnterNativeFullscreen, defaultExitNativeFullscreen;

import '../../data/models.dart';
import '../../services/preview_service.dart';
import '../../services/screenshot_service.dart';
import '../../utils/media_source.dart';
import '../../utils/preview_source.dart';
import 'preview_playback.dart';

/// What the user asked for when the preview closed.
enum PreviewAction { createClip }

/// Everything the preview needs from the outside world. Production uses the
/// defaults (media_kit, `ScreenshotService`, `PreviewService`, the native
/// Windows fullscreen channel); tests replace the pieces that need native
/// libraries.
class VideoPreviewEnvironment {
  const VideoPreviewEnvironment({
    this.createPlayback = _createMediaKitPlayback,
    this.resolveSource = resolvePreviewSource,
    this.prepare = _prepareServices,
    this.release = _releaseServices,
    this.enterNativeFullscreen = defaultEnterNativeFullscreen,
    this.exitNativeFullscreen = defaultExitNativeFullscreen,
  });

  /// Called at most once per dialog, and not at all when the source cannot
  /// be played (missing file, expired link).
  final PreviewPlaybackFactory createPlayback;
  final Future<PreviewSource> Function(Object video) resolveSource;

  /// Runs before the dialog is shown: pause background frame work and wait
  /// for the screenshot queue so a visible Player never races it.
  final Future<void> Function() prepare;

  /// Runs once, after the dialog's player has been disposed.
  final void Function() release;

  final Future<void> Function() enterNativeFullscreen;
  final Future<void> Function() exitNativeFullscreen;
}

PreviewPlayback _createMediaKitPlayback() => MediaKitPreviewPlayback();

Future<void> _prepareServices() async {
  PreviewService().pauseGlobalPreGeneration();
  await ScreenshotService().prepareForPlayback();
}

void _releaseServices() {
  PreviewService().resumeGlobalPreGeneration();
  ScreenshotService().markReady();
}

/// Preview of an original (source) video: play, pause, seek, mute and
/// fullscreen. It never edits or saves clip ranges; "Create Clip" closes it
/// with [PreviewAction.createClip] after the player is released.
class VideoPreviewDialog extends StatefulWidget {
  const VideoPreviewDialog({
    super.key,
    required this.video,
    this.clipCount,
    this.environment = const VideoPreviewEnvironment(),
  });

  /// An [OriginalVideo] or an [OnlineVideo].
  final Object video;
  final int? clipCount;
  final VideoPreviewEnvironment environment;

  /// Prepares the media services, then shows the dialog. Returns
  /// [PreviewAction.createClip] when the user chose to create a clip.
  static Future<PreviewAction?> show(
    BuildContext context,
    Object video, {
    int? clipCount,
    VideoPreviewEnvironment environment = const VideoPreviewEnvironment(),
  }) async {
    await environment.prepare();
    if (!context.mounted) {
      environment.release();
      return null;
    }
    return showDialog<PreviewAction>(
      context: context,
      builder: (_) => VideoPreviewDialog(
        video: video,
        clipCount: clipCount,
        environment: environment,
      ),
    );
  }

  @override
  State<VideoPreviewDialog> createState() => _VideoPreviewDialogState();
}

class _VideoPreviewDialogState extends State<VideoPreviewDialog> {
  late final VideoPreviewEnvironment _env = widget.environment;
  final FocusNode _focus = FocusNode(debugLabel: 'video-preview');
  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);

  /// Bumped whenever anything the control bars show changes. The fullscreen
  /// route listens to it too.
  final ValueNotifier<int> _rev = ValueNotifier(0);

  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _loadTimer;

  PreviewPlayback? _playback;
  PreviewSource? _source;
  String? _error;
  Future<void>? _releaseFuture;
  bool _closing = false;

  bool _playing = false;
  Duration _duration = Duration.zero;
  int? _videoW;
  int? _videoH;

  bool _muted = false;
  double _volumeBeforeMute = 100;

  bool _scrubbing = false;
  bool _seeking = false;
  Duration? _queuedSeek;

  bool _fullscreen = false;
  bool _fullscreenBusy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  @override
  void dispose() {
    unawaited(_release());
    _loadTimer?.cancel();
    _position.dispose();
    _rev.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Lifecycle: exactly one playback per dialog, released exactly once.
  // ---------------------------------------------------------------------

  String get _title {
    final v = widget.video;
    if (v is OriginalVideo) return v.name;
    if (v is OnlineVideo) return v.title;
    return '';
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    _rev.value++;
  }

  Future<void> _boot() async {
    PreviewSource source;
    try {
      source = await _env.resolveSource(widget.video);
    } catch (e) {
      source = PreviewSource.failed('无法读取视频: $e');
    }
    if (!mounted || _closing) return;
    _source = source;
    if (!source.isPlayable) {
      setState(() => _error = source.failureMessage);
      return;
    }

    final playback = _env.createPlayback();
    _playback = playback;
    _subs.addAll([
      playback.playingStream.listen((v) {
        _playing = v;
        if (v) _error = null;
        _changed();
      }),
      playback.positionStream.listen((p) {
        if (!_scrubbing && !_seeking) _position.value = p;
      }),
      playback.durationStream.listen((d) {
        _duration = d;
        if (d > Duration.zero) _error = null;
        _changed();
      }),
      playback.widthStream.listen((w) {
        if (w != _videoW) {
          _videoW = w;
          _changed();
        }
      }),
      playback.heightStream.listen((h) {
        if (h != _videoH) {
          _videoH = h;
          _changed();
        }
      }),
      playback.errorStream.listen((message) {
        if (message.isNotEmpty && _duration == Duration.zero) {
          _error = mediaFailureMessage(
            MediaSourceFailure.openFailed,
            source.path!,
          );
          _changed();
        }
      }),
    ]);

    _loadTimer = Timer(Duration(seconds: source.isNetwork ? 20 : 8), () {
      if (!mounted || _closing) return;
      if (_duration == Duration.zero && !_playing) {
        _error = mediaFailureMessage(
          MediaSourceFailure.openTimeout,
          source.path!,
        );
        _changed();
      }
    });

    try {
      await playback.open(source.path!, httpHeaders: source.httpHeaders);
    } catch (e) {
      if (!mounted || _closing) return;
      _error = mediaFailureMessage(classifyOpenError(e), source.path!);
    }
    _changed();
  }

  Future<void> _release() => _releaseFuture ??= _doRelease();

  Future<void> _doRelease() async {
    _closing = true;
    _loadTimer?.cancel();
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
    final playback = _playback;
    _playback = null;
    try {
      if (_fullscreen) await _env.exitNativeFullscreen();
      await playback?.dispose();
    } catch (e) {
      debugPrint('VideoPreviewDialog: error while releasing player: $e');
    } finally {
      _env.release();
    }
  }

  /// Hides the video first, releases the player, and only then pops with
  /// [PreviewAction.createClip], so the editor never opens while this
  /// player still owns the media.
  Future<void> _createClip() async {
    if (_closing) return;
    setState(() => _closing = true);
    await WidgetsBinding.instance.endOfFrame;
    await _release();
    if (!mounted) return;
    Navigator.of(context).pop(PreviewAction.createClip);
  }

  // ---------------------------------------------------------------------
  // Transport
  // ---------------------------------------------------------------------

  Future<void> _togglePlay() async {
    final playback = _playback;
    if (playback == null || _closing) return;
    try {
      if (_playing) {
        await playback.pause();
        return;
      }
      final atEnd =
          _duration > Duration.zero &&
          _position.value >= _duration - const Duration(milliseconds: 250);
      if (atEnd) await playback.seek(Duration.zero);
      await playback.play();
    } catch (e) {
      debugPrint('VideoPreviewDialog: play/pause failed: $e');
    }
  }

  /// One seek at a time; the latest request wins while one is in flight.
  Future<void> _seekTo(Duration target) async {
    final playback = _playback;
    if (playback == null || _closing) return;
    if (_seeking) {
      _queuedSeek = target;
      return;
    }
    _seeking = true;
    try {
      var next = target;
      while (true) {
        _position.value = next;
        await playback.seek(next);
        final queued = _queuedSeek;
        _queuedSeek = null;
        if (queued == null || _closing) break;
        next = queued;
      }
    } catch (e) {
      debugPrint('VideoPreviewDialog: seek failed: $e');
    } finally {
      _seeking = false;
    }
  }

  Future<void> _toggleMute() async {
    final playback = _playback;
    if (playback == null || _closing) return;
    try {
      if (_muted) {
        await playback.setVolume(
          _volumeBeforeMute > 0 ? _volumeBeforeMute : 100,
        );
        _muted = false;
      } else {
        _volumeBeforeMute = playback.volume > 0 ? playback.volume : 100;
        await playback.setVolume(0);
        _muted = true;
      }
      _changed();
    } catch (e) {
      debugPrint('VideoPreviewDialog: mute failed: $e');
    }
  }

  // ---------------------------------------------------------------------
  // Fullscreen: a route that reuses the same playback. No Player is created.
  // ---------------------------------------------------------------------

  Future<void> _enterFullscreen() async {
    final playback = _playback;
    if (playback == null || _closing || _fullscreen || _fullscreenBusy) return;
    _fullscreenBusy = true;
    _fullscreen = true;
    _changed();

    final navigator = Navigator.of(context, rootNavigator: true);
    final route = PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (routeContext, _, _) => _FullscreenShell(
        video: playback.buildVideo(),
        onExit: () => Navigator.of(routeContext).maybePop(),
        onTogglePlay: _togglePlay,
        controls: _buildControls(
          fullscreen: true,
          onToggleFullscreen: () => Navigator.of(routeContext).maybePop(),
        ),
      ),
    );
    final popped = navigator.push<void>(route);
    try {
      await _env.enterNativeFullscreen();
    } finally {
      _fullscreenBusy = false;
    }
    await popped;

    // The route is gone (Esc, button or back). Leave native fullscreen.
    _fullscreenBusy = true;
    try {
      await _env.exitNativeFullscreen();
    } finally {
      _fullscreen = false;
      _fullscreenBusy = false;
      if (mounted) {
        _changed();
        _focus.requestFocus();
      }
    }
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    // Space only when no button owns the focus, so a focused button keeps
    // its own Space behaviour.
    if (event.logicalKey == LogicalKeyboardKey.space && node.hasPrimaryFocus) {
      unawaited(_togglePlay());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String _kindLabel() {
    final v = widget.video;
    if (v is OnlineVideo) return 'Online · ${v.platform}';
    return _source?.isNetwork == true ? 'Network stream' : 'Local file';
  }

  Duration get _knownDuration {
    if (_duration > Duration.zero) return _duration;
    final v = widget.video;
    if (v is OriginalVideo) return v.duration ?? Duration.zero;
    if (v is OnlineVideo) return v.duration ?? Duration.zero;
    return Duration.zero;
  }

  String get _sourceText {
    final v = widget.video;
    if (v is OriginalVideo) return v.path;
    if (v is OnlineVideo) return v.url;
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = math.max(320.0, math.min(1100.0, size.width - 48));
    final height = math.max(320.0, math.min(780.0, size.height - 48));
    final scheme = Theme.of(context).colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Focus(
        autofocus: true,
        focusNode: _focus,
        onKeyEvent: _onKey,
        child: SizedBox(
          width: width,
          height: height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(scheme),
              Expanded(child: _buildVideoArea()),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: _buildControls(
                  fullscreen: false,
                  onToggleFullscreen: _enterFullscreen,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme scheme) {
    final style = Theme.of(context).textTheme;
    final duration = _knownDuration;
    final hasSize = (_videoW ?? 0) > 0 && (_videoH ?? 0) > 0;
    final facts = <String>[
      _kindLabel(),
      if (duration > Duration.zero) formatPreviewClock(duration),
      if (hasSize)
        '$_videoW×$_videoH${_videoH! > _videoW! ? ' (portrait)' : ''}',
      if (widget.clipCount != null) '${widget.clipCount} clips',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tooltip(
                  message: _title,
                  child: Text(
                    _title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style.titleMedium,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  facts.join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Tooltip(
                  message: _sourceText,
                  child: Text(
                    _sourceText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoArea() {
    final playback = _playback;
    final error = _error;
    final loading = error == null && _duration == Duration.zero;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (playback != null && !_closing)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _togglePlay,
              child: playback.buildVideo(),
            ),
          if (error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.white70,
                      size: 40,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      error,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            )
          else if (loading && _playback != null && !_closing)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }

  Widget _buildControls({
    required bool fullscreen,
    required VoidCallback onToggleFullscreen,
  }) {
    return ValueListenableBuilder<int>(
      valueListenable: _rev,
      builder: (context, _, _) {
        final ready = _playback != null && !_closing;
        final canSeek = ready && _duration > Duration.zero;
        final maxMs = math.max(1, _duration.inMilliseconds).toDouble();
        final onVideo = fullscreen;
        final fg = onVideo ? Colors.white : null;

        final seekRow = ValueListenableBuilder<Duration>(
          valueListenable: _position,
          builder: (context, position, _) {
            final posMs = position.inMilliseconds
                .clamp(0, maxMs.toInt())
                .toDouble();
            return Row(
              children: [
                SizedBox(
                  width: 56,
                  child: Text(
                    formatPreviewClock(position),
                    textAlign: TextAlign.end,
                    style: TextStyle(color: fg),
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: posMs,
                    max: maxMs,
                    semanticFormatterCallback: (v) =>
                        formatPreviewClock(Duration(milliseconds: v.round())),
                    onChangeStart: canSeek ? (_) => _scrubbing = true : null,
                    onChanged: canSeek
                        ? (v) => _position.value = Duration(
                            milliseconds: v.round(),
                          )
                        : null,
                    onChangeEnd: canSeek
                        ? (v) {
                            _scrubbing = false;
                            unawaited(
                              _seekTo(Duration(milliseconds: v.round())),
                            );
                          }
                        : null,
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    formatPreviewClock(_duration),
                    style: TextStyle(color: fg),
                  ),
                ),
              ],
            );
          },
        );

        final buttons = Row(
          children: [
            IconButton(
              tooltip: _playing ? 'Pause' : 'Play',
              color: fg,
              icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
              onPressed: ready ? _togglePlay : null,
            ),
            IconButton(
              tooltip: _muted ? 'Unmute' : 'Mute',
              color: fg,
              icon: Icon(_muted ? Icons.volume_off : Icons.volume_up),
              onPressed: ready ? _toggleMute : null,
            ),
            const Spacer(),
            IconButton(
              tooltip: fullscreen ? 'Exit Fullscreen' : 'Fullscreen',
              color: fg,
              icon: Icon(fullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
              onPressed: ready ? onToggleFullscreen : null,
            ),
            if (!fullscreen) ...[
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _closing ? null : _createClip,
                icon: const Icon(Icons.content_cut, size: 18),
                label: const Text('Create Clip'),
              ),
            ],
          ],
        );

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [seekRow, buttons],
        );
      },
    );
  }
}

/// Black full-window page: the shared video, a bottom control bar, Esc to
/// leave, tap to play or pause.
class _FullscreenShell extends StatelessWidget {
  const _FullscreenShell({
    required this.video,
    required this.controls,
    required this.onExit,
    required this.onTogglePlay,
  });

  final Widget video;
  final Widget controls;
  final VoidCallback onExit;
  final VoidCallback onTogglePlay;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          onExit();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.space &&
            node.hasPrimaryFocus) {
          onTogglePlay();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTogglePlay,
              child: video,
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                  child: controls,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
