import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'dart:async';

class CustomPlayerControls extends StatefulWidget {
  final Player player;
  final bool isFullscreen;
  final VoidCallback onToggleFullscreen;

  const CustomPlayerControls({
    super.key,
    required this.player,
    required this.isFullscreen,
    required this.onToggleFullscreen,
  });

  @override
  State<CustomPlayerControls> createState() => _CustomPlayerControlsState();
}

class _CustomPlayerControlsState extends State<CustomPlayerControls> {
  bool _areControlsVisible = true;
  double _currentVolume = 1.0;
  final FocusNode _controlsFocusNode = FocusNode();
  Timer? _autoHideTimer;

  @override
  void initState() {
    super.initState();
    _currentVolume = widget.player.state.volume / 100.0;
    _startAutoHideTimer();
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    _controlsFocusNode.dispose();
    super.dispose();
  }

  void _startAutoHideTimer() {
    _autoHideTimer?.cancel();
    _autoHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _areControlsVisible) {
        setState(() {
          _areControlsVisible = false;
        });
      }
    });
  }

  void _toggleControlsVisibility() {
    setState(() {
      _areControlsVisible = !_areControlsVisible;
    });
    if (_areControlsVisible) {
      _startAutoHideTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    return RawKeyboardListener(
      focusNode: _controlsFocusNode,
      autofocus: true,
      onKey: (RawKeyEvent event) {
        if (event is RawKeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape &&
            widget.isFullscreen) {
          widget.onToggleFullscreen();
        }
      },
      child: GestureDetector(
        onTap: _toggleControlsVisibility,
        child: Stack(
          children: [
            Container(color: Colors.transparent),
            StreamBuilder<bool>(
              stream: widget.player.stream.playing,
              initialData: widget.player.state.playing,
              builder: (context, snapshot) {
                final isPlaying = snapshot.data ?? false;
                return AnimatedOpacity(
                  opacity: _areControlsVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black38,
                          Colors.transparent,
                          Colors.black54,
                        ],
                      ),
                    ),
                    child: _buildControlsContent(context, isPlaying),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsContent(BuildContext context, bool isPlaying) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const SizedBox.shrink(),
        if (!isPlaying)
          Center(
            child: IconButton.filled(
              iconSize: 50,
              icon: const Icon(Icons.play_arrow),
              onPressed: widget.player.play,
              style: IconButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(0.9),
                foregroundColor: Colors.black,
              ),
            ),
          ),
        _buildBottomControls(context, isPlaying),
      ],
    );
  }

  Widget _buildBottomControls(BuildContext context, bool isPlaying) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 进度条
          StreamBuilder<Duration>(
            stream: widget.player.stream.position,
            initialData: widget.player.state.position,
            builder: (context, snapshot) {
              final position = snapshot.data ?? Duration.zero;
              return StreamBuilder<Duration>(
                stream: widget.player.stream.duration,
                initialData: widget.player.state.duration,
                builder: (context, durationSnapshot) {
                  final duration = durationSnapshot.data ?? Duration.zero;
                  if (duration.inSeconds == 0) return const SizedBox.shrink();

                  return Column(
                    children: [
                      Slider(
                        value: position.inMilliseconds.toDouble(),
                        max: duration.inMilliseconds.toDouble(),
                        onChanged: (value) {
                          widget.player.seek(
                            Duration(milliseconds: value.toInt()),
                          );
                        },
                        activeColor: Colors.white,
                        inactiveColor: Colors.white.withOpacity(0.3),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(position),
                              style: const TextStyle(color: Colors.white),
                            ),
                            Text(
                              _formatDuration(duration),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),

          // 控制按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 左侧控制按钮
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                    ),
                    onPressed: widget.player.playOrPause,
                  ),
                  IconButton(
                    icon: const Icon(Icons.replay_10, color: Colors.white),
                    onPressed: () {
                      final currentPosition = widget.player.state.position;
                      final newPosition =
                          currentPosition - const Duration(seconds: 10);
                      widget.player.seek(newPosition);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.forward_10, color: Colors.white),
                    onPressed: () {
                      final currentPosition = widget.player.state.position;
                      final newPosition =
                          currentPosition + const Duration(seconds: 10);
                      widget.player.seek(newPosition);
                    },
                  ),
                ],
              ),

              // 右侧控制按钮
              Row(
                children: [
                  // 音量控制
                  StreamBuilder<double>(
                    stream: widget.player.stream.volume,
                    initialData: widget.player.state.volume,
                    builder: (context, snapshot) {
                      final volume = snapshot.data ?? 100.0;
                      return Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              volume == 0 ? Icons.volume_off : Icons.volume_up,
                              color: Colors.white,
                            ),
                            onPressed: () {
                              if (volume > 0) {
                                widget.player.setVolume(0);
                              } else {
                                widget.player.setVolume(100);
                              }
                            },
                          ),
                          SizedBox(
                            width: 80,
                            child: Slider(
                              value: volume,
                              max: 100,
                              onChanged: (value) {
                                widget.player.setVolume(value);
                              },
                              activeColor: Colors.white,
                              inactiveColor: Colors.white.withOpacity(0.3),
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  // 全屏按钮
                  IconButton(
                    icon: Icon(
                      widget.isFullscreen
                          ? Icons.fullscreen_exit
                          : Icons.fullscreen,
                      color: Colors.white,
                    ),
                    onPressed: widget.onToggleFullscreen,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
