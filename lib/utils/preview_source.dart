import '../data/models.dart';
import '../services/online_video_cache_service.dart';
import 'media_source.dart';

/// Same User-Agent the online clip editor sends for sniffed direct links.
const String kPreviewUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36';

/// What the original-video preview should open, or why it cannot.
///
/// Pure data: resolving a source never creates a player.
class PreviewSource {
  const PreviewSource._({
    this.path,
    this.kind = MediaSourceKind.invalid,
    this.httpHeaders = const {},
    this.failureMessage,
  });

  /// A source that may be handed to `Player.open`.
  const PreviewSource.playable({
    required String path,
    required MediaSourceKind kind,
    Map<String, String> httpHeaders = const {},
  }) : this._(path: path, kind: kind, httpHeaders: httpHeaders);

  /// A source that cannot be opened; [failureMessage] is shown to the user.
  const PreviewSource.failed(String failureMessage)
    : this._(failureMessage: failureMessage);

  final String? path;
  final MediaSourceKind kind;
  final Map<String, String> httpHeaders;
  final String? failureMessage;

  bool get isPlayable => path != null && failureMessage == null;
  bool get isNetwork => kind == MediaSourceKind.network;
}

const _directMediaExtensions = [
  '.mp4',
  '.m4v',
  '.webm',
  '.mkv',
  '.mov',
  '.flv',
  '.ts',
];

/// True when [url] can be given to the player as is (HLS, a direct media
/// file, or a streaming scheme). A YouTube or Bilibili page URL is not.
bool isDirectMediaUrl(String url) {
  if (classifyMediaSource(url) != MediaSourceKind.network) return false;
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return false;
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'rtmp' || scheme == 'rtsp') return true;
  if (isM3u8Source(url)) return true;
  final path = uri.path.toLowerCase();
  return _directMediaExtensions.any(path.endsWith);
}

const String kPreviewNoDirectLink =
    '没有可直接播放的有效链接（链接已过期或尚未解析）。请使用“创建剪辑”重新解析后再播放。';

/// Decides what the preview dialog opens for [video], an [OriginalVideo] or
/// an [OnlineVideo].
///
/// * local paths must exist (missing file is reported as such);
/// * network sources, including `.m3u8`, are not checked on disk;
/// * online videos prefer the downloaded file, then the cached direct link
///   (same expiry rule as `OnlineClipEditorScreen`), then a direct URL.
///   No sniffing happens here; the editor owns that flow.
Future<PreviewSource> resolvePreviewSource(
  Object video, {
  FileExistsCheck? fileExists,
}) async {
  Future<MediaSourceResolution> resolve(String path) => fileExists == null
      ? resolveMediaSource(path)
      : resolveMediaSource(path, fileExists: fileExists);

  if (video is OriginalVideo) {
    final result = await resolve(video.path);
    if (!result.isUsable) {
      return PreviewSource.failed(
        mediaFailureMessage(result.failure, video.path) ?? '无法播放该视频',
      );
    }
    return PreviewSource.playable(path: video.path, kind: result.kind);
  }

  if (video is OnlineVideo) {
    final localPath = video.localPath;
    if (video.isDownloaded && localPath != null && localPath.isNotEmpty) {
      final result = await resolve(localPath);
      if (result.isUsable) {
        return PreviewSource.playable(path: localPath, kind: result.kind);
      }
    }

    final cached = video.metadata['videoUrl'];
    if (cached is String &&
        cached.isNotEmpty &&
        !OnlineVideoCacheService.isVideoUrlExpired(video) &&
        classifyMediaSource(cached) == MediaSourceKind.network) {
      final rawHeaders = video.metadata['httpHeaders'];
      return PreviewSource.playable(
        path: cached,
        kind: MediaSourceKind.network,
        httpHeaders: {
          if (rawHeaders is Map)
            for (final e in rawHeaders.entries)
              e.key.toString(): e.value.toString(),
          'User-Agent': kPreviewUserAgent,
        },
      );
    }

    if (isDirectMediaUrl(video.url)) {
      return PreviewSource.playable(
        path: video.url.trim(),
        kind: MediaSourceKind.network,
      );
    }
    return const PreviewSource.failed(kPreviewNoDirectLink);
  }

  return const PreviewSource.failed('不支持的视频类型');
}

/// `m:ss`, or `h:mm:ss` from one hour up. Negative values show as zero.
String formatPreviewClock(Duration d) {
  final total = d.isNegative ? 0 : d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}
