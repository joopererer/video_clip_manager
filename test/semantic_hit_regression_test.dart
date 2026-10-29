import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_clip_manager/data/app_state.dart';
import 'package:video_clip_manager/data/models.dart';
import 'package:video_clip_manager/services/delta_engine.dart';
import 'package:video_clip_manager/services/path_service.dart';
import 'package:video_clip_manager/services/thumbnail_service.dart';

class _NoThumbs2 extends Fake implements ThumbnailService {
  @override
  Future<String?> generateThumbnail(String videoPath, Duration time, String clipId, {String? dbPath}) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('semantic hit timestamp is propagated to filtered clips', () async {
    final tempDir = await Directory.systemTemp.createTemp('semantic_hit_');
    final dbFile = File('${tempDir.path}/db.json');
    await dbFile.writeAsString('[]');
    SharedPreferences.setMockInitialValues({'db_path': dbFile.path});
    final prefs = await SharedPreferences.getInstance();
    final appState = AppState(
      prefs: prefs,
      pathService: PathService(),
      thumbnailService: _NoThumbs2(),
    );
    await appState.loadInitialData();
    await appState.addClip(VideoClip(
      id: 'c1',
      name: 'snow mountain',
      videoPath: 'v1.mp4',
    ));

    final withoutHit = appState.getFilteredClips(searchQuery: 'snow');
    expect(withoutHit.first.hitTimestampMs, isNull);

    appState.debugSetSemanticScores({
      'c1': const MaxSimResult(score: 0.9, hitTimestampMs: 1234),
    });
    final withHit = appState.getFilteredClips(searchQuery: 'snow');
    expect(withHit.first.hitTimestampMs, 1234);

    await tempDir.delete(recursive: true);
  });
}
