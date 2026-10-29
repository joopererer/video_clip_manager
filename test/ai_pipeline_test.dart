import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_clip_manager/data/app_state.dart';
import 'package:video_clip_manager/data/models.dart';
import 'package:video_clip_manager/services/ai_failure.dart';
import 'package:video_clip_manager/services/ai_service.dart';
import 'package:video_clip_manager/services/delta_engine.dart';
import 'package:video_clip_manager/services/frame_embedding_pool.dart';
import 'package:video_clip_manager/services/path_service.dart';
import 'package:video_clip_manager/services/thumbnail_service.dart';

/// Keeps every cache / temp write inside the test's own folder instead of the
/// real application-support directory.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => p.join(root, 'support');

  @override
  Future<String?> getTemporaryPath() async => p.join(root, 'tmp');
}

class _NoThumbnails extends Fake implements ThumbnailService {
  @override
  Future<String?> generateThumbnail(
    String videoPath,
    Duration time,
    String clipId, {
    String? dbPath,
  }) async => null;
}

class ExtractCall {
  ExtractCall(this.video, this.start, this.end);
  final String video;
  final int start;
  final int end;
}

/// Scriptable stand-in for the sidecar-backed [AiService] used by
/// [DeltaEngine] and [AppState].
class ScriptedAi extends Fake implements AiService {
  String? modelDir = 'model';
  final extractCalls = <ExtractCall>[];
  int embedCalls = 0;

  /// Per-call behaviour; defaults produce one frame per 2 s step.
  Future<List<ExtractedClipFrame>> Function(String video, int start, int end)?
  onExtract;
  Future<List<Map<String, dynamic>>> Function(List<ExtractedClipFrame> frames)?
  onEmbed;

  @override
  Future<String?> resolveEmbeddingModelDir() async => modelDir;

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
    extractCalls.add(ExtractCall(videoPathOrUrl, startMs, endMs));
    final custom = onExtract;
    if (custom != null) return custom(videoPathOrUrl, startMs, endMs);
    return [
      for (
        var t = startMs;
        t <= endMs && (t - startMs) ~/ everyMs < 12;
        t += everyMs
      )
        ExtractedClipFrame(tMs: t, path: 'f_$t.jpg', sizeBytes: 10),
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> embedFrames({
    required List<ExtractedClipFrame> frames,
    required String modelDir,
    String? ortLib,
    int softTokens = 140,
  }) async {
    embedCalls++;
    final custom = onEmbed;
    if (custom != null) return custom(frames);
    return [
      for (final f in frames)
        {
          't_ms': f.tMs,
          'vector': [1.0, 0.0, 0.0],
        },
    ];
  }
}

AiStageException _extractionFailure(AiFailureKind kind, String video) =>
    AiStageException(
      stage: AiStage.extraction,
      kind: kind,
      message: describeAiFailure(AiStage.extraction, kind, videoPath: video),
      videoPath: video,
    );

String _ok({String method = 'Seek', List<int> times = const [0]}) => jsonEncode(
  {
    'ok': true,
    'data': {
      'method': method,
      'frames': [
        for (final t in times) {'t_ms': t, 'path': 'f$t.jpg', 'size_bytes': 5},
      ],
    },
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late PathProviderPlatform originalProvider;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ai_pipeline_test_');
    originalProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(root.path);
  });

  tearDown(() async {
    PathProviderPlatform.instance = originalProvider;
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('failure classification', () {
    test('missing source, bad range, unreachable stream, bad media', () {
      expect(
        classifySidecarText('视频不存在: D:\\a\\b.mp4'),
        AiFailureKind.sourceMissing,
      );
      expect(
        classifySidecarText('Error: -to value smaller than -ss'),
        AiFailureKind.invalidRange,
      );
      expect(
        classifySidecarText(
          'Connection to tcp://cdn.example.com:443 failed: Connection refused',
        ),
        AiFailureKind.sourceUnreachable,
      );
      expect(
        classifySidecarText('Server returned 403 Forbidden (access denied)'),
        AiFailureKind.sourceUnreachable,
      );
      expect(
        classifySidecarText('moov atom not found'),
        AiFailureKind.sourceUnsupported,
      );
      expect(
        classifySidecarText('Invalid data found when processing input'),
        AiFailureKind.sourceUnsupported,
      );
    });

    test('unknown text stays processFailed rather than a guess', () {
      expect(classifySidecarText('something odd'), AiFailureKind.processFailed);
      expect(classifySidecarText(''), AiFailureKind.processFailed);
    });

    test('inference stage ignores source-style wording', () {
      expect(
        classifySidecarText(
          'No such file: frame.png',
          stage: AiStage.inference,
        ),
        AiFailureKind.processFailed,
      );
      expect(
        classifySidecarText(
          'failed to load onnxruntime.dll',
          stage: AiStage.inference,
        ),
        AiFailureKind.ortMissing,
      );
      expect(
        classifySidecarText(
          'tokenizer.json not readable',
          stage: AiStage.inference,
        ),
        AiFailureKind.modelMissing,
      );
    });

    test('only environment-wide kinds stop a batch', () {
      bool env(AiFailureKind k) => _extractionFailure(k, 'v').isEnvironmental;
      expect(env(AiFailureKind.cliMissing), isTrue);
      expect(env(AiFailureKind.ffmpegMissing), isTrue);
      expect(env(AiFailureKind.ortMissing), isTrue);
      expect(env(AiFailureKind.modelMissing), isTrue);
      expect(env(AiFailureKind.sourceMissing), isFalse);
      expect(env(AiFailureKind.sourceUnsupported), isFalse);
      expect(env(AiFailureKind.timeout), isFalse);
      expect(env(AiFailureKind.storageFailed), isFalse);
    });

    test('every kind has a distinct, non-empty explanation', () {
      final texts = <String>{};
      for (final k in AiFailureKind.values) {
        final t = describeAiFailure(AiStage.extraction, k);
        expect(t, isNotEmpty);
        texts.add(t);
      }
      // processFailed differs per stage, the rest must not collapse together.
      expect(texts.length, AiFailureKind.values.length);
    });

    test('report carries stage, range, command and exit code', () {
      const e = AiStageException(
        stage: AiStage.extraction,
        kind: AiFailureKind.processFailed,
        message: 'm',
        detail: 'stderr tail',
        videoPath: r'D:\视频 库\a.mp4',
        startMs: 10,
        endMs: 20,
        command: 'extract-clip --video "x"',
        exitCode: 1,
      );
      final r = e.report();
      expect(r, contains('extraction'));
      expect(r, contains(r'D:\视频 库\a.mp4'));
      expect(r, contains('10 - 20 ms'));
      expect(r, contains('extract-clip'));
      expect(r, contains('退出码: 1'));
      expect(r, contains('stderr tail'));
      expect('$e', 'm');
    });

    test('tailForLog redacts credentials and truncates', () {
      final s = tailForLog(
        'GET https://u:pw@host/x.m3u8?token=SECRET123&a=1 Bearer abc.def',
      );
      expect(s, isNot(contains('SECRET123')));
      expect(s, isNot(contains('u:pw')));
      expect(s, isNot(contains('abc.def')));
      final long = tailForLog('x' * 5000, max: 100);
      expect(long.length, lessThanOrEqualTo(101));
      expect(long.startsWith('…'), isTrue);
    });
  });

  group('resolveClipIndexRange', () {
    test('plain range is kept', () {
      final r = resolveClipIndexRange(
        startMs: 1000,
        endMs: 5000,
        videoDurationMs: 60000,
      );
      expect(r.isUsable, isTrue);
      expect((r.startMs, r.endMs), (1000, 5000));
    });

    test('end == 0 means "until the end" and uses the source duration', () {
      final r = resolveClipIndexRange(
        startMs: 2000,
        endMs: 0,
        videoDurationMs: 9000,
      );
      expect(r.isUsable, isTrue);
      expect((r.startMs, r.endMs), (2000, 9000));
    });

    test('end == 0 without a known duration is reported, not guessed', () {
      final r = resolveClipIndexRange(startMs: 0, endMs: 0);
      expect(r.isUsable, isFalse);
      expect(r.problem, AiFailureKind.unknownDuration);
      final r2 = resolveClipIndexRange(
        startMs: 0,
        endMs: 0,
        videoDurationMs: 0,
      );
      expect(r2.problem, AiFailureKind.unknownDuration);
    });

    test('end beyond the video is clamped to the duration', () {
      final r = resolveClipIndexRange(
        startMs: 1000,
        endMs: 90000,
        videoDurationMs: 30000,
      );
      expect(r.endMs, 30000);
      expect(r.isUsable, isTrue);
    });

    test('start at or past the end is an invalid range', () {
      expect(
        resolveClipIndexRange(startMs: 5000, endMs: 5000).problem,
        AiFailureKind.invalidRange,
      );
      expect(
        resolveClipIndexRange(startMs: 7000, endMs: 5000).problem,
        AiFailureKind.invalidRange,
      );
      expect(
        resolveClipIndexRange(
          startMs: 40000,
          endMs: 90000,
          videoDurationMs: 30000,
        ).problem,
        AiFailureKind.invalidRange,
      );
      expect(
        resolveClipIndexRange(startMs: -1, endMs: 5000).problem,
        AiFailureKind.invalidRange,
      );
    });
  });

  group('AiService sidecar calls', () {
    late AiService ai;
    late SidecarRunner originalRunner;
    late Duration originalTimeout;
    List<String>? lastArgs;

    setUp(() {
      ai = AiService();
      originalRunner = ai.sidecarRunner;
      originalTimeout = ai.sidecarTimeout;
      lastArgs = null;
    });

    tearDown(() {
      ai.sidecarRunner = originalRunner;
      ai.sidecarTimeout = originalTimeout;
    });

    void script(SidecarOutput out) {
      ai.sidecarRunner = (exe, args, {required timeout}) async {
        lastArgs = args;
        return out;
      };
    }

    Future<List<ExtractedClipFrame>> extract({
      int start = 4000,
      int end = 8000,
    }) => ai.extractClipFrames(
      videoPathOrUrl: r'D:\视频 库\竖屏 clip.mp4',
      startMs: start,
      endMs: end,
      customOutDir: p.join(root.path, 'frames'),
    );

    Future<AiStageException> extractError({
      int start = 4000,
      int end = 8000,
    }) async {
      try {
        await extract(start: start, end: end);
      } on AiStageException catch (e) {
        return e;
      }
      fail('expected AiStageException');
    }

    test('Seek frames keep their absolute time', () async {
      script(
        SidecarOutput(
          exitCode: 0,
          stdout: _ok(times: [4000, 6000]),
          stderr: '',
        ),
      );
      final frames = await extract();
      expect(frames.map((f) => f.tMs), [4000, 6000]);
    });

    test('Filter frames are shifted by start so t_ms is absolute', () async {
      script(
        SidecarOutput(
          exitCode: 0,
          stdout: _ok(method: 'Filter', times: [0, 2000]),
          stderr: '',
        ),
      );
      final frames = await extract(start: 4000, end: 8000);
      expect(frames.map((f) => f.tMs), [4000, 6000]);
    });

    test('missing method leaves times unchanged', () {
      const f = ExtractedClipFrame(tMs: 500, path: 'a', sizeBytes: 1);
      expect(
        AiService.normalizeFrameTime(f, startMs: 4000, method: null).tMs,
        500,
      );
      expect(
        AiService.normalizeFrameTime(f, startMs: 0, method: 'Filter').tMs,
        500,
      );
      expect(
        AiService.normalizeFrameTime(f, startMs: 4000, method: 'FILTER').tMs,
        4500,
      );
    });

    test('Unicode path with spaces is passed as one argument', () async {
      script(SidecarOutput(exitCode: 0, stdout: _ok(), stderr: ''));
      await extract();
      final i = lastArgs!.indexOf('--video');
      expect(lastArgs![i + 1], r'D:\视频 库\竖屏 clip.mp4');
    });

    test('empty range is rejected before the sidecar runs', () async {
      var ran = false;
      ai.sidecarRunner = (exe, args, {required timeout}) async {
        ran = true;
        return const SidecarOutput(exitCode: 0, stdout: '', stderr: '');
      };
      final e = await extractError(start: 5000, end: 5000);
      expect(e.kind, AiFailureKind.invalidRange);
      expect(e.stage, AiStage.extraction);
      expect(ran, isFalse);
    });

    test('JSON error on stdout is classified and carries context', () async {
      script(
        SidecarOutput(
          exitCode: 1,
          stdout: jsonEncode({'ok': false, 'error': '视频不存在: x.mp4'}),
          stderr: '',
        ),
      );
      final e = await extractError();
      expect(e.kind, AiFailureKind.sourceMissing);
      expect(e.exitCode, 1);
      expect(e.startMs, 4000);
      expect(e.endMs, 8000);
      expect(e.command, contains('extract-clip'));
      expect(e.detail, contains('视频不存在'));
    });

    test('stderr text is used when stdout is not JSON', () async {
      script(
        const SidecarOutput(
          exitCode: 1,
          stdout: '',
          stderr: 'moov atom not found',
        ),
      );
      final e = await extractError();
      expect(e.kind, AiFailureKind.sourceUnsupported);
      expect(e.detail, contains('moov atom'));
    });

    test('credentials in the stream URL never reach the report', () async {
      script(
        const SidecarOutput(
          exitCode: 1,
          stdout: '',
          stderr:
              'Server returned 403 for https://u:pw@cdn.example.com/a.m3u8?token=SECRET123',
        ),
      );
      Object? caught;
      try {
        await ai.extractClipFrames(
          videoPathOrUrl: 'https://u:pw@cdn.example.com/a.m3u8?token=SECRET123',
          startMs: 0,
          endMs: 4000,
          customOutDir: p.join(root.path, 'frames'),
        );
      } on AiStageException catch (e) {
        caught = e;
      }
      final e = caught as AiStageException;
      expect(e.kind, AiFailureKind.sourceUnreachable);
      final report = e.report();
      expect(report, isNot(contains('SECRET123')));
      expect(report, isNot(contains('u:pw')));
    });

    test('exit 0 with unreadable output is outputInvalid', () async {
      script(const SidecarOutput(exitCode: 0, stdout: 'not json', stderr: ''));
      final e = await extractError();
      expect(e.kind, AiFailureKind.outputInvalid);
    });

    test('timeout is reported as timeout, with the limit', () async {
      ai.sidecarTimeout = const Duration(seconds: 7);
      script(
        const SidecarOutput(
          exitCode: -1,
          stdout: '',
          stderr: 'partial',
          timedOut: true,
        ),
      );
      final e = await extractError();
      expect(e.kind, AiFailureKind.timeout);
      expect(e.detail, contains('7s'));
    });

    test('missing executable becomes cliMissing', () async {
      ai.sidecarRunner = (exe, args, {required timeout}) async =>
          throw ProcessException(exe, args, 'not found', 2);
      final e = await extractError();
      expect(e.kind, AiFailureKind.cliMissing);
      expect(e.isEnvironmental, isTrue);
    });

    group('embedFrames', () {
      late Directory modelDir;

      setUp(() async {
        modelDir = await Directory(p.join(root.path, 'model')).create();
        await File(p.join(modelDir.path, 'tokenizer.json')).writeAsString('{}');
      });

      Future<AiStageException> embedError() async {
        try {
          await ai.embedFrames(
            frames: const [ExtractedClipFrame(tMs: 0, path: 'a', sizeBytes: 1)],
            modelDir: modelDir.path,
            ortLib: 'ort.dll',
          );
        } on AiStageException catch (e) {
          return e;
        }
        fail('expected AiStageException');
      }

      test('success returns embeddings', () async {
        script(
          SidecarOutput(
            exitCode: 0,
            stdout: jsonEncode({
              'ok': true,
              'data': {
                'embeddings': [
                  {
                    't_ms': 0,
                    'vector': [1.0, 2.0],
                  },
                ],
              },
            }),
            stderr: '',
          ),
        );
        final out = await ai.embedFrames(
          frames: const [ExtractedClipFrame(tMs: 0, path: 'a', sizeBytes: 1)],
          modelDir: modelDir.path,
          ortLib: 'ort.dll',
        );
        expect(out.single['vector'], [1.0, 2.0]);
      });

      test(
        'failure is an inference-stage error, not an extraction one',
        () async {
          script(
            SidecarOutput(
              exitCode: 1,
              stdout: jsonEncode({
                'ok': false,
                'error': 'onnxruntime load failed',
              }),
              stderr: '',
            ),
          );
          final e = await embedError();
          expect(e.stage, AiStage.inference);
          expect(e.kind, AiFailureKind.ortMissing);
          expect(e.command, contains('embed-frames'));
          // The frame payload must not be echoed into the report.
          expect(e.command, isNot(contains('size_bytes')));
        },
      );

      test('timeout is an inference timeout', () async {
        script(
          const SidecarOutput(
            exitCode: -1,
            stdout: '',
            stderr: '',
            timedOut: true,
          ),
        );
        final e = await embedError();
        expect((e.stage, e.kind), (AiStage.inference, AiFailureKind.timeout));
      });

      test('no frames means no sidecar call', () async {
        var ran = false;
        ai.sidecarRunner = (exe, args, {required timeout}) async {
          ran = true;
          return const SidecarOutput(exitCode: 0, stdout: '', stderr: '');
        };
        expect(
          await ai.embedFrames(frames: const [], modelDir: modelDir.path),
          isEmpty,
        );
        expect(ran, isFalse);
      });
    });
  });

  group('FrameEmbeddingPool storage', () {
    late Directory cacheDir;
    late FrameEmbeddingPool pool;
    const video = r'D:\视频 库\a.mp4';

    setUp(() async {
      cacheDir = await Directory(p.join(root.path, 'cache')).create();
      pool = FrameEmbeddingPool();
    });

    VideoFrameEmbeddingRecord rec(int t) =>
        VideoFrameEmbeddingRecord(tMs: t, vector: const [1, 0], createdAtMs: 1);

    File cacheFile() =>
        File(p.join(cacheDir.path, '${pool.computeVideoKey(video)}.json'));

    test('save is atomic: no .tmp left, content round-trips', () async {
      pool.putFrames(video, [rec(0), rec(2000)]);
      await pool.saveToDisk(video, customStorageDir: cacheDir.path);

      expect(await cacheFile().exists(), isTrue);
      expect(await File('${cacheFile().path}.tmp').exists(), isFalse);

      final fresh = FrameEmbeddingPool();
      expect(
        await fresh.loadFromDisk(video, customStorageDir: cacheDir.path),
        2,
      );
      expect(fresh.getCachedTimestamps(video), {0, 2000});
    });

    test('corrupt cache is set aside, not overwritten silently', () async {
      await cacheFile().writeAsString('{ this is not json');
      expect(
        await pool.loadFromDisk(video, customStorageDir: cacheDir.path),
        0,
      );
      expect(await cacheFile().exists(), isFalse);
      final kept = cacheDir.listSync().whereType<File>().where(
        (f) => f.path.contains('.corrupt-'),
      );
      expect(kept, hasLength(1));
      expect(await kept.single.readAsString(), '{ this is not json');
    });

    test('a failed write surfaces as a storage-stage error', () async {
      // A directory where the cache file should be makes the rename fail.
      await Directory(cacheFile().path).create();
      pool.putFrames(video, [rec(0)]);
      Object? caught;
      try {
        await pool.saveToDisk(video, customStorageDir: cacheDir.path);
      } on AiStageException catch (e) {
        caught = e;
      }
      final e = caught as AiStageException;
      expect(e.stage, AiStage.storage);
      expect(e.kind, AiFailureKind.storageFailed);
      expect(await File('${cacheFile().path}.tmp').exists(), isFalse);
    });

    test('empty pool writes nothing', () async {
      await pool.saveToDisk(video, customStorageDir: cacheDir.path);
      expect(await cacheFile().exists(), isFalse);
    });
  });

  group('DeltaEngine.syncClipRange', () {
    late Directory cacheDir;
    late ScriptedAi ai;
    late FrameEmbeddingPool pool;
    late DeltaEngine engine;
    const video = r'D:\视频 库\a.mp4';

    setUp(() async {
      cacheDir = await Directory(p.join(root.path, 'cache')).create();
      ai = ScriptedAi();
      pool = FrameEmbeddingPool();
      engine = DeltaEngine(pool: pool, aiService: ai);
    });

    Future<List<VideoFrameEmbeddingRecord>> sync(int s, int e) =>
        engine.syncClipRange(
          videoPathOrUrl: video,
          startMs: s,
          endMs: e,
          modelDir: 'model',
          customStorageDir: cacheDir.path,
        );

    Future<AiStageException> syncError(int s, int e) async {
      try {
        await sync(s, e);
      } on AiStageException catch (err) {
        return err;
      }
      fail('expected AiStageException');
    }

    test(
      'single missing point asks for one step, never an empty range',
      () async {
        // 1.5 s clip -> one expected frame, so min == max.
        final frames = await sync(1000, 2500);
        expect(ai.extractCalls, hasLength(1));
        expect(ai.extractCalls.single.start, 1750);
        expect(ai.extractCalls.single.end, 1750 + 2000);
        expect(frames, isNotEmpty);
      },
    );

    test('second run is a pure cache hit', () async {
      await sync(0, 4000);
      expect(ai.extractCalls, hasLength(1));
      await sync(0, 4000);
      expect(ai.extractCalls, hasLength(1));
      expect(ai.embedCalls, 1);
    });

    test('cache written by one engine is reused by a fresh one', () async {
      await sync(0, 4000);
      final ai2 = ScriptedAi();
      final engine2 = DeltaEngine(pool: FrameEmbeddingPool(), aiService: ai2);
      await engine2.syncClipRange(
        videoPathOrUrl: video,
        startMs: 0,
        endMs: 4000,
        modelDir: 'model',
        customStorageDir: cacheDir.path,
      );
      expect(ai2.extractCalls, isEmpty);
    });

    test('extension extracts only the new part', () async {
      await sync(0, 4000);
      await sync(0, 8000);
      expect(ai.extractCalls, hasLength(2));
      expect(ai.extractCalls.last.start, 6000);
      expect(ai.extractCalls.last.end, 8000);
    });

    test('empty extraction is a noFrames extraction error', () async {
      ai.onExtract = (v, s, e) async => const [];
      final e = await syncError(0, 4000);
      expect((e.stage, e.kind), (AiStage.extraction, AiFailureKind.noFrames));
      expect(ai.embedCalls, 0);
    });

    test('frames without vectors are not cached as valid', () async {
      ai.onEmbed = (frames) async => [
        {'t_ms': frames.first.tMs, 'vector': <double>[]},
        for (final f in frames.skip(1))
          {
            't_ms': f.tMs,
            'vector': [0.0, 1.0],
          },
      ];
      final out = await sync(0, 4000);
      expect(out.map((r) => r.tMs), isNot(contains(0)));
      expect(pool.getCachedTimestamps(video), isNot(contains(0)));

      // The empty frame is still "missing", so the next run asks for it again.
      ai.onEmbed = null;
      ai.extractCalls.clear();
      await sync(0, 4000);
      expect(ai.extractCalls, hasLength(1));
      expect(pool.getCachedTimestamps(video), contains(0));
    });

    test(
      'no vector for any frame is an inference error and caches nothing',
      () async {
        ai.onEmbed = (frames) async => [
          for (final f in frames) {'t_ms': f.tMs, 'vector': <double>[]},
        ];
        final e = await syncError(0, 4000);
        expect(
          (e.stage, e.kind),
          (AiStage.inference, AiFailureKind.outputInvalid),
        );
        expect(pool.getCachedTimestamps(video), isEmpty);
        expect(cacheDir.listSync(), isEmpty);
      },
    );

    test('a failure while extending keeps what was already cached', () async {
      await sync(0, 4000);
      ai.onExtract = (v, s, e) async =>
          throw _extractionFailure(AiFailureKind.timeout, v);
      final e = await syncError(0, 10000);
      expect(e.kind, AiFailureKind.timeout);

      // Same engine and a brand-new one both still see the first 3 frames.
      expect(pool.getCachedTimestamps(video), containsAll([0, 2000, 4000]));
      final fresh = FrameEmbeddingPool();
      await fresh.loadFromDisk(video, customStorageDir: cacheDir.path);
      expect(fresh.getCachedTimestamps(video), {0, 2000, 4000});
    });

    test('inference failure keeps earlier cache too', () async {
      await sync(0, 4000);
      ai.onEmbed = (frames) async => throw const AiStageException(
        stage: AiStage.inference,
        kind: AiFailureKind.timeout,
        message: 'timeout',
      );
      final e = await syncError(0, 10000);
      expect(e.stage, AiStage.inference);
      final fresh = FrameEmbeddingPool();
      await fresh.loadFromDisk(video, customStorageDir: cacheDir.path);
      expect(fresh.getCachedTimestamps(video), {0, 2000, 4000});
    });
  });

  group('AppState.indexAllClips', () {
    late ScriptedAi ai;

    Future<File> media(String name) async {
      final f = File(p.join(root.path, 'media', name));
      await f.parent.create(recursive: true);
      await f.writeAsBytes(const [0]);
      return f;
    }

    Map<String, dynamic> clipJson(
      String id,
      String path, {
      int start = 0,
      int end = 4000,
    }) => {
      'id': id,
      'label': 'Clip $id',
      'videoPath': path,
      'start': start,
      'end': end,
    };

    /// Builds an [AppState] backed by a database holding [clips] and the given
    /// source durations (ms) for end == 0 resolution.
    Future<AppState> load(
      List<Map<String, dynamic>> clips, {
      Map<String, int> durations = const {},
    }) async {
      final db = File(p.join(root.path, 'db.json'));
      await db.writeAsString(
        jsonEncode({
          'clips': clips,
          'videos': [
            for (final e in durations.entries)
              {
                'id': 'vid_${e.key.hashCode}',
                'path': e.key,
                'name': p.basename(e.key),
                'duration': e.value,
              },
          ],
        }),
      );
      SharedPreferences.setMockInitialValues({'db_path': db.path});
      final prefs = await SharedPreferences.getInstance();
      final state = AppState(
        prefs: prefs,
        pathService: PathService(),
        thumbnailService: _NoThumbnails(),
        aiService: ai,
      );
      await state.loadInitialData();
      return state;
    }

    setUp(() {
      ai = ScriptedAi();
    });

    test('one missing file is skipped and the rest are indexed', () async {
      final a = await media('a.mp4');
      final c = await media('c.mp4');
      final missing = p.join(root.path, 'media', 'gone.mp4');
      final state = await load([
        clipJson('a', a.path),
        clipJson('b', missing),
        clipJson('c', c.path),
      ]);

      await state.indexAllClips();

      expect(state.lastIndexOkCount, 2);
      expect(state.indexFailures, hasLength(1));
      final f = state.indexFailures.single;
      expect(f.clipId, 'b');
      expect(
        (f.stage, f.kind),
        (AiStage.extraction, AiFailureKind.sourceMissing),
      );
      expect(f.report, contains('gone.mp4'));
      expect(ai.extractCalls.map((e) => e.video), [a.path, c.path]);
      expect(state.isIndexingEmbeddings, isFalse);
      expect(state.indexingStatus, contains('成功 2 个'));
      expect(state.indexingStatus, contains('失败 1 个'));
    });

    test('Unicode path with spaces on a portrait source is indexed', () async {
      final v = await media('竖屏 视频 01.mp4');
      final state = await load([clipJson('u', v.path)]);
      await state.indexAllClips();
      expect(state.indexFailures, isEmpty);
      expect(ai.extractCalls.single.video, v.path);
      expect(state.indexingStatus, contains('构建完成'));
    });

    test('end == 0 is resolved with the source duration', () async {
      final v = await media('whole.mp4');
      final state = await load(
        [clipJson('w', v.path, start: 1000, end: 0)],
        durations: {v.path: 6000},
      );
      await state.indexAllClips();
      expect(state.indexFailures, isEmpty);
      expect(ai.extractCalls.first.start, 1000);
      expect(ai.extractCalls.every((e) => e.end <= 6000), isTrue);
      // The stored clip is untouched: still "until the end".
      expect(state.clips.single.endTime, Duration.zero);
    });

    test('end == 0 with unknown duration is reported and skipped', () async {
      final v = await media('whole.mp4');
      final ok = await media('ok.mp4');
      final state = await load([
        clipJson('w', v.path, end: 0),
        clipJson('ok', ok.path),
      ]);
      await state.indexAllClips();
      expect(state.lastIndexOkCount, 1);
      expect(state.indexFailures.single.kind, AiFailureKind.unknownDuration);
      expect(ai.extractCalls.map((e) => e.video), [ok.path]);
    });

    test('invalid range is reported without calling the sidecar', () async {
      final v = await media('v.mp4');
      final state = await load([clipJson('r', v.path, start: 5000, end: 3000)]);
      await state.indexAllClips();
      expect(state.indexFailures.single.kind, AiFailureKind.invalidRange);
      expect(ai.extractCalls, isEmpty);
    });

    test(
      'a failing clip does not stop later clips; failures are labelled by stage',
      () async {
        final a = await media('a.mp4');
        final bad = await media('bad.mp4');
        final slow = await media('slow.mp4');
        final c = await media('c.mp4');
        ai.onExtract = (v, s, e) async {
          if (v == bad.path) {
            throw _extractionFailure(AiFailureKind.sourceUnsupported, v);
          }
          return [ExtractedClipFrame(tMs: s, path: 'f.jpg', sizeBytes: 1)];
        };
        ai.onEmbed = (frames) async {
          if (frames.any((f) => f.path == 'slow')) {
            throw const AiStageException(
              stage: AiStage.inference,
              kind: AiFailureKind.timeout,
              message: 'timeout',
            );
          }
          return [
            for (final f in frames)
              {
                't_ms': f.tMs,
                'vector': [1.0, 0.0],
              },
          ];
        };
        final prev = ai.onExtract!;
        ai.onExtract = (v, s, e) async {
          if (v == slow.path) {
            return [ExtractedClipFrame(tMs: s, path: 'slow', sizeBytes: 1)];
          }
          return prev(v, s, e);
        };

        final state = await load([
          clipJson('a', a.path),
          clipJson('bad', bad.path),
          clipJson('slow', slow.path),
          clipJson('c', c.path),
        ]);
        await state.indexAllClips();

        expect(state.lastIndexOkCount, 2);
        final byId = {for (final f in state.indexFailures) f.clipId: f};
        expect(byId.keys, {'bad', 'slow'});
        expect(byId['bad']!.stage, AiStage.extraction);
        expect(byId['slow']!.stage, AiStage.inference);
        expect(ai.extractCalls.map((e) => e.video), contains(c.path));
      },
    );

    test('environmental failure stops the batch after one report', () async {
      final a = await media('a.mp4');
      final b = await media('b.mp4');
      final c = await media('c.mp4');
      ai.onExtract = (v, s, e) async =>
          throw _extractionFailure(AiFailureKind.ffmpegMissing, v);
      final state = await load([
        clipJson('a', a.path),
        clipJson('b', b.path),
        clipJson('c', c.path),
      ]);
      await state.indexAllClips();
      expect(ai.extractCalls, hasLength(1));
      expect(state.indexFailures, hasLength(1));
      expect(state.indexingStatus, contains('已停止'));
      expect(state.isIndexingEmbeddings, isFalse);
    });

    test(
      'an unexpected exception is shown as an internal error and isolated',
      () async {
        final a = await media('a.mp4');
        final b = await media('b.mp4');
        var first = true;
        ai.onExtract = (v, s, e) async {
          if (first) {
            first = false;
            throw StateError('boom');
          }
          return [ExtractedClipFrame(tMs: s, path: 'f.jpg', sizeBytes: 1)];
        };
        final state = await load([
          clipJson('a', a.path),
          clipJson('b', b.path),
        ]);
        await state.indexAllClips();
        expect(state.lastIndexOkCount, 1);
        final f = state.indexFailures.single;
        expect((f.stage, f.kind), (AiStage.internal, AiFailureKind.unknown));
        expect(f.message, contains('boom'));
      },
    );

    test(
      'a failed clip keeps earlier cache, and a re-run retries only failures',
      () async {
        final a = await media('a.mp4');
        final b = await media('b.mp4');
        var bFails = true;
        ai.onExtract = (v, s, e) async {
          if (v == b.path && bFails) {
            throw _extractionFailure(AiFailureKind.timeout, v);
          }
          return [
            for (var t = s; t <= e; t += 2000)
              ExtractedClipFrame(tMs: t, path: 'f_$t.jpg', sizeBytes: 1),
          ];
        };
        final state = await load([
          clipJson('a', a.path),
          clipJson('b', b.path),
        ]);

        await state.indexAllClips();
        expect(state.indexFailures.map((f) => f.clipId), ['b']);
        expect(state.framePool.getCachedTimestamps(a.path), {0, 2000, 4000});
        expect(state.framePool.getCachedTimestamps(b.path), isEmpty);

        // The cache for A is on disk, not just in memory.
        final reread = FrameEmbeddingPool();
        expect(await reread.loadFromDisk(a.path), 3);

        // Second run: A is a cache hit (no extraction), B is retried and works.
        bFails = false;
        ai.extractCalls.clear();
        await state.indexAllClips();
        expect(ai.extractCalls.map((e) => e.video), [b.path]);
        expect(state.indexFailures, isEmpty);
        expect(state.framePool.getCachedTimestamps(b.path), {0, 2000, 4000});
        expect(state.framePool.getCachedTimestamps(a.path), {0, 2000, 4000});
      },
    );

    test(
      'a failure in one clip of a video does not drop another clip of it',
      () async {
        final v = await media('shared.mp4');
        final state = await load([
          clipJson('first', v.path, start: 0, end: 4000),
          clipJson('second', v.path, start: 4000, end: 8000),
        ]);
        await state.indexAllClips();
        ai.onExtract = (vv, s, e) async =>
            throw _extractionFailure(AiFailureKind.timeout, vv);
        // Extending the video's coverage fails, existing frames stay usable.
        await state.indexAllClips();
        expect(
          state.framePool.getCachedTimestamps(v.path),
          containsAll([0, 2000, 4000, 6000, 8000]),
        );
      },
    );

    test('online clips are counted as skipped, not failed', () async {
      final a = await media('a.mp4');
      final state = await load([
        clipJson('a', a.path),
        clipJson('net', 'https://cdn.example.com/live.m3u8?token=SECRET123'),
      ]);
      await state.indexAllClips();
      expect(state.lastIndexOkCount, 1);
      expect(state.lastIndexSkippedCount, 1);
      expect(state.indexFailures, isEmpty);
      expect(state.indexingStatus, contains('跳过 1 个在线片段'));
      expect(ai.extractCalls.map((e) => e.video), [a.path]);
    });

    test('only online clips leaves a clear message', () async {
      final state = await load([
        clipJson('net', 'http://cdn.example.com/a.m3u8'),
      ]);
      await state.indexAllClips();
      expect(state.indexingStatus, contains('暂无需要索引的本地片段'));
      expect(ai.extractCalls, isEmpty);
    });

    test('missing model stops before any extraction with guidance', () async {
      final a = await media('a.mp4');
      ai.modelDir = null;
      final state = await load([clipJson('a', a.path)]);
      await state.indexAllClips();
      expect(ai.extractCalls, isEmpty);
      expect(state.indexingStatus, contains('下载'));
      expect(state.isIndexingEmbeddings, isFalse);
    });

    test('a second call while running is ignored', () async {
      final a = await media('a.mp4');
      final gate = Completer<void>();
      ai.onExtract = (v, s, e) async {
        await gate.future;
        return [ExtractedClipFrame(tMs: s, path: 'f.jpg', sizeBytes: 1)];
      };
      final state = await load([clipJson('a', a.path)]);
      final running = state.indexAllClips();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(state.isIndexingEmbeddings, isTrue);
      await state.indexAllClips(); // returns immediately
      gate.complete();
      await running;
      expect(ai.extractCalls, hasLength(1));
      expect(state.isIndexingEmbeddings, isFalse);
    });
  });
}
