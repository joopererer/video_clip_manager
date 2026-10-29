import 'package:flutter/material.dart';

/// Compact, shared volume control used by all four playback surfaces.
///
/// Layout: `[icon] ─────●──── [65%]`
///
/// The bar is a small custom drag target instead of a [Slider], so it stays
/// compact in desktop control bars and cannot be confused with the seek bar.
class VolumeControl extends StatelessWidget {
  const VolumeControl({
    super.key,
    required this.volume,
    required this.muted,
    required this.onVolumeChanged,
    required this.onToggleMute,
    this.width = 140,
  });

  /// 0..100
  final double volume;
  final bool muted;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onToggleMute;
  final double width;

  @override
  Widget build(BuildContext context) {
    final icon = muted || volume <= 0
        ? Icons.volume_off
        : volume < 50
        ? Icons.volume_down
        : Icons.volume_up;
    final display = muted ? 0.0 : volume.clamp(0.0, 100.0);
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: muted ? 'Unmute' : 'Mute',
            icon: Icon(icon, size: 18),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: onToggleMute,
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                void update(Offset local) {
                  final w = constraints.maxWidth;
                  if (w <= 0) return;
                  onVolumeChanged((local.dx / w * 100).clamp(0.0, 100.0));
                }

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => update(d.localPosition),
                  onHorizontalDragStart: (d) => update(d.localPosition),
                  onHorizontalDragUpdate: (d) => update(d.localPosition),
                  child: SizedBox(
                    height: 28,
                    child: CustomPaint(
                      painter: _VolumeBarPainter(
                        value: display / 100,
                        track: colors.onSurface.withValues(alpha: 0.18),
                        fill: colors.primary,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              '${display.round()}%',
              style: Theme.of(context).textTheme.labelSmall,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _VolumeBarPainter extends CustomPainter {
  const _VolumeBarPainter({
    required this.value,
    required this.track,
    required this.fill,
  });

  final double value;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final bar = Paint()
      ..color = track
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final active = Paint()
      ..color = fill
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), bar);
    final x = (size.width * value.clamp(0.0, 1.0));
    if (x > 0) canvas.drawLine(Offset(0, cy), Offset(x, cy), active);
    canvas.drawCircle(Offset(x, cy), 5, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(covariant _VolumeBarPainter old) =>
      old.value != value || old.track != track || old.fill != fill;
}
