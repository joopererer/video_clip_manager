import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_clip_manager/data/app_state.dart';
import 'package:video_clip_manager/data/models.dart';
import 'package:video_clip_manager/screens/main_screen.dart';
import 'package:video_clip_manager/screens/tabs/clips_tab.dart';
import 'package:video_clip_manager/screens/tabs/playlists_tab.dart';
import 'package:video_clip_manager/services/path_service.dart';
import 'package:video_clip_manager/services/thumbnail_service.dart';
import 'package:video_clip_manager/theme/app_colors.dart';
import 'package:video_clip_manager/theme/app_spacing.dart';
import 'package:video_clip_manager/theme/app_theme.dart';
import 'package:video_clip_manager/theme/app_typography.dart';
import 'package:video_clip_manager/widgets/common/timecode_chip.dart';

Future<void> _captureWidget(
  WidgetTester tester,
  Widget widget,
  String outputPath, {
  Size size = const Size(1280, 800),
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
      home: RepaintBoundary(key: repaintKey, child: widget),
    ),
  );

  await tester.pump();

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

  await tester.pumpWidget(const SizedBox());
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Capture 1: Theme Unified Components & Contrast Showcase', (
    tester,
  ) async {
    await _captureWidget(
      tester,
      Scaffold(
        appBar: AppBar(
          title: const Text('Design System Components Showcase'),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: '设置选项',
              onPressed: () {},
            ),
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: '关于',
              onPressed: () {},
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Dark Media Workspace — 核心组件规范',
                style: AppTypography.pageTitle,
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                '包含按钮、输入框、标签、时间码徽章、卡片与对话框样式验证',
                style: AppTypography.bodySecondary,
              ),
              const SizedBox(height: AppSpacing.lg),

              // 卡片与表面层
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '标准表面 (Surface #252A34)',
                              style: AppTypography.subtitle,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            const Text(
                              '卡片使用 12px 圆角与 #3B414E 细微边框，确保在 #171A20 基础背景上具备清晰层次感。',
                              style: AppTypography.body,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Wrap(
                              spacing: AppSpacing.xs,
                              runSpacing: AppSpacing.xs,
                              children: [
                                TimecodeChip(
                                  duration: const Duration(seconds: 9),
                                  label: 'IN',
                                  labelColor: AppColors.success,
                                  showMs: true,
                                ),
                                TimecodeChip(
                                  duration: const Duration(
                                    minutes: 1,
                                    seconds: 30,
                                  ),
                                  label: 'OUT',
                                  labelColor: AppColors.warning,
                                  showMs: true,
                                ),
                                TimecodeChip(
                                  duration: const Duration(
                                    minutes: 1,
                                    seconds: 21,
                                  ),
                                  label: 'DURATION',
                                  labelColor: AppColors.primary,
                                  showMs: true,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Card(
                      color: AppColors.surfaceElevated,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '抬升表面 (Surface Elevated #303644)',
                              style: AppTypography.subtitle,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            const Text(
                              '用于对话框、浮层与二级面板，提供更高阶对比度与深色质感。',
                              style: AppTypography.body,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Row(
                              children: [
                                FilledButton.icon(
                                  onPressed: () {},
                                  icon: const Icon(Icons.check, size: 16),
                                  label: const Text('保存修改'),
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                OutlinedButton(
                                  onPressed: () {},
                                  child: const Text('取消重置'),
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                TextButton(
                                  onPressed: () {},
                                  child: const Text('查看详情'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.lg),
              const Text('表单输入与筛选组件', style: AppTypography.sectionTitle),
              const SizedBox(height: AppSpacing.sm),

              // 输入框与表单
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: '片段名称',
                        hintText: '输入片段标题或标签…',
                        prefixIcon: Icon(Icons.label_outline),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        labelText: '语义搜索',
                        hintText: '输入自然语言描述画面…',
                        prefixIcon: const Icon(
                          Icons.auto_awesome,
                          color: AppColors.primary,
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {},
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  FilterChip(
                    label: const Text('全部片段'),
                    selected: true,
                    onSelected: (_) {},
                  ),
                  FilterChip(
                    label: const Text('仅收藏 (12)'),
                    selected: false,
                    onSelected: (_) {},
                  ),
                  FilterChip(
                    label: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star, size: 14, color: AppColors.starActive),
                        SizedBox(width: 4),
                        Text('5 星精选'),
                      ],
                    ),
                    selected: false,
                    onSelected: (_) {},
                  ),
                  Chip(label: const Text('4K 航拍'), onDeleted: () {}),
                  Chip(label: const Text('城市风景'), onDeleted: () {}),
                ],
              ),
            ],
          ),
        ),
      ),
      'docs/ui-upgrade/screenshots/stage1/04_theme_components_dark.png',
      size: const Size(1280, 800),
    );
  });

  testWidgets('Capture 2: Clips Tab with data and dark theme', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final pathService = PathService();
    final thumbnailService = ThumbnailService(pathService: pathService);
    final appState = AppState(
      prefs: prefs,
      pathService: pathService,
      thumbnailService: thumbnailService,
    );

    final repaintKey = GlobalKey();
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider.value(value: pathService),
          Provider.value(value: thumbnailService),
          ChangeNotifierProvider.value(value: appState),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: Scaffold(
            appBar: AppBar(title: const Text('Clips Library (Dark Theme)')),
            body: RepaintBoundary(
              key: repaintKey,
              child: const ClipsTab(searchQuery: '', selectedTags: []),
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    final boundary =
        repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary != null) {
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final byteData = await image.toByteData(format: ImageByteFormat.png);
        if (byteData != null) {
          File(
            'docs/ui-upgrade/screenshots/stage1/02_clips_tab_dark.png',
          ).writeAsBytesSync(byteData.buffer.asUint8List());
        }
      });
    }

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Capture 3: Playlists Tab in Dark Theme', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final pathService = PathService();
    final thumbnailService = ThumbnailService(pathService: pathService);
    final appState = AppState(
      prefs: prefs,
      pathService: pathService,
      thumbnailService: thumbnailService,
    );

    appState.createPlaylist('年度精选宣传片', description: '汇总精彩片头与转场');

    final repaintKey = GlobalKey();
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider.value(value: pathService),
          Provider.value(value: thumbnailService),
          ChangeNotifierProvider.value(value: appState),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: Scaffold(
            body: RepaintBoundary(
              key: repaintKey,
              child: const PlaylistsTab(searchQuery: ''),
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    final boundary =
        repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary != null) {
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final byteData = await image.toByteData(format: ImageByteFormat.png);
        if (byteData != null) {
          File(
            'docs/ui-upgrade/screenshots/stage1/03_playlists_tab_dark.png',
          ).writeAsBytesSync(byteData.buffer.asUint8List());
        }
      });
    }

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 600));
  });
}
