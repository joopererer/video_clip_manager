import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../utils/clip_range.dart';
import '../utils/timecode.dart';

/// Maps between horizontal pixels and *absolute source time*.
///
/// The timeline always spans `[0, source]`; this class never deals with
/// clip-relative or playlist-accumulated time.
@immutable
class TimelineGeometry {
  const TimelineGeometry({required this.width, required this.source});

  /// Horizontal inset so handles at 0 and `source` stay fully visible.
  static const double padding = 14;

  final double width;
  final Duration source;

  double get trackWidth => math.max(1.0, width - 2 * padding);

  double timeToDx(Duration t) {
    if (source <= Duration.zero) return padding;
    final ratio = (t.inMicroseconds / source.inMicroseconds).clamp(0.0, 1.0);
    return padding + ratio * trackWidth;
  }

  /// Converts a pixel position to a whole-millisecond source time.
  Duration dxToTime(double dx) {
    final ratio = ((dx - padding) / trackWidth).clamp(0.0, 1.0);
    return roundToMs(
      Duration(microseconds: (ratio * source.inMicroseconds).round()),
    );
  }
}

const List<Duration> _tickSteps = [
  Duration(milliseconds: 1),
  Duration(milliseconds: 2),
  Duration(milliseconds: 5),
  Duration(milliseconds: 10),
  Duration(milliseconds: 20),
  Duration(milliseconds: 50),
  Duration(milliseconds: 100),
  Duration(milliseconds: 200),
  Duration(milliseconds: 500),
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 5),
  Duration(seconds: 10),
  Duration(seconds: 15),
  Duration(seconds: 30),
  Duration(minutes: 1),
  Duration(minutes: 2),
  Duration(minutes: 5),
  Duration(minutes: 10),
  Duration(minutes: 15),
  Duration(minutes: 30),
  Duration(hours: 1),
  Duration(hours: 2),
  Duration(hours: 4),
];

/// Smallest "round" tick spacing that keeps labels at least [minTickPx] apart.
Duration niceTickInterval(
  Duration source,
  double trackWidth, {
  double minTickPx = 84,
}) {
  if (source <= Duration.zero || trackWidth <= 0) {
    return const Duration(seconds: 1);
  }
  final maxTicks = math.max(1.0, trackWidth / minTickPx);
  final target = source.inMicroseconds / maxTicks;
  for (final step in _tickSteps) {
    if (step.inMicroseconds >= target) return step;
  }
  return _tickSteps.last;
}

String _tickLabel(Duration t, Duration interval, Duration source) {
  if (interval < const Duration(seconds: 1)) return formatTimecodeShort(t);
  final full = formatTimecode(t).substring(0, 8); // HH:MM:SS
  return source >= const Duration(hours: 1) ? full : full.substring(3);
}

enum _DragTarget { none, start, end, playhead }

/// Millisecond-precision timeline for the clip editor.
///
/// All values are *absolute source times*. The widget owns no media
/// resources: it reports user intent through callbacks and reads the playhead
/// from [position]. Hover thumbnails come from [previewLookup] (the editor
/// wires this to the existing `PreviewService` keyframe cache), so no extra
/// player is ever created.
class ClipRangeTimeline extends StatefulWidget {
  const ClipRangeTimeline({
    super.key,
    required this.source,
    required this.start,
    required this.end,
    required this.position,
    required this.onSeek,
    required this.onRangeChanged,
    this.cover,
    this.enabled = true,
    this.previewLookup,
    this.onRequestSetStart,
    this.onRequestSetEnd,
    this.onRequestSetCover,
    this.onScrubChanged,
    this.height = 76,
  });

  /// Total source duration. [Duration.zero] means "not loaded".
  final Duration source;
  final Duration start;
  final Duration end;
  final Duration? cover;

  /// Current absolute playhead position.
  final ValueListenable<Duration> position;
  final bool enabled;
  final double height;

  final ValueChanged<Duration> onSeek;

  /// Live result of dragging a handle; always a legal range.
  final void Function(Duration start, Duration end) onRangeChanged;

  /// Context menu / Shift-click requests. The owner validates them.
  final ValueChanged<Duration>? onRequestSetStart;
  final ValueChanged<Duration>? onRequestSetEnd;
  final ValueChanged<Duration>? onRequestSetCover;

  /// `true` while a handle or the playhead is being dragged.
  final ValueChanged<bool>? onScrubChanged;

  /// Returns encoded image bytes of the nearest cached keyframe, if any.
  final Uint8List? Function(Duration time)? previewLookup;

  @override
  State<ClipRangeTimeline> createState() => _ClipRangeTimelineState();
}

class _ClipRangeTimelineState extends State<ClipRangeTimeline> {
  static const double _hitSlop = 10;

  double? _hoverDx;
  Duration? _hoverTime;
  Uint8List? _hoverFrame;
  _DragTarget _target = _DragTarget.none;
  _DragTarget _hoverHandle = _DragTarget.none;

  bool get _active => widget.enabled && widget.source > Duration.zero;

  _DragTarget _hit(TimelineGeometry g, double dx) {
    final sx = g.timeToDx(widget.start);
    final ex = g.timeToDx(widget.end);
    final ds = (dx - sx).abs();
    final de = (dx - ex).abs();
    if (ds > _hitSlop && de > _hitSlop) return _DragTarget.none;
    if (ds == de) return dx <= sx ? _DragTarget.start : _DragTarget.end;
    return ds < de ? _DragTarget.start : _DragTarget.end;
  }

  void _onHover(PointerHoverEvent e, TimelineGeometry g) {
    if (!_active) return;
    final dx = e.localPosition.dx;
    final time = g.dxToTime(dx);
    setState(() {
      _hoverDx = dx;
      if (_hoverTime != time) {
        _hoverTime = time;
        _hoverFrame = widget.previewLookup?.call(time);
      }
      _hoverHandle = _hit(g, dx);
    });
  }

  void _clearHover() {
    if (_hoverDx == null) return;
    setState(() {
      _hoverDx = null;
      _hoverTime = null;
      _hoverFrame = null;
      _hoverHandle = _DragTarget.none;
    });
  }

  void _dragUpdate(TimelineGeometry g, double dx) {
    final t = g.dxToTime(dx);
    switch (_target) {
      case _DragTarget.start:
        final next = ClipRangeRules.clampStart(t, widget.end);
        if (next != widget.start) {
          widget.onRangeChanged(next, widget.end);
          widget.onSeek(next);
        }
      case _DragTarget.end:
        final next = ClipRangeRules.clampEnd(t, widget.start, widget.source);
        if (next != widget.end) {
          widget.onRangeChanged(widget.start, next);
          widget.onSeek(next);
        }
      case _DragTarget.playhead:
        widget.onSeek(t);
      case _DragTarget.none:
        break;
    }
    setState(() {
      _hoverDx = dx;
      _hoverTime = t;
    });
  }

  void _endDrag() {
    if (_target == _DragTarget.none) return;
    _target = _DragTarget.none;
    widget.onScrubChanged?.call(false);
  }

  Future<void> _showMenu(TimelineGeometry g, TapUpDetails d) async {
    final time = g.dxToTime(d.localPosition.dx);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final pos = RelativeRect.fromRect(
      Rect.fromLTWH(d.globalPosition.dx, d.globalPosition.dy, 1, 1),
      Offset.zero & overlay.size,
    );
    final label = formatTimecode(time);
    final choice = await showMenu<String>(
      context: context,
      position: pos,
      items: [
        PopupMenuItem(value: 'seek', child: Text('Seek to $label')),
        if (widget.onRequestSetStart != null)
          PopupMenuItem(value: 'in', child: Text('Set IN here  ($label)')),
        if (widget.onRequestSetEnd != null)
          PopupMenuItem(value: 'out', child: Text('Set OUT here  ($label)')),
        if (widget.onRequestSetCover != null)
          PopupMenuItem(
            value: 'cover',
            child: Text('Set cover here  ($label)'),
          ),
      ],
    );
    switch (choice) {
      case 'seek':
        widget.onSeek(time);
      case 'in':
        widget.onRequestSetStart?.call(time);
      case 'out':
        widget.onRequestSetEnd?.call(time);
      case 'cover':
        widget.onRequestSetCover?.call(time);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final range = ClipRangeRules.length(widget.start, widget.end);
    return Semantics(
      container: true,
      label: 'Clip range timeline',
      value:
          'IN ${formatTimecode(widget.start)}, OUT ${formatTimecode(widget.end)}, '
          'length ${formatTimecode(range)}',
      child: SizedBox(
        height: widget.height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final geometry = TimelineGeometry(
              width: constraints.maxWidth,
              source: widget.source,
            );
            final cursor = !_active
                ? SystemMouseCursors.basic
                : (_hoverHandle != _DragTarget.none ||
                      _target == _DragTarget.start ||
                      _target == _DragTarget.end)
                ? SystemMouseCursors.resizeLeftRight
                : SystemMouseCursors.click;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: MouseRegion(
                    cursor: cursor,
                    onHover: (e) => _onHover(e, geometry),
                    onExit: (_) => _clearHover(),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragDown: !_active
                          ? null
                          : (d) {
                              final hit = _hit(geometry, d.localPosition.dx);
                              _target = hit == _DragTarget.none
                                  ? _DragTarget.playhead
                                  : hit;
                            },
                      onHorizontalDragStart: !_active
                          ? null
                          : (d) => widget.onScrubChanged?.call(true),
                      onHorizontalDragUpdate: !_active
                          ? null
                          : (d) => _dragUpdate(geometry, d.localPosition.dx),
                      onHorizontalDragEnd: (_) => _endDrag(),
                      onHorizontalDragCancel: () => _target = _DragTarget.none,
                      onTapUp: !_active
                          ? null
                          : (d) {
                              final t = geometry.dxToTime(d.localPosition.dx);
                              if (HardwareKeyboard.instance.isShiftPressed &&
                                  widget.onRequestSetStart != null) {
                                widget.onRequestSetStart!(t);
                              } else {
                                widget.onSeek(t);
                              }
                            },
                      onSecondaryTapUp: !_active
                          ? null
                          : (d) {
                              final t = geometry.dxToTime(d.localPosition.dx);
                              if (HardwareKeyboard.instance.isShiftPressed &&
                                  widget.onRequestSetEnd != null) {
                                widget.onRequestSetEnd!(t);
                              } else {
                                _showMenu(geometry, d);
                              }
                            },
                      child: CustomPaint(
                        painter: _TimelinePainter(
                          geometry: geometry,
                          colors: colors,
                          start: widget.start,
                          end: widget.end,
                          cover: widget.cover,
                          position: widget.position,
                          hoverDx: _hoverDx,
                          activeHandle: _target != _DragTarget.none
                              ? _target
                              : _hoverHandle,
                          active: _active,
                        ),
                        size: Size.infinite,
                      ),
                    ),
                  ),
                ),
                if (_active && _hoverDx != null && _hoverTime != null)
                  Positioned(
                    left: (_hoverDx! - 82).clamp(
                      0.0,
                      math.max(0.0, constraints.maxWidth - 164),
                    ),
                    bottom: widget.height + 6,
                    child: IgnorePointer(
                      child: _HoverCard(
                        time: _hoverTime!,
                        frame: _hoverFrame,
                        colors: colors,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HoverCard extends StatelessWidget {
  const _HoverCard({
    required this.time,
    required this.frame,
    required this.colors,
  });

  final Duration time;
  final Uint8List? frame;
  final AppColorExtension colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 164,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (frame != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                width: 156,
                height: 88,
                color: Colors.black,
                child: Image.memory(
                  frame!,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              formatTimecode(time),
              style: AppTypography.timecode(
                fontSize: 12,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.geometry,
    required this.colors,
    required this.start,
    required this.end,
    required this.cover,
    required this.position,
    required this.hoverDx,
    required this.activeHandle,
    required this.active,
  }) : super(repaint: position);

  final TimelineGeometry geometry;
  final AppColorExtension colors;
  final Duration start;
  final Duration end;
  final Duration? cover;
  final ValueListenable<Duration> position;
  final double? hoverDx;
  final _DragTarget activeHandle;
  final bool active;

  static const double _trackTop = 26;
  static const double _trackBottom = 62;
  static const double _handleWidth = 10;

  @override
  void paint(Canvas canvas, Size size) {
    final trackRect = RRect.fromLTRBR(
      TimelineGeometry.padding,
      _trackTop,
      size.width - TimelineGeometry.padding,
      _trackBottom,
      const Radius.circular(6),
    );
    canvas.drawRRect(trackRect, Paint()..color = colors.surfaceElevated);

    if (!active) {
      _paintLabel(
        canvas,
        'Timeline unavailable until the video is loaded',
        Offset(size.width / 2, (_trackTop + _trackBottom) / 2),
        colors.textMuted,
        center: true,
      );
      return;
    }

    _paintRuler(canvas, size);

    final sx = geometry.timeToDx(start);
    final ex = geometry.timeToDx(end);

    // Dim everything outside the selected range, highlight inside.
    final dim = Paint()..color = const Color(0x66000000);
    canvas.save();
    canvas.clipRRect(trackRect);
    canvas.drawRect(
      Rect.fromLTRB(trackRect.left, _trackTop, sx, _trackBottom),
      dim,
    );
    canvas.drawRect(
      Rect.fromLTRB(ex, _trackTop, trackRect.right, _trackBottom),
      dim,
    );
    canvas.drawRect(
      Rect.fromLTRB(sx, _trackTop, math.max(ex, sx + 1), _trackBottom),
      Paint()..color = colors.primary.withValues(alpha: 0.32),
    );
    final edge = Paint()
      ..color = colors.primary
      ..strokeWidth = 2;
    canvas.drawLine(Offset(sx, _trackTop + 1), Offset(ex, _trackTop + 1), edge);
    canvas.drawLine(
      Offset(sx, _trackBottom - 1),
      Offset(ex, _trackBottom - 1),
      edge,
    );
    canvas.restore();

    // Cover marker.
    if (cover != null) {
      final cx = geometry.timeToDx(cover!);
      final path = Path()
        ..moveTo(cx, _trackBottom + 2)
        ..lineTo(cx - 4, _trackBottom + 8)
        ..lineTo(cx + 4, _trackBottom + 8)
        ..close();
      canvas.drawPath(path, Paint()..color = colors.info);
    }

    _paintHandle(
      canvas,
      sx,
      isStart: true,
      hot: activeHandle == _DragTarget.start,
    );
    _paintHandle(
      canvas,
      ex,
      isStart: false,
      hot: activeHandle == _DragTarget.end,
    );

    if (hoverDx != null) {
      canvas.drawLine(
        Offset(hoverDx!, _trackTop - 2),
        Offset(hoverDx!, _trackBottom + 2),
        Paint()
          ..color = colors.textSecondary.withValues(alpha: 0.55)
          ..strokeWidth = 1,
      );
    }

    // Playhead (absolute source position).
    final px = geometry.timeToDx(position.value);
    final head = Paint()..color = colors.textPrimary;
    canvas.drawRect(
      Rect.fromLTRB(px - 1, _trackTop - 6, px + 1, _trackBottom + 4),
      head,
    );
    canvas.drawPath(
      Path()
        ..moveTo(px - 5, _trackTop - 8)
        ..lineTo(px + 5, _trackTop - 8)
        ..lineTo(px, _trackTop - 1)
        ..close(),
      head,
    );
  }

  void _paintHandle(
    Canvas canvas,
    double x, {
    required bool isStart,
    required bool hot,
  }) {
    final left = isStart ? x - _handleWidth : x;
    final rect = RRect.fromLTRBAndCorners(
      left,
      _trackTop - 4,
      left + _handleWidth,
      _trackBottom + 4,
      topLeft: isStart ? const Radius.circular(5) : Radius.zero,
      bottomLeft: isStart ? const Radius.circular(5) : Radius.zero,
      topRight: isStart ? Radius.zero : const Radius.circular(5),
      bottomRight: isStart ? Radius.zero : const Radius.circular(5),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..color = hot
            ? Color.lerp(colors.primary, Colors.white, 0.2)!
            : colors.primary,
    );
    final grip = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 1.5;
    final cx = left + _handleWidth / 2;
    final mid = (_trackTop + _trackBottom) / 2;
    canvas.drawLine(Offset(cx - 1.5, mid - 7), Offset(cx - 1.5, mid + 7), grip);
    canvas.drawLine(Offset(cx + 1.5, mid - 7), Offset(cx + 1.5, mid + 7), grip);
  }

  void _paintRuler(Canvas canvas, Size size) {
    final interval = niceTickInterval(geometry.source, geometry.trackWidth);
    final tick = Paint()
      ..color = colors.textMuted
      ..strokeWidth = 1;
    final minor = Paint()
      ..color = colors.border
      ..strokeWidth = 1;
    final stepUs = interval.inMicroseconds;
    final total = geometry.source.inMicroseconds;
    // Guard against pathological tick counts.
    if (stepUs <= 0 || total / stepUs > 400) return;
    for (var us = 0; us <= total; us += stepUs) {
      final x = geometry.timeToDx(Duration(microseconds: us));
      canvas.drawLine(Offset(x, 14), Offset(x, _trackTop - 1), tick);
      final half = us + stepUs ~/ 2;
      if (half < total) {
        final hx = geometry.timeToDx(Duration(microseconds: half));
        canvas.drawLine(Offset(hx, 20), Offset(hx, _trackTop - 1), minor);
      }
      final label = _tickLabel(
        Duration(microseconds: us),
        interval,
        geometry.source,
      );
      _paintLabel(
        canvas,
        label,
        Offset(x, 1),
        colors.textMuted,
        edgeAware: size.width,
      );
    }
  }

  void _paintLabel(
    Canvas canvas,
    String text,
    Offset at,
    Color color, {
    bool center = false,
    double? edgeAware,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: AppTypography.timecode(
          fontSize: 10.5,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    var dx = at.dx - tp.width / 2;
    if (edgeAware != null) {
      dx = dx.clamp(0.0, math.max(0.0, edgeAware - tp.width));
    }
    final dy = center ? at.dy - tp.height / 2 : at.dy;
    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.geometry.width != geometry.width ||
      old.geometry.source != geometry.source ||
      old.colors != colors ||
      old.start != start ||
      old.end != end ||
      old.cover != cover ||
      old.hoverDx != hoverDx ||
      old.activeHandle != activeHandle ||
      old.active != active;
}
