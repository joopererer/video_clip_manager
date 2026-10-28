import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_clip_manager/data/app_state.dart';
import 'package:video_clip_manager/data/models.dart';
import 'package:video_clip_manager/screens/playlist/playlist_management_screen.dart';
import 'package:video_clip_manager/services/path_service.dart';
import 'package:video_clip_manager/services/thumbnail_service.dart';
import 'package:video_clip_manager/theme/app_theme.dart';

class _FakeThumbnailService extends Fake implements ThumbnailService {
  @override
  Future<String?> generateThumbnail(
    String videoPath,
    Duration time,
    String clipId, {
    String? dbPath,
  }) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppState state;
  late PathService pathService;
  late ThumbnailService thumbs;
  late String playlistId;

  setUp(() async {
    // Online URLs make ClipThumbnail skip any local file / preview lookups.
    tempDir = await Directory.systemTemp.createTemp('playlist_mgmt_test_');
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
    for (var i = 1; i <= 4; i++) {
      await state.addClip(
        VideoClip(
          id: 'c$i',
          name: 'Clip $i',
          videoPath: 'https://example.com/v$i.mp4',
          startTime: Duration.zero,
          endTime: Duration(milliseconds: 1000 * i + 7),
        ),
      );
    }
    state.createPlaylist('测试列表');
    playlistId = state.playlists.last.id;
    for (var i = 1; i <= 4; i++) {
      state.addClipToPlaylist(playlistId, 'c$i');
    }
  });

  tearDown(() async {
    await state.forceSave();
    state.dispose();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Playlist stored() => state.playlists.firstWhere((p) => p.id == playlistId);
  List<String> storedOrder() => stored().items.map((e) => e.clipId).toList();

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<PathService>.value(value: pathService),
          Provider<ThumbnailService>.value(value: thumbs),
          ChangeNotifierProvider<AppState>.value(value: state),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          PlaylistManagementScreen(playlist: stored()),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> removeFirstRow(WidgetTester tester) async {
    await tester.tap(find.byTooltip('从草稿移除').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '移除'));
    await tester.pumpAndSettle();
  }

  testWidgets('clean screen leaves without a prompt', (tester) async {
    await open(tester);
    expect(find.text('管理播放列表'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('有未保存的更改'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('removing marks dirty and does not touch AppState', (
    tester,
  ) async {
    await open(tester);
    await removeFirstRow(tester);
    expect(find.text('有未保存的更改'), findsOneWidget); // toolbar subtitle
    expect(storedOrder(), ['c1', 'c2', 'c3', 'c4']);
    expect(find.text('3 个片段'), findsOneWidget);
  });

  testWidgets('back with edits: keep editing stays on the screen', (
    tester,
  ) async {
    await open(tester);
    await removeFirstRow(tester);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('播放列表的顺序或片段已修改但尚未保存。离开前要保存吗？'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(find.text('管理播放列表'), findsNothing); // subtitle shows dirty text
    expect(find.text('3 个片段'), findsOneWidget);
    expect(storedOrder(), ['c1', 'c2', 'c3', 'c4']);
  });

  testWidgets('back with edits: discard leaves and writes nothing', (
    tester,
  ) async {
    await open(tester);
    await removeFirstRow(tester);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃更改'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(storedOrder(), ['c1', 'c2', 'c3', 'c4']);
  });

  testWidgets('back with edits: save and leave persists the draft', (
    tester,
  ) async {
    await open(tester);
    await removeFirstRow(tester);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存并离开'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(storedOrder(), ['c2', 'c3', 'c4']);
  });

  testWidgets('reset restores the list without writing', (tester) async {
    await open(tester);
    await removeFirstRow(tester);
    await tester.tap(find.text('重置'));
    await tester.pumpAndSettle();
    expect(find.text('4 个片段'), findsOneWidget);
    expect(find.text('管理播放列表'), findsOneWidget);
    expect(storedOrder(), ['c1', 'c2', 'c3', 'c4']);
  });

  testWidgets('drag handle reorders the draft and save writes all of it', (
    tester,
  ) async {
    await open(tester);
    final handles = find.byIcon(Icons.drag_indicator);
    expect(handles, findsNWidgets(4));
    // Drag the first row below the third row.
    await tester.drag(handles.first, const Offset(0, 190));
    await tester.pumpAndSettle();
    // Drag the new last row to the top.
    await tester.drag(
      find.byIcon(Icons.drag_indicator).last,
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();

    expect(storedOrder(), ['c1', 'c2', 'c3', 'c4']); // nothing written yet
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final saved = storedOrder();
    expect(saved.toSet(), {'c1', 'c2', 'c3', 'c4'});
    expect(saved, isNot(['c1', 'c2', 'c3', 'c4']));
    expect(stored().items.map((e) => e.order), [0, 1, 2, 3]);
    expect(find.text('管理播放列表'), findsOneWidget); // clean again
  });

  testWidgets('no layout overflow at 900x700 with a long title', (
    tester,
  ) async {
    state.updatePlaylist(playlistId, name: '很长的播放列表名称 ' * 8);
    await open(tester, size: const Size(900, 700));
    await removeFirstRow(tester);
    expect(tester.takeException(), isNull);
  });
}
