import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_clip_manager/data/app_state.dart';
import 'package:video_clip_manager/data/models.dart';
import 'package:video_clip_manager/services/ai_service.dart';
import 'package:video_clip_manager/services/frame_embedding_pool.dart';
import 'package:video_clip_manager/services/path_service.dart';
import 'package:video_clip_manager/services/thumbnail_service.dart';

class FakeThumbnailService extends Fake implements ThumbnailService {
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

  group('AppState Semantic Search & AI Integration', () {
    late AppState appState;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('app_state_test_');
      final dbFile = File('${tempDir.path}/test_db.json');
      await dbFile.writeAsString('[]');

      SharedPreferences.setMockInitialValues({
        'db_path': dbFile.path,
      });
      final prefs = await SharedPreferences.getInstance();
      final pathService = PathService();
      final thumbService = FakeThumbnailService();

      appState = AppState(
        prefs: prefs,
        pathService: pathService,
        thumbnailService: thumbService,
      );
      await appState.loadInitialData();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('getFilteredClips matches AI generated summary, scene, and actions via text query', () async {
      final clip1 = VideoClip(
        id: 'c1',
        name: 'Clip 1',
        videoPath: 'v1.mp4',
        aiSummary: 'A red sports car drifting under the rain',
        aiScene: 'Rainy City Night',
        aiActions: const ['drifting', 'acceleration'],
      );
      final clip2 = VideoClip(
        id: 'c2',
        name: 'Clip 2',
        videoPath: 'v2.mp4',
        notes: 'Ordinary footage',
      );

      await appState.addClip(clip1);
      await appState.addClip(clip2);

      // Search by AI summary keyword
      final resSummary = appState.getFilteredClips(searchQuery: 'drifting');
      expect(resSummary.length, 1);
      expect(resSummary.first.id, 'c1');

      // Search by AI scene keyword
      final resScene = appState.getFilteredClips(searchQuery: 'Rainy');
      expect(resScene.length, 1);
      expect(resScene.first.id, 'c1');

      // Search by non-matching keyword
      final resNone = appState.getFilteredClips(searchQuery: 'airplane');
      expect(resNone, isEmpty);
    });

    test('computeMaxSim ranks by cosine similarity and finds hitTimestampMs', () async {
      final clip1 = VideoClip(
        id: 'c1',
        name: 'Action Clip',
        videoPath: 'v1.mp4',
        startTime: const Duration(milliseconds: 1000),
        endTime: const Duration(milliseconds: 7000),
      );
      final clip2 = VideoClip(
        id: 'c2',
        name: 'Ocean Clip',
        videoPath: 'v2.mp4',
        startTime: const Duration(milliseconds: 0),
        endTime: const Duration(milliseconds: 5000),
      );

      await appState.addClip(clip1);
      await appState.addClip(clip2);

      // Populate frame pool with embeddings
      // c1 has a frame at 3500ms aligned with [1.0, 0, 0]
      appState.framePool.putFrames('v1.mp4', [
        const VideoFrameEmbeddingRecord(tMs: 3500, vector: [0.95, 0.05, 0.0], createdAtMs: 1),
      ]);
      // c2 has a frame at 2000ms aligned with [0, 1.0, 0]
      appState.framePool.putFrames('v2.mp4', [
        const VideoFrameEmbeddingRecord(tMs: 2000, vector: [0.0, 0.98, 0.0], createdAtMs: 1),
      ]);

      final queryVec = [1.0, 0.0, 0.0];
      final resC1 = appState.deltaEngine.computeMaxSim(
        queryVector: queryVec,
        frames: appState.framePool.getFramesInRange('v1.mp4', 1000, 7000),
      );
      final resC2 = appState.deltaEngine.computeMaxSim(
        queryVector: queryVec,
        frames: appState.framePool.getFramesInRange('v2.mp4', 0, 5000),
      );

      expect(resC1.score, greaterThan(0.9));
      expect(resC1.hitTimestampMs, 3500);
      expect(resC2.score, closeTo(0.0, 0.05));
    });
  });
}
