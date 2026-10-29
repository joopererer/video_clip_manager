import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'ai_model_manifest.dart';
import 'ai_model_verifier.dart';

/// Why an install attempt stopped. Each kind needs a different user action.
enum ModelFailureKind {
  /// The target folder cannot be created or is not writable.
  permission,

  /// A file is held open by another process (for example the ONNX runtime).
  fileLocked,

  /// Not enough free space for the files still missing.
  diskSpace,

  /// Host name could not be resolved.
  dns,

  /// Connection refused / reset / unreachable.
  connection,

  /// TLS handshake or certificate problem.
  tls,

  /// No bytes arrived within the stall window.
  timeout,

  /// The server answered with an HTTP error status.
  http,

  /// The download finished but its sha256 does not match the manifest.
  hashMismatch,

  /// The server sent a different number of bytes than the manifest says.
  sizeMismatch,

  /// The user cancelled.
  cancelled,

  unknown,
}

class ModelFailure {
  const ModelFailure({
    required this.kind,
    required this.message,
    this.file,
    this.targetPath,
    this.url,
    this.httpStatus,
    this.osErrorCode,
    this.technical,
  });

  final ModelFailureKind kind;

  /// User-facing explanation including what to do next.
  final String message;

  /// Manifest-relative file that was being processed.
  final String? file;

  /// Absolute path on disk.
  final String? targetPath;

  /// URL with credentials and query removed.
  final String? url;
  final int? httpStatus;
  final int? osErrorCode;

  /// Raw exception text (already passed through [redactSecrets]).
  final String? technical;
}

enum ModelPhase { preparing, checking, downloading, verifying, finishing }

class ModelProgress {
  const ModelProgress({
    required this.phase,
    this.file,
    this.fileBytesDone = 0,
    this.fileBytesTotal = 0,
    this.overallBytesDone = 0,
    this.overallBytesTotal = 0,
  });

  final ModelPhase phase;
  final String? file;
  final int fileBytesDone;
  final int fileBytesTotal;
  final int overallBytesDone;
  final int overallBytesTotal;

  double? get fraction =>
      overallBytesTotal > 0 ? overallBytesDone / overallBytesTotal : null;
}

class ModelInstallResult {
  const ModelInstallResult({
    required this.dir,
    required this.verification,
    required this.log,
    this.failure,
    this.downloadedFiles = const [],
    this.skippedFiles = const [],
  });

  final String dir;

  /// State of the folder after the attempt (always re-measured).
  final ModelVerification verification;
  final ModelFailure? failure;
  final List<String> downloadedFiles;
  final List<String> skippedFiles;
  final List<String> log;

  /// Folder is complete and verified. Independent of [failure] on purpose: a
  /// failed refresh must not turn a still-valid install into "not ready".
  bool get isReady => verification.isComplete;

  bool get succeeded => failure == null && isReady;

  String get logText => log.join('\n');
}

/// Free bytes on the volume holding [path], or null when unknown.
typedef FreeSpaceProvider = Future<int?> Function(String path);

/// Default: asks .NET `DriveInfo` through PowerShell on Windows; unknown
/// elsewhere (the disk-full error from the write is still classified).
Future<int?> defaultFreeSpace(String path) async {
  if (!Platform.isWindows) return null;
  final root = p.rootPrefix(p.absolute(path));
  // `D:\` only. UNC roots are not handled and fall back to "unknown".
  final match = RegExp(r'^([A-Za-z]):').firstMatch(root);
  if (match == null) return null;
  try {
    final res = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      '(New-Object System.IO.DriveInfo("${match.group(1)}")).AvailableFreeSpace',
    ]).timeout(const Duration(seconds: 10));
    if (res.exitCode != 0) return null;
    return int.tryParse((res.stdout as String).trim());
  } catch (_) {
    return null;
  }
}

/// Removes credentials from text that is shown or logged.
String redactSecrets(String input) {
  var s = input;
  // user:pass@host
  s = s.replaceAllMapped(
    RegExp(r'(https?://)[^/\s:@]+:[^/\s@]+@'),
    (m) => '${m.group(1)}***@',
  );
  // query-string secrets
  s = s.replaceAllMapped(
    RegExp(
      r'([?&](?:token|access_token|key|api_key|apikey|sign|signature|auth|password|secret)=)[^&\s"]+',
      caseSensitive: false,
    ),
    (m) => '${m.group(1)}***',
  );
  // Authorization headers / bearer tokens
  s = s.replaceAllMapped(
    RegExp(r'(Bearer\s+)[A-Za-z0-9._~+/=-]+', caseSensitive: false),
    (m) => '${m.group(1)}***',
  );
  s = s.replaceAllMapped(
    RegExp(r'(Authorization["\s:=]+)[^\s",]+', caseSensitive: false),
    (m) => '${m.group(1)}***',
  );
  return s;
}

/// URL without user info and query string, safe to show.
String safeUrl(Uri uri) => Uri(
  scheme: uri.scheme,
  host: uri.host,
  port: uri.hasPort ? uri.port : null,
  path: uri.path,
).toString();

/// Downloads and verifies a [ModelManifest] into a folder.
///
/// Guarantees:
///  * a file that already matches the manifest (size and sha256) is never
///    touched;
///  * data is written to `<name>.part` and only moved over the target after
///    sha256 passes, so an interrupted or corrupt download cannot damage a
///    usable file;
///  * `.part` files from network failures are kept so the next attempt
///    resumes (HTTP Range) instead of starting over;
///  * nothing outside the manifest's file list is deleted.
class ModelDownloader {
  ModelDownloader({
    http.Client? client,
    this.verifier = const ModelVerifier(),
    FreeSpaceProvider? freeSpace,
    this.stallTimeout = const Duration(seconds: 60),
    this.connectTimeout = const Duration(seconds: 30),
    this.freeSpaceMarginBytes = 64 * 1024 * 1024,
  }) : _client = client,
       _freeSpace = freeSpace ?? defaultFreeSpace;

  final http.Client? _client;
  final ModelVerifier verifier;
  final FreeSpaceProvider _freeSpace;
  final Duration stallTimeout;
  final Duration connectTimeout;
  final int freeSpaceMarginBytes;

  static const _writeProbeName = '.vcm_write_test';

  Future<ModelInstallResult> install({
    required ModelManifest manifest,
    required String dir,
    String mirror = 'https://hf-mirror.com',
    void Function(ModelProgress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final log = <String>[];
    void note(String m) =>
        log.add('${DateTime.now().toIso8601String()} ${redactSecrets(m)}');
    bool cancelled() => isCancelled?.call() ?? false;

    final downloaded = <String>[];
    final skipped = <String>[];

    Future<ModelInstallResult> finish(ModelFailure? failure) async {
      // Always re-measure: the folder is the truth, not the attempt outcome.
      // Files proven good in this run are not hashed twice; everything else
      // gets a full sha256 check so a same-size corrupt file can never be
      // reported as ready.
      final proven = {...skipped, ...downloaded};
      final reports = <ModelFileReport>[];
      for (final spec in manifest.files) {
        reports.add(
          proven.contains(spec.path)
              ? ModelFileReport(
                  spec: spec,
                  state: ModelFileState.ok,
                  actualSize: spec.size,
                )
              : await verifier.verifyFile(dir, spec, checkHash: true),
        );
      }
      final v = ModelVerification(
        dir: dir,
        reports: reports,
        hashChecked: true,
      );
      note(
        failure == null
            ? 'DONE complete=${v.isComplete}'
            : 'STOP kind=${failure.kind.name} file=${failure.file} '
                  'httpStatus=${failure.httpStatus} os=${failure.osErrorCode}; '
                  'folder complete=${v.isComplete}',
      );
      return ModelInstallResult(
        dir: dir,
        verification: v,
        failure: failure,
        log: log,
        downloadedFiles: downloaded,
        skippedFiles: skipped,
      );
    }

    note(
      'START model=${manifest.id} commit=${manifest.commit} dir=$dir '
      'mirror=${safeUrl(Uri.parse(mirror))}',
    );
    onProgress?.call(const ModelProgress(phase: ModelPhase.preparing));

    // 1. Folder must exist and be writable.
    final dirFailure = await _prepareDir(dir, note);
    if (dirFailure != null) return finish(dirFailure);

    // 2. Full check (size + sha256). Valid files are skipped, never rewritten.
    final total = manifest.totalBytes;
    var checkedBytes = 0;
    final needed = <ModelFileSpec>[];
    for (final spec in manifest.files) {
      if (cancelled()) return finish(_cancelled());
      final report = await verifier.verifyFile(
        dir,
        spec,
        checkHash: true,
        onProgress: (file, done, fileTotal) => onProgress?.call(
          ModelProgress(
            phase: ModelPhase.checking,
            file: file,
            fileBytesDone: done,
            fileBytesTotal: fileTotal,
            overallBytesDone: checkedBytes + done,
            overallBytesTotal: total,
          ),
        ),
        isCancelled: cancelled,
      );
      checkedBytes += spec.size;
      note(
        'CHECK ${spec.path}: ${report.state.name}'
        '${report.detail != null ? ' (${report.detail})' : ''}',
      );
      if (report.isOk) {
        skipped.add(spec.path);
      } else {
        needed.add(spec);
      }
    }
    if (needed.isEmpty) return finish(null);

    // 3. Disk space for what is still missing (minus resumable .part data).
    var required = 0;
    for (final spec in needed) {
      final part = File(_partPath(dir, spec));
      final have = await part.exists() ? await part.length() : 0;
      required += (spec.size - (have < spec.size ? have : 0));
    }
    final free = await _freeSpace(dir);
    note('SPACE need=$required free=${free ?? 'unknown'}');
    if (free != null && free < required + freeSpaceMarginBytes) {
      return finish(
        ModelFailure(
          kind: ModelFailureKind.diskSpace,
          message:
              '磁盘可用空间不足：还需下载约 ${_mb(required)} MB，'
              '目标磁盘仅剩 ${_mb(free)} MB。请清理磁盘，或在“模型目录”中选择空间更大的位置。'
              '已有文件未被改动。',
          targetPath: dir,
        ),
      );
    }

    // 4. Download each needed file.
    var doneBytes = total - needed.fold<int>(0, (s, f) => s + f.size);
    final ownClient = _client == null;
    final client = _client ?? http.Client();
    try {
      for (final spec in needed) {
        if (cancelled()) return finish(_cancelled());
        final failure = await _downloadOne(
          client: client,
          manifest: manifest,
          spec: spec,
          dir: dir,
          mirror: mirror,
          overallDone: doneBytes,
          overallTotal: total,
          onProgress: onProgress,
          isCancelled: cancelled,
          note: note,
        );
        if (failure != null) return finish(failure);
        downloaded.add(spec.path);
        doneBytes += spec.size;
      }
    } finally {
      if (ownClient) client.close();
    }
    onProgress?.call(
      ModelProgress(
        phase: ModelPhase.finishing,
        overallBytesDone: total,
        overallBytesTotal: total,
      ),
    );
    return finish(null);
  }

  Future<ModelFailure?> _prepareDir(
    String dir,
    void Function(String) note,
  ) async {
    try {
      await Directory(dir).create(recursive: true);
      final probe = File(p.join(dir, _writeProbeName));
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      note('DIR writable: $dir');
      return null;
    } on FileSystemException catch (e) {
      note('DIR error: ${e.message} os=${e.osError?.errorCode}');
      return _fromFileSystem(e, targetPath: dir, action: '创建或写入模型目录');
    }
  }

  Future<ModelFailure?> _downloadOne({
    required http.Client client,
    required ModelManifest manifest,
    required ModelFileSpec spec,
    required String dir,
    required String mirror,
    required int overallDone,
    required int overallTotal,
    required void Function(ModelProgress)? onProgress,
    required bool Function() isCancelled,
    required void Function(String) note,
    bool allowRestart = true,
  }) async {
    final target = p.joinAll([dir, ...spec.path.split('/')]);
    final partFile = File('$target.part');
    final url = manifest.urlFor(mirror, spec);
    final shownUrl = safeUrl(url);

    try {
      await partFile.parent.create(recursive: true);
    } on FileSystemException catch (e) {
      return _fromFileSystem(e, file: spec.path, targetPath: target);
    }

    var offset = 0;
    try {
      if (await partFile.exists()) {
        offset = await partFile.length();
        if (offset > spec.size) {
          await partFile.delete();
          offset = 0;
        }
      }
    } on FileSystemException catch (e) {
      return _fromFileSystem(e, file: spec.path, targetPath: target);
    }

    note('GET $shownUrl resumeFrom=$offset');
    final request = http.Request('GET', url);
    if (offset > 0) request.headers['Range'] = 'bytes=$offset-';

    http.StreamedResponse response;
    try {
      response = await client.send(request).timeout(connectTimeout);
    } catch (e) {
      return _fromTransport(e, spec: spec, url: shownUrl, target: target);
    }
    note('HTTP ${response.statusCode} len=${response.contentLength}');

    if (response.statusCode == 416 && allowRestart) {
      // Our .part is not a valid prefix of the file. It is our own temp file.
      await _drain(response);
      await _safeDelete(partFile);
      return _downloadOne(
        client: client,
        manifest: manifest,
        spec: spec,
        dir: dir,
        mirror: mirror,
        overallDone: overallDone,
        overallTotal: overallTotal,
        onProgress: onProgress,
        isCancelled: isCancelled,
        note: note,
        allowRestart: false,
      );
    }
    if (response.statusCode != 200 && response.statusCode != 206) {
      await _drain(response);
      return ModelFailure(
        kind: ModelFailureKind.http,
        message: _httpMessage(response.statusCode, shownUrl),
        file: spec.path,
        targetPath: target,
        url: shownUrl,
        httpStatus: response.statusCode,
      );
    }

    final resumed = response.statusCode == 206 && offset > 0;
    if (!resumed && offset > 0) {
      // Server ignored Range and sent the whole file: start the part over.
      offset = 0;
    }
    final expectedBody = spec.size - offset;
    final declared = response.contentLength;
    if (declared != null && declared != expectedBody) {
      await _drain(response);
      return ModelFailure(
        kind: ModelFailureKind.sizeMismatch,
        message:
            '服务器返回的文件大小与清单不一致 (${spec.path}：期望 $expectedBody 字节，'
            '服务器声明 $declared 字节)。镜像上的文件可能不是固定版本，请换用其他镜像后重试。',
        file: spec.path,
        targetPath: target,
        url: shownUrl,
      );
    }

    RandomAccessFile? raf;
    try {
      final out = await partFile.open(
        mode: resumed ? FileMode.append : FileMode.write,
      );
      raf = out;
      var written = offset;
      await for (final chunk in response.stream.timeout(stallTimeout)) {
        if (isCancelled()) {
          raf = null;
          await out.close();
          return _cancelled(file: spec.path, targetPath: target);
        }
        await out.writeFrom(chunk);
        written += chunk.length;
        onProgress?.call(
          ModelProgress(
            phase: ModelPhase.downloading,
            file: spec.path,
            fileBytesDone: written,
            fileBytesTotal: spec.size,
            overallBytesDone: overallDone + written,
            overallBytesTotal: overallTotal,
          ),
        );
      }
      await out.flush();
      raf = null;
      await out.close();
    } on FileSystemException catch (e) {
      try {
        await raf?.close();
      } catch (_) {}
      return _fromFileSystem(e, file: spec.path, targetPath: '$target.part');
    } catch (e) {
      try {
        await raf?.close();
      } catch (_) {}
      // The .part stays on disk: the next attempt resumes from it.
      return _fromTransport(e, spec: spec, url: shownUrl, target: target);
    }

    // Verify before the file can replace anything.
    onProgress?.call(
      ModelProgress(
        phase: ModelPhase.verifying,
        file: spec.path,
        overallBytesDone: overallDone + spec.size,
        overallBytesTotal: overallTotal,
      ),
    );
    final partSize = await partFile.length();
    if (partSize != spec.size) {
      // Stream ended early without an error: keep the part, resume next time.
      note('SHORT ${spec.path} got=$partSize want=${spec.size}');
      return ModelFailure(
        kind: ModelFailureKind.connection,
        message:
            '下载在 ${_mb(partSize)} / ${_mb(spec.size)} MB 处被中断 (${spec.path})。'
            '已保留下载进度，重试会从断点继续。',
        file: spec.path,
        targetPath: target,
        url: shownUrl,
      );
    }
    final String digest;
    try {
      digest = await ModelVerifier.sha256OfFile(partFile);
    } on FileSystemException catch (e) {
      return _fromFileSystem(e, file: spec.path, targetPath: '$target.part');
    }
    if (digest != spec.sha256) {
      note('HASH MISMATCH ${spec.path} got=$digest want=${spec.sha256}');
      // Corrupt download: discard our own temp file so the retry is clean.
      await _safeDelete(partFile);
      return ModelFailure(
        kind: ModelFailureKind.hashMismatch,
        message:
            '${spec.path} 下载完成但 sha256 校验失败，文件已丢弃 (原有文件未改动)。'
            '镜像返回的内容可能被篡改或不完整，请稍后重试或更换镜像。',
        file: spec.path,
        targetPath: target,
        url: shownUrl,
      );
    }

    // Verified: now (and only now) replace the target.
    try {
      await File(target).parent.create(recursive: true);
      await partFile.rename(target);
    } on FileSystemException catch (e) {
      return _fromFileSystem(e, file: spec.path, targetPath: target);
    }
    note('OK ${spec.path} -> $target');
    return null;
  }

  @visibleForTesting
  ModelFailure classifyFileSystemException(
    FileSystemException e, {
    String? file,
    String? targetPath,
  }) => _fromFileSystem(e, file: file, targetPath: targetPath);

  @visibleForTesting
  ModelFailure classifyTransportError(
    Object e, {
    required ModelFileSpec spec,
    required String url,
    required String target,
  }) => _fromTransport(e, spec: spec, url: url, target: target);

  ModelFailure _cancelled({String? file, String? targetPath}) => ModelFailure(
    kind: ModelFailureKind.cancelled,
    message: '已取消。已保留已下载的部分，下次可继续；已有的有效文件未被改动。',
    file: file,
    targetPath: targetPath,
  );

  static String _partPath(String dir, ModelFileSpec spec) =>
      '${p.joinAll([dir, ...spec.path.split('/')])}.part';

  static Future<void> _drain(http.StreamedResponse r) async {
    try {
      await r.stream.drain<void>();
    } catch (_) {}
  }

  static Future<void> _safeDelete(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  static String _httpMessage(int code, String url) {
    final host = Uri.parse(url).host;
    if (code == 404) {
      return '$host 上找不到该文件 (HTTP 404)。镜像可能尚未同步，请稍后重试或更换镜像。';
    }
    if (code == 401 || code == 403) {
      return '$host 拒绝访问 (HTTP $code)。该模型可能需要登录授权，或镜像限制了访问。';
    }
    if (code == 429) {
      return '$host 返回请求过多 (HTTP 429)，请稍后重试。';
    }
    if (code >= 500) {
      return '$host 服务器错误 (HTTP $code)，请稍后重试。';
    }
    return '下载失败：$host 返回 HTTP $code。';
  }

  static const _noSpaceErrnos = {
    112,
    39,
    28,
  }; // WIN disk full, handle disk full, ENOSPC
  static const _deniedErrnos = {
    5,
    13,
    1,
    19,
    30,
  }; // access denied, EACCES, EPERM, write-protect, read-only
  static const _lockedErrnos = {32, 33}; // sharing / lock violation

  ModelFailure _fromFileSystem(
    FileSystemException e, {
    String? file,
    String? targetPath,
    String action = '写入文件',
  }) {
    final code = e.osError?.errorCode;
    final raw = redactSecrets(
      '${e.message}${e.osError != null ? ' | os: ${e.osError!.message.trim()} (errno ${e.osError!.errorCode})' : ''}'
      '${e.path != null ? ' | path: ${e.path}' : ''}',
    );
    if (code != null && _noSpaceErrnos.contains(code)) {
      return ModelFailure(
        kind: ModelFailureKind.diskSpace,
        message: '磁盘空间不足，写入中断。已有的有效文件未被改动。请清理磁盘或更换模型目录。',
        file: file,
        targetPath: targetPath,
        osErrorCode: code,
        technical: raw,
      );
    }
    if (code != null && _lockedErrnos.contains(code)) {
      return ModelFailure(
        kind: ModelFailureKind.fileLocked,
        message:
            '文件正被其他程序占用，无法替换：${targetPath ?? file}。'
            '请关闭正在使用模型的任务（例如向量索引）后重试。',
        file: file,
        targetPath: targetPath,
        osErrorCode: code,
        technical: raw,
      );
    }
    if (code != null && _deniedErrnos.contains(code)) {
      return ModelFailure(
        kind: ModelFailureKind.permission,
        message:
            '没有权限$action：${targetPath ?? file}。'
            '请在“模型目录”中选择一个你有写入权限的文件夹（避免 Program Files 等受保护位置）。',
        file: file,
        targetPath: targetPath,
        osErrorCode: code,
        technical: raw,
      );
    }
    return ModelFailure(
      kind: ModelFailureKind.unknown,
      message: '$action失败：${e.message}${code != null ? ' (errno $code)' : ''}',
      file: file,
      targetPath: targetPath,
      osErrorCode: code,
      technical: raw,
    );
  }

  ModelFailure _fromTransport(
    Object e, {
    required ModelFileSpec spec,
    required String url,
    required String target,
  }) {
    final host = Uri.parse(url).host;
    final raw = redactSecrets(e.toString());
    final proxyEnv = _proxyEnvHint();

    if (e is TimeoutException) {
      return ModelFailure(
        kind: ModelFailureKind.timeout,
        message: '连接 $host 超时或下载长时间无数据 (${spec.path})。已保留下载进度，重试会继续。$proxyEnv',
        file: spec.path,
        targetPath: target,
        url: url,
        technical: raw,
      );
    }
    final lower = raw.toLowerCase();
    if (e is HandshakeException ||
        e is TlsException ||
        lower.contains('handshake') ||
        lower.contains('certificate')) {
      return ModelFailure(
        kind: ModelFailureKind.tls,
        message: '与 $host 的 TLS/证书握手失败。系统时间错误、证书被代理替换或网络拦截都会导致此问题。',
        file: spec.path,
        targetPath: target,
        url: url,
        technical: raw,
      );
    }
    final os = e is SocketException ? e.osError?.errorCode : null;
    if (lower.contains('failed host lookup') ||
        lower.contains('no address associated') ||
        os == 11001 ||
        os == 11002) {
      return ModelFailure(
        kind: ModelFailureKind.dns,
        message: '无法解析域名 $host，请检查网络、DNS 或代理设置。$proxyEnv',
        file: spec.path,
        targetPath: target,
        url: url,
        osErrorCode: os,
        technical: raw,
      );
    }
    if (e is SocketException ||
        e is http.ClientException ||
        e is HttpException) {
      return ModelFailure(
        kind: ModelFailureKind.connection,
        message:
            '无法连接 $host${os != null ? ' (errno $os)' : ''}，网络不可达或连接被重置 (${spec.path})。'
            '已保留下载进度，重试会继续。$proxyEnv',
        file: spec.path,
        targetPath: target,
        url: url,
        osErrorCode: os,
        technical: raw,
      );
    }
    return ModelFailure(
      kind: ModelFailureKind.unknown,
      message: '下载 ${spec.path} 时出现未分类错误：$raw',
      file: spec.path,
      targetPath: target,
      url: url,
      technical: raw,
    );
  }

  /// Mentions proxy environment variables only to help diagnosis. The app
  /// never reads or changes system proxy settings itself.
  static String _proxyEnvHint() {
    final env = Platform.environment;
    final set = [
      for (final k in const ['HTTPS_PROXY', 'HTTP_PROXY', 'ALL_PROXY'])
        if ((env[k] ?? env[k.toLowerCase()] ?? '').isNotEmpty) k,
    ];
    if (set.isEmpty) return '';
    return ' 检测到环境变量 ${set.join('/')}，下载会经过该代理；若代理不可用请检查它。';
  }
}
