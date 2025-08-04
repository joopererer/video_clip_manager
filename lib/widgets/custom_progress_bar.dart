import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

// Helper function
String formatDuration(Duration d) {
  final parts = d.toString().split('.').first.padLeft(8, '0').split(':');
  return '${parts[0]}:${parts[1]}:${parts[2]}';
}


class CustomProgressBar extends StatefulWidget {
  final Player player;
  final Duration startTime;
  final Duration endTime;
  final Function(Duration) onSetStart;
  final Function(Duration) onSetEnd;
  final bool showThumbnailPreview;

  const CustomProgressBar({
    super.key,
    required this.player,
    required this.startTime,
    required this.endTime,
    required this.onSetStart,
    required this.onSetEnd,
    this.showThumbnailPreview = false,
  });

  @override
  State<CustomProgressBar> createState() => _CustomProgressBarState();
}

class _CustomProgressBarState extends State<CustomProgressBar> {
  bool _isHovering = false;
  double? _hoverDx;
  Duration? _hoverTime;
  Uint8List? _thumbnailData;
  Future<void>? _pendingPreview;
  Duration? _positionBeforeHover;
  bool _clickPerformed = false;

  Duration _getTimeFromDx(double dx, double maxWidth, Duration totalDuration) {
    final double progress = (dx / maxWidth).clamp(0.0, 1.0);
    return totalDuration * progress;
  }

  void _updatePreview(Duration time) {
    _pendingPreview?.ignore();
    _pendingPreview = Future(() async {
      await widget.player.seek(time);
      await Future.delayed(const Duration(milliseconds: 50));
      if (!_isHovering || !mounted) return;
      final data = await widget.player.screenshot();
      if (mounted && _isHovering) {
        setState(() {
          _thumbnailData = data;
        });
      }
    });
  }

  void _handleHover(PointerHoverEvent event, BoxConstraints constraints, Duration totalDuration) {
    final dx = event.localPosition.dx;
    final hoverTime = _getTimeFromDx(dx, constraints.maxWidth, totalDuration);

    setState(() {
      _hoverDx = dx;
      _hoverTime = hoverTime;
      if (widget.showThumbnailPreview) _thumbnailData = null;
    });

    if (widget.showThumbnailPreview) {
      _updatePreview(hoverTime);
    } else {
      widget.player.seek(hoverTime);
    }
  }

  void _handleEnter(PointerEnterEvent event) {
    setState(() {
      _isHovering = true;
      _positionBeforeHover = widget.player.state.position;
      _clickPerformed = false;
    });
  }

  void _handleExit(PointerExitEvent event) {
    setState(() {
      _isHovering = false;
    });
    if (!_clickPerformed && _positionBeforeHover != null) {
      widget.player.seek(_positionBeforeHover!);
    }
  }

  void _handlePrimaryTap(TapUpDetails details, double maxWidth, Duration totalDuration) {
    final tappedTime = _getTimeFromDx(details.localPosition.dx, maxWidth, totalDuration);
    widget.onSetStart(tappedTime);
    widget.player.seek(tappedTime);
    _clickPerformed = true;
  }

  void _handleSecondaryTap(TapUpDetails details, double maxWidth, Duration totalDuration) {
    final tappedTime = _getTimeFromDx(details.localPosition.dx, maxWidth, totalDuration);
    widget.onSetEnd(tappedTime);
    widget.player.seek(tappedTime);
    _clickPerformed = true;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: widget.player.stream.duration,
      initialData: widget.player.state.duration,
      builder: (context, durationSnapshot) {
        final totalDuration = durationSnapshot.data ?? Duration.zero;
        if (totalDuration == Duration.zero) {
          return const SizedBox(height: 48);
        }

        return Row(
          children: [
            StreamBuilder<Duration>(
              stream: widget.player.stream.position,
              initialData: widget.player.state.position,
              builder: (context, snapshot) {
                return Text(
                  formatDuration(snapshot.data ?? Duration.zero),
                  style: const TextStyle(fontFamily: 'monospace'),
                );
              },
            ),
            const SizedBox(width: 8),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return MouseRegion(
                    onEnter: _handleEnter,
                    onExit: _handleExit,
                    onHover: (event) => _handleHover(event, constraints, totalDuration),
                    child: GestureDetector(
                      onTapUp: (details) => _handlePrimaryTap(details, constraints.maxWidth, totalDuration),
                      onSecondaryTapUp: (details) => _handleSecondaryTap(details, constraints.maxWidth, totalDuration),
                      child: Tooltip(
                        message: 'Left Click: Set Start / Right Click: Set End',
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.centerLeft,
                          children: [
                            Container(
                              height: 8,
                              width: constraints.maxWidth,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            _buildPositionedBar(
                              constraints.maxWidth,
                              totalDuration,
                              widget.startTime,
                              widget.endTime,
                              Theme.of(context).primaryColor.withOpacity(0.4),
                            ),
                            StreamBuilder<Duration>(
                              stream: widget.player.stream.position,
                              initialData: widget.player.state.position,
                              builder: (context, positionSnapshot) {
                                return _buildPositionedBar(
                                  constraints.maxWidth,
                                  totalDuration,
                                  Duration.zero,
                                  positionSnapshot.data ?? Duration.zero,
                                  Theme.of(context).primaryColor,
                                );
                              },
                            ),
                            _buildMarker(constraints.maxWidth, totalDuration, widget.startTime, Colors.blue),
                            _buildMarker(constraints.maxWidth, totalDuration, widget.endTime, Colors.red),
                            if (_isHovering && _hoverDx != null)
                              Positioned(
                                left: _hoverDx! - (widget.showThumbnailPreview ? 50 : 28),
                                bottom: 20,
                                child: widget.showThumbnailPreview
                                    ? _buildThumbnailPreview()
                                    : _buildHoverTimePreview(),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatDuration(totalDuration),
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPositionedBar(double maxWidth, Duration total, Duration start, Duration end, Color color) {
    final startDx = (start.inMilliseconds / total.inMilliseconds) * maxWidth;
    final endDx = (end.inMilliseconds / total.inMilliseconds) * maxWidth;
    return Positioned(
      left: startDx.clamp(0, maxWidth),
      child: Container(
        height: 8,
        width: (endDx - startDx).clamp(0, maxWidth),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  Widget _buildMarker(double maxWidth, Duration total, Duration time, Color color) {
    final dx = (time.inMilliseconds / total.inMilliseconds) * maxWidth;
    return Positioned(
      left: dx.clamp(0.0, maxWidth) - 8,
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
      ),
    );
  }

  Widget _buildThumbnailPreview() {
    return Container(
      width: 100,
      padding: const EdgeInsets.all(4.0),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white54, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_thumbnailData != null)
            Image.memory(_thumbnailData!, width: 100, fit: BoxFit.contain)
          else
            const SizedBox(
              height: 56,
              child: Center(child: CircularProgressIndicator()),
            ),
          const SizedBox(height: 4),
          Text(
            formatDuration(_hoverTime ?? Duration.zero),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHoverTimePreview() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        formatDuration(_hoverTime ?? Duration.zero),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
