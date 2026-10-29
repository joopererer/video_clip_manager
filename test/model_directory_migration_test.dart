import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_clip_manager/data/app_state.dart';
import 'package:video_clip_manager/services/path_service.dart';
import 'package:video_clip_manager/services/thumbnail_service.dart';
import 'package:video_clip_manager/widgets/ai_settings_dialog.dart';

class _NoThumbs3 extends Fake implements ThumbnailService {
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

  test(
    'model directory migration rolls back on verification failure',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('model_migrate_');
      final oldDir = Directory(p.join(tempDir.path, 'old'));
      final newDir = Directory(p.join(tempDir.path, 'new'));
      await oldDir.create(recursive: true);
      await newDir.create(recursive: true);

      final oldConfig = File(p.join(oldDir.path, 'config.json'));
      await oldConfig.writeAsString('old-model');
      final existingTarget = File(p.join(newDir.path, 'existing.txt'));
      await existingTarget.writeAsString('keep-me');

      final dbFile = File(p.join(tempDir.path, 'db.json'));
      await dbFile.writeAsString('[]');
      SharedPreferences.setMockInitialValues({
        'db_path': dbFile.path,
        'ai_model_dir': oldDir.path,
      });
      final prefs = await SharedPreferences.getInstance();
      final appState = AppState(
        prefs: prefs,
        pathService: PathService(),
        thumbnailService: _NoThumbs3(),
      );
      await appState.loadInitialData();
      expect(appState.aiModelDir, oldDir.path);

      final copied = <String>[];
      await expectLater(
        migrateEmbeddingModelDirectory(
          from: oldDir.path,
          to: newDir.path,
          appState: appState,
          previousDir: oldDir.path,
          copied: copied,
        ),
        throwsA(anything),
      );

      expect(appState.aiModelDir, oldDir.path);
      expect(await oldConfig.readAsString(), 'old-model');
      expect(await existingTarget.readAsString(), 'keep-me');
      expect(File(p.join(newDir.path, 'config.json')).existsSync(), isFalse);

      await tempDir.delete(recursive: true);
    },
  );

  test(
    'model directory copy refuses to overwrite existing target files',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('model_copy_');
      final fromDir = Directory(p.join(tempDir.path, 'from'));
      final toDir = Directory(p.join(tempDir.path, 'to'));
      await fromDir.create(recursive: true);
      await toDir.create(recursive: true);

      await File(p.join(fromDir.path, 'config.json')).writeAsString('source');
      final targetFile = File(p.join(toDir.path, 'config.json'));
      await targetFile.writeAsString('target');

      final copied = <String>[];
      await expectLater(
        copyEmbeddingModelDirectory(fromDir.path, toDir.path, created: copied),
        throwsA(isA<FileSystemException>()),
      );
      expect(await targetFile.readAsString(), 'target');
      expect(copied, isEmpty);

      await tempDir.delete(recursive: true);
    },
  );
}
