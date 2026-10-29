import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_clip_manager/data/app_state.dart';
import 'package:video_clip_manager/data/models.dart';
import 'package:video_clip_manager/services/ai_failure.dart';
import 'package:video_clip_manager/services/ai_service.dart';
import 'package:video_clip_manager/services/frame_embedding_pool.dart';
import 'package:video_clip_manager/services/path_service.dart';
import 'package:video_clip_manager/services/thumbnail_service.dart';

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => p.join(root, 'support');
  @override
  Future<String?> getTemporaryPath() async => p.join(root, 'tmp');
}

class _NoThumbs extends Fake implements ThumbnailService {
  @override
  Future<String?> generateThumbnail(String videoPath, Duration time, String clipId, {String? dbPath}) async => null;
}

class _ScriptedAi extends Fake implements AiService {
  @override
  Future<String?> resolveEmbeddingModelDir() async => 'model';

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
    return [
      ExtractedClipFrame(tMs: startMs, path: 'f.jpg', sizeBytes: 10),
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> embedFrames({
    required List<ExtractedClipFrame> frames,
    required String modelDir,
    String? ortLib,
    int softTokens = 140,
  }) async {
    return [
      for (final f in frames)
        {'t_ms': f.tMs, 'vector': [1.0, 0.0, 0.0]},
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('indexAllClips isolates a missing-media failure', () async {
    final tempDir = await Directory.systemTemp.createTemp('index_iso_');
    final dbFile = File(p.join(tempDir.path, 'db.json'));
    await dbFile.writeAsString('[]');
    SharedPreferences.setMockInitialValues({'db_path': dbFile.path});
    final prefs = await SharedPreferences.getInstance();

    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);

    final validVideo = File(p.join(tempDir.path, 'valid.mp4'));
    await validVideo.writeAsBytes([1, 2, 3]);

    final appState = AppState(
      prefs: prefs,
      pathService: PathService(),
      thumbnailService: _NoThumbs(),
      aiService: _ScriptedAi(),
    );
    await appState.loadInitialData();

    await appState.addClip(VideoClip(
      id: 'valid',
      name: 'valid clip',
      videoPath: validVideo.path,
      startTime: Duration.zero,
      endTime: const Duration(seconds: 2),
    ));
    await appState.addClip(VideoClip(
      id: 'missing',
      name: 'missing clip',
      videoPath: p.join(tempDir.path, 'missing.mp4'),
      startTime: Duration.zero,
      endTime: const Duration(seconds: 2),
    ));

    await appState.indexAllClips();

    expect(appState.lastIndexOkCount, 1);
    expect(appState.indexFailures, hasLength(1));
    expect(appState.indexFailures.single.clipName, 'missing clip');
    expect(appState.indexFailures.single.kind, AiFailureKind.sourceMissing);
    expect(
      appState.framePool.getFramesInRange(validVideo.path, 0, 2000),
      isNotEmpty,
    );

    await tempDir.delete(recursive: true);
  });
}
