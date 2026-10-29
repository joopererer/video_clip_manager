import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_clip_manager/theme/app_theme.dart';
import 'package:video_clip_manager/widgets/common/app_header.dart';

Future<void> _pumpHeader(
  WidgetTester tester, {
  String text = '',
  bool searching = false,
  int count = 0,
}) async {
  tester.view.physicalSize = const Size(1440, 200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final controller = TextEditingController(text: text);
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: AppHeader(
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
        ),
      ),
    ),
  );
  await tester.pump();
}

String _label(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const Key('search-mode-label')))
    .data!;

String _hint(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const Key('search-action-hint')))
    .data!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('empty query shows the AI search hint in the placeholder', (
    tester,
  ) async {
    await _pumpHeader(tester);
    expect(_label(tester), '关键词筛选');
    expect(_hint(tester), contains('Enter'));
    expect(_hint(tester), contains('✨'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('typing text keeps the Enter / sparkle hint visible', (
    tester,
  ) async {
    await _pumpHeader(tester, text: '雪山');
    expect(_label(tester), '关键词筛选');
    expect(_hint(tester), '按 Enter 或点击 ✨ 进行 AI 语义搜索');
  });

  testWidgets('searching shows a loading label and status', (tester) async {
    await _pumpHeader(tester, text: '雪山', searching: true);
    expect(_label(tester), 'AI 语义检索中');
    expect(_hint(tester), contains('AI 语义搜索'));
    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });

  testWidgets('semantic results show the real result count', (tester) async {
    await _pumpHeader(tester, text: '雪山', count: 6);
    expect(_label(tester), contains('AI 语义结果'));
    expect(_label(tester), contains('6'));
    expect(_hint(tester), contains('相似度'));
  });

  testWidgets('the sparkle button explains both triggers', (tester) async {
    await _pumpHeader(tester, text: '雪山');
    expect(
      find.byTooltip('点击 ✨ 或按 Enter 执行 AI 语义搜索'),
      findsOneWidget,
    );
  });
}
