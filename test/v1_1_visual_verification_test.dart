import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_clip_manager/app_info.dart';
import 'package:video_clip_manager/data/app_state.dart';
import 'package:video_clip_manager/data/models.dart';
import 'package:video_clip_manager/screens/tabs/clips_tab.dart';
import 'package:video_clip_manager/services/delta_engine.dart';
import 'package:video_clip_manager/services/path_service.dart';
import 'package:video_clip_manager/services/thumbnail_service.dart';
import 'package:video_clip_manager/services/update_service.dart';
import 'package:video_clip_manager/theme/app_theme.dart';
import 'package:video_clip_manager/widgets/about_dialog.dart';
import 'package:video_clip_manager/widgets/common/app_header.dart';

class _NoThumbs extends Fake implements ThumbnailService {
  @override
  Future<String?> generateThumbnail(
    String videoPath,
    Duration time,
    String clipId, {
    String? dbPath,
  }) async => null;
}

class _StubUpdateService extends UpdateService {
  _StubUpdateService(this.result);
  final UpdateCheckResult result;

  @override
  Future<UpdateCheckResult> checkForUpdate({
    required String currentVersion,
  }) async => result;
}

const _outDir = 'docs/ui-upgrade/screenshots/v1_1';

Future<void> _capture(
  WidgetTester tester,
  Widget widget,
  String fileName, {
  Size size = const Size(1280, 760),
  Future<void> Function()? beforeCapture,
}) async {
  final key = GlobalKey();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: RepaintBoundary(key: key, child: widget),
    ),
  );
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pump();
  if (beforeCapture != null) await beforeCapture();
  await tester.pump();

  final boundary =
      key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary != null) {
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      if (bytes != null) {
        final file = File('$_outDir/$fileName');
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(bytes.buffer.asUint8List());
      }
    });
  }
  await tester.pumpWidget(const SizedBox());
}

Widget _header({
  required TextEditingController controller,
  required String text,
  bool searching = false,
  int count = 0,
}) {
  controller.text = text;
  return AppHeader(
    title: '片段库',
    searchController: controller,
    onSearchChanged: (_) {},
    onSearchSubmitted: (_) {},
    onClearSearch: () {},
    isSemanticSearching: searching,
    hasSemanticScores: count > 0,
    semanticResultCount: count,
    onTriggerSemanticSearch: () {},
    onRefreshThumbnails: () {},
    onImportMerge: () {},
    onSwitchDb: () {},
    onOpenAiSettings: () {},
    onOpenScraperSettings: () {},
    onOpenAbout: () {},
  );
}

Widget _clipsPage({
  required AppState appState,
  required String query,
  required bool withScores,
}) {
  final controller = TextEditingController();
  return MultiProvider(
    providers: [ChangeNotifierProvider<AppState>.value(value: appState)],
    child: Scaffold(
      backgroundColor: const Color(0xFF171A20),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(
            controller: controller,
            text: query,
            count: withScores ? appState.semanticScores.length : 0,
          ),
          Expanded(child: ClipsTab(searchQuery: query, selectedTags: const [])),
        ],
      ),
    ),
  );
}

Future<AppState> _appState({required bool grid}) async {
  final dir = await Directory.systemTemp.createTemp('v11_shots_');
  final db = File('${dir.path}/db.json');
  await db.writeAsString('[]');
  SharedPreferences.setMockInitialValues({'db_path': db.path});
  final prefs = await SharedPreferences.getInstance();
  final appState = AppState(
    prefs: prefs,
    pathService: PathService(),
    thumbnailService: _NoThumbs(),
  );
  await appState.loadInitialData();
  await appState.addClip(
    const VideoClip(
      id: 'c1',
      name: '雪山湖泊日出',
      videoPath: 'shot_clip_1.mp4',
      notes: 'mountain_lake_01.mp4 · 清晨雪山与湖泊',
      endTime: Duration(minutes: 2, seconds: 18),
      rating: 4,
      tags: ['雪山', '湖泊', '日出'],
    ),
  );
  await appState.addClip(
    const VideoClip(
      id: 'c2',
      name: '雪山徒步',
      videoPath: 'shot_clip_2.mp4',
      notes: 'hiking_03.mp4 · 雪地远足',
      endTime: Duration(minutes: 1, seconds: 42),
      rating: 5,
      isFavorite: true,
      tags: ['雪山', '徒步'],
    ),
  );
  await appState.addClip(
    const VideoClip(
      id: 'c3',
      name: '山顶远景',
      videoPath: 'shot_clip_3.mp4',
      endTime: Duration(minutes: 3),
      tags: ['雪山'],
    ),
  );
  appState.setClipsViewMode(grid);
  appState.debugSetSemanticScores({
    'c1': const MaxSimResult(score: 0.871, hitTimestampMs: 144000),
    'c2': const MaxSimResult(score: 0.823, hitTimestampMs: 46000),
    'c3': const MaxSimResult(score: 0.312, hitTimestampMs: 302000),
  }, query: '雪山');
  return appState;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('v1.1 capture: grid results with Score and relevance sort', (
    tester,
  ) async {
    late AppState appState;
    await tester.runAsync(() async {
      appState = await _appState(grid: true);
    });
    await _capture(
      tester,
      _clipsPage(appState: appState, query: '雪山', withScores: true),
      '01_grid_semantic_score.png',
    );
  });

  testWidgets('v1.1 capture: list results with Score and HIT', (tester) async {
    late AppState appState;
    await tester.runAsync(() async {
      appState = await _appState(grid: false);
    });
    await _capture(
      tester,
      _clipsPage(appState: appState, query: '雪山', withScores: true),
      '02_list_semantic_score.png',
    );
  });

  testWidgets('v1.1 capture: keyword mode hint without AI results', (
    tester,
  ) async {
    late AppState appState;
    await tester.runAsync(() async {
      appState = await _appState(grid: true);
      appState.clearSemanticSearch();
    });
    await _capture(
      tester,
      _clipsPage(appState: appState, query: '雪山', withScores: false),
      '03_keyword_hint.png',
      size: const Size(1280, 420),
    );
  });

  testWidgets('v1.1 capture: semantic loading state', (tester) async {
    late AppState appState;
    await tester.runAsync(() async {
      appState = await _appState(grid: true);
      appState.clearSemanticSearch();
    });
    await _capture(
      tester,
      MultiProvider(
        providers: [ChangeNotifierProvider<AppState>.value(value: appState)],
        child: Scaffold(
          backgroundColor: const Color(0xFF171A20),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Builder(
                builder: (context) {
                  final controller = TextEditingController(text: '雪山');
                  return AppHeader(
                    title: '片段库',
                    searchController: controller,
                    onSearchChanged: (_) {},
                    onSearchSubmitted: (_) {},
                    onClearSearch: () {},
                    isSemanticSearching: true,
                    hasSemanticScores: false,
                    semanticResultCount: 0,
                    onTriggerSemanticSearch: () {},
                    onRefreshThumbnails: () {},
                    onImportMerge: () {},
                    onSwitchDb: () {},
                    onOpenAiSettings: () {},
                    onOpenScraperSettings: () {},
                    onOpenAbout: () {},
                  );
                },
              ),
              Expanded(
                child: ClipsTab(searchQuery: '雪山', selectedTags: const []),
              ),
            ],
          ),
        ),
      ),
      '04_semantic_loading.png',
      size: const Size(1280, 420),
    );
  });

  testWidgets('v1.1 capture: About dialog with update available', (
    tester,
  ) async {
    await _capture(
      tester,
      Scaffold(
        backgroundColor: const Color(0xFF171A20),
        body: Center(
          child: AppAboutDialog(
            version: const AppVersion(version: '1.1.0', buildNumber: '3'),
            updateService: _StubUpdateService(
              UpdateCheckResult(
                currentVersion: '1.1.0',
                latest: ReleaseInfo(
                  tagName: 'v1.2.0',
                  version: '1.2.0',
                  name: 'v1.2.0',
                  notes: '- 语义检索结果显示相似度分数\n- 增加「检查更新」入口',
                  htmlUrl: '${AppInfo.releasesUrl}/tag/v1.2.0',
                  publishedAt: DateTime(2026, 10, 1, 12),
                ),
                updateAvailable: true,
              ),
            ),
          ),
        ),
      ),
      '05_about_dialog.png',
      size: const Size(760, 760),
      beforeCapture: () async {
        await tester.tap(find.byKey(const Key('about-check-update-button')));
        await tester.pump();
        await tester.pump();
      },
    );
  });
}
