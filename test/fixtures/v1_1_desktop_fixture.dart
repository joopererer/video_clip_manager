// Windows desktop verification entry point for the v1.1.0 release prep.
//
// It boots the production app with an explicitly supplied sample database and a
// pre-seeded semantic result set (real score values, not fabricated UI numbers),
// so the search hint, the Score display, the relevance sort and the About dialog
// can be verified on the real Windows binary by UI Automation.
//
// Preferences are in-memory: the user's database selection, view mode and AI
// configuration are never touched. Nothing here ships in the release build.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_clip_manager/data/app_state.dart';
import 'package:video_clip_manager/screens/main_screen.dart';
import 'package:video_clip_manager/services/delta_engine.dart';
import 'package:video_clip_manager/services/path_service.dart';
import 'package:video_clip_manager/services/thumbnail_service.dart';
import 'package:video_clip_manager/theme/app_theme.dart';
import 'package:video_clip_manager/theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Expose the semantics tree to Windows UI Automation so the capture tooling can
  // confirm what is on screen instead of guessing from pixels.
  SemanticsBinding.instance.ensureSemantics();

  try {
    MediaKit.ensureInitialized();
  } catch (e) {
    debugPrint('MediaKit initialization failed: $e');
  }

  final database = Platform.environment['VCM_V11_DB'];
  if (database == null || !File(database).existsSync()) {
    throw StateError('Set VCM_V11_DB to the generated sample database.');
  }

  final pathService = PathService();
  await pathService.init();

  SharedPreferences.setMockInitialValues({
    'db_path': database,
    'clipsIsGridView': Platform.environment['VCM_V11_GRID'] == '1',
  });
  final prefs = await SharedPreferences.getInstance();
  final thumbnailService = ThumbnailService(pathService: pathService);
  final themeController = ThemeController(prefs);

  final appState = AppState(
    prefs: prefs,
    pathService: pathService,
    thumbnailService: thumbnailService,
  );
  await appState.loadInitialData();

  // Scores below are the values the retrieval pipeline produced for this sample
  // library; the fixture only replays them so the UI can be checked without the
  // 542 MB model and the sidecar binary.
  appState.debugSetSemanticScores({
    'v11_clip_1': const MaxSimResult(score: 0.871, hitTimestampMs: 144000),
    'v11_clip_2': const MaxSimResult(score: 0.823, hitTimestampMs: 46000),
    'v11_clip_3': const MaxSimResult(score: 0.312, hitTimestampMs: 302000),
  }, query: '雪山');

  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: pathService),
        Provider.value(value: thumbnailService),
        ChangeNotifierProvider.value(value: themeController),
        ChangeNotifierProvider.value(value: appState),
      ],
      child: Consumer<ThemeController>(
        builder: (context, theme, _) => MaterialApp(
          title: 'Video Clip Manager',
          theme: AppTheme.lightTheme,
          darkTheme: theme.themeData,
          themeMode: ThemeMode.dark,
          home: const MainScreen(),
          debugShowCheckedModeBanner: false,
        ),
      ),
    ),
  );
}
