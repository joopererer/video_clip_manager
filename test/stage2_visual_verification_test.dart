import 'dart:io';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:video_clip_manager/widgets/clip_card.dart';
import 'package:video_clip_manager/widgets/clip_list_row.dart';
import 'package:video_clip_manager/widgets/clip_media_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:video_clip_manager/data/app_state.dart';
import 'package:video_clip_manager/data/models.dart';
import 'package:video_clip_manager/screens/tabs/clips_tab.dart';
import 'package:video_clip_manager/widgets/common/app_sidebar.dart';
import 'package:video_clip_manager/widgets/common/app_header.dart';
import 'package:video_clip_manager/services/path_service.dart';
import 'package:video_clip_manager/services/thumbnail_service.dart';
import 'package:video_clip_manager/theme/app_theme.dart';

class FakeThumbnailService extends Fake implements ThumbnailService {
  @override
  Future<String?> generateThumbnail(
    String videoPath,
    Duration time,
    String clipId, {
    String? dbPath,
  }) async => null;
}

class TestServices {
  final AppState appState;
  final PathService pathService;
  final ThumbnailService thumbnailService;

  TestServices({
    required this.appState,
    required this.pathService,
    required this.thumbnailService,
  });
}

Future<TestServices> _createInitializedServices(Directory tempDir) async {
  final dbFile = File('${tempDir.path}/test_db.json');
  await dbFile.writeAsString('[]');
  SharedPreferences.setMockInitialValues({'db_path': dbFile.path});
  final prefs = await SharedPreferences.getInstance();
  final pathService = PathService();
  final thumbService = FakeThumbnailService();

  final appState = AppState(
    prefs: prefs,
    pathService: pathService,
    thumbnailService: thumbService,
  );
  await appState.loadInitialData();
  return TestServices(
    appState: appState,
    pathService: pathService,
    thumbnailService: thumbService,
  );
}

Future<void> _captureWidgetToFile(
  WidgetTester tester,
  Widget widget,
  String outputPath, {
  Size size = const Size(1280, 800),
  Future<void> Function()? exercise,
}) async {
  final repaintKey = GlobalKey();

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      debugShowCheckedModeBanner: false,
      home: RepaintBoundary(key: repaintKey, child: widget),
    ),
  );

  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  expect(tester.takeException(), isNull);

  if (exercise != null) {
    await exercise();
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);
  }

  final boundary =
      repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary != null) {
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final byteData = await image.toByteData(format: ImageByteFormat.png);
      if (byteData != null) {
        final file = File(outputPath);
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(byteData.buffer.asUint8List());
      }
    });
  }

  final appState = tester.element(find.byType(ClipsTab)).read<AppState>();
  await tester.runAsync(appState.forceSave);
  await tester.pumpWidget(const SizedBox());
  appState.dispose();
  expect(tester.takeException(), isNull);
}

Future<void> _populateSampleData(AppState appState) async {
  final video1 = OriginalVideo(
    id: 'vid_nature_4k',
    path:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
    name: 'BigBuckBunny_4K_60FPS.mp4',
    duration: const Duration(milliseconds: 360000),
  );
  final video2 = OriginalVideo(
    id: 'vid_city_aerial',
    path:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
    name: 'ElephantsDream_HDR.mp4',
    duration: const Duration(milliseconds: 653000),
  );
  appState.addOriginalVideo(video1);
  appState.addOriginalVideo(video2);

  final clip1 = VideoClip(
    id: 'clip_01',
    videoPath: video1.path,
    startTime: const Duration(milliseconds: 12500),
    endTime: const Duration(milliseconds: 38200),
    name: '森林清晨与兔子奔跑特写',
    notes: '慢动作 60fps，色温偏暖，非常适合作为宣传片片头',
    tags: const ['4K', '动物', '风景', '慢动作'],
    rating: 5,
    isFavorite: true,
  );
  final clip2 = VideoClip(
    id: 'clip_02',
    videoPath: video1.path,
    startTime: const Duration(milliseconds: 45000),
    endTime: const Duration(milliseconds: 78500),
    name: '鸟类滑翔与林间光影过渡',
    notes: '丁达尔光效，转场自然',
    tags: const ['航拍', '光影', '自然'],
    rating: 4,
    isFavorite: false,
  );
  final clip3 = VideoClip(
    id: 'clip_03',
    videoPath: video2.path,
    startTime: const Duration(milliseconds: 102000),
    endTime: const Duration(milliseconds: 145000),
    name: '机械管道与蒸汽动力特写',
    notes: '赛博朋克工业风格，音效饱满',
    tags: const ['用于验证边界的非常长的工业镜头分类标签', '机械', '科幻'],
    rating: 5,
    isFavorite: true,
  );
  final clip4 = VideoClip(
    id: 'clip_04',
    videoPath: video2.path,
    startTime: const Duration(milliseconds: 210000),
    endTime: const Duration(milliseconds: 255000),
    name: '控制室主控台全景变焦',
    notes: '镜头推拉流畅，适合作为中段高潮铺垫',
    tags: const ['室内', '变焦', '全景'],
    rating: 3,
    isFavorite: false,
  );

  await appState.addClip(clip1);
  await appState.addClip(clip2);
  await appState.addClip(clip3);
  await appState.addClip(clip4);

  appState.createPlaylist('年度精选宣传片', description: '汇总精彩片头与转场');
  await appState.forceSave();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('stage2_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('Missing source is explicit without starting a native preview', (
    tester,
  ) async {
    final missing = '${tempDir.path}/missing_测试.mp4';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: ClipMediaPreview(
            clip: VideoClip(id: 'missing', videoPath: missing),
          ),
        ),
      ),
    );
    expect(await tester.runAsync(() => File(missing).exists()), isFalse);
    await tester.pump();
    expect(find.text('源文件缺失'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Stage 2 Capture 1: Widget harness 1280x800 Clips Grid View', (
    tester,
  ) async {
    final services = (await tester.runAsync(
      () => _createInitializedServices(tempDir),
    ))!;
    await tester.runAsync(() => _populateSampleData(services.appState));
    services.appState.setClipsViewMode(true); // Grid view

    await _captureWidgetToFile(
      tester,
      MultiProvider(
        providers: [
          Provider.value(value: services.pathService),
          Provider.value(value: services.thumbnailService),
          ChangeNotifierProvider.value(value: services.appState),
        ],
        child: const LibraryHarness(),
      ),
      'docs/ui-upgrade/screenshots/stage2/widget/stage2_01_clips_grid_1280x800.png',
      size: const Size(1280, 800),
      exercise: () async {
        expect(find.byType(ClipCard), findsNWidgets(4));
      },
    );
  });

  testWidgets('Stage 2 Capture 2: Widget harness 1280x800 Clips List View', (
    tester,
  ) async {
    final services = (await tester.runAsync(
      () => _createInitializedServices(tempDir),
    ))!;
    await tester.runAsync(() => _populateSampleData(services.appState));
    services.appState.setClipsViewMode(false); // List view

    await _captureWidgetToFile(
      tester,
      MultiProvider(
        providers: [
          Provider.value(value: services.pathService),
          Provider.value(value: services.thumbnailService),
          ChangeNotifierProvider.value(value: services.appState),
        ],
        child: const LibraryHarness(),
      ),
      'docs/ui-upgrade/screenshots/stage2/widget/stage2_02_clips_list_1280x800.png',
      size: const Size(1280, 800),
      exercise: () async {
        expect(find.byType(ClipListRow), findsNWidgets(4));
      },
    );
  });

  testWidgets(
    'Stage 2 Capture 3: Widget harness 900x700 Narrow Collapsed Sidebar',
    (tester) async {
      final services = (await tester.runAsync(
        () => _createInitializedServices(tempDir),
      ))!;
      await tester.runAsync(() => _populateSampleData(services.appState));
      services.appState.setClipsViewMode(true);

      await _captureWidgetToFile(
        tester,
        MultiProvider(
          providers: [
            Provider.value(value: services.pathService),
            Provider.value(value: services.thumbnailService),
            ChangeNotifierProvider.value(value: services.appState),
          ],
          child: const LibraryHarness(),
        ),
        'docs/ui-upgrade/screenshots/stage2/widget/stage2_03_narrow_collapsed_900x700.png',
        size: const Size(900, 700),
        exercise: () async {
          expect(tester.getSize(find.byType(AppSidebar)).width, 64);
          await tester.tap(find.byTooltip('更多操作与设置'));
          await tester.pumpAndSettle();
          for (final label in [
            '导入并合并 JSON 库',
            '切换/新建数据库',
            'AI 视觉与模型设置',
            '爬虫设置',
            '关于软件',
          ]) {
            expect(find.text(label), findsWidgets);
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
        },
      );
    },
  );

  testWidgets('Stage 2 Capture 4: Active Search and Filter State', (
    tester,
  ) async {
    final services = (await tester.runAsync(
      () => _createInitializedServices(tempDir),
    ))!;
    await tester.runAsync(() => _populateSampleData(services.appState));
    services.appState.setClipsViewMode(true);
    services.appState.setSelectedTags(['4K']);
    services.appState.setSelectedFavorite(true);

    await _captureWidgetToFile(
      tester,
      MultiProvider(
        providers: [
          Provider.value(value: services.pathService),
          Provider.value(value: services.thumbnailService),
          ChangeNotifierProvider.value(value: services.appState),
        ],
        child: const LibraryHarness(),
      ),
      'docs/ui-upgrade/screenshots/stage2/widget/stage2_05_search_and_filter.png',
      size: const Size(1280, 800),
      exercise: () async {
        await tester.enterText(find.byType(TextField), '森林');
        await tester.pump();
        expect(find.byType(ClipCard), findsOneWidget);
        expect(find.text('森林清晨与兔子奔跑特写'), findsOneWidget);
      },
    );
  });
  testWidgets(
    'Desktop interactions: hover, context menu, favorite, rating, reset',
    (tester) async {
      final services = (await tester.runAsync(
        () => _createInitializedServices(tempDir),
      ))!;
      await tester.runAsync(() => _populateSampleData(services.appState));
      services.appState.setClipsViewMode(true);
      await _captureWidgetToFile(
        tester,
        MultiProvider(
          providers: [
            Provider.value(value: services.pathService),
            Provider.value(value: services.thumbnailService),
            ChangeNotifierProvider.value(value: services.appState),
          ],
          child: const LibraryHarness(),
        ),
        'docs/ui-upgrade/screenshots/stage2/widget/interaction_1600x800.png',
        size: const Size(1600, 800),
        exercise: () async {
          final card = find.byKey(const ValueKey('clip_01'));
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          await mouse.moveTo(
            tester.getBottomLeft(card) + const Offset(20, -10),
          );
          await tester.pump(const Duration(milliseconds: 200));
          expect(
            find.descendant(of: card, matching: find.byTooltip('更多操作')),
            findsOneWidget,
          );
          await mouse.moveTo(Offset.zero);
          Focus.of(
            tester.element(
              find
                  .descendant(
                    of: card,
                    matching: find.byType(AnimatedContainer),
                  )
                  .first,
            ),
          ).requestFocus();
          await tester.pump();
          expect(
            find.descendant(of: card, matching: find.byTooltip('更多操作')),
            findsOneWidget,
          );
          await tester.tap(
            find.descendant(of: card, matching: find.byTooltip('更多操作')),
          );
          await tester.pumpAndSettle();
          for (final label in [
            '播放片段',
            '编辑时间范围与元数据',
            '添加到播放列表',
            '复制源视频完整路径',
            '删除片段',
          ]) {
            expect(find.text(label), findsOneWidget);
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(tester.widget<ClipCard>(card).isSelected, isTrue);
          await tester.tap(
            find.descendant(of: card, matching: find.byTooltip('取消收藏')),
          );
          await tester.pump();
          expect(
            services.appState.clips
                .firstWhere((c) => c.id == 'clip_01')
                .isFavorite,
            isFalse,
          );
          await tester.tap(
            find.descendant(of: card, matching: find.byTooltip('评为 3 星')),
          );
          await tester.pump();
          expect(
            services.appState.clips.firstWhere((c) => c.id == 'clip_01').rating,
            3,
          );
          final persisted = await tester.runAsync(() async {
            await services.appState.forceSave();
            final json =
                jsonDecode(
                      await File(
                        services.appState.currentDbFullPath!,
                      ).readAsString(),
                    )
                    as Map<String, dynamic>;
            return (json['clips'] as List)
                .cast<Map<String, dynamic>>()
                .firstWhere((c) => c['id'] == 'clip_01');
          });
          expect(persisted!['rating'], 3);
          expect(persisted['isFavorite'], isFalse);
          await tester.enterText(find.byType(TextField), '森林');
          services.appState.setSelectedRating(3);
          await tester.pump();
          expect(find.byType(ClipCard), findsOneWidget);
          await tester.tap(find.text('重置筛选'));
          await tester.pump();
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            isEmpty,
          );
          expect(services.appState.selectedRating, isNull);
          expect(find.byType(ClipCard), findsNWidgets(4));
          await mouse.removePointer();
        },
      );
    },
  );
}

// Widget-only harness: production sidebar/header/library, without native video host.
class LibraryHarness extends StatefulWidget {
  const LibraryHarness({super.key});
  @override
  State<LibraryHarness> createState() => _LibraryHarnessState();
}

class _LibraryHarnessState extends State<LibraryHarness> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    void noop() {}
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 1050;
          return Row(
            children: [
              AppSidebar(
                currentIndex: 0,
                onIndexChanged: (_) {},
                isCollapsed: narrow,
                onToggleCollapse: noop,
                onSwitchDb: noop,
                currentDbName: 'Widget test sample database',
              ),
              Expanded(
                child: Column(
                  children: [
                    AppHeader(
                      title: '片段库',
                      searchController: controller,
                      onSearchChanged: (_) => setState(() {}),
                      onSearchSubmitted: (_) {},
                      onClearSearch: () => setState(controller.clear),
                      isSemanticSearching: false,
                      hasSemanticScores: false,
                      onTriggerSemanticSearch: noop,
                      onRefreshThumbnails: noop,
                      onImportMerge: noop,
                      onSwitchDb: noop,
                      onOpenAiSettings: noop,
                      onOpenScraperSettings: noop,
                      onOpenAbout: noop,
                      isNarrow: narrow,
                    ),
                    Expanded(
                      child: ClipsTab(
                        searchQuery: controller.text,
                        selectedTags: state.selectedTags,
                        selectedRating: state.selectedRating,
                        selectedFavorite: state.selectedFavorite,
                        onClearSearch: () => setState(controller.clear),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
