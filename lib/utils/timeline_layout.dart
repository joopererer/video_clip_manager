/// Pure width layout for the playlist timeline, free of Flutter so it can be
/// unit tested.
///
/// Segment widths are proportional to their real duration, except that no
/// segment is drawn narrower than [minSegment]. The extra pixels given to tiny
/// segments are taken proportionally from the larger ones so the total stays
/// exactly [totalWidth]. Widths are only a visual aid: labels, tooltips and
/// offsets must always use the real durations, never these widths.
class TimelineLayout {
  const TimelineLayout({required this.widths, required this.expanded});

  /// Drawn width of each segment, in logical pixels.
  final List<double> widths;

  /// Whether the segment is drawn wider than its true proportion.
  final List<bool> expanded;

  /// Left edge of every segment boundary: `length + 1` values, from 0 to the
  /// total width.
  List<double> get boundaries {
    final result = <double>[0];
    var x = 0.0;
    for (final w in widths) {
      x += w;
      result.add(x);
    }
    return result;
  }

  /// Index of the boundary (insertion slot, `0..length`) nearest to [x].
  int nearestSlot(double x) {
    final b = boundaries;
    var best = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < b.length; i++) {
      final d = (b[i] - x).abs();
      if (d < bestDistance) {
        best = i;
        bestDistance = d;
      }
    }
    return best;
  }

  /// Index of the segment containing [x], or `null` when there are none.
  int? segmentAt(double x) {
    if (widths.isEmpty) return null;
    var edge = 0.0;
    for (var i = 0; i < widths.length; i++) {
      edge += widths[i];
      if (x < edge) return i;
    }
    return widths.length - 1;
  }
}

/// Lays out [durationsMs] across [totalWidth] with a visual floor of
/// [minSegment] per segment.
TimelineLayout computeTimelineLayout(
  List<int> durationsMs,
  double totalWidth, {
  double minSegment = 8,
}) {
  final n = durationsMs.length;
  if (n == 0) return const TimelineLayout(widths: [], expanded: []);
  if (totalWidth <= 0) {
    return TimelineLayout(
      widths: List.filled(n, 0),
      expanded: List.filled(n, false),
    );
  }

  final ms = [for (final d in durationsMs) d < 0 ? 0 : d];
  final total = ms.fold<int>(0, (a, b) => a + b);

  // Not enough room for the floor, or nothing to be proportional to: share
  // the space equally.
  if (total <= 0 || n * minSegment >= totalWidth) {
    return TimelineLayout(
      widths: List.filled(n, totalWidth / n),
      expanded: List.filled(n, false),
    );
  }

  // Segments pinned to the floor; everything else shares what is left in
  // proportion to duration. Pinning can push other segments below the floor,
  // so repeat until stable (at most n rounds).
  final pinned = List.filled(n, false);
  var widths = List.filled(n, 0.0);
  for (var round = 0; round <= n; round++) {
    final pinnedCount = pinned.where((p) => p).length;
    final freeWidth = totalWidth - pinnedCount * minSegment;
    final freeMs = [
      for (var i = 0; i < n; i++)
        if (!pinned[i]) ms[i],
    ].fold<int>(0, (a, b) => a + b);

    widths = [
      for (var i = 0; i < n; i++)
        if (pinned[i])
          minSegment
        else if (freeMs > 0)
          freeWidth * ms[i] / freeMs
        else
          0.0,
    ];

    var changed = false;
    for (var i = 0; i < n; i++) {
      if (!pinned[i] && widths[i] < minSegment) {
        pinned[i] = true;
        changed = true;
      }
    }
    if (!changed) break;
  }

  final expanded = [
    for (var i = 0; i < n; i++) widths[i] > totalWidth * ms[i] / total + 0.5,
  ];
  return TimelineLayout(widths: widths, expanded: expanded);
}

/// Converts an insertion [slot] (`0..length`) into the index the dragged
/// entry ends up at after being removed and re-inserted. Returns `null` when
/// the move would not change the order.
int? finalIndexForSlot(int from, int slot) {
  if (slot == from || slot == from + 1) return null;
  return slot > from ? slot - 1 : slot;
}
