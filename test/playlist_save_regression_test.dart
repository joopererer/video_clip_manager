import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_clip_manager/data/app_state.dart';
import 'package:video_clip_manager/data/models.dart';
import 'package:video_clip_manager/services/path_service.dart';
import 'package:video_clip_manager/services/thumbnail_service.dart';
import 'package:video_clip_manager/utils/playlist_draft.dart';

class _FakeThumbnailService extends Fake implements ThumbnailService {
  @override
  Future<String?> generateThumbnail(
    String videoPath,
    Duration time,
    String clipId, {
    String? dbPath,
  }) async => null;
}

Future<AppState> _open(File db) async {
  SharedPreferences.setMockInitialValues({'db_path': db.path});
  final prefs = await SharedPreferences.getInstance();
  final state = AppState(
    prefs: prefs,
    pathService: PathService(),
    thumbnailService: _FakeThumbnailService(),
  );
  await state.loadInitialData();
  return state;
}

Playlist _playlist(AppState s, String id) =>
    s.playlists.firstWhere((p) => p.id == id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File db;
  late AppState state;
  late String playlistId;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('playlist_save_test_');
    db = File('${tempDir.path}/test_db.json');
    await db.writeAsString('[]');
    state = await _open(db);

    for (var i = 1; i <= 5; i++) {
      await state.addClip(
        VideoClip(
          id: 'c$i',
          name: 'Clip $i',
          videoPath: 'C:\\视频\\v$i.mp4',
          startTime: Duration.zero,
          endTime: Duration(milliseconds: 1000 * i + 7),
        ),
      );
    }
    state.createPlaylist('我的列表', description: 'original description');
    playlistId = state.playlists.last.id;
    for (var i = 1; i <= 5; i++) {
      state.addClipToPlaylist(playlistId, 'c$i');
    }
  });

  tearDown(() async {
    await state.forceSave();
    state.dispose();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  PlaylistDraft draftOf(AppState s) =>
      PlaylistDraft.from(items: _playlist(s, playlistId).items, clips: s.clips);

  List<String> clipOrder(Playlist p) => p.items.map((e) => e.clipId).toList();

  test('baseline: playlist holds the five clips in insertion order', () {
    expect(clipOrder(_playlist(state, playlistId)), [
      'c1',
      'c2',
      'c3',
      'c4',
      'c5',
    ]);
  });

  test('several drags are all saved in one commit', () async {
    final draft = draftOf(state);
    draft.reorder(0, 5); // c2 c3 c4 c5 c1
    draft.reorder(3, 0); // c5 c2 c3 c4 c1
    draft.reorder(1, 4); // c5 c3 c4 c2 c1

    state.updatePlaylist(playlistId, items: draft.commit());

    final saved = _playlist(state, playlistId);
    expect(clipOrder(saved), ['c5', 'c3', 'c4', 'c2', 'c1']);
    expect(saved.items.map((e) => e.order), [0, 1, 2, 3, 4]);
  });

  test('remove then reorder, then reload from disk', () async {
    final draft = draftOf(state);
    draft.removeAt(1); // c1 c3 c4 c5
    draft.reorder(3, 0); // c5 c1 c3 c4
    state.updatePlaylist(playlistId, items: draft.commit());
    await state.forceSave();

    final reloaded = await _open(db);
    addTearDown(reloaded.dispose);
    final p = _playlist(reloaded, playlistId);
    expect(clipOrder(p), ['c5', 'c1', 'c3', 'c4']);
    expect(p.items.map((e) => e.order), [0, 1, 2, 3]);
    // The clip itself is never deleted by removing it from a playlist.
    expect(reloaded.clips.any((c) => c.id == 'c2'), isTrue);
  });

  test('save keeps name, description and createdAt', () {
    final before = _playlist(state, playlistId);
    final draft = draftOf(state)..reorder(0, 3);
    state.updatePlaylist(playlistId, items: draft.commit());
    final after = _playlist(state, playlistId);
    expect(after.name, '我的列表');
    expect(after.description, 'original description');
    expect(after.createdAt, before.createdAt);
    expect(after.id, before.id);
  });

  test('custom ranges survive a reorder save', () {
    final p = _playlist(state, playlistId);
    final edited = p.items
        .map(
          (e) => e.clipId == 'c3'
              ? e.copyWith(
                  customStartTime: const Duration(milliseconds: 250),
                  customEndTime: const Duration(milliseconds: 1750),
                )
              : e,
        )
        .toList();
    state.updatePlaylist(playlistId, items: edited);

    final draft = draftOf(state)..reorder(2, 0);
    state.updatePlaylist(playlistId, items: draft.commit());

    final c3 = _playlist(state, playlistId).items.first;
    expect(c3.clipId, 'c3');
    expect(c3.customStartTime, const Duration(milliseconds: 250));
    expect(c3.customEndTime, const Duration(milliseconds: 1750));
  });

  test('reset and discard never write to AppState', () {
    final snapshot = _playlist(state, playlistId);
    var notifications = 0;
    state.addListener(() => notifications++);

    final draft = draftOf(state);
    draft.reorder(0, 5);
    draft.removeAt(2);
    draft.reset();
    // Discarding = dropping the draft without calling commit/updatePlaylist.
    draft.reorder(1, 4);

    expect(notifications, 0);
    expect(_playlist(state, playlistId), snapshot);
  });

  test('stale draft is detected after an outside change', () {
    final draft = draftOf(state)..reorder(0, 3);
    state.addClipToPlaylist(playlistId, 'c1'); // ignored: already present
    expect(draft.isStale(_playlist(state, playlistId).items), isFalse);

    state.removePlaylistItem(
      playlistId,
      _playlist(state, playlistId).items.first.id,
    );
    expect(draft.isStale(_playlist(state, playlistId).items), isTrue);
  });

  test('items whose clip was deleted are not lost on save', () async {
    final p = _playlist(state, playlistId);
    final withGhost = [
      ...p.items,
      PlaylistItem(id: 'ghost', clipId: 'deleted-clip', order: 5),
    ];
    state.updatePlaylist(playlistId, items: withGhost);

    final draft = draftOf(state)..reorder(0, 5);
    state.updatePlaylist(playlistId, items: draft.commit());

    final saved = _playlist(state, playlistId);
    expect(saved.items.last.id, 'ghost');
    expect(saved.items.length, 6);
  });
}
