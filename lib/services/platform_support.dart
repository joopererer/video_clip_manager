import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../data/models.dart';

/// 视频信息类
class VideoInfo {
  final String id;
  final String title;
  final String? description;
  final Duration? duration;
  final String? thumbnailUrl;
  final String platform;
  final Map<String, dynamic> metadata;

  const VideoInfo({
    required this.id,
    required this.title,
    this.description,
    this.duration,
    this.thumbnailUrl,
    required this.platform,
    this.metadata = const {},
  });

  factory VideoInfo.fromJson(Map<String, dynamic> json) {
    return VideoInfo(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'],
      duration: json['duration'] != null
          ? Duration(milliseconds: json['duration'])
          : null,
      thumbnailUrl: json['thumbnail_url'] ?? json['thumbnailUrl'],
      platform: json['platform'] ?? 'unknown',
      metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'duration': duration?.inMilliseconds,
      'thumbnail_url': thumbnailUrl,
      'platform': platform,
      'metadata': metadata,
    };
  }
}

/// 平台支持抽象接口
abstract class PlatformSupport {
  /// 提取视频信息
  Future<VideoInfo> extractVideoInfo(String url);
  
  /// 获取内嵌播放URL
  String getEmbedUrl(String videoId);
  
  /// 是否支持内嵌播放
  bool supportsEmbeddedPlayback();
  
  /// 获取播放器控制脚本
  String getPlayerControlScript();
  
  /// 获取指定时间的缩略图
  Future<String?> getThumbnail(String videoId, Duration time);
  
  /// 获取平台显示名称
  String getPlatformName();
  
  /// 获取平台图标
  String getPlatformIcon();
  
  /// 验证URL是否有效
  bool isValidUrl(String url);
  
  /// 获取视频流URL（如果可能）
  Future<String?> getVideoStreamUrl(String url);
  
  /// 获取播放质量选项
  List<String> getAvailableQualities();
  
  /// 是否支持精确时间控制
  bool supportsPreciseTimeControl();
}

/// YouTube平台支持
class YouTubeSupport implements PlatformSupport {
  @override
  Future<VideoInfo> extractVideoInfo(String url) async {
    try {
      // 使用yt-dlp提取信息
      final result = await Process.run('yt-dlp', [
        '--dump-json',
        '--no-playlist',
        url,
      ]);

      if (result.exitCode == 0) {
        final json = jsonDecode(result.stdout);
        return VideoInfo.fromJson({
          ...json,
          'platform': 'youtube',
        });
      } else {
        throw Exception('Failed to extract YouTube info: ${result.stderr}');
      }
    } catch (e) {
      throw Exception('Failed to extract YouTube info: $e');
    }
  }

  @override
  String getEmbedUrl(String videoId) {
    return 'https://www.youtube.com/embed/$videoId?enablejsapi=1';
  }

  @override
  bool supportsEmbeddedPlayback() => true;

  @override
  String getPlayerControlScript() {
    return '''
      // YouTube IFrame API
      var player;
      function onYouTubeIframeAPIReady() {
        player = new YT.Player('player', {
          height: '360',
          width: '640',
          videoId: 'videoId',
          events: {
            'onReady': onPlayerReady,
            'onStateChange': onPlayerStateChange
          }
        });
      }
      
      function onPlayerReady(event) {
        // 播放器准备就绪
      }
      
      function seekTo(seconds) {
        player.seekTo(seconds, true);
      }
      
      function getCurrentTime() {
        return player.getCurrentTime();
      }
      
      function play() {
        player.playVideo();
      }
      
      function pause() {
        player.pauseVideo();
      }
    ''';
  }

  @override
  Future<String?> getThumbnail(String videoId, Duration time) async {
    final timeInSeconds = time.inSeconds;
    return 'https://img.youtube.com/vi/$videoId/$timeInSeconds.jpg';
  }

  @override
  String getPlatformName() => 'YouTube';

  @override
  String getPlatformIcon() => '🎥';

  @override
  bool isValidUrl(String url) {
    return url.contains('youtube.com') || url.contains('youtu.be');
  }

  @override
  Future<String?> getVideoStreamUrl(String url) async {
    try {
      final result = await Process.run('yt-dlp', [
        '--get-url',
        '--format', 'best',
        '--no-playlist',
        url,
      ]);

      if (result.exitCode == 0) {
        return result.stdout.trim();
      }
    } catch (e) {
      // 忽略错误
    }
    return null;
  }

  @override
  List<String> getAvailableQualities() => ['144p', '240p', '360p', '480p', '720p', '1080p'];

  @override
  bool supportsPreciseTimeControl() => true;
}

/// Bilibili平台支持
class BilibiliSupport implements PlatformSupport {
  @override
  Future<VideoInfo> extractVideoInfo(String url) async {
    try {
      // 使用bilibili-api提取信息
      final result = await Process.run('python', [
        'bilibili_extractor.py',
        url,
      ]);

      if (result.exitCode == 0) {
        final json = jsonDecode(result.stdout);
        return VideoInfo.fromJson({
          ...json,
          'platform': 'bilibili',
        });
      } else {
        throw Exception('Failed to extract Bilibili info: ${result.stderr}');
      }
    } catch (e) {
      throw Exception('Failed to extract Bilibili info: $e');
    }
  }

  @override
  String getEmbedUrl(String bvid) {
    return 'https://player.bilibili.com/player.html?bvid=$bvid&page=1&high_quality=1&danmaku=0';
  }

  @override
  bool supportsEmbeddedPlayback() => true;

  @override
  String getPlayerControlScript() {
    return '''
      // B站播放器控制
      function seekTo(seconds) {
        window.postMessage({
          type: 'seek',
          data: seconds
        }, '*');
      }
      
      function getCurrentTime() {
        return new Promise((resolve) => {
          window.postMessage({
            type: 'getCurrentTime',
            id: Date.now()
          }, '*');
          
          window.addEventListener('message', function(event) {
            if (event.data.type === 'currentTime') {
              resolve(event.data.data);
            }
          });
        });
      }
      
      function play() {
        window.postMessage({
          type: 'play'
        }, '*');
      }
      
      function pause() {
        window.postMessage({
          type: 'pause'
        }, '*');
      }
    ''';
  }

  @override
  Future<String?> getThumbnail(String bvid, Duration time) async {
    // B站缩略图通常使用视频ID
    return 'https://i0.hdslb.com/bfs/archive/$bvid.jpg';
  }

  @override
  String getPlatformName() => 'Bilibili';

  @override
  String getPlatformIcon() => '📺';

  @override
  bool isValidUrl(String url) {
    return url.contains('bilibili.com');
  }

  @override
  Future<String?> getVideoStreamUrl(String url) async {
    try {
      final result = await Process.run('yt-dlp', [
        '--get-url',
        '--format', 'best',
        '--no-playlist',
        url,
      ]);

      if (result.exitCode == 0) {
        return result.stdout.trim();
      }
    } catch (e) {
      // 忽略错误
    }
    return null;
  }

  @override
  List<String> getAvailableQualities() => ['360p', '480p', '720p', '1080p'];

  @override
  bool supportsPreciseTimeControl() => true;
}

/// MissAV平台支持
class MissAVSupport implements PlatformSupport {
  @override
  Future<VideoInfo> extractVideoInfo(String url) async {
    try {
      // 使用yt-dlp提取信息
      final result = await Process.run('yt-dlp', [
        '--dump-json',
        '--no-playlist',
        '--user-agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        url,
      ]);

      if (result.exitCode == 0) {
        final json = jsonDecode(result.stdout);
        return VideoInfo.fromJson({
          ...json,
          'platform': 'missav',
        });
      } else {
        throw Exception('Failed to extract MissAV info: ${result.stderr}');
      }
    } catch (e) {
      throw Exception('Failed to extract MissAV info: $e');
    }
  }

  @override
  String getEmbedUrl(String videoId) {
    // 尝试使用WebView加载原始页面
    return 'https://missav.ws/en/$videoId';
  }

  @override
  bool supportsEmbeddedPlayback() => true; // 改为true，使用WebView方案

  @override
  String getPlayerControlScript() {
    return '''
      // MissAV WebView控制脚本
      function seekTo(seconds) {
        // 尝试通过WebView控制播放器
        try {
          const video = document.querySelector('video');
          if (video) {
            video.currentTime = seconds;
          }
        } catch (e) {
          console.log('Cannot control video playback:', e);
        }
      }
      
      function getCurrentTime() {
        try {
          const video = document.querySelector('video');
          return video ? video.currentTime : 0;
        } catch (e) {
          return 0;
        }
      }
      
      function play() {
        try {
          const video = document.querySelector('video');
          if (video) video.play();
        } catch (e) {
          console.log('Cannot play video:', e);
        }
      }
      
      function pause() {
        try {
          const video = document.querySelector('video');
          if (video) video.pause();
        } catch (e) {
          console.log('Cannot pause video:', e);
        }
      }
    ''';
  }

  @override
  Future<String?> getThumbnail(String videoId, Duration time) async {
    // 尝试获取视频缩略图
    try {
      final response = await http.get(Uri.parse('https://missav.ws/en/$videoId'));
      if (response.statusCode == 200) {
        // 解析HTML获取缩略图URL
        final html = response.body;
        final regex = RegExp(r'<meta property="og:image" content="([^"]+)"');
        final match = regex.firstMatch(html);
        return match?.group(1);
      }
    } catch (e) {
      // 忽略错误
    }
    return null;
  }

  @override
  String getPlatformName() => 'MissAV';

  @override
  String getPlatformIcon() => '🎬';

  @override
  bool isValidUrl(String url) {
    return url.contains('missav.ws') || url.contains('missav.com');
  }

  @override
  Future<String?> getVideoStreamUrl(String url) async {
    try {
      final result = await Process.run('yt-dlp', [
        '--get-url',
        '--format', 'best',
        '--no-playlist',
        url,
      ]);

      if (result.exitCode == 0) {
        return result.stdout.trim();
      }
    } catch (e) {
      // 忽略错误
    }
    return null;
  }

  @override
  List<String> getAvailableQualities() => ['480p', '720p', '1080p'];

  @override
  bool supportsPreciseTimeControl() => false; // WebView控制可能不够精确
}

/// XVideos平台支持
class XVideosSupport implements PlatformSupport {
  @override
  Future<VideoInfo> extractVideoInfo(String url) async {
    try {
      // 使用yt-dlp提取信息
      final result = await Process.run('yt-dlp', [
        '--dump-json',
        '--no-playlist',
        '--user-agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        url,
      ]);

      if (result.exitCode == 0) {
        final json = jsonDecode(result.stdout);
        return VideoInfo.fromJson({
          ...json,
          'platform': 'xvideos',
        });
      } else {
        throw Exception('Failed to extract XVideos info: ${result.stderr}');
      }
    } catch (e) {
      throw Exception('Failed to extract XVideos info: $e');
    }
  }

  @override
  String getEmbedUrl(String videoId) {
    // 尝试使用WebView加载原始页面
    return 'https://www.xvideos.com/video.$videoId';
  }

  @override
  bool supportsEmbeddedPlayback() => true; // 改为true，使用WebView方案

  @override
  String getPlayerControlScript() {
    return '''
      // XVideos WebView控制脚本
      function seekTo(seconds) {
        try {
          const video = document.querySelector('video');
          if (video) {
            video.currentTime = seconds;
          }
        } catch (e) {
          console.log('Cannot control video playback:', e);
        }
      }
      
      function getCurrentTime() {
        try {
          const video = document.querySelector('video');
          return video ? video.currentTime : 0;
        } catch (e) {
          return 0;
        }
      }
      
      function play() {
        try {
          const video = document.querySelector('video');
          if (video) video.play();
        } catch (e) {
          console.log('Cannot play video:', e);
        }
      }
      
      function pause() {
        try {
          const video = document.querySelector('video');
          if (video) video.pause();
        } catch (e) {
          console.log('Cannot pause video:', e);
        }
      }
    ''';
  }

  @override
  Future<String?> getThumbnail(String videoId, Duration time) async {
    // 尝试获取视频缩略图
    try {
      final response = await http.get(Uri.parse('https://www.xvideos.com/video.$videoId'));
      if (response.statusCode == 200) {
        // 解析HTML获取缩略图URL
        final html = response.body;
        final regex = RegExp(r'<meta property="og:image" content="([^"]+)"');
        final match = regex.firstMatch(html);
        return match?.group(1);
      }
    } catch (e) {
      // 忽略错误
    }
    return null;
  }

  @override
  String getPlatformName() => 'XVideos';

  @override
  String getPlatformIcon() => '🎭';

  @override
  bool isValidUrl(String url) {
    return url.contains('xvideos.com');
  }

  @override
  Future<String?> getVideoStreamUrl(String url) async {
    try {
      final result = await Process.run('yt-dlp', [
        '--get-url',
        '--format', 'best',
        '--no-playlist',
        url,
      ]);

      if (result.exitCode == 0) {
        return result.stdout.trim();
      }
    } catch (e) {
      // 忽略错误
    }
    return null;
  }

  @override
  List<String> getAvailableQualities() => ['480p', '720p', '1080p'];

  @override
  bool supportsPreciseTimeControl() => false; // WebView控制可能不够精确
}

/// 未知平台支持
class UnknownPlatformSupport implements PlatformSupport {
  @override
  Future<VideoInfo> extractVideoInfo(String url) async {
    throw UnsupportedError('Unsupported platform for URL: $url');
  }

  @override
  String getEmbedUrl(String videoId) => '';

  @override
  bool supportsEmbeddedPlayback() => false;

  @override
  String getPlayerControlScript() => '';

  @override
  Future<String?> getThumbnail(String videoId, Duration time) async => null;

  @override
  String getPlatformName() => 'Unknown';

  @override
  String getPlatformIcon() => '🌐';

  @override
  bool isValidUrl(String url) => false;

  @override
  Future<String?> getVideoStreamUrl(String url) async => null;

  @override
  List<String> getAvailableQualities() => [];

  @override
  bool supportsPreciseTimeControl() => false;
}

/// 平台工厂类
class PlatformFactory {
  static final Map<String, PlatformSupport> _platforms = {
    'youtube': YouTubeSupport(),
    'bilibili': BilibiliSupport(),
    'missav': MissAVSupport(),
    'xvideos': XVideosSupport(),
  };

  /// 根据平台名称获取平台支持
  static PlatformSupport getPlatform(String platform) {
    return _platforms[platform] ?? UnknownPlatformSupport();
  }

  /// 根据URL检测平台
  static String detectPlatform(String url) {
    if (url.contains('youtube.com') || url.contains('youtu.be')) {
      return 'youtube';
    } else if (url.contains('bilibili.com')) {
      return 'bilibili';
    } else if (url.contains('missav.ws') || url.contains('missav.com')) {
      return 'missav';
    } else if (url.contains('xvideos.com')) {
      return 'xvideos';
    }
    return 'unknown';
  }

  /// 根据URL获取平台支持
  static PlatformSupport getPlatformByUrl(String url) {
    final platform = detectPlatform(url);
    return getPlatform(platform);
  }

  /// 获取支持的平台列表
  static List<String> getSupportedPlatforms() {
    return _platforms.keys.toList();
  }

  /// 获取平台显示名称
  static String getPlatformName(String platform) {
    return getPlatform(platform).getPlatformName();
  }

  /// 获取平台图标
  static String getPlatformIcon(String platform) {
    return getPlatform(platform).getPlatformIcon();
  }

  /// 检查平台是否支持内嵌播放
  static bool supportsEmbeddedPlayback(String platform) {
    return getPlatform(platform).supportsEmbeddedPlayback();
  }

  /// 检查平台是否支持精确时间控制
  static bool supportsPreciseTimeControl(String platform) {
    return getPlatform(platform).supportsPreciseTimeControl();
  }

  /// 验证URL是否有效
  static bool isValidUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && uri.hasAuthority;
    } catch (e) {
      return false;
    }
  }
}
