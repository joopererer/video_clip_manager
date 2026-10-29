import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'ai_model_manifest.dart';

enum ModelFileState {
  ok,
  missing,

  /// File exists but its length differs from the manifest (truncated / other
  /// version).
  sizeMismatch,

  /// Length matches but sha256 differs.
  hashMismatch,

  /// The file or folder exists but cannot be read (permissions, locked).
  unreadable,
}

class ModelFileReport {
  const ModelFileReport({
    required this.spec,
    required this.state,
    this.actualSize,
    this.detail,
  });

  final ModelFileSpec spec;
  final ModelFileState state;
  final int? actualSize;

  /// Technical detail for [ModelFileState.unreadable].
  final String? detail;

  bool get isOk => state == ModelFileState.ok;
}

class ModelVerification {
  const ModelVerification({
    required this.dir,
    required this.reports,
    required this.hashChecked,
  });

  final String dir;
  final List<ModelFileReport> reports;

  /// True when sha256 was computed for every file that passed the size check.
  /// False means only existence and size were compared.
  final bool hashChecked;

  bool get isComplete => reports.every((r) => r.isOk);

  List<ModelFileReport> get problems =>
      reports.where((r) => !r.isOk).toList(growable: false);

  bool get hasUnreadable =>
      reports.any((r) => r.state == ModelFileState.unreadable);

  bool get anyFilePresent => reports.any(
    (r) =>
        r.state != ModelFileState.missing &&
        r.state != ModelFileState.unreadable,
  );

  /// Short human summary, one line per problem file (at most [max]).
  String describeProblems({int max = 5}) {
    final lines = <String>[];
    for (final r in problems.take(max)) {
      final what = switch (r.state) {
        ModelFileState.missing => '缺失',
        ModelFileState.sizeMismatch =>
          '大小不符 (期望 ${r.spec.size}，实际 ${r.actualSize})',
        ModelFileState.hashMismatch => 'sha256 不符',
        ModelFileState.unreadable => '无法读取 (${r.detail ?? '权限/占用'})',
        ModelFileState.ok => '',
      };
      lines.add('• ${r.spec.path}: $what');
    }
    if (problems.length > max) {
      lines.add('• 另有 ${problems.length - max} 个文件有问题');
    }
    return lines.join('\n');
  }
}

/// Checks a model folder against a [ModelManifest]. Never writes or deletes.
class ModelVerifier {
  const ModelVerifier();

  /// [checkHash] false: existence and length only (cheap, used for readiness).
  /// true: also sha256 of every file whose length matches.
  Future<ModelVerification> verify(
    String dir,
    ModelManifest manifest, {
    bool checkHash = false,
    void Function(String file, int doneBytes, int totalBytes)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final reports = <ModelFileReport>[];
    for (final spec in manifest.files) {
      if (isCancelled?.call() ?? false) break;
      reports.add(
        await verifyFile(
          dir,
          spec,
          checkHash: checkHash,
          onProgress: onProgress,
          isCancelled: isCancelled,
        ),
      );
    }
    return ModelVerification(dir: dir, reports: reports, hashChecked: checkHash);
  }

  Future<ModelFileReport> verifyFile(
    String dir,
    ModelFileSpec spec, {
    bool checkHash = false,
    void Function(String file, int doneBytes, int totalBytes)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final file = File(p.joinAll([dir, ...spec.path.split('/')]));
    final int length;
    try {
      if (!await file.exists()) {
        return ModelFileReport(spec: spec, state: ModelFileState.missing);
      }
      length = await file.length();
    } on FileSystemException catch (e) {
      return ModelFileReport(
        spec: spec,
        state: ModelFileState.unreadable,
        detail: _osDetail(e),
      );
    }
    if (length != spec.size) {
      return ModelFileReport(
        spec: spec,
        state: ModelFileState.sizeMismatch,
        actualSize: length,
      );
    }
    if (!checkHash) {
      return ModelFileReport(
        spec: spec,
        state: ModelFileState.ok,
        actualSize: length,
      );
    }
    try {
      final digest = await sha256OfFile(
        file,
        onProgress: onProgress == null
            ? null
            : (done) => onProgress(spec.path, done, length),
        isCancelled: isCancelled,
      );
      return ModelFileReport(
        spec: spec,
        state: digest == spec.sha256
            ? ModelFileState.ok
            : ModelFileState.hashMismatch,
        actualSize: length,
      );
    } on FileSystemException catch (e) {
      return ModelFileReport(
        spec: spec,
        state: ModelFileState.unreadable,
        actualSize: length,
        detail: _osDetail(e),
      );
    }
  }

  /// Streaming sha256 (lowercase hex); does not load the file into memory.
  static Future<String> sha256OfFile(
    File file, {
    void Function(int doneBytes)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final output = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(output);
    var done = 0;
    await for (final chunk in file.openRead()) {
      if (isCancelled?.call() ?? false) break;
      input.add(chunk);
      done += chunk.length;
      onProgress?.call(done);
    }
    input.close();
    return output.events.single.toString();
  }

  static String _osDetail(FileSystemException e) {
    final code = e.osError?.errorCode;
    final msg = e.osError?.message.trim();
    return [
      if (code != null) 'errno $code',
      if (msg != null && msg.isNotEmpty) msg else e.message,
    ].join(' ');
  }
}

/// Minimal sink collecting the single digest of a chunked conversion.
class AccumulatorSink<T> implements Sink<T> {
  final List<T> events = [];

  @override
  void add(T data) => events.add(data);

  @override
  void close() {}
}
