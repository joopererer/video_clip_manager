import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import '../main.dart'; // for formatDuration

class CustomProgressBar extends StatefulWidget {
  final Player player;
  final Duration? startTime;
  final Duration? endTime;
  final Function(Duration) onSetStart; // Callback to set start time
  final Function(Duration) onSetEnd; // Callback to set end time

  const CustomProgressBar({
    super.key,
    required this.player,
    this.startTime,
    this.endTime,
    required this.onSetStart,
    required this.onSetEnd,
  });

  @override
  State<CustomProgressBar> createState() => _CustomProgressBarState();
}

class _CustomProgressBarState extends State<CustomProgressBar> {
  @override
  Widget build(BuildContext context) {
    final SliderThemeData sliderTheme = SliderTheme.of(context);

    return StreamBuilder<Duration>(
      stream: widget.player.stream.duration,
      builder: (context, durationSnapshot) {
        return StreamBuilder<Duration>(
          stream: widget.player.stream.position,
          builder: (context, positionSnapshot) {
            final Duration duration = durationSnapshot.data ?? Duration.zero;
            final Duration position = positionSnapshot.data ?? Duration.zero;

            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: Text(
                    formatDuration(position),
                    style: const TextStyle(
                      fontSize: 12.0,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const double customThumbRadius = 7.0;
                      final double totalWidth = constraints.maxWidth;
                      final double trackWidth =
                          totalWidth - (customThumbRadius * 2);
                      final double trackStartOffset = customThumbRadius;
                      final double durationValue = duration.inMilliseconds
                          .toDouble();
                      final double positionValue = position.inMilliseconds
                          .toDouble()
                          .clamp(0.0, durationValue);

                      double calculatePixelPosition(Duration? markerTime) {
                        if (markerTime == null ||
                            durationValue <= 0 ||
                            trackWidth <= 0) {
                          return 0.0;
                        }
                        final double ratio =
                            markerTime.inMilliseconds / durationValue;
                        return trackStartOffset + (ratio * trackWidth);
                      }

                      const double markerWidth = 8.0;
                      final startPixelPosition = calculatePixelPosition(
                        widget.startTime,
                      );
                      final endPixelPosition = calculatePixelPosition(
                        widget.endTime,
                      );

                      final double startMarkerOffset =
                          startPixelPosition - (markerWidth / 2);
                      final double endMarkerOffset =
                          endPixelPosition - (markerWidth / 2);

                      return SizedBox(
                        height: 40.0,
                        child: GestureDetector(
                          onTapDown: (details) {
                            // Left-click
                            if (duration == Duration.zero || trackWidth <= 0) {
                              return;
                            }
                            final double tappedDx =
                                details.localPosition.dx - trackStartOffset;
                            final double ratio = (tappedDx / trackWidth).clamp(
                              0.0,
                              1.0,
                            );
                            final newMillis = (duration.inMilliseconds * ratio)
                                .toInt();
                            widget.onSetStart(
                              Duration(milliseconds: newMillis),
                            );
                          },
                          onSecondaryTapDown: (details) {
                            // Right-click
                            if (duration == Duration.zero || trackWidth <= 0) {
                              return;
                            }
                            final double tappedDx =
                                details.localPosition.dx - trackStartOffset;
                            final double ratio = (tappedDx / trackWidth).clamp(
                              0.0,
                              1.0,
                            );
                            final newMillis = (duration.inMilliseconds * ratio)
                                .toInt();
                            widget.onSetEnd(Duration(milliseconds: newMillis));
                          },
                          child: Stack(
                            alignment: Alignment.center,
                            clipBehavior: Clip.none,
                            children: [
                              SliderTheme(
                                data: sliderTheme.copyWith(
                                  trackShape:
                                      const RectangularSliderTrackShape(),
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: customThumbRadius,
                                  ),
                                  overlayShape: RoundSliderOverlayShape(
                                    overlayRadius: customThumbRadius * 2.0,
                                  ),
                                ),
                                child: Slider(
                                  value: positionValue,
                                  max: durationValue > 0 ? durationValue : 1.0,
                                  onChanged: (value) {
                                    widget.player.seek(
                                      Duration(milliseconds: value.toInt()),
                                    );
                                  },
                                ),
                              ),
                              if (widget.startTime != null &&
                                  widget.startTime != Duration.zero)
                                Positioned(
                                  left: startMarkerOffset,
                                  child: Tooltip(
                                    message:
                                        'Start: ${formatDuration(widget.startTime!)}',
                                    child: const BracketMarker(
                                      type: MarkerType.start,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ),
                              if (widget.endTime != null &&
                                  widget.endTime != Duration.zero)
                                Positioned(
                                  left: endMarkerOffset,
                                  child: Tooltip(
                                    message:
                                        'End: ${formatDuration(widget.endTime!)}',
                                    child: const BracketMarker(
                                      type: MarkerType.end,
                                      color: Colors.red,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 12.0),
                  child: Text(
                    formatDuration(duration),
                    style: const TextStyle(
                      fontSize: 12.0,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

enum MarkerType { start, end }

class BracketMarker extends StatelessWidget {
  final MarkerType type;
  final Color color;
  final double width;
  final double height;
  final double strokeWidth;

  const BracketMarker({
    super.key,
    required this.type,
    required this.color,
    this.width = 8.0,
    this.height = 20.0,
    this.strokeWidth = 2.5,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        border: Border(
          left: type == MarkerType.start
              ? BorderSide(color: color, width: strokeWidth)
              : BorderSide.none,
          right: type == MarkerType.end
              ? BorderSide(color: color, width: strokeWidth)
              : BorderSide.none,
          top: BorderSide(color: color, width: strokeWidth),
          bottom: BorderSide(color: color, width: strokeWidth),
        ),
      ),
    );
  }
}
