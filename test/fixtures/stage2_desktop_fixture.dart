// Windows desktop visual verification entry point. Uses the production app,
// native Media Kit and real AppState with an explicitly supplied sample database.
// Preferences are in memory so verification cannot change the user's database
// selection, ratings, view mode, or AI configuration.
import 'dart:io';

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_clip_manager/main.dart' as production;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Expose the semantics tree to Windows UI Automation so the capture tooling
  // can confirm which screen is showing instead of guessing from pixels.
  SemanticsBinding.instance.ensureSemantics();
  final database = Platform.environment['VCM_STAGE2_DB'];
  if (database == null || !File(database).existsSync()) {
    throw StateError('Set VCM_STAGE2_DB to the generated sample database.');
  }
  SharedPreferences.setMockInitialValues({'db_path': database});
  production.main();
}
