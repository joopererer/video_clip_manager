import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_clip_manager/data/app_state.dart';
import 'package:video_clip_manager/data/models.dart';
import 'package:video_clip_manager/screens/tabs/clips_tab.dart';
import 'package:video_clip_manager/services/delta_engine.dart';
import 'package:video_clip_manager/services/path_service.dart';
import 'package:video_clip_manager/services/thumbnail_service.dart';
import 'package:video_clip_manager/theme/app_theme.dart';
import 'package:video_clip_manager/widgets/clip_card.dart';
import 'package:video_clip_manager/widgets/clip_list_row.dart';

class _NoThumbs extends Fake implements ThumbnailService {
  @override
  Future<String?> generateThumbnail(
    String videoPath,
    Duration time,
    String clipId, {
    String? dbPath,
  }) async => null;
}

// 不存在的本地路径：避免使用网络盘符（Windows 上检查不可达驱动器会长时间阻塞）。
const _localMissing = 'vcm_missing_eval_clip.mp4';

VideoClip _clip(String id, String name, {int hitMs = 0}) => VideoClip(
  id: id,
  name: name,
  videoPath: _localMissing,
  endTime: const Duration(seconds: 5),
  hitTimestampMs: hitMs == 0 ? null : hitMs,
);

Future<AppState> _appState(List<VideoClip> clips) async {
  final tempDir = await Directory.systemTemp.createTemp('score_display_');
  final dbFile = File('${tempDir.path}/db.json');
  await dbFile.writeAsString('[]');
  SharedPreferences.setMockInitialValues({'db_path': dbFile.path});
  final prefs = await SharedPreferences.getInstance();
  final appState = AppState(
    prefs: prefs,
    pathService: PathService(),
    thumbnailService: _NoThumbs(),
  );
  await appState.loadInitialData();
  for (final clip in clips) {
    await appState.addClip(clip);
  }
  return appState;
}

Future<void> _pumpTab(
  WidgetTester tester,
  AppState appState, {
  String query = '',
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MultiProvider(
      providers: [ChangeNotifierProvider<AppState>.value(value: appState)],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: ClipsTab(searchQuery: query, selectedTags: const []),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  await tester.pump();
}

List<String> _gridOrder(WidgetTester tester) => tester
    .widgetList<ClipCard>(find.byType(ClipCard))
    .map((c) => c.clip.id)
    .toList();

List<String> _listOrder(WidgetTester tester) => tester
    .widgetList<ClipListRow>(find.byType(ClipListRow))
    .map((c) => c.clip.id)
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('semantic score rendering', () {
    testWidgets('grid card shows Score directly below the HIT timecode', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 340,
              child: ClipCard(
                clip: _clip('c1', 'snow', hitMs: 183000),
                semanticScore: 0.8632,
                onPlay: () {},
                onEdit: () {},
                onDelete: () {},
                onAddToPlaylist: () {},
                onRatingChanged: (_) {},
                onFavoriteToggled: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Score: 0.863'), findsOneWidget);
      final hit = find.text('03:03');
      expect(hit, findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Score: 0.863')).dy,
        greaterThan(tester.getTopLeft(hit).dy),
        reason: 'Score sits below the HIT marker',
      );
    });

    testWidgets('grid card hides Score for keyword-only results', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 340,
              child: ClipCard(
                clip: _clip('c1', 'snow'),
                onPlay: () {},
                onEdit: () {},
                onDelete: () {},
                onAddToPlaylist: () {},
                onRatingChanged: (_) {},
                onFavoriteToggled: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('Score:'), findsNothing);
      expect(find.textContaining('命中'), findsNothing);
    });

    testWidgets('list row shows Score below the 命中 marker and keeps actions', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: SizedBox(
              width: 1100,
              height: 96,
              child: ClipListRow(
                clip: _clip('c1', 'snow', hitMs: 46000),
                semanticScore: 0.8123,
                onPlay: () {},
                onEdit: () {},
                onDelete: () {},
                onAddToPlaylist: () {},
                onRatingChanged: (_) {},
                onFavoriteToggled: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Score: 0.812'), findsOneWidget);
      expect(find.text('命中: 00:46'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Score: 0.812')).dy,
        greaterThan(tester.getTopLeft(find.text('命中: 00:46')).dy),
      );
      // Right-hand action buttons stay reachable.
      expect(find.byTooltip('播放'), findsOneWidget);
      expect(find.byTooltip('编辑'), findsOneWidget);
      expect(find.byTooltip('更多选项'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('ClipsTab semantic results', () {
    testWidgets('grid mode: banner, default relevance sort, real scores', (
      tester,
    ) async {
      late AppState appState;
      await tester.runAsync(() async {
        appState = await _appState([
          _clip('c1', 'alpha'),
          _clip('c2', 'beta'),
          _clip('c3', 'gamma'),
        ]);
        appState.setClipsViewMode(true);
        appState.debugSetSemanticScores({
          'c1': const MaxSimResult(score: 0.41, hitTimestampMs: 1000),
          'c2': const MaxSimResult(score: 0.92, hitTimestampMs: 2000),
          'c3': const MaxSimResult(score: 0.63, hitTimestampMs: 3000),
        }, query: '雪山');
      });

      await _pumpTab(tester, appState, query: '雪山');

      expect(find.textContaining('AI 语义搜索结果'), findsOneWidget);
      expect(find.textContaining('「雪山」'), findsOneWidget);
      expect(find.text('相关度最高'), findsOneWidget);
      expect(_gridOrder(tester), ['c2', 'c3', 'c1']);
      expect(find.text('Score: 0.920'), findsOneWidget);
      expect(find.text('Score: 0.630'), findsOneWidget);
      expect(find.text('Score: 0.410'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('list mode shows the same scores as grid mode', (tester) async {
      late AppState appState;
      await tester.runAsync(() async {
        appState = await _appState([_clip('c1', 'alpha')]);
        appState.setClipsViewMode(false);
        appState.debugSetSemanticScores({
          'c1': const MaxSimResult(score: 0.8632, hitTimestampMs: 24000),
        }, query: '雪山');
      });

      await _pumpTab(tester, appState, query: '雪山');

      expect(_listOrder(tester), ['c1']);
      expect(find.text('Score: 0.863'), findsOneWidget);
      expect(find.text('命中: 00:24'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keyword-only search shows no Score at all', (tester) async {
      late AppState appState;
      await tester.runAsync(() async {
        appState = await _appState([_clip('c1', 'snow mountain')]);
        appState.setClipsViewMode(true);
      });

      await _pumpTab(tester, appState, query: 'snow');

      expect(find.byType(ClipCard), findsOneWidget);
      expect(find.textContaining('Score:'), findsNothing);
      expect(find.textContaining('AI 语义搜索结果'), findsNothing);
    });

    testWidgets('switching sort keeps HIT time and Score intact', (
      tester,
    ) async {
      late AppState appState;
      await tester.runAsync(() async {
        appState = await _appState([_clip('c1', 'zulu'), _clip('c2', 'alpha')]);
        appState.setClipsViewMode(true);
        appState.debugSetSemanticScores({
          'c1': const MaxSimResult(score: 0.30, hitTimestampMs: 1000),
          'c2': const MaxSimResult(score: 0.90, hitTimestampMs: 2000),
        }, query: '雪山');
      });

      await _pumpTab(tester, appState, query: '雪山');
      expect(_gridOrder(tester), ['c2', 'c1']);

      await tester.tap(find.text('相关度最高'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('名称 (A-Z)').last);
      await tester.pumpAndSettle();

      expect(_gridOrder(tester), ['c2', 'c1'], reason: 'alpha before zulu');
      expect(find.text('Score: 0.900'), findsOneWidget);
      expect(find.text('Score: 0.300'), findsOneWidget);
      expect(find.text('00:02'), findsWidgets);
    });

    testWidgets('clearing the AI result restores plain keyword filtering', (
      tester,
    ) async {
      late AppState appState;
      await tester.runAsync(() async {
        appState = await _appState([_clip('c1', 'snow')]);
        appState.setClipsViewMode(true);
        appState.debugSetSemanticScores({
          'c1': const MaxSimResult(score: 0.5, hitTimestampMs: 1000),
        }, query: '雪山');
      });

      await _pumpTab(tester, appState, query: '雪山');
      expect(find.text('Score: 0.500'), findsOneWidget);

      await tester.tap(find.text('清除 AI 结果'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Score:'), findsNothing);
      expect(find.textContaining('AI 语义搜索结果'), findsNothing);
      expect(appState.semanticScores, isEmpty);
    });
  });
}
