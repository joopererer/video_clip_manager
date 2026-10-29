import '../data/models.dart';

/// Pure playlist time helpers. Everything is computed from milliseconds so
/// short clips never round to zero.

/// Effective length of one playlist entry, never negative.
///
/// This is [PlaylistItemWithClip.effectiveDuration]: the playlist's custom
/// range when both bounds are set, otherwise the source clip length.
Duration playlistItemDuration(PlaylistItemWithClip entry) {
  final d = entry.effectiveDuration;
  return d.isNegative ? Duration.zero : d;
}

/// Total playlist length: the sum of effective durations in milliseconds.
///
/// Do not use `Playlist.totalDuration` for display; it sums the cached
/// nullable `PlaylistItem.duration` and can disagree with this value.
Duration playlistTotalDuration(Iterable<PlaylistItemWithClip> entries) {
  var ms = 0;
  for (final e in entries) {
    ms += playlistItemDuration(e).inMilliseconds;
  }
  return Duration(milliseconds: ms);
}

/// Playlist time at which entry [index] starts (sum of earlier entries).
Duration playlistOffsetOf(List<PlaylistItemWithClip> entries, int index) {
  var ms = 0;
  final end = index.clamp(0, entries.length);
  for (var i = 0; i < end; i++) {
    ms += playlistItemDuration(entries[i]).inMilliseconds;
  }
  return Duration(milliseconds: ms);
}

/// Formats a duration as `M:SS` or `H:MM:SS`, optionally with `.mmm`.
String formatPlaylistDuration(Duration d, {bool millis = false}) {
  final total = d.isNegative ? Duration.zero : d;
  final h = total.inHours;
  final m = total.inMinutes % 60;
  final s = total.inSeconds % 60;
  final ms = total.inMilliseconds % 1000;
  final ss = s.toString().padLeft(2, '0');
  final base = h > 0
      ? '$h:${m.toString().padLeft(2, '0')}:$ss'
      : '${total.inMinutes}:$ss';
  return millis ? '$base.${ms.toString().padLeft(3, '0')}' : base;
}
