import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_clip_manager/services/ai_service.dart';
import 'package:video_clip_manager/services/delta_engine.dart';
import 'package:video_clip_manager/services/frame_embedding_pool.dart';

class MockAiService extends Fake implements AiService {
  int extractCount = 0;
  int embedCount = 0;

  @override
  Future<List<ExtractedClipFrame>> extractClipFrames({
    required String videoPathOrUrl,
    required int startMs,
    required int endMs,
    String strategy = 'interval',
    int everyMs = 2000,
    double threshold = 0.4,
    int maxFrames = 12,
    int maxEdge = 768,
    String? customOutDir,
  }) async {
    extractCount++;
    return [
      ExtractedClipFrame(
        tMs: startMs,
        path: '/tmp/frame0.jpg',
        sizeBytes: 1024,
      ),
      ExtractedClipFrame(tMs: endMs, path: '/tmp/frame1.jpg', sizeBytes: 1024),
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> embedFrames({
    required List<ExtractedClipFrame> frames,
    required String modelDir,
    String? ortLib,
    int softTokens = 140,
  }) async {
    embedCount++;
    return frames
        .map(
          (f) => {
            't_ms': f.tMs,
            'vector': [1.0, 0.0, 0.0],
          },
        )
        .toList();
  }
}

void main() {
  group('FrameEmbeddingPool & VideoFrameEmbeddingRecord', () {
    test('cosineSimilarity computes correctly', () {
      final r1 = VideoFrameEmbeddingRecord(
        tMs: 1000,
        vector: [1.0, 0.0, 0.0],
        createdAtMs: 12345,
      );
      // Identical
      expect(r1.cosineSimilarity([1.0, 0.0, 0.0]), closeTo(1.0, 1e-5));
      // Orthogonal
      expect(r1.cosineSimilarity([0.0, 1.0, 0.0]), closeTo(0.0, 1e-5));
      // Negative
      expect(r1.cosineSimilarity([-1.0, 0.0, 0.0]), closeTo(-1.0, 1e-5));
      // Mismatched dimension
      expect(r1.cosineSimilarity([1.0, 0.0]), 0.0);
    });

    test('putFrames and getFramesInRange filters by time window', () {
      final pool = FrameEmbeddingPool();
      const url = 'https://example.com/stream.m3u8';

      pool.putFrames(url, [
        const VideoFrameEmbeddingRecord(
          tMs: 1000,
          vector: [1.0, 0.0],
          createdAtMs: 1,
        ),
        const VideoFrameEmbeddingRecord(
          tMs: 3000,
          vector: [0.0, 1.0],
          createdAtMs: 1,
        ),
        const VideoFrameEmbeddingRecord(
          tMs: 5000,
          vector: [0.5, 0.5],
          createdAtMs: 1,
        ),
      ]);

      expect(pool.getCachedTimestamps(url), {1000, 3000, 5000});

      final inRange = pool.getFramesInRange(url, 2000, 4000);
      expect(inRange.length, 1);
      expect(inRange.first.tMs, 3000);

      final fullRange = pool.getFramesInRange(url, 0, 6000);
      expect(fullRange.length, 3);
      expect(fullRange.map((f) => f.tMs).toList(), [1000, 3000, 5000]);
    });

    test('saveToDisk and loadFromDisk persists records', () async {
      final tempDir = await Directory.systemTemp.createTemp('pool_test_');
      try {
        final pool1 = FrameEmbeddingPool();
        const video = 'D:/videos/test.mp4';
        pool1.putFrames(video, [
          const VideoFrameEmbeddingRecord(
            tMs: 1500,
            vector: [0.6, 0.8],
            frameImagePath: 'D:/tmp/f1.jpg',
            createdAtMs: 1000,
          ),
          const VideoFrameEmbeddingRecord(
            tMs: 3500,
            vector: [0.8, 0.6],
            frameImagePath: 'D:/tmp/f2.jpg',
            createdAtMs: 2000,
          ),
        ]);

        await pool1.saveToDisk(video, customStorageDir: tempDir.path);

        final pool2 = FrameEmbeddingPool();
        final loadedCount = await pool2.loadFromDisk(
          video,
          customStorageDir: tempDir.path,
        );

        expect(loadedCount, 2);
        final loadedFrames = pool2.getFramesInRange(video, 0, 5000);
        expect(loadedFrames.length, 2);
        expect(loadedFrames[0].tMs, 1500);
        expect(loadedFrames[0].vector, [0.6, 0.8]);
        expect(loadedFrames[0].frameImagePath, 'D:/tmp/f1.jpg');
        expect(loadedFrames[1].tMs, 3500);
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });
  });

  group('DeltaEngine', () {
    test('planDelta detects full missing on empty cache', () {
      final pool = FrameEmbeddingPool();
      final engine = DeltaEngine(pool: pool);
      const video = 'video1.mp4';

      final plan = engine.planDelta(
        videoPathOrUrl: video,
        startMs: 0,
        endMs: 6000,
        stepMs: 2000,
      );

      expect(plan.expectedTimestamps, [0, 2000, 4000, 6000]);
      expect(plan.cachedTimestamps, isEmpty);
      expect(plan.missingTimestamps, [0, 2000, 4000, 6000]);
      expect(plan.isFullCacheHit, isFalse);
      expect(plan.reuseRatio, 0.0);
    });

    test('planDelta detects partial cache hit with tolerance', () {
      final pool = FrameEmbeddingPool();
      const video = 'video1.mp4';

      // Cached frame at 2100ms (tolerance 250ms matches 2000ms)
      pool.putFrames(video, [
        const VideoFrameEmbeddingRecord(
          tMs: 2100,
          vector: [1.0],
          createdAtMs: 1,
        ),
      ]);

      final engine = DeltaEngine(pool: pool);
      final plan = engine.planDelta(
        videoPathOrUrl: video,
        startMs: 0,
        endMs: 4000,
        stepMs: 2000,
        toleranceMs: 250,
      );

      expect(plan.expectedTimestamps, [0, 2000, 4000]);
      expect(plan.cachedTimestamps, [2000]);
      expect(plan.missingTimestamps, [0, 4000]);
      expect(plan.isFullCacheHit, isFalse);
      expect(plan.reuseRatio, closeTo(1 / 3, 1e-4));
    });

    test(
      'planDelta detects 100% cache hit on trimmed/already cached range',
      () {
        final pool = FrameEmbeddingPool();
        const video = 'video1.mp4';

        pool.putFrames(video, [
          const VideoFrameEmbeddingRecord(
            tMs: 0,
            vector: [1.0],
            createdAtMs: 1,
          ),
          const VideoFrameEmbeddingRecord(
            tMs: 2000,
            vector: [1.0],
            createdAtMs: 1,
          ),
          const VideoFrameEmbeddingRecord(
            tMs: 4000,
            vector: [1.0],
            createdAtMs: 1,
          ),
          const VideoFrameEmbeddingRecord(
            tMs: 6000,
            vector: [1.0],
            createdAtMs: 1,
          ),
        ]);

        final engine = DeltaEngine(pool: pool);

        // User trims clip from [0..6000] down to [2000..4000]
        final plan = engine.planDelta(
          videoPathOrUrl: video,
          startMs: 2000,
          endMs: 4000,
          stepMs: 2000,
        );

        expect(plan.expectedTimestamps, [2000, 4000]);
        expect(plan.cachedTimestamps, [2000, 4000]);
        expect(plan.missingTimestamps, isEmpty);
        expect(plan.isFullCacheHit, isTrue);
        expect(plan.reuseRatio, 1.0);
      },
    );

    test('computeMaxSim finds optimal frame and timestamp', () {
      final engine = DeltaEngine();
      final frames = [
        const VideoFrameEmbeddingRecord(
          tMs: 1000,
          vector: [1.0, 0.0, 0.0],
          createdAtMs: 1,
        ),
        const VideoFrameEmbeddingRecord(
          tMs: 3000,
          vector: [0.0, 1.0, 0.0],
          createdAtMs: 1,
        ),
        const VideoFrameEmbeddingRecord(
          tMs: 5000,
          vector: [0.7071, 0.7071, 0.0],
          createdAtMs: 1,
        ),
      ];

      // Query vector strongly aligned with [0, 1, 0]
      final query = [0.1, 0.99, 0.0];
      final result = engine.computeMaxSim(queryVector: query, frames: frames);

      expect(result.hitTimestampMs, 3000);
      expect(result.score, closeTo(0.99, 0.05));
      expect(result.bestFrame?.tMs, 3000);
    });

    test('syncClipRange skips extraction when 100% cache hit', () async {
      final pool = FrameEmbeddingPool();
      const video = 'video1.mp4';
      pool.putFrames(video, [
        const VideoFrameEmbeddingRecord(
          tMs: 1000,
          vector: [1.0, 0.0],
          createdAtMs: 1,
        ),
      ]);

      final mockAi = MockAiService();
      final engine = DeltaEngine(pool: pool, aiService: mockAi);

      final tempDir = await Directory.systemTemp.createTemp('sync_test_');
      try {
        final result = await engine.syncClipRange(
          videoPathOrUrl: video,
          startMs: 1000,
          endMs: 1000,
          stepMs: 2000,
          modelDir: '/models',
          customStorageDir: tempDir.path,
        );

        expect(result.length, 1);
        expect(mockAi.extractCount, 0); // 0 extraction!
        expect(mockAi.embedCount, 0); // 0 inference!
      } finally {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      }
    });
  });
}
