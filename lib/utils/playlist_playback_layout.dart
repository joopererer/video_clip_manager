// Pure layout decisions for the playlist player, kept out of the widget so
// they can be unit tested.

enum PlaybackLayout {
  /// Video + controls on the left, queue panel on the right.
  sideQueue,

  /// Video + controls on top, compact queue underneath.
  bottomQueue,
}

/// Width (logical px) from which the queue sits beside the video.
const double kPlaybackSideQueueBreakpoint = 1100;

PlaybackLayout playbackLayoutFor(double width) =>
    width >= kPlaybackSideQueueBreakpoint
    ? PlaybackLayout.sideQueue
    : PlaybackLayout.bottomQueue;

/// Fixed width of the side queue panel.
double playbackSideQueueWidth(double width) => width >= 1500 ? 380 : 320;

/// Height of the bottom queue panel; leaves the video as much room as
/// possible on short windows.
double playbackBottomQueueHeight(double height) =>
    (height * 0.26).clamp(112.0, 220.0).toDouble();

/// Scroll offset that centres row [index] in a viewport, clamped to the list.
double queueScrollOffsetFor({
  required int index,
  required double rowExtent,
  required double viewport,
  required int itemCount,
}) {
  if (itemCount <= 0 || viewport <= 0) return 0;
  final maxOffset = (itemCount * rowExtent - viewport).clamp(
    0.0,
    double.infinity,
  );
  final target = index * rowExtent - (viewport - rowExtent) / 2;
  return target.clamp(0.0, maxOffset).toDouble();
}

/// Whole-number percentage (0..100) of [played] within [total], computed from
/// milliseconds so sub-second playlists still report progress.
int playbackPercent(Duration played, Duration total) {
  if (total.inMilliseconds <= 0) return 0;
  final p = played.inMilliseconds / total.inMilliseconds * 100;
  return p.clamp(0.0, 100.0).round();
}
