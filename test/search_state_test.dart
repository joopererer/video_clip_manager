import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_clip_manager/data/app_state.dart';
import 'package:video_clip_manager/data/models.dart';
import 'package:video_clip_manager/services/ai_service.dart';
import 'package:video_clip_manager/services/delta_engine.dart';
import 'package:video_clip_manager/services/frame_embedding_pool.dart';
import 'package:video_clip_manager/services/path_service.dart';
import 'package:video_clip_manager/services/thumbnail_service.dart';
import 'package:video_clip_manager/utils/search_mode.dart';

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
  _FakeAi({this.gate});

  Completer<void>? gate;
  int embedCalls = 0;
  final List<String> texts = [];
  final List<String> prefixes = [];

  @override
  Future<List<double>> embedText({
    required String text,
    String prefix = '',
    required String modelDir,
    String? ortLib,
  }) async {
    embedCalls++;
    texts.add(text);
    prefixes.add(prefix);
    final g = gate;
    if (g != null) await g.future;
    return const [1.0, 0.0, 0.0];
  }
}

const String _videoPath = 'C:/media/snow.mp4';

Future<AppState> _createAppState(_FakeAi ai) async {
  final tempDir = await Directory.systemTemp.createTemp('search_state_');
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

void _seedFrames(
  AppState appState, {
  List<int> timestamps = const [1000, 3000],
}) {
  appState.framePool.putFrames(_videoPath, [
    VideoFrameEmbeddingRecord(
      tMs: timestamps[0],
      vector: const [1.0, 0.0, 0.0],
      createdAtMs: 0,
    ),
    VideoFrameEmbeddingRecord(
      tMs: timestamps[1],
      vector: const [0.0, 1.0, 0.0],
      createdAtMs: 0,
    ),
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('search mode helpers', () {
    test('empty query is idle, text is keyword mode', () {
      expect(
        resolveSearchMode(
          query: '   ',
          isSemanticSearching: false,
          semanticResultCount: 0,
        ),
        SearchMode.idle,
      );
      expect(
        resolveSearchMode(
          query: '雪山',
          isSemanticSearching: false,
          semanticResultCount: 0,
        ),
        SearchMode.keyword,
      );
    });

    test('loading wins over keyword and results', () {
      expect(
        resolveSearchMode(
          query: '雪山',
          isSemanticSearching: true,
          semanticResultCount: 4,
        ),
        SearchMode.semanticLoading,
      );
    });

    test('semantic results mode reports the real result count', () {
      final mode = resolveSearchMode(
        query: '雪山',
        isSemanticSearching: false,
        semanticResultCount: 6,
      );
      expect(mode, SearchMode.semanticResults);
      expect(searchModeLabel(mode, semanticResultCount: 6), contains('6'));
      expect(isSemanticMode(mode), isTrue);
      expect(showsSemanticTriggerHint(mode), isFalse);
    });

    test('keyword mode tells the user about Enter and the sparkle button', () {
      final mode = resolveSearchMode(
        query: '雪山',
        isSemanticSearching: false,
        semanticResultCount: 0,
      );
      final hint = searchActionHint(mode);
      expect(hint, contains('Enter'));
      expect(hint, contains('✨'));
      expect(searchModeLabel(mode), '关键词筛选');
      expect(showsSemanticTriggerHint(mode), isTrue);
      expect(
        searchActionHint(SearchMode.semanticLoading),
        contains('AI 语义搜索'),
      );
    });

    test('score is formatted with three decimals and never as accuracy', () {
      expect(formatSemanticScore(0.8632), 'Score: 0.863');
      expect(formatSemanticScore(0.8), 'Score: 0.800');
      expect(formatSemanticScore(0.8).toLowerCase(), isNot(contains('准确')));
      expect(
        formatSemanticScore(0.8).toLowerCase(),
        isNot(contains('confidence')),
      );
      expect(formatSemanticScore(0.8).toLowerCase(), isNot(contains('准确率')));
    });

    test('result headline mentions the query and the count', () {
      expect(semanticResultHeadline('雪山', 6), contains('雪山'));
      expect(semanticResultHeadline('雪山', 6), contains('6'));
    });
  });

  group('AppState semantic search state', () {
    test('commits scores together with the query that produced them', () async {
      final ai = _FakeAi();
      final appState = await _createAppState(ai);
      _seedFrames(appState);
      await appState.addClip(
        const VideoClip(
          id: 'c1',
          name: 'snow mountain',
          videoPath: _videoPath,
          startTime: Duration.zero,
          endTime: Duration(seconds: 2),
        ),
      );

      await appState.performSemanticSearch(
        query: '  雪山  ',
        modelDir: 'model',
      );

      expect(ai.texts, ['雪山'], reason: 'query is trimmed before embedding');
      expect(ai.prefixes.single, 'search_query: ');
      expect(appState.semanticScores.keys, ['c1']);
      expect(appState.semanticQuery, '雪山');
      expect(appState.searchQueryText, '雪山');
      expect(appState.hasStaleSemanticResults, isFalse);
      expect(appState.isSemanticSearching, isFalse);
    });

    test('duplicate Enter never starts a second concurrent request', () async {
      final gate = Completer<void>();
      final ai = _FakeAi(gate: gate);
      final appState = await _createAppState(ai);
      _seedFrames(appState);
      await appState.addClip(
        const VideoClip(
          id: 'c1',
          name: 'snow',
          videoPath: _videoPath,
          endTime: Duration(seconds: 2),
        ),
      );

      final first = appState.performSemanticSearch(
        query: '雪山',
        modelDir: 'model',
      );
      expect(appState.isSemanticSearching, isTrue);

      await appState.performSemanticSearch(query: '雪山', modelDir: 'model');
      await appState.performSemanticSearch(query: '雪山', modelDir: 'model');
      expect(ai.embedCalls, 1, reason: 'no duplicate concurrent embeddings');

      gate.complete();
      await first;

      expect(appState.isSemanticSearching, isFalse);
      expect(appState.semanticScores, isNotEmpty);
    });

    test('changing the query clears the previous HIT and score', () async {
      final ai = _FakeAi();
      final appState = await _createAppState(ai);
      _seedFrames(appState);
      await appState.addClip(
        const VideoClip(
          id: 'c1',
          name: 'snow mountain',
          videoPath: _videoPath,
          endTime: Duration(seconds: 2),
        ),
      );

      await appState.performSemanticSearch(query: '雪山', modelDir: 'model');
      expect(
        appState.getFilteredClips(searchQuery: '雪山').first.hitTimestampMs,
        1000,
      );

      // A new query string in the box invalidates the old semantic result set.
      appState.syncSearchQueryText('自行车');

      expect(appState.semanticScores, isEmpty);
      expect(appState.semanticQuery, isNull);
      final clips = appState.getFilteredClips(searchQuery: '自行车');
      expect(clips, isEmpty, reason: 'no keyword match for 自行车');
      expect(
        appState
            .getFilteredClips(searchQuery: '')
            .every((c) => c.hitTimestampMs == null),
        isTrue,
        reason: 'no stale HIT markers survive the query change',
      );
    });

    test('whitespace-only edits keep the semantic result set', () async {
      final ai = _FakeAi();
      final appState = await _createAppState(ai);
      _seedFrames(appState);
      await appState.addClip(
        const VideoClip(
          id: 'c1',
          name: 'snow',
          videoPath: _videoPath,
          endTime: Duration(seconds: 2),
        ),
      );

      await appState.performSemanticSearch(query: '雪山', modelDir: 'model');
      appState.syncSearchQueryText('  雪山 ');
      expect(appState.semanticScores, isNotEmpty);
    });

    test('a request finishing after the query changed writes nothing', () async {
      final gate = Completer<void>();
      final ai = _FakeAi(gate: gate);
      final appState = await _createAppState(ai);
      _seedFrames(appState);
      await appState.addClip(
        const VideoClip(
          id: 'c1',
          name: 'snow',
          videoPath: _videoPath,
          endTime: Duration(seconds: 2),
        ),
      );

      final future = appState.performSemanticSearch(
        query: '雪山',
        modelDir: 'model',
      );
      appState.syncSearchQueryText('自行车');
      gate.complete();
      await future;

      expect(appState.semanticScores, isEmpty);
      expect(appState.semanticQuery, isNull);
      expect(appState.isSemanticSearching, isFalse);
    });

    test('empty query clears semantic state without embedding', () async {
      final ai = _FakeAi();
      final appState = await _createAppState(ai);
      await appState.performSemanticSearch(query: '   ', modelDir: 'model');
      expect(ai.embedCalls, 0);
      expect(appState.semanticScores, isEmpty);
      expect(appState.semanticQuery, isNull);
    });

    test('a persisted HIT timestamp is never shown without a live match', () async {
      final ai = _FakeAi();
      final appState = await _createAppState(ai);
      await appState.addClip(
        const VideoClip(
          id: 'legacy',
          name: 'legacy clip',
          videoPath: _videoPath,
          endTime: Duration(seconds: 2),
          hitTimestampMs: 5000,
        ),
      );

      final clips = appState.getFilteredClips(searchQuery: '');
      expect(clips.single.hitTimestampMs, isNull);

      // Writing back to the database must not persist the transient HIT.
      await appState.updateClip(clips.single.copyWith(rating: 4));
      expect(appState.clips.single.hitTimestampMs, isNull);
      expect(appState.clips.single.rating, 4);
    });

    test('debug score seeding supports the display contract', () async {
      final ai = _FakeAi();
      final appState = await _createAppState(ai);
      await appState.addClip(
        const VideoClip(
          id: 'c1',
          name: 'snow',
          videoPath: _videoPath,
          endTime: Duration(seconds: 2),
        ),
      );
      appState.debugSetSemanticScores({
        'c1': const MaxSimResult(score: 0.8632, hitTimestampMs: 1234),
      }, query: '雪山');
      final clip = appState.getFilteredClips(searchQuery: '雪山').single;
      expect(clip.hitTimestampMs, 1234);
      expect(appState.semanticScores['c1']!.score, closeTo(0.8632, 1e-9));
    });
  });
}
