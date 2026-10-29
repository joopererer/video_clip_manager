import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:video_clip_manager/services/ai_model_downloader.dart';
import 'package:video_clip_manager/services/ai_model_manifest.dart';
import 'package:video_clip_manager/services/ai_model_verifier.dart';

String _sha(List<int> bytes) => sha256.convert(bytes).toString();

/// Small two-file manifest so tests stay fast.
class _Fixture {
  _Fixture() {
    a = utf8.encode('config-file-content');
    b = List<int>.generate(4096, (i) => i % 251);
    manifest = ModelManifest(
      id: 'test-model',
      repo: 'owner/repo',
      commit: 'abc123',
      files: [
        ModelFileSpec(path: 'config.json', size: a.length, sha256: _sha(a)),
        ModelFileSpec(path: 'onnx/model.onnx', size: b.length, sha256: _sha(b)),
      ],
    );
  }

  late final List<int> a;
  late final List<int> b;
  late final ModelManifest manifest;

  Map<String, List<int>> get bodies => {
    '/owner/repo/resolve/abc123/config.json': a,
    '/owner/repo/resolve/abc123/onnx/model.onnx': b,
  };
}

Future<void> _writeValid(String dir, _Fixture f) async {
  await File(p.join(dir, 'config.json')).writeAsBytes(f.a);
  await Directory(p.join(dir, 'onnx')).create(recursive: true);
  await File(p.join(dir, 'onnx', 'model.onnx')).writeAsBytes(f.b);
}

/// Serves [bodies] and honours single-range requests (`bytes=N-`).
MockClient _server(
  Map<String, List<int>> bodies, {
  List<http.BaseRequest>? seen,
  int? statusFor404,
}) {
  return MockClient.streaming((request, _) async {
    seen?.add(request);
    final body = bodies[request.url.path];
    if (body == null) {
      return http.StreamedResponse(
        Stream.value(utf8.encode('nope')),
        statusFor404 ?? 404,
      );
    }
    final range = request.headers['Range'];
    if (range != null) {
      final start = int.parse(
        RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!,
      );
      final slice = body.sublist(start);
      return http.StreamedResponse(
        Stream.value(slice),
        206,
        contentLength: slice.length,
      );
    }
    return http.StreamedResponse(
      Stream.value(body),
      200,
      contentLength: body.length,
    );
  });
}

ModelDownloader _downloader(http.Client client, {int? free = 1 << 40}) =>
    ModelDownloader(
      client: client,
      freeSpace: (_) async => free,
      freeSpaceMarginBytes: 0,
      stallTimeout: const Duration(seconds: 2),
      connectTimeout: const Duration(seconds: 2),
    );

void main() {
  late Directory tmp;
  late _Fixture fx;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('vcm_model_test_');
    fx = _Fixture();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('ModelManifest', () {
    test('embeddingGemmaManifest matches models/*_manifest.json', () {
      final file = File(p.join('models', 'embeddinggemma2_onnx_manifest.json'));
      if (!file.existsSync()) {
        markTestSkipped('manifest json not present in this checkout');
        return;
      }
      final json = ModelManifest.parse(
        file.readAsStringSync(),
        repo: embeddingGemmaManifest.repo,
      );
      expect(json.commit, embeddingGemmaManifest.commit);
      expect(json.files.length, embeddingGemmaManifest.files.length);
      for (var i = 0; i < json.files.length; i++) {
        final x = json.files[i];
        final y = embeddingGemmaManifest.files[i];
        expect(x.path, y.path);
        expect(x.size, y.size);
        expect(x.sha256, y.sha256);
      }
    });

    test('urlFor pins the commit and tolerates a trailing slash', () {
      final spec = fx.manifest.files[1];
      expect(
        fx.manifest.urlFor('https://hf-mirror.com/', spec).toString(),
        'https://hf-mirror.com/owner/repo/resolve/abc123/onnx/model.onnx',
      );
    });
  });

  group('ModelVerifier', () {
    const verifier = ModelVerifier();

    test('complete folder passes quick and deep checks', () async {
      await _writeValid(tmp.path, fx);
      expect((await verifier.verify(tmp.path, fx.manifest)).isComplete, isTrue);
      final deep = await verifier.verify(
        tmp.path,
        fx.manifest,
        checkHash: true,
      );
      expect(deep.isComplete, isTrue);
      expect(deep.hashChecked, isTrue);
    });

    test('empty folder reports every file as missing', () async {
      final v = await verifier.verify(tmp.path, fx.manifest);
      expect(v.isComplete, isFalse);
      expect(v.anyFilePresent, isFalse);
      expect(v.problems.map((r) => r.state).toSet(), {ModelFileState.missing});
      expect(v.describeProblems(), contains('config.json'));
    });

    test('non-existent folder is reported as missing, not thrown', () async {
      final v = await verifier.verify(
        p.join(tmp.path, 'does', 'not', 'exist'),
        fx.manifest,
      );
      expect(v.isComplete, isFalse);
    });

    test('truncated file is a size mismatch', () async {
      await _writeValid(tmp.path, fx);
      await File(
        p.join(tmp.path, 'onnx', 'model.onnx'),
      ).writeAsBytes(fx.b.sublist(0, 100));
      final v = await verifier.verify(tmp.path, fx.manifest);
      expect(v.isComplete, isFalse);
      expect(v.problems.single.state, ModelFileState.sizeMismatch);
      expect(v.problems.single.actualSize, 100);
    });

    test('same length but different content needs the deep check', () async {
      await _writeValid(tmp.path, fx);
      final corrupt = List<int>.of(fx.b)..[10] ^= 0xFF;
      await File(p.join(tmp.path, 'onnx', 'model.onnx')).writeAsBytes(corrupt);

      // Quick check cannot see it: this is exactly why "exists" is not "ready".
      expect((await verifier.verify(tmp.path, fx.manifest)).isComplete, isTrue);

      final deep = await verifier.verify(
        tmp.path,
        fx.manifest,
        checkHash: true,
      );
      expect(deep.isComplete, isFalse);
      expect(deep.problems.single.state, ModelFileState.hashMismatch);
    });

    test('verify never modifies or deletes files', () async {
      await _writeValid(tmp.path, fx);
      final extra = File(p.join(tmp.path, 'user_notes.txt'))
        ..writeAsStringSync('keep me');
      await verifier.verify(tmp.path, fx.manifest, checkHash: true);
      expect(extra.existsSync(), isTrue);
      expect(extra.readAsStringSync(), 'keep me');
    });

    test('a directory in place of a file is not reported as ok', () async {
      await Directory(p.join(tmp.path, 'config.json')).create();
      final v = await verifier.verify(tmp.path, fx.manifest);
      expect(v.isComplete, isFalse);
    });

    test('cancel stops hashing early', () async {
      await _writeValid(tmp.path, fx);
      final v = await verifier.verify(
        tmp.path,
        fx.manifest,
        checkHash: true,
        isCancelled: () => true,
      );
      expect(v.reports, isEmpty);
    });

    test('unicode and spaced folder names work', () async {
      final dir = Directory(p.join(tmp.path, '模型 目录 ü'));
      await dir.create();
      await _writeValid(dir.path, fx);
      final v = await verifier.verify(dir.path, fx.manifest, checkHash: true);
      expect(v.isComplete, isTrue);
    });
  });

  group('ModelDownloader success paths', () {
    test('downloads into an empty folder and verifies', () async {
      final r = await _downloader(
        _server(fx.bodies),
      ).install(manifest: fx.manifest, dir: p.join(tmp.path, 'models'));
      expect(r.failure, isNull);
      expect(r.succeeded, isTrue);
      expect(r.downloadedFiles, ['config.json', 'onnx/model.onnx']);
      expect(
        File(
          p.join(tmp.path, 'models', 'onnx', 'model.onnx'),
        ).readAsBytesSync(),
        fx.b,
      );
      // No temp files left behind.
      final leftovers = Directory(
        tmp.path,
      ).listSync(recursive: true).where((e) => e.path.endsWith('.part'));
      expect(leftovers, isEmpty);
    });

    test('already valid folder makes zero network requests', () async {
      await _writeValid(tmp.path, fx);
      final seen = <http.BaseRequest>[];
      final r = await _downloader(
        _server(fx.bodies, seen: seen),
      ).install(manifest: fx.manifest, dir: tmp.path);
      expect(r.succeeded, isTrue);
      expect(seen, isEmpty);
      expect(r.skippedFiles.length, 2);
      expect(r.downloadedFiles, isEmpty);
    });

    test('only the missing file is fetched', () async {
      await File(p.join(tmp.path, 'config.json')).writeAsBytes(fx.a);
      final seen = <http.BaseRequest>[];
      final r = await _downloader(
        _server(fx.bodies, seen: seen),
      ).install(manifest: fx.manifest, dir: tmp.path);
      expect(r.succeeded, isTrue);
      expect(seen.map((q) => q.url.path), [
        '/owner/repo/resolve/abc123/onnx/model.onnx',
      ]);
    });

    test('reports progress and finishes at 100%', () async {
      final events = <ModelProgress>[];
      await _downloader(
        _server(fx.bodies),
      ).install(manifest: fx.manifest, dir: tmp.path, onProgress: events.add);
      expect(events.first.phase, ModelPhase.preparing);
      expect(events.last.phase, ModelPhase.finishing);
      expect(events.last.fraction, 1.0);
    });

    test('mirror host is used in the request URL', () async {
      final seen = <http.BaseRequest>[];
      await _downloader(_server(fx.bodies, seen: seen)).install(
        manifest: fx.manifest,
        dir: tmp.path,
        mirror: 'https://example.invalid',
      );
      expect(seen.first.url.host, 'example.invalid');
    });
  });

  group('ModelDownloader never clobbers working files', () {
    test('corrupt file is replaced only after the new copy verifies', () async {
      await _writeValid(tmp.path, fx);
      final corrupt = List<int>.of(fx.b)..[5] ^= 0xFF;
      final target = File(p.join(tmp.path, 'onnx', 'model.onnx'));
      await target.writeAsBytes(corrupt);

      final r = await _downloader(
        _server(fx.bodies),
      ).install(manifest: fx.manifest, dir: tmp.path);
      expect(r.succeeded, isTrue);
      expect(r.downloadedFiles, ['onnx/model.onnx']);
      expect(target.readAsBytesSync(), fx.b);
    });

    test('network failure keeps the good file and reports ready=false only '
        'for what is actually missing', () async {
      // config.json is valid; model is absent; server is unreachable.
      await File(p.join(tmp.path, 'config.json')).writeAsBytes(fx.a);
      final client = MockClient.streaming(
        (_, _) async => throw const SocketException(
          'Failed host lookup',
          osError: OSError('No such host is known', 11001),
        ),
      );
      final r = await _downloader(
        client,
      ).install(manifest: fx.manifest, dir: tmp.path);
      expect(r.failure!.kind, ModelFailureKind.dns);
      expect(r.isReady, isFalse);
      expect(File(p.join(tmp.path, 'config.json')).readAsBytesSync(), fx.a);
      expect(r.verification.problems.single.spec.path, 'onnx/model.onnx');
    });

    test(
      'hash mismatch discards the download and keeps the old file',
      () async {
        final old = List<int>.of(fx.b)..[1] ^= 0xFF; // same size, wrong hash
        await File(p.join(tmp.path, 'config.json')).writeAsBytes(fx.a);
        await Directory(p.join(tmp.path, 'onnx')).create();
        final target = File(p.join(tmp.path, 'onnx', 'model.onnx'));
        await target.writeAsBytes(old);

        // Server serves yet another same-size but wrong body.
        final wrong = List<int>.of(fx.b)..[2] ^= 0xFF;
        final bodies = {
          ...fx.bodies,
          '/owner/repo/resolve/abc123/onnx/model.onnx': wrong,
        };
        final r = await _downloader(
          _server(bodies),
        ).install(manifest: fx.manifest, dir: tmp.path);

        expect(r.failure!.kind, ModelFailureKind.hashMismatch);
        expect(r.failure!.file, 'onnx/model.onnx');
        // Existing (even if not valid) file is untouched; bad .part is gone.
        expect(target.readAsBytesSync(), old);
        expect(File('${target.path}.part').existsSync(), isFalse);
        expect(r.isReady, isFalse);
      },
    );

    test('files outside the manifest are never deleted', () async {
      final mine = File(p.join(tmp.path, 'my_other_model.bin'))
        ..writeAsStringSync('user data');
      await _downloader(
        _server(fx.bodies),
      ).install(manifest: fx.manifest, dir: tmp.path);
      expect(mine.existsSync(), isTrue);
      expect(mine.readAsStringSync(), 'user data');
    });
  });

  group('ModelDownloader failure classification', () {
    test('HTTP 404 names the file and status', () async {
      final r = await _downloader(
        _server({}),
      ).install(manifest: fx.manifest, dir: tmp.path);
      expect(r.failure!.kind, ModelFailureKind.http);
      expect(r.failure!.httpStatus, 404);
      expect(r.failure!.file, 'config.json');
      expect(r.failure!.message, contains('404'));
    });

    test('HTTP 403 and 500 are distinguished in the message', () async {
      final r403 = await _downloader(
        _server({}, statusFor404: 403),
      ).install(manifest: fx.manifest, dir: tmp.path);
      expect(r403.failure!.httpStatus, 403);
      expect(r403.failure!.message, contains('403'));

      final r500 = await _downloader(
        _server({}, statusFor404: 500),
      ).install(manifest: fx.manifest, dir: tmp.path);
      expect(r500.failure!.httpStatus, 500);
      expect(r500.failure!.message, contains('500'));
    });

    test('connection refused -> connection', () async {
      final client = MockClient.streaming(
        (_, _) async => throw const SocketException(
          'Connection refused',
          osError: OSError('refused', 1225),
        ),
      );
      final r = await _downloader(
        client,
      ).install(manifest: fx.manifest, dir: tmp.path);
      expect(r.failure!.kind, ModelFailureKind.connection);
      expect(r.failure!.osErrorCode, 1225);
    });

    test('TLS failure -> tls', () async {
      final client = MockClient.streaming(
        (_, _) async => throw const HandshakeException('bad cert'),
      );
      final r = await _downloader(
        client,
      ).install(manifest: fx.manifest, dir: tmp.path);
      expect(r.failure!.kind, ModelFailureKind.tls);
    });

    test('connect timeout -> timeout', () async {
      final client = MockClient.streaming((_, _) async {
        await Future<void>.delayed(const Duration(seconds: 5));
        throw StateError('unreachable');
      });
      final r = await ModelDownloader(
        client: client,
        freeSpace: (_) async => 1 << 40,
        connectTimeout: const Duration(milliseconds: 100),
      ).install(manifest: fx.manifest, dir: tmp.path);
      expect(r.failure!.kind, ModelFailureKind.timeout);
    });

    test(
      'declared size that differs from the manifest -> sizeMismatch',
      () async {
        final client = MockClient.streaming(
          (_, _) async => http.StreamedResponse(
            Stream.value(utf8.encode('short')),
            200,
            contentLength: 5,
          ),
        );
        final r = await _downloader(
          client,
        ).install(manifest: fx.manifest, dir: tmp.path);
        expect(r.failure!.kind, ModelFailureKind.sizeMismatch);
      },
    );

    test('insufficient disk space is detected before any download', () async {
      final seen = <http.BaseRequest>[];
      final r = await _downloader(
        _server(fx.bodies, seen: seen),
        free: 10,
      ).install(manifest: fx.manifest, dir: tmp.path);
      expect(r.failure!.kind, ModelFailureKind.diskSpace);
      expect(seen, isEmpty);
    });

    test('unknown free space does not block the attempt', () async {
      final r = await _downloader(
        _server(fx.bodies),
        free: null,
      ).install(manifest: fx.manifest, dir: tmp.path);
      expect(r.succeeded, isTrue);
    });

    test(
      'credentials in a failing URL never reach the log or message',
      () async {
        final client = MockClient.streaming(
          (_, _) async => throw const SocketException(
            'failed https://user:hunter2@host/x?token=SECRET123&a=1',
          ),
        );
        final r = await _downloader(
          client,
        ).install(manifest: fx.manifest, dir: tmp.path);
        final all =
            '${r.logText}\n${r.failure!.message}\n${r.failure!.technical}';
        expect(all, isNot(contains('hunter2')));
        expect(all, isNot(contains('SECRET123')));
      },
    );

    test('permission denied maps to permission with the path', () {
      final f = _downloader(_server({})).classifyFileSystemException(
        const FileSystemException(
          'Cannot create file',
          r'C:\Program Files\x',
          OSError('Access is denied', 5),
        ),
        targetPath: r'C:\Program Files\x',
      );
      expect(f.kind, ModelFailureKind.permission);
      expect(f.osErrorCode, 5);
      expect(f.message, contains('Program Files'));
    });

    test('disk full errnos map to diskSpace', () {
      final d = _downloader(_server({}));
      for (final code in [112, 28]) {
        final f = d.classifyFileSystemException(
          FileSystemException('write failed', 'x', OSError('full', code)),
        );
        expect(f.kind, ModelFailureKind.diskSpace, reason: 'errno $code');
      }
    });

    test('sharing violation maps to fileLocked', () {
      final f = _downloader(_server({})).classifyFileSystemException(
        const FileSystemException('rename', 'x', OSError('in use', 32)),
      );
      expect(f.kind, ModelFailureKind.fileLocked);
    });

    test(
      'unwritable target folder -> permission/unknown, nothing downloaded',
      () async {
        // A regular file where the folder should be makes create() fail on all
        // platforms without needing special ACLs.
        final blocker = File(p.join(tmp.path, 'blocked'))
          ..writeAsStringSync('x');
        final seen = <http.BaseRequest>[];
        final r = await _downloader(
          _server(fx.bodies, seen: seen),
        ).install(manifest: fx.manifest, dir: blocker.path);
        expect(r.failure, isNotNull);
        expect(
          r.failure!.kind,
          anyOf(ModelFailureKind.permission, ModelFailureKind.unknown),
        );
        expect(seen, isEmpty);
        expect(blocker.readAsStringSync(), 'x');
      },
    );
  });

  group('ModelDownloader resume and cancel', () {
    test('resumes from a .part file using a Range request', () async {
      final part = File(p.join(tmp.path, 'onnx', 'model.onnx.part'));
      await part.parent.create(recursive: true);
      await part.writeAsBytes(fx.b.sublist(0, 1000));
      await File(p.join(tmp.path, 'config.json')).writeAsBytes(fx.a);

      final seen = <http.BaseRequest>[];
      final r = await _downloader(
        _server(fx.bodies, seen: seen),
      ).install(manifest: fx.manifest, dir: tmp.path);

      expect(r.succeeded, isTrue);
      expect(seen.single.headers['Range'], 'bytes=1000-');
      expect(
        File(p.join(tmp.path, 'onnx', 'model.onnx')).readAsBytesSync(),
        fx.b,
      );
      expect(part.existsSync(), isFalse);
    });

    test('server that ignores Range still yields a correct file', () async {
      final part = File(p.join(tmp.path, 'onnx', 'model.onnx.part'));
      await part.parent.create(recursive: true);
      await part.writeAsBytes(fx.b.sublist(0, 1000));
      await File(p.join(tmp.path, 'config.json')).writeAsBytes(fx.a);

      final client = MockClient.streaming(
        (request, _) async => http.StreamedResponse(
          Stream.value(fx.b),
          200,
          contentLength: fx.b.length,
        ),
      );
      final r = await _downloader(
        client,
      ).install(manifest: fx.manifest, dir: tmp.path);
      expect(r.succeeded, isTrue);
    });

    test('stale oversized .part is discarded and download restarts', () async {
      final part = File(p.join(tmp.path, 'onnx', 'model.onnx.part'));
      await part.parent.create(recursive: true);
      await part.writeAsBytes(List<int>.filled(fx.b.length + 50, 1));
      await File(p.join(tmp.path, 'config.json')).writeAsBytes(fx.a);
      final r = await _downloader(
        _server(fx.bodies),
      ).install(manifest: fx.manifest, dir: tmp.path);
      expect(r.succeeded, isTrue);
    });

    test('truncated stream keeps the .part for the next attempt', () async {
      await File(p.join(tmp.path, 'config.json')).writeAsBytes(fx.a);
      final client = MockClient.streaming(
        (request, _) async =>
            http.StreamedResponse(Stream.value(fx.b.sublist(0, 500)), 200),
      );
      final r = await _downloader(
        client,
      ).install(manifest: fx.manifest, dir: tmp.path);
      expect(r.failure!.kind, ModelFailureKind.connection);
      final part = File(p.join(tmp.path, 'onnx', 'model.onnx.part'));
      expect(part.existsSync(), isTrue);
      expect(part.lengthSync(), 500);
      expect(
        File(p.join(tmp.path, 'onnx', 'model.onnx')).existsSync(),
        isFalse,
      );

      // Next attempt completes from the saved bytes.
      final seen = <http.BaseRequest>[];
      final r2 = await _downloader(
        _server(fx.bodies, seen: seen),
      ).install(manifest: fx.manifest, dir: tmp.path);
      expect(r2.succeeded, isTrue);
      expect(seen.single.headers['Range'], 'bytes=500-');
    });

    test('cancel before start downloads nothing and changes nothing', () async {
      await _writeValid(tmp.path, fx);
      final target = File(p.join(tmp.path, 'config.json'));
      final before = target.lastModifiedSync();
      final seen = <http.BaseRequest>[];
      final r = await _downloader(
        _server(fx.bodies, seen: seen),
      ).install(manifest: fx.manifest, dir: tmp.path, isCancelled: () => true);
      expect(r.failure!.kind, ModelFailureKind.cancelled);
      expect(seen, isEmpty);
      expect(target.lastModifiedSync(), before);
    });

    test('cancel mid-download keeps the .part and reports cancelled', () async {
      var cancel = false;
      final client = MockClient.streaming((request, _) async {
        final controller = StreamController<List<int>>();
        controller.add(fx.b.sublist(0, 100));
        Timer(const Duration(milliseconds: 50), () {
          cancel = true;
          controller.add(fx.b.sublist(100));
          controller.close();
        });
        return http.StreamedResponse(
          controller.stream,
          200,
          contentLength: fx.b.length,
        );
      });
      await File(p.join(tmp.path, 'config.json')).writeAsBytes(fx.a);
      final r = await _downloader(client).install(
        manifest: fx.manifest,
        dir: tmp.path,
        isCancelled: () => cancel,
      );
      expect(r.failure!.kind, ModelFailureKind.cancelled);
      expect(
        File(p.join(tmp.path, 'onnx', 'model.onnx')).existsSync(),
        isFalse,
      );
    });
  });

  group('redactSecrets', () {
    test('masks user info, query tokens and bearer headers', () {
      final out = redactSecrets(
        'GET https://u:p4ss@h.example/x?token=abc&n=1 '
        'Authorization: Bearer eyJ.abc-def',
      );
      expect(out, isNot(contains('p4ss')));
      expect(out, isNot(contains('=abc')));
      expect(out, isNot(contains('eyJ.abc-def')));
      expect(out, contains('n=1'));
    });

    test('safeUrl drops query and user info', () {
      expect(
        safeUrl(Uri.parse('https://u:p@h.example/a/b?token=1#f')),
        'https://h.example/a/b',
      );
    });
  });
}
