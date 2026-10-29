import 'dart:async';
import 'dart:io';

/// Where a clip's media lives. Only [local] sources are subject to a file
/// existence check; network sources are validated by the player itself.
enum MediaSourceKind { local, network, invalid }

/// Why a media source could not be used. Keeps "file missing" separate from
/// network problems so the UI never reports an expired URL as a missing file.
enum MediaSourceFailure {
  none,
  emptyPath,
  invalidUrl,
  localFileMissing,
  openTimeout,
  openFailed,
}

const _networkSchemes = {'http', 'https', 'rtmp', 'rtsp'};

/// Classifies [path] without touching the file system.
///
/// Mirrors the checks already used by `ClipPlaybackScreen`,
/// `ScreenshotService` and `clip_editor_screen.dart` (case-insensitive scheme
/// prefix). A Windows path such as `C:\a\b.m3u8` has a one-letter "scheme"
/// and is therefore local, not network.
MediaSourceKind classifyMediaSource(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return MediaSourceKind.invalid;
  final lower = trimmed.toLowerCase();
  for (final scheme in _networkSchemes) {
    if (lower.startsWith('$scheme://')) {
      final uri = Uri.tryParse(trimmed);
      if (uri == null || uri.host.isEmpty) return MediaSourceKind.invalid;
      return MediaSourceKind.network;
    }
  }
  return MediaSourceKind.local;
}

bool isNetworkMediaSource(String path) =>
    classifyMediaSource(path) == MediaSourceKind.network;

/// True when [path] looks like an HLS playlist (local file or URL, query
/// string ignored).
bool isM3u8Source(String path) {
  final trimmed = path.trim();
  final uri = Uri.tryParse(trimmed);
  final target = (uri != null && uri.hasScheme && uri.scheme.length > 1)
      ? uri.path
      : trimmed;
  final lower = target.toLowerCase();
  return lower.endsWith('.m3u8') || lower.endsWith('.m3u');
}

typedef FileExistsCheck = Future<bool> Function(String path);

Future<bool> _defaultFileExists(String path) => File(path).exists();

/// Result of [resolveMediaSource].
class MediaSourceResolution {
  const MediaSourceResolution(this.kind, this.failure);

  final MediaSourceKind kind;
  final MediaSourceFailure failure;

  bool get isUsable => failure == MediaSourceFailure.none;
}

/// Decides whether [path] may be handed to `Player.open`.
///
/// * network sources skip the file check (never `File.exists()` on a URL);
/// * local sources, including local `.m3u8` files, must exist;
/// * invalid URLs and empty paths are reported separately.
///
/// [fileExists] is injectable for tests.
Future<MediaSourceResolution> resolveMediaSource(
  String path, {
  FileExistsCheck fileExists = _defaultFileExists,
}) async {
  final kind = classifyMediaSource(path);
  switch (kind) {
    case MediaSourceKind.invalid:
      return MediaSourceResolution(
        kind,
        path.trim().isEmpty
            ? MediaSourceFailure.emptyPath
            : MediaSourceFailure.invalidUrl,
      );
    case MediaSourceKind.network:
      return MediaSourceResolution(kind, MediaSourceFailure.none);
    case MediaSourceKind.local:
      bool exists;
      try {
        exists = await fileExists(path);
      } catch (_) {
        // An unreadable path is reported as missing, as before.
        exists = false;
      }
      return MediaSourceResolution(
        kind,
        exists ? MediaSourceFailure.none : MediaSourceFailure.localFileMissing,
      );
  }
}

/// Classifies an error thrown by `Player.open` for [kind].
MediaSourceFailure classifyOpenError(Object error) {
  return error is TimeoutException
      ? MediaSourceFailure.openTimeout
      : MediaSourceFailure.openFailed;
}

/// Last path segment for messages; handles both `\` and `/` and strips the
/// query string of URLs.
String mediaDisplayName(String path) {
  var s = path.trim();
  final q = s.indexOf('?');
  if (q > 0 && classifyMediaSource(s) == MediaSourceKind.network) {
    s = s.substring(0, q);
  }
  final i = s.lastIndexOf(RegExp(r'[\\/]'));
  final name = i >= 0 ? s.substring(i + 1) : s;
  return name.isEmpty ? s : name;
}

/// User-facing message for a failure, or null when there is none.
String? mediaFailureMessage(MediaSourceFailure failure, String path) {
  final name = mediaDisplayName(path);
  switch (failure) {
    case MediaSourceFailure.none:
      return null;
    case MediaSourceFailure.emptyPath:
      return '片段没有有效的媒体路径';
    case MediaSourceFailure.invalidUrl:
      return '媒体地址无效: $path';
    case MediaSourceFailure.localFileMissing:
      return '文件不存在: $name';
    case MediaSourceFailure.openTimeout:
      return '打开媒体超时: $name';
    case MediaSourceFailure.openFailed:
      return '无法打开媒体（网络错误或地址已过期）: $name';
  }
}
