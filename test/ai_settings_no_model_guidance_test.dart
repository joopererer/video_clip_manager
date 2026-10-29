import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_clip_manager/data/app_state.dart';
import 'package:video_clip_manager/services/ai_failure.dart';
import 'package:video_clip_manager/services/ai_model_manifest.dart';
import 'package:video_clip_manager/services/path_service.dart';
import 'package:video_clip_manager/services/thumbnail_service.dart';
import 'package:video_clip_manager/theme/app_theme.dart';
import 'package:video_clip_manager/widgets/ai_settings_dialog.dart';

class _NoThumbs extends Fake implements ThumbnailService {
  @override
  Future<String?> generateThumbnail(
    String videoPath,
    Duration time,
    String clipId, {
    String? dbPath,
  }) async => null;
}

/// An [AppState] pointed at [modelDir] as its semantic model folder. Anything
/// touching the filesystem has to run inside `tester.runAsync`, otherwise the
/// futures never complete under the test binding.
Future<AppState> _freshAppState(Directory modelDir) async {
  final dir = await Directory.systemTemp.createTemp('v11_no_model_');
  final db = File('${dir.path}/db.json');
  await db.writeAsString('[]');
  SharedPreferences.setMockInitialValues({
    'db_path': db.path,
    'ai_model_dir': modelDir.path,
  });
  final prefs = await SharedPreferences.getInstance();
  final appState = AppState(
    prefs: prefs,
    pathService: PathService(),
    thumbnailService: _NoThumbs(),
  );
  await appState.loadInitialData();
  return appState;
}

Widget _dialog(AppState appState) {
  return ChangeNotifierProvider<AppState>.value(
    value: appState,
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: const Scaffold(body: AiSettingsDialog()),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a machine that never installed the semantic model', () {
    test('reports the model as absent rather than ready', () async {
      final modelDir = await Directory.systemTemp.createTemp('v11_absent_');
      addTearDown(() => modelDir.delete(recursive: true));
      final appState = await _freshAppState(modelDir);

      final inspection = await appState.aiService.inspectEmbeddingModel();

      expect(inspection.dir, modelDir.path);
      expect(inspection.isComplete, isFalse);
      expect(inspection.anyFilePresent, isFalse);
      expect(inspection.reports.length, embeddingGemmaManifest.files.length);
      expect(
        await appState.aiService.resolveEmbeddingModelDir(),
        isNull,
        reason: '空目录不能被当成可用模型',
      );
    });

    test('reports a half-copied folder as incomplete, file by file', () async {
      final modelDir = await Directory.systemTemp.createTemp('v11_partial_');
      addTearDown(() => modelDir.delete(recursive: true));
      // One real manifest entry, truncated: the case a user hits when a manual
      // copy is interrupted.
      await File(
        '${modelDir.path}${Platform.pathSeparator}${embeddingGemmaManifest.files.first.path}',
      ).writeAsString('truncated');
      final appState = await _freshAppState(modelDir);

      final inspection = await appState.aiService.inspectEmbeddingModel();

      expect(inspection.isComplete, isFalse);
      expect(inspection.anyFilePresent, isTrue, reason: '已复制的那一份要被看见');
      expect(
        inspection.problems.length,
        embeddingGemmaManifest.files.length,
        reason: '损坏的那份加上其余缺失的，都应计入问题',
      );
      expect(inspection.describeProblems(), isNotEmpty);
      expect(await appState.aiService.resolveEmbeddingModelDir(), isNull);
    });

    testWidgets('AI settings show 未下载 and a download action, not an error', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final modelDir = await tester.runAsync(
        () => Directory.systemTemp.createTemp('v11_absent_ui_'),
      );
      addTearDown(() => modelDir!.delete(recursive: true));
      final appState = await tester.runAsync(() => _freshAppState(modelDir!));
      expect(appState, isNotNull);

      // `initState` kicks off the size check; the frame that matters for this
      // assertion is the one rendered before it answers: the section is always
      // labelled, and a download action is always offered.
      await tester.pumpWidget(_dialog(appState!));
      await tester.pump();

      expect(find.text('语义检索模型 (EmbeddingGemma 2)'), findsOneWidget);
      expect(find.text('未下载'), findsOneWidget);
      expect(find.textContaining('一键下载'), findsOneWidget);

      // The rest of the settings page still renders: a missing model is a
      // normal state, not a broken app.
      expect(find.text('片段特征向量库'), findsOneWidget);
      expect(find.text('模型目录 (仅应用内 EmbeddingGemma)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  test('model failures tell the user what to do next', () {
    final inference = describeAiFailure(
      AiStage.inference,
      AiFailureKind.modelMissing,
    );
    expect(inference, contains('模型文件缺失'));
    expect(inference, contains('AI 设置'));

    // On a machine that only unzipped the release, the sidecar is the first
    // blocker, so that message has to be actionable too.
    final cli = describeAiFailure(AiStage.extraction, AiFailureKind.cliMissing);
    expect(cli, contains('local-media-ai.exe'));
    expect(cli, contains('同一目录'));
  });
}
