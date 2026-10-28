import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_clip_manager/data/app_state.dart';
import 'package:video_clip_manager/data/models.dart';
import 'package:video_clip_manager/screens/tabs/playlists_tab.dart';
import 'package:video_clip_manager/services/path_service.dart';
import 'package:video_clip_manager/services/thumbnail_service.dart';
import 'package:video_clip_manager/theme/app_theme.dart';
import 'package:video_clip_manager/utils/playlist_summary.dart';
import 'package:video_clip_manager/widgets/playlist_card_parts.dart';
import 'package:video_clip_manager/widgets/playlist_cards.dart';

class _FakeThumbnailService extends Fake implements ThumbnailService {
  @override
  Future<String?> generateThumbnail(
    String videoPath,
    Duration time,
    String clipId, {
    String? dbPath,
  }) async => null;
}

VideoClip clip(String id, int ms) => VideoClip(
  id: id,
  name: 'Clip $id',
  videoPath: 'https://example.com/$id.mp4',
  endTime: Duration(milliseconds: ms),
);

Playlist playlist(
  String id,
  String name,
  List<PlaylistItem> items, {
  int createdMs = 0,
  String? description,
}) => Playlist(
  id: id,
  name: name,
  description: description,
  createdAt: DateTime.fromMillisecondsSinceEpoch(createdMs),
  updatedAt: DateTime.fromMillisecondsSinceEpoch(createdMs),
  items: items,
);

class _Services {
  _Services(this.dir, this.state, this.paths, this.thumbs);
  final Directory dir;
  final AppState state;
  final PathService paths;
  final ThumbnailService thumbs;
}

Future<_Services> _createServices() async {
  final dir = await Directory.systemTemp.createTemp('playlist_card_test_');
  final db = File('${dir.path}/db.json');
  await db.writeAsString('[]');
  SharedPreferences.setMockInitialValues({'db_path': db.path});
  final prefs = await SharedPreferences.getInstance();
  final paths = PathService();
  final thumbs = _FakeThumbnailService();
  final state = AppState(
    prefs: prefs,
    pathService: paths,
    thumbnailService: thumbs,
  );
  await state.loadInitialData();
  return _Services(dir, state, paths, thumbs);
}

PlaylistItem item(String id, String clipId, int order, {int? cachedMs}) =>
    PlaylistItem(
      id: id,
      clipId: clipId,
      order: order,
      duration: cachedMs == null ? null : Duration(milliseconds: cachedMs),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('summarizePlaylist', () {
    final clips = {'a': clip('a', 4000), 'b': clip('b', 250)};

    test('uses real effective durations, ignoring stale cached ones', () {
      final p = playlist('p', 'P', [
        item('1', 'a', 0, cachedMs: 999999),
        item('2', 'b', 1), // no cached duration at all
      ]);
      final s = summarizePlaylist(p, clips);
      expect(s.duration.inMilliseconds, 4250);
      expect(s.availableCount, 2);
      expect(s.missingCount, 0);
    });

    test('custom range overrides the clip length', () {
      final p = playlist('p', 'P', [
        PlaylistItem(
          id: '1',
          clipId: 'a',
          order: 0,
          customStartTime: const Duration(milliseconds: 500),
          customEndTime: const Duration(milliseconds: 1750),
        ),
      ]);
      expect(summarizePlaylist(p, clips).duration.inMilliseconds, 1250);
    });

    test('missing clips are counted but add no time', () {
      final p = playlist('p', 'P', [item('1', 'a', 0), item('2', 'gone', 1)]);
      final s = summarizePlaylist(p, clips);
      expect(s.storedCount, 2);
      expect(s.availableCount, 1);
      expect(s.missingCount, 1);
      expect(s.duration.inMilliseconds, 4000);
    });

    test('empty playlist', () {
      final s = summarizePlaylist(playlist('p', 'P', []), clips);
      expect(s.duration, Duration.zero);
      expect(s.availableCount, 0);
    });
  });

  group('playlistGridMetrics', () {
    test('adapts columns to the width, within 2..6', () {
      expect(playlistGridMetrics(500).columns, 2);
      expect(playlistGridMetrics(868).columns, 3); // 900 px window, content
      expect(playlistGridMetrics(1000).columns, 4);
      expect(playlistGridMetrics(1240).columns, 5);
      expect(playlistGridMetrics(1700).columns, 6);
      expect(playlistGridMetrics(4000).columns, 6);
    });

    test('tiles never get narrower than the minimum except at 2 columns', () {
      for (var w = 600.0; w <= 2400; w += 37) {
        final m = playlistGridMetrics(w);
        expect(m.tileWidth, greaterThanOrEqualTo(220 - 1e-9), reason: '$w');
        expect(
          m.tileWidth * m.columns + 16 * (m.columns - 1),
          closeTo(w, 1e-6),
        );
      }
    });

    test('tile height is a 16:9 cover plus the footer', () {
      final m = playlistGridMetrics(1000);
      expect(m.tileHeight, closeTo(m.tileWidth * 9 / 16 + 88, 1e-9));
      expect(m.aspectRatio, closeTo(m.tileWidth / m.tileHeight, 1e-12));
    });

    test('unbounded or zero width does not throw', () {
      expect(playlistGridMetrics(double.infinity).columns, 2);
      expect(playlistGridMetrics(0).columns, 2);
    });
  });

  group('sortPlaylistEntries', () {
    // Entries pair a playlist with its real duration; ids may collide in
    // legacy data, so sorting must not look anything up by id.
    final a = (playlist('a', 'beta', [], createdMs: 100), 5);
    final b = (playlist('b', 'Alpha', [], createdMs: 300), 1);
    final c = (playlist('c', 'gamma', [], createdMs: 200), 9);

    List<(Playlist, int)> sorted(List<(Playlist, int)> input, String by) =>
        sortPlaylistEntries<(Playlist, int)>(
          input,
          by,
          playlistOf: (e) => e.$1,
          durationOf: (e) => Duration(seconds: e.$2),
        );

    List<String> ids(String by) =>
        sorted([a, b, c], by).map((e) => e.$1.id).toList();

    test('by name ignores case', () => expect(ids('name'), ['b', 'a', 'c']));
    test('by date is newest first', () => expect(ids('date'), ['b', 'c', 'a']));
    test(
      'by duration is longest first, from real durations',
      () => expect(ids('duration'), ['c', 'a', 'b']),
    );
    test('unknown key falls back to name', () {
      expect(ids('???'), ['b', 'a', 'c']);
    });
    test('does not mutate the input', () {
      final input = [a, b, c];
      sorted(input, 'name');
      expect(input.map((e) => e.$1.id), ['a', 'b', 'c']);
    });
    test('equal keys keep their original order, even with duplicate ids', () {
      final x = (playlist('same', 'Same', [], createdMs: 1), 3);
      final y = (playlist('same', 'same', [], createdMs: 1), 3);
      final z = (playlist('same', 'SAME', [], createdMs: 1), 3);
      for (final by in ['name', 'date', 'duration']) {
        expect(sorted([y, z, x], by), [y, z, x], reason: by);
      }
    });
  });

  group('DoubleTapTracker', () {
    testWidgets('second tap inside the window counts, then resets', (
      tester,
    ) async {
      final t = DoubleTapTracker();
      addTearDown(t.dispose);
      expect(t.registerTap(), isFalse);
      await tester.pump(const Duration(milliseconds: 200));
      expect(t.registerTap(), isTrue);
      await tester.pump(const Duration(milliseconds: 100));
      expect(t.registerTap(), isFalse); // a third tap starts over
      t.dispose(); // cancels the open window so no timer outlives the test
    });

    testWidgets('slow second tap only starts a new window', (tester) async {
      final t = DoubleTapTracker();
      addTearDown(t.dispose);
      expect(t.registerTap(), isFalse);
      await tester.pump(const Duration(milliseconds: 800));
      expect(t.registerTap(), isFalse);
      await tester.pump(const Duration(milliseconds: 200));
      expect(t.registerTap(), isTrue);
    });
  });

  group('PlaylistGridCard interactions', () {
    late List<String> log;

    Future<void> pumpCard(WidgetTester tester) async {
      log = [];
      final c1 = clip('a', 4000);
      final data = PlaylistCardData(
        playlist: playlist('p', 'My list', [item('1', 'a', 0)]),
        summary: const PlaylistSummary(
          storedCount: 1,
          availableCount: 1,
          duration: Duration(seconds: 4),
        ),
        entries: [PlaylistItemWithClip(item: item('1', 'a', 0), clip: c1)],
      );
      final services = await tester.runAsync(_createServices);
      addTearDown(() async {
        await services!.state.forceSave();
        services.state.dispose();
        await services.dir.delete(recursive: true);
      });
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<PathService>.value(value: services!.paths),
            Provider<ThumbnailService>.value(value: services.thumbs),
            ChangeNotifierProvider<AppState>.value(value: services.state),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 280,
                  height: 240,
                  child: PlaylistGridCard(
                    data: data,
                    selected: false,
                    onSelect: () => log.add('select'),
                    onAction: (a) => log.add(a.name),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('single click selects without playing', (tester) async {
      await pumpCard(tester);
      await tester.tapAt(
        tester.getTopLeft(find.byType(PlaylistGridCard)) + const Offset(20, 20),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(log, ['select']);
    });

    testWidgets('double click plays', (tester) async {
      await pumpCard(tester);
      final p =
          tester.getTopLeft(find.byType(PlaylistGridCard)) +
          const Offset(20, 20);
      await tester.tapAt(p);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(p);
      await tester.pump(const Duration(milliseconds: 600));
      expect(log, ['select', 'select', 'play']);
    });

    testWidgets('two slow clicks never play', (tester) async {
      await pumpCard(tester);
      final p =
          tester.getTopLeft(find.byType(PlaylistGridCard)) +
          const Offset(20, 20);
      await tester.tapAt(p);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tapAt(p);
      await tester.pump(const Duration(milliseconds: 700));
      expect(log, ['select', 'select']);
    });

    testWidgets('right click selects and offers the menu actions', (
      tester,
    ) async {
      await pumpCard(tester);
      final p =
          tester.getTopLeft(find.byType(PlaylistGridCard)) +
          const Offset(30, 30);
      final g = await tester.startGesture(
        p,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await g.up();
      await tester.pumpAndSettle();
      expect(log, ['select']);
      for (final label in ['播放', '重命名 / 编辑信息', '管理片段与顺序', '导出', '删除播放列表']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      await tester.tap(find.text('管理片段与顺序'));
      await tester.pumpAndSettle();
      expect(log, ['select', 'manage']);
    });

    testWidgets('more button shows the same menu', (tester) async {
      await pumpCard(tester);
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('导出'));
      await tester.pumpAndSettle();
      expect(log, ['export']);
    });
  });

  group('PlaylistsTab', () {
    late Directory tempDir;
    late AppState state;
    late PathService pathService;
    late ThumbnailService thumbs;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('playlists_tab_test_');
      final db = File('${tempDir.path}/db.json');
      await db.writeAsString('[]');
      SharedPreferences.setMockInitialValues({'db_path': db.path});
      final prefs = await SharedPreferences.getInstance();
      pathService = PathService();
      thumbs = _FakeThumbnailService();
      state = AppState(
        prefs: prefs,
        pathService: pathService,
        thumbnailService: thumbs,
      );
      await state.loadInitialData();
      for (var i = 1; i <= 3; i++) {
        await state.addClip(clip('c$i', 1000 * i + 7));
      }
      // Playlist.create derives its id from the current millisecond, so wait
      // between calls to get distinct ids (real time: this is setUp work).
      Future<void> create(String name, {String? description}) async {
        state.createPlaylist(name, description: description);
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      await create('Alpha 播放列表', description: '第一个');
      await create('Beta');
      await create('Gamma');
      expect(state.playlists.map((p) => p.id).toSet().length, 3);
      for (final p in state.playlists) {
        for (var i = 1; i <= 3; i++) {
          state.addClipToPlaylist(p.id, 'c$i');
        }
      }
    });

    tearDown(() async {
      await state.forceSave();
      state.dispose();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    Future<void> pumpTab(
      WidgetTester tester,
      Size size, {
      bool grid = true,
      String query = '',
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      state.setPlaylistsViewMode(grid);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<PathService>.value(value: pathService),
            Provider<ThumbnailService>.value(value: thumbs),
            ChangeNotifierProvider<AppState>.value(value: state),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(body: PlaylistsTab(searchQuery: query)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final size in const [
      Size(900, 700),
      Size(1280, 800),
      Size(1600, 900),
    ]) {
      for (final grid in [true, false]) {
        testWidgets(
          'no overflow at ${size.width.toInt()}x${size.height.toInt()} '
          '(${grid ? 'grid' : 'list'})',
          (tester) async {
            await pumpTab(tester, size, grid: grid);
            expect(tester.takeException(), isNull);
            expect(
              find.byType(grid ? PlaylistGridCard : PlaylistListRow),
              findsNWidgets(3),
            );
          },
        );
      }
    }

    testWidgets('header shows real totals and create button', (tester) async {
      await pumpTab(tester, const Size(1280, 800));
      expect(find.text('播放列表  3'), findsOneWidget);
      expect(find.text('总片段  9'), findsOneWidget);
      // 3 lists x (1.007 + 2.007 + 3.007 s) = 18.021 s
      expect(find.text('总时长  0:18'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '创建播放列表'), findsOneWidget);
    });

    testWidgets('search filters by name and description', (tester) async {
      await pumpTab(tester, const Size(1280, 800), query: '第一个');
      expect(find.byType(PlaylistGridCard), findsOneWidget);
      expect(find.text('Alpha 播放列表'), findsOneWidget);
    });

    testWidgets('search with no hit shows the filtered empty state', (
      tester,
    ) async {
      await pumpTab(tester, const Size(1280, 800), query: 'zzz');
      expect(find.text('没有匹配的播放列表'), findsOneWidget);
    });

    testWidgets('view toggle persists the choice in AppState', (tester) async {
      await pumpTab(tester, const Size(1280, 800), grid: true);
      await tester.tap(find.byTooltip('切换为列表视图'));
      await tester.pumpAndSettle();
      expect(state.playlistsIsGridView, isFalse);
      expect(find.byType(PlaylistListRow), findsNWidgets(3));
    });

    testWidgets('delete asks for confirmation and keeps the clips', (
      tester,
    ) async {
      await pumpTab(tester, const Size(1280, 800), grid: false);
      await tester.tap(find.byTooltip('更多操作').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除播放列表'));
      await tester.pumpAndSettle();
      expect(find.text('确认删除'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(state.playlists.length, 3);

      await tester.tap(find.byTooltip('更多操作').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除播放列表'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      expect(state.playlists.length, 2);
      expect(state.clips.length, 3);
      await tester.runAsync(state.forceSave); // flush the debounced save timer
    });

    testWidgets('empty library shows the create prompt', (tester) async {
      for (final p in List.of(state.playlists)) {
        state.deletePlaylist(p.id);
      }
      await tester.runAsync(state.forceSave); // flush the debounced save timer
      await pumpTab(tester, const Size(900, 700));
      expect(find.text('暂无播放列表'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
