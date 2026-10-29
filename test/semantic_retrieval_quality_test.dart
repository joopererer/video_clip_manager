import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_clip_manager/data/app_state.dart';
import 'package:video_clip_manager/data/models.dart';
import 'package:video_clip_manager/services/ai_service.dart';
import 'package:video_clip_manager/services/frame_embedding_pool.dart';
import 'package:video_clip_manager/services/path_service.dart';
import 'package:video_clip_manager/services/thumbnail_service.dart';

/// Reproducible, offline evaluation harness for semantic retrieval.
///
/// The sidecar model, the embedding cache and the user's media are not needed:
/// frames are seeded directly into the frame pool with known unit vectors, so
/// the retrieval contract (thresholding, ordering, best-frame mapping, query
/// preprocessing) can be verified deterministically. Real-world relevance still
/// has to be judged by a human; `docs/ui-upgrade/semantic_eval/` holds the
/// evaluation set used for that.
class _NoThumbs extends Fake implements ThumbnailService {
  @override
  Future<String?> generateThumbnail(
    String videoPath,
    Duration time,
    String clipId, {
    String? dbPath,
  }) async => null;
}

class _FakeAi extends Fake implements AiService {
  _FakeAi(this.vector);

  final List<double> vector;
  final List<String> texts = [];
  final List<String> prefixes = [];

  @override
  Future<List<double>> embedText({
    required String text,
    String prefix = '',
    required String modelDir,
    String? ortLib,
  }) async {
    texts.add(text);
    prefixes.add(prefix);
    return vector;
  }
}

const String _videoPath = 'C:/media/eval.mp4';

Future<AppState> _newAppState(_FakeAi ai) async {
  final tempDir = await Directory.systemTemp.createTemp('semantic_eval_');
  final dbFile = File('${tempDir.path}/db.json');
  await dbFile.writeAsString('[]');
  SharedPreferences.setMockInitialValues({'db_path': dbFile.path});
  final prefs = await SharedPreferences.getInstance();
  final appState = AppState(
    prefs: prefs,
    pathService: PathService(),
    thumbnailService: _NoThumbs(),
    aiService: ai,
  );
  await appState.loadInitialData();
  return appState;
}

/// A frame whose cosine similarity with the query `[1, 0, 0]` is exactly
/// [similarity] (the vector is a unit vector in the x/y plane).
VideoFrameEmbeddingRecord _frameAt(int tMs, double similarity) {
  final y = (1 - similarity * similarity).clamp(0.0, 1.0);
  final vector = <double>[similarity, y == 0 ? 0.0 : math.sqrt(y), 0.0];
  return VideoFrameEmbeddingRecord(tMs: tMs, vector: vector, createdAtMs: 0);
}

VideoClip _clip(String id, int startMs, int endMs, {String? name}) => VideoClip(
  id: id,
  name: name ?? id,
  videoPath: _videoPath,
  startTime: Duration(milliseconds: startMs),
  endTime: Duration(milliseconds: endMs),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('retrieval contract', () {
    test('returns every clip above minScore instead of a fixed Top-K', () async {
      final ai = _FakeAi(const [1.0, 0.0, 0.0]);
      final appState = await _newAppState(ai);

      const clipCount = 12;
      for (var i = 0; i < clipCount; i++) {
        final startMs = i * 4000;
        appState.framePool.putFrames(_videoPath, [
          _frameAt(startMs + 1000, 0.9),
        ]);
        await appState.addClip(_clip('c$i', startMs, startMs + 3000));
      }

      await appState.performSemanticSearch(query: '雪山', modelDir: 'model');

      expect(
        appState.semanticScores.length,
        clipCount,
        reason:
            'the pipeline has no Top-K cut: every clip over the score '
            'threshold is returned',
      );
    });

    test('minScore is the only filter, so borderline scores are returned', () async {
      final ai = _FakeAi(const [1.0, 0.0, 0.0]);
      final appState = await _newAppState(ai);

      appState.framePool.putFrames(_videoPath, [
        _frameAt(1000, 0.95), // clearly relevant
        _frameAt(5000, 0.30), // just above the 0.28 default threshold
        _frameAt(9000, 0.10), // below the threshold
      ]);
      await appState.addClip(_clip('strong', 0, 2000));
      await appState.addClip(_clip('borderline', 4000, 6000));
      await appState.addClip(_clip('weak', 8000, 10000));

      await appState.performSemanticSearch(query: '自行车', modelDir: 'model');

      final scores = appState.semanticScores;
      expect(scores.keys.toSet(), {'strong', 'borderline'});
      expect(scores['strong']!.score, closeTo(0.95, 1e-6));
      expect(
        scores['borderline']!.score,
        closeTo(0.30, 1e-6),
        reason:
            'low scores are not filtered out to "look good"; the threshold '
            'is the only gate and is unchanged in v1.1',
      );
      expect(scores.containsKey('weak'), isFalse);

      // An explicit minScore is honoured as well.
      await appState.performSemanticSearch(
        query: '自行车',
        modelDir: 'model',
        minScore: 0.5,
      );
      expect(appState.semanticScores.keys.toSet(), {'strong'});
    });

    test('clip score is the max over the frames inside the clip range', () async {
      final ai = _FakeAi(const [1.0, 0.0, 0.0]);
      final appState = await _newAppState(ai);

      appState.framePool.putFrames(_videoPath, [
        _frameAt(1000, 0.42),
        _frameAt(3000, 0.88),
        _frameAt(5000, 0.51),
      ]);
      await appState.addClip(_clip('wide', 0, 6000), );
      await appState.addClip(_clip('narrow', 4000, 6000));

      await appState.performSemanticSearch(query: '雪山', modelDir: 'model');

      final wide = appState.semanticScores['wide']!;
      expect(wide.score, closeTo(0.88, 1e-6));
      expect(
        wide.hitTimestampMs,
        3000,
        reason: 'HIT is the timestamp of the frame that produced the score',
      );

      final narrow = appState.semanticScores['narrow']!;
      expect(narrow.score, closeTo(0.51, 1e-6));
      expect(narrow.hitTimestampMs, 5000);
    });

    test('results are ordered strictly by descending similarity', () async {
      final ai = _FakeAi(const [1.0, 0.0, 0.0]);
      final appState = await _newAppState(ai);

      appState.framePool.putFrames(_videoPath, [
        _frameAt(1000, 0.31),
        _frameAt(5000, 0.87),
        _frameAt(9000, 0.56),
      ]);
      await appState.addClip(_clip('a', 0, 2000));
      await appState.addClip(_clip('b', 4000, 6000));
      await appState.addClip(_clip('c', 8000, 10000));

      await appState.performSemanticSearch(query: '雪山', modelDir: 'model');

      final filtered = appState.getFilteredClips(searchQuery: '雪山');
      expect(filtered.map((c) => c.id).toList(), ['b', 'c', 'a']);
      expect(filtered.map((c) => c.hitTimestampMs).toList(), [5000, 9000, 1000]);
    });

    test('Chinese query text reaches the embedder unchanged', () async {
      final ai = _FakeAi(const [1.0, 0.0, 0.0]);
      final appState = await _newAppState(ai);
      await appState.performSemanticSearch(
        query: '  自行车  ',
        modelDir: 'model',
      );

      expect(ai.texts.single, '自行车');
      expect(
        ai.prefixes.single,
        'search_query: ',
        reason: 'query prefix must match the embedding model task prefix',
      );
    });

    test('records the score distribution for the audit trail', () async {
      final ai = _FakeAi(const [1.0, 0.0, 0.0]);
      final appState = await _newAppState(ai);

      final cases = <String, double>{
        'bicycle_trail': 0.71,
        'bicycle_road': 0.34,
        'beach_sunset': 0.29,
        'snow_mountain': 0.18,
      };
      var t = 1000;
      for (final entry in cases.entries) {
        appState.framePool.putFrames(_videoPath, [
          _frameAt(t, entry.value),
        ]);
        await appState.addClip(_clip(entry.key, t - 500, t + 500));
        t += 4000;
      }

      await appState.performSemanticSearch(query: '自行车', modelDir: 'model');

      final rows = appState.semanticScores.entries
          .map(
            (e) =>
                '${e.key}\tscore=${e.value.score.toStringAsFixed(3)}'
                '\thit=${e.value.hitTimestampMs}ms',
          )
          .toList()
        ..sort();

      // ignore: avoid_print
      print(
        '[semantic-eval] query=自行车 (default minScore=0.28)\n'
        '${rows.join('\n')}',
      );

      expect(appState.semanticScores.length, 3);
      expect(
        appState.semanticScores.containsKey('snow_mountain'),
        isFalse,
        reason: '0.18 is below the default threshold',
      );
    });
  });
}
