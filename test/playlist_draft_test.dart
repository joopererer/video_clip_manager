import 'package:flutter_test/flutter_test.dart';
import 'package:video_clip_manager/data/models.dart';
import 'package:video_clip_manager/utils/playlist_draft.dart';
import 'package:video_clip_manager/utils/playlist_time.dart';

VideoClip clip(String id, int startMs, int endMs) => VideoClip(
  id: id,
  name: 'clip $id',
  videoPath: 'C:\\视频\\$id.mp4',
  startTime: Duration(milliseconds: startMs),
  endTime: Duration(milliseconds: endMs),
);

PlaylistItem item(
  String id,
  String clipId,
  int order, {
  int? customStart,
  int? customEnd,
}) => PlaylistItem(
  id: id,
  clipId: clipId,
  order: order,
  customStartTime: customStart == null
      ? null
      : Duration(milliseconds: customStart),
  customEndTime: customEnd == null ? null : Duration(milliseconds: customEnd),
);

List<String> ids(PlaylistDraft d) => d.items.map((e) => e.item.id).toList();

void main() {
  final clips = [
    clip('a', 1000, 5000), // 4000 ms
    clip('b', 0, 250), // 250 ms
    clip('c', 10000, 70500), // 60500 ms
    clip('d', 0, 1),
  ];

  List<PlaylistItem> stored() => [
    item('i1', 'a', 0),
    item('i2', 'b', 1),
    item('i3', 'c', 2),
    item('i4', 'd', 3),
  ];

  group('playlist_time', () {
    test('effective duration uses custom range only when both bounds set', () {
      final both = PlaylistItemWithClip(
        item: item('x', 'a', 0, customStart: 1500, customEnd: 2250),
        clip: clips[0],
      );
      final one = PlaylistItemWithClip(
        item: item('x', 'a', 0, customStart: 1500),
        clip: clips[0],
      );
      expect(playlistItemDuration(both), const Duration(milliseconds: 750));
      expect(playlistItemDuration(one), const Duration(milliseconds: 4000));
    });

    test('total is the exact millisecond sum, not whole seconds', () {
      final entries = [
        PlaylistItemWithClip(item: item('1', 'b', 0), clip: clips[1]),
        PlaylistItemWithClip(item: item('2', 'd', 1), clip: clips[3]),
      ];
      expect(playlistTotalDuration(entries).inMilliseconds, 251);
    });

    test('offset is the sum of earlier entries', () {
      final entries = [
        PlaylistItemWithClip(item: item('1', 'a', 0), clip: clips[0]),
        PlaylistItemWithClip(item: item('2', 'b', 1), clip: clips[1]),
        PlaylistItemWithClip(item: item('3', 'c', 2), clip: clips[2]),
      ];
      expect(playlistOffsetOf(entries, 0), Duration.zero);
      expect(playlistOffsetOf(entries, 2).inMilliseconds, 4250);
      expect(playlistOffsetOf(entries, 99).inMilliseconds, 64750);
    });

    test('negative custom range counts as zero', () {
      final bad = PlaylistItemWithClip(
        item: item('x', 'a', 0, customStart: 3000, customEnd: 1000),
        clip: clips[0],
      );
      expect(playlistItemDuration(bad), Duration.zero);
    });

    test('formatting', () {
      expect(formatPlaylistDuration(const Duration(milliseconds: 250)), '0:00');
      expect(
        formatPlaylistDuration(const Duration(milliseconds: 250), millis: true),
        '0:00.250',
      );
      expect(
        formatPlaylistDuration(
          const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 4),
          millis: true,
        ),
        '1:02:03.004',
      );
      expect(formatPlaylistDuration(const Duration(minutes: 90)), '1:30:00');
      expect(formatPlaylistDuration(const Duration(milliseconds: -5)), '0:00');
    });
  });

  group('PlaylistDraft', () {
    test('untouched draft is not dirty', () {
      final d = PlaylistDraft.from(items: stored(), clips: clips);
      expect(d.isDirty, isFalse);
      expect(ids(d), ['i1', 'i2', 'i3', 'i4']);
    });

    test('reorder follows ReorderableListView semantics', () {
      final d = PlaylistDraft.from(items: stored(), clips: clips);
      d.reorder(0, 3); // drag first row below the third row
      expect(ids(d), ['i2', 'i3', 'i1', 'i4']);
      d.reorder(3, 0); // drag last row to the top
      expect(ids(d), ['i4', 'i2', 'i3', 'i1']);
      expect(d.isDirty, isTrue);
    });

    test('several drags then commit persist the full order', () {
      final d = PlaylistDraft.from(items: stored(), clips: clips);
      d.reorder(0, 4); // i2 i3 i4 i1
      d.reorder(2, 0); // i4 i2 i3 i1
      d.reorder(1, 3); // i4 i3 i2 i1
      final saved = d.commit();
      expect(saved.map((e) => e.id), ['i4', 'i3', 'i2', 'i1']);
      expect(saved.map((e) => e.order), [0, 1, 2, 3]);
    });

    test('moving back to the original order is not dirty', () {
      final d = PlaylistDraft.from(items: stored(), clips: clips);
      d.reorder(0, 2);
      d.reorder(1, 0);
      expect(ids(d), ['i1', 'i2', 'i3', 'i4']);
      expect(d.isDirty, isFalse);
    });

    test('remove then reorder then commit', () {
      final d = PlaylistDraft.from(items: stored(), clips: clips);
      expect(d.removeAt(1), isTrue); // i1 i3 i4
      d.reorder(2, 0); // i4 i1 i3
      final saved = d.commit();
      expect(saved.map((e) => e.id), ['i4', 'i1', 'i3']);
      expect(saved.map((e) => e.order), [0, 1, 2]);
      expect(d.removeAt(9), isFalse);
    });

    test('reset restores the loaded state and writes nothing', () {
      final source = stored();
      final d = PlaylistDraft.from(items: source, clips: clips);
      d.reorder(0, 4);
      d.removeAt(0);
      d.reset();
      expect(ids(d), ['i1', 'i2', 'i3', 'i4']);
      expect(d.isDirty, isFalse);
      expect(source.map((e) => e.id), ['i1', 'i2', 'i3', 'i4']);
    });

    test('duplicate or empty item ids are edited by position', () {
      final dup = [
        item('', 'a', 0),
        item('', 'b', 1),
        item('same', 'c', 2),
        item('same', 'd', 3),
      ];
      final d = PlaylistDraft.from(items: dup, clips: clips);
      d.removeAt(3);
      expect(d.items.map((e) => e.clip.id), ['a', 'b', 'c']);
      d.reorder(0, 3);
      expect(d.items.map((e) => e.clip.id), ['b', 'c', 'a']);
    });

    test('commit keeps custom times and every other field', () {
      final custom = [
        item('i1', 'a', 5, customStart: 1500, customEnd: 2250),
        item('i2', 'b', 6),
      ];
      final d = PlaylistDraft.from(items: custom, clips: clips);
      d.reorder(0, 2);
      final saved = d.commit();
      expect(saved[1].id, 'i1');
      expect(saved[1].customStartTime, const Duration(milliseconds: 1500));
      expect(saved[1].customEndTime, const Duration(milliseconds: 2250));
      expect(saved[1].order, 1);
    });

    test('orphan items are kept and appended on commit', () {
      final withOrphan = [
        item('i1', 'a', 0),
        item('gone', 'missing-clip', 1),
        item('i2', 'b', 2),
      ];
      final d = PlaylistDraft.from(items: withOrphan, clips: clips);
      expect(d.length, 2);
      expect(d.orphanCount, 1);
      d.reorder(0, 2);
      final saved = d.commit();
      expect(saved.map((e) => e.id), ['i2', 'i1', 'gone']);
      expect(saved.map((e) => e.order), [0, 1, 2]);
    });

    test('draft total follows the draft, in milliseconds', () {
      final d = PlaylistDraft.from(items: stored(), clips: clips);
      expect(d.totalDuration.inMilliseconds, 4000 + 250 + 60500 + 1);
      d.removeAt(2);
      expect(d.totalDuration.inMilliseconds, 4000 + 250 + 1);
    });

    test('staleness detection compares against the loaded items', () {
      final source = stored();
      final d = PlaylistDraft.from(items: source, clips: clips);
      expect(d.isStale(stored()), isFalse);
      expect(d.isStale([...stored(), item('i5', 'a', 4)]), isTrue);
      expect(d.isStale(stored().reversed.toList()), isTrue);
    });

    test('save then reload through JSON keeps order and metadata', () {
      final original = Playlist(
        id: 'p1',
        name: '名称 テスト',
        description: 'desc',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
        items: stored(),
      );
      final d = PlaylistDraft.from(items: original.items, clips: clips);
      d.reorder(0, 4); // i2 i3 i4 i1
      d.reorder(3, 1); // i2 i1 i3 i4
      d.removeAt(0); // i1 i3 i4
      // Same call AppState.updatePlaylist makes: only `items` is passed.
      final updated = original.copyWith(
        items: d.commit(),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(3000),
      );
      final reloaded = Playlist.fromJson(updated.toJson());
      expect(reloaded.items.map((e) => e.id), ['i1', 'i3', 'i4']);
      expect(reloaded.items.map((e) => e.order), [0, 1, 2]);
      expect(reloaded.name, '名称 テスト');
      expect(reloaded.description, 'desc');
      expect(reloaded.createdAt, original.createdAt);
      final again = PlaylistDraft.from(items: reloaded.items, clips: clips);
      expect(again.isDirty, isFalse);
    });
  });
}
