import '../data/models.dart';
import 'playlist_time.dart';

/// Real figures for one playlist, computed from the clips it references.
///
/// `Playlist.totalDuration` sums the cached nullable `PlaylistItem.duration`,
/// which can be stale or missing, so lists must use this instead.
class PlaylistSummary {
  const PlaylistSummary({
    required this.storedCount,
    required this.availableCount,
    required this.duration,
  });

  /// Items stored in the playlist, including ones whose clip is gone.
  final int storedCount;

  /// Items whose clip still exists (these are the ones that play).
  final int availableCount;

  /// Sum of effective durations of available items, exact to the millisecond.
  final Duration duration;

  int get missingCount => storedCount - availableCount;
}

/// Summarises [playlist] using [clipsById]. Pass a map built once per frame
/// when summarising many playlists.
PlaylistSummary summarizePlaylist(
  Playlist playlist,
  Map<String, VideoClip> clipsById,
) {
  var available = 0;
  var ms = 0;
  for (final item in playlist.items) {
    final clip = clipsById[item.clipId];
    if (clip == null) continue;
    available++;
    ms += playlistItemDuration(
      PlaylistItemWithClip(item: item, clip: clip),
    ).inMilliseconds;
  }
  return PlaylistSummary(
    storedCount: playlist.items.length,
    availableCount: available,
    duration: Duration(milliseconds: ms),
  );
}

/// Grid geometry for the playlist cards.
class PlaylistGridMetrics {
  const PlaylistGridMetrics({
    required this.columns,
    required this.tileWidth,
    required this.tileHeight,
  });

  final int columns;
  final double tileWidth;
  final double tileHeight;
  double get aspectRatio => tileWidth / tileHeight;
}

/// Chooses 2..6 columns so tiles stay at least [minTileWidth] wide, then sizes
/// each tile as a 16:9 cover plus a fixed [footerHeight].
PlaylistGridMetrics playlistGridMetrics(
  double availableWidth, {
  double spacing = 16,
  double minTileWidth = 220,
  double footerHeight = 88,
}) {
  final usable = availableWidth.isFinite && availableWidth > 0
      ? availableWidth
      : minTileWidth * 2;
  final fit = ((usable + spacing) / (minTileWidth + spacing)).floor();
  final columns = fit.clamp(2, 6);
  final tileWidth = (usable - spacing * (columns - 1)) / columns;
  return PlaylistGridMetrics(
    columns: columns,
    tileWidth: tileWidth,
    tileHeight: tileWidth * 9 / 16 + footerHeight,
  );
}

/// Sorts [items] by one of the tab's sort keys (`name`, `date`, `duration`).
///
/// Works on the caller's own objects rather than playlist ids, because legacy
/// data can contain playlists that share an id. `duration` is longest first
/// and `date` is newest first. The sort is stable and [items] is not mutated.
List<T> sortPlaylistEntries<T>(
  List<T> items,
  String sortBy, {
  required Playlist Function(T) playlistOf,
  required Duration Function(T) durationOf,
}) {
  int byName(T a, T b) => playlistOf(
    a,
  ).name.toLowerCase().compareTo(playlistOf(b).name.toLowerCase());

  // List.sort is not stable, so tie-break on the original position.
  final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
  int Function(T, T) compare;
  switch (sortBy) {
    case 'date':
      compare = (a, b) =>
          playlistOf(b).createdAt.compareTo(playlistOf(a).createdAt);
    case 'duration':
      compare = (a, b) => durationOf(b).compareTo(durationOf(a));
    default:
      compare = byName;
  }
  indexed.sort((x, y) {
    final c = compare(x.$2, y.$2);
    return c != 0 ? c : x.$1.compareTo(y.$1);
  });
  return [for (final e in indexed) e.$2];
}
