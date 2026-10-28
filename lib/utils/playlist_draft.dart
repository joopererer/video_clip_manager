import '../data/models.dart';
import 'playlist_time.dart';

/// Transactional local draft of a playlist's items.
///
/// All edits stay in memory until the caller commits [commit] to AppState in
/// one `updatePlaylist(id, items: ...)` call. Reset and discard never touch
/// AppState. Entries are addressed by position, not id, because legacy data
/// may contain empty or duplicate item ids.
///
/// Items whose clip no longer exists are not shown (same as
/// `AppState.getPlaylistItemsWithClips`). They are kept as orphans and written
/// back by [commit] so saving never deletes data the user could not see.
class PlaylistDraft {
  PlaylistDraft._(this._base, this._baseline, this._orphans)
    : _items = List.of(_baseline);

  /// Builds a draft from the stored [items] and the known [clips].
  factory PlaylistDraft.from({
    required List<PlaylistItem> items,
    required Iterable<VideoClip> clips,
  }) {
    final byId = <String, VideoClip>{};
    for (final c in clips) {
      byId.putIfAbsent(c.id, () => c);
    }
    final visible = <PlaylistItemWithClip>[];
    final orphans = <PlaylistItem>[];
    for (final item in items) {
      final clip = byId[item.clipId];
      if (clip == null) {
        orphans.add(item);
      } else {
        visible.add(PlaylistItemWithClip(item: item, clip: clip));
      }
    }
    return PlaylistDraft._(List.unmodifiable(items), visible, orphans);
  }

  /// Stored items at the time the draft was created (including orphans).
  final List<PlaylistItem> _base;
  final List<PlaylistItemWithClip> _baseline;
  final List<PlaylistItem> _orphans;
  List<PlaylistItemWithClip> _items;

  /// Current editable entries.
  List<PlaylistItemWithClip> get items => List.unmodifiable(_items);

  int get length => _items.length;

  /// Number of stored items hidden because their clip is missing.
  int get orphanCount => _orphans.length;

  /// Total effective length of the current draft, in milliseconds.
  Duration get totalDuration => playlistTotalDuration(_items);

  /// Whether the draft differs from what was loaded.
  bool get isDirty {
    if (_items.length != _baseline.length) return true;
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].item != _baseline[i].item) return true;
    }
    return false;
  }

  /// Moves an entry using `ReorderableListView.onReorder` semantics
  /// ([newIndex] is the position before the removal shift).
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _items.length) return;
    var target = newIndex.clamp(0, _items.length);
    if (oldIndex < target) target -= 1;
    moveTo(oldIndex, target);
  }

  /// Moves an entry so it ends at [finalIndex] in the resulting list.
  void moveTo(int from, int finalIndex) {
    if (from < 0 || from >= _items.length) return;
    final to = finalIndex.clamp(0, _items.length - 1);
    if (to == from) return;
    final next = List.of(_items);
    next.insert(to, next.removeAt(from));
    _items = next;
  }

  /// Removes the entry at [index]. Returns false if out of range.
  bool removeAt(int index) {
    if (index < 0 || index >= _items.length) return false;
    _items = List.of(_items)..removeAt(index);
    return true;
  }

  /// Discards all edits and returns to the loaded state.
  void reset() => _items = List.of(_baseline);

  /// Items to persist: visible entries in draft order with `order` renumbered
  /// from zero, followed by hidden orphans (unchanged except for `order`).
  /// Other fields, including custom times, are left as stored.
  List<PlaylistItem> commit() {
    final all = [..._items.map((e) => e.item), ..._orphans];
    return [for (var i = 0; i < all.length; i++) all[i].copyWith(order: i)];
  }

  /// True when [current] stored items differ from the ones this draft was
  /// created from, e.g. clips were added to the playlist elsewhere. Saving a
  /// stale draft would overwrite those changes.
  bool isStale(List<PlaylistItem> current) {
    if (current.length != _base.length) return true;
    for (var i = 0; i < current.length; i++) {
      if (current[i] != _base[i]) return true;
    }
    return false;
  }
}
