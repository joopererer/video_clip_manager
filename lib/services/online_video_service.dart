import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../data/models.dart';
import 'platform_support.dart';

class OnlineVideoService {
  /// 提取视频信息
  static Future<OnlineVideo> extractVideoInfo(String url) async {
    try {
      // 使用平台支持提取信息
      final platformSupport = PlatformFactory.getPlatformByUrl(url);
      final videoInfo = await platformSupport.extractVideoInfo(url);
      
      // 验证必要信息
      if (videoInfo.title.isEmpty) {
        throw Exception('Failed to extract video title');
      }
      
      return OnlineVideo(
        id: videoInfo.id,
        url: url,
        title: videoInfo.title,
        description: videoInfo.description,
        duration: videoInfo.duration,
        thumbnailUrl: videoInfo.thumbnailUrl,
        platform: videoInfo.platform,
        metadata: videoInfo.metadata,
      );
    } catch (e) {
      throw Exception('Failed to extract video info: $e');
    }
  }

  /// 下载视频到本地
  static Future<String> downloadVideo(OnlineVideo video, {
    Duration? startTime,
    Duration? endTime,
  }) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final downloadsDir = Directory(path.join(appDir.path, 'downloads'));
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }

      final fileName = '${video.id}_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final localPath = path.join(downloadsDir.path, fileName);

      // 使用yt-dlp下载视频
      final List<String> args = [
        '-o', localPath,
        '--no-playlist',
      ];

      // 如果指定了时间段，添加裁剪参数
      if (startTime != null && endTime != null) {
        args.addAll([
          '--download-sections', '*${startTime.inSeconds}-${endTime.inSeconds}',
        ]);
      }

      args.add(video.url);

      final result = await Process.run('yt-dlp', args);

      if (result.exitCode == 0) {
        return localPath;
      } else {
        throw Exception('Download failed: ${result.stderr}');
      }
    } catch (e) {
      throw Exception('Failed to download video: $e');
    }
  }

  /// 生成内嵌播放器URL
  static String getEmbedUrl(String url, String platform) {
    final platformSupport = PlatformFactory.getPlatform(platform);
    final videoId = _extractVideoId(url, platform);
    return platformSupport.getEmbedUrl(videoId);
  }

  /// 提取视频ID
  static String _extractVideoId(String url, String platform) {
    switch (platform) {
      case 'youtube':
        return _extractYouTubeVideoId(url);
      case 'bilibili':
        return _extractBilibiliVideoId(url);
      case 'missav':
        return _extractMissAVVideoId(url);
      case 'xvideos':
        return _extractXVideosVideoId(url);
      default:
        return '';
    }
  }

  /// 提取YouTube视频ID
  static String _extractYouTubeVideoId(String url) {
    final regex = RegExp(r'(?:youtube\.com\/watch\?v=|youtu\.be\/)([^&\n?#]+)');
    final match = regex.firstMatch(url);
    return match?.group(1) ?? '';
  }

  /// 提取Bilibili视频ID
  static String _extractBilibiliVideoId(String url) {
    final regex = RegExp(r'bilibili\.com\/video\/(BV[a-zA-Z0-9]+)');
    final match = regex.firstMatch(url);
    return match?.group(1) ?? '';
  }

  /// 提取MissAV视频ID
  static String _extractMissAVVideoId(String url) {
    final regex = RegExp(r'missav\.ws\/[^\/]+\/([^\/\?]+)');
    final match = regex.firstMatch(url);
    return match?.group(1) ?? '';
  }

  /// 提取XVideos视频ID
  static String _extractXVideosVideoId(String url) {
    final regex = RegExp(r'xvideos\.com\/video\.([^\/\?]+)');
    final match = regex.firstMatch(url);
    return match?.group(1) ?? '';
  }

  /// 获取平台显示名称
  static String getPlatformName(String platform) {
    return PlatformFactory.getPlatformName(platform);
  }

  /// 获取平台图标
  static String getPlatformIcon(String platform) {
    return PlatformFactory.getPlatformIcon(platform);
  }

  /// 检查平台是否支持内嵌播放
  static bool supportsEmbeddedPlayback(String platform) {
    return PlatformFactory.supportsEmbeddedPlayback(platform);
  }

  /// 检查平台是否需要下载才能播放
  static bool requiresDownload(String platform) {
    return !PlatformFactory.supportsEmbeddedPlayback(platform);
  }

  /// 验证URL是否有效
  static bool isValidUrl(String url) {
    return PlatformFactory.isValidUrl(url);
  }

  /// 获取支持的平台列表
  static List<String> getSupportedPlatforms() {
    return PlatformFactory.getSupportedPlatforms();
  }

  /// 检测URL属于哪个平台
  static String detectPlatform(String url) {
    return PlatformFactory.detectPlatform(url);
  }

  /// 检查外部工具是否可用
  static Future<bool> checkExternalTools() async {
    try {
      // 检查yt-dlp
      final ytDlpResult = await Process.run('yt-dlp', ['--version']);
      if (ytDlpResult.exitCode != 0) {
        return false;
      }

      // 检查Python (用于bilibili-api)
      final pythonResult = await Process.run('python', ['--version']);
      if (pythonResult.exitCode != 0) {
        return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// 获取外部工具安装指导
  static String getInstallationGuide() {
    return '''
External tools installation guide:

1. Install yt-dlp:
   pip install yt-dlp

2. Install Python (if not already installed):
   Download from https://www.python.org/downloads/

3. Install bilibili-api (for Bilibili support):
   pip install bilibili-api

4. Install FFmpeg (for video processing):
   Download from https://ffmpeg.org/download.html
    ''';
  }
}
