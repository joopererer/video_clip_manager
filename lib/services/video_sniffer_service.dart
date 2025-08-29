import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';

class VideoSnifferService {
  static const Map<String, String> _headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.5',
    'Accept-Encoding': 'gzip, deflate',
    'Connection': 'keep-alive',
    'Upgrade-Insecure-Requests': '1',
  };

  /// 从网页URL中嗅探视频链接
  static Future<List<VideoInfo>> sniffVideoUrls(String pageUrl) async {
    try {
      print('VideoSnifferService: 开始嗅探视频链接: $pageUrl');
      
      // 1. 获取网页内容
      final response = await http.get(Uri.parse(pageUrl), headers: _headers);
      if (response.statusCode != 200) {
        print('VideoSnifferService: 获取网页失败: ${response.statusCode}');
        return [];
      }

      final document = html_parser.parse(response.body);
      
      // 2. 多种方式嗅探视频
      final videos = <VideoInfo>[];
      
      // 2.1 从 <video> 标签嗅探
      videos.addAll(_extractFromVideoTags(document, pageUrl));
      
      // 2.2 从 <source> 标签嗅探
      videos.addAll(_extractFromSourceTags(document, pageUrl));
      
      // 2.3 从 OpenGraph meta 标签嗅探
      videos.addAll(_extractFromMetaTags(document, pageUrl));
      
      // 2.4 从 JSON-LD 结构化数据嗅探
      videos.addAll(_extractFromJsonLd(document, pageUrl));
      
      // 2.5 从链接嗅探
      videos.addAll(_extractFromLinks(document, pageUrl));
      
      // 2.6 特殊网站处理
      videos.addAll(await _extractFromSpecialSites(pageUrl, document));
      
      // 3. 去重和过滤
      final uniqueVideos = _deduplicateVideos(videos);
      
      print('VideoSnifferService: 找到 ${uniqueVideos.length} 个视频链接');
      for (final video in uniqueVideos) {
        print('VideoSnifferService: - ${video.url} (${video.type})');
      }
      
      return uniqueVideos;
    } catch (e) {
      print('VideoSnifferService: 嗅探失败: $e');
      return [];
    }
  }

  /// 从 <video> 标签提取视频链接
  static List<VideoInfo> _extractFromVideoTags(Document document, String baseUrl) {
    final videos = <VideoInfo>[];
    
    for (final video in document.querySelectorAll('video')) {
      // 直接 src 属性
      final src = video.attributes['src'];
      if (src != null && _isVideoUrl(src)) {
        videos.add(VideoInfo(
          url: _resolveUrl(src, baseUrl),
          type: VideoType.direct,
          title: video.attributes['title'] ?? '',
          width: _parseInt(video.attributes['width']),
          height: _parseInt(video.attributes['height']),
        ));
      }
      
      // poster 属性（可能是视频封面）
      final poster = video.attributes['poster'];
      if (poster != null) {
        videos.add(VideoInfo(
          url: _resolveUrl(poster, baseUrl),
          type: VideoType.thumbnail,
          title: 'Video Poster',
        ));
      }
    }
    
    return videos;
  }

  /// 从 <source> 标签提取视频链接
  static List<VideoInfo> _extractFromSourceTags(Document document, String baseUrl) {
    final videos = <VideoInfo>[];
    
    for (final source in document.querySelectorAll('source')) {
      final src = source.attributes['src'];
      final type = source.attributes['type'];
      
      if (src != null && _isVideoUrl(src)) {
        videos.add(VideoInfo(
          url: _resolveUrl(src, baseUrl),
          type: VideoType.direct,
          title: source.attributes['title'] ?? '',
          mimeType: type,
        ));
      }
    }
    
    return videos;
  }

  /// 从 meta 标签提取视频链接
  static List<VideoInfo> _extractFromMetaTags(Document document, String baseUrl) {
    final videos = <VideoInfo>[];
    
    final metaSelectors = [
      'meta[property="og:video"]',
      'meta[property="og:video:secure_url"]',
      'meta[property="og:video:url"]',
      'meta[name="twitter:player:stream"]',
      'meta[property="video"]',
    ];
    
    for (final selector in metaSelectors) {
      for (final meta in document.querySelectorAll(selector)) {
        final content = meta.attributes['content'];
        if (content != null && _isVideoUrl(content)) {
          videos.add(VideoInfo(
            url: _resolveUrl(content, baseUrl),
            type: VideoType.meta,
            title: 'Meta Video',
          ));
        }
      }
    }
    
    return videos;
  }

  /// 从 JSON-LD 结构化数据提取视频链接
  static List<VideoInfo> _extractFromJsonLd(Document document, String baseUrl) {
    final videos = <VideoInfo>[];
    
    for (final script in document.querySelectorAll('script[type="application/ld+json"]')) {
      try {
        final data = json.decode(script.text);
        final items = data is List ? data : [data];
        
        for (final item in items) {
          if (item is Map) {
            // 检查各种可能的视频URL字段
            final videoUrls = [
              item['contentUrl'],
              item['embedUrl'],
              item['url'],
              item['video']?['contentUrl'],
              item['video']?['embedUrl'],
            ].where((url) => url != null && _isVideoUrl(url)).cast<String>();
            
            for (final url in videoUrls) {
              videos.add(VideoInfo(
                url: _resolveUrl(url, baseUrl),
                type: VideoType.jsonLd,
                title: item['name'] ?? item['title'] ?? 'JSON-LD Video',
              ));
            }
          }
        }
      } catch (e) {
        print('VideoSnifferService: JSON-LD 解析失败: $e');
      }
    }
    
    return videos;
  }

  /// 从链接提取视频
  static List<VideoInfo> _extractFromLinks(Document document, String baseUrl) {
    final videos = <VideoInfo>[];
    
    for (final link in document.querySelectorAll('a[href]')) {
      final href = link.attributes['href'];
      if (href != null && _isVideoUrl(href)) {
        videos.add(VideoInfo(
          url: _resolveUrl(href, baseUrl),
          type: VideoType.link,
          title: link.text.trim(),
        ));
      }
    }
    
    return videos;
  }

  /// 特殊网站处理
  static Future<List<VideoInfo>> _extractFromSpecialSites(String pageUrl, Document document) async {
    final videos = <VideoInfo>[];
    
    // MissAV 特殊处理
    if (pageUrl.contains('missav.ws') || pageUrl.contains('missav.com')) {
      videos.addAll(await _extractFromMissav(pageUrl, document));
    }
    
    // XVideos 特殊处理
    if (pageUrl.contains('xvideos.com')) {
      videos.addAll(await _extractFromXvideos(pageUrl, document));
    }
    
    // YouTube 特殊处理
    if (pageUrl.contains('youtube.com') || pageUrl.contains('youtu.be')) {
      videos.addAll(await _extractFromYoutube(pageUrl, document));
    }
    
    // Bilibili 特殊处理
    if (pageUrl.contains('bilibili.com')) {
      videos.addAll(await _extractFromBilibili(pageUrl, document));
    }
    
    return videos;
  }

  /// MissAV 特殊处理
  static Future<List<VideoInfo>> _extractFromMissav(String pageUrl, Document document) async {
    final videos = <VideoInfo>[];
    
    try {
      // 查找视频播放器相关的脚本
      for (final script in document.querySelectorAll('script')) {
        final content = script.text;
        if (content.contains('video') || content.contains('player')) {
          // 查找可能的视频URL模式
          final videoUrlPattern = RegExp(r'["\']([^"\']*\.(?:mp4|m3u8|webm)[^"\']*)["\']');
          final matches = videoUrlPattern.allMatches(content);
          
          for (final match in matches) {
            final url = match.group(1);
            if (url != null && _isVideoUrl(url)) {
              videos.add(VideoInfo(
                url: _resolveUrl(url, pageUrl),
                type: VideoType.special,
                title: 'MissAV Video',
              ));
            }
          }
        }
      }
    } catch (e) {
      print('VideoSnifferService: MissAV 处理失败: $e');
    }
    
    return videos;
  }

  /// XVideos 特殊处理
  static Future<List<VideoInfo>> _extractFromXvideos(String pageUrl, Document document) async {
    final videos = <VideoInfo>[];
    
    try {
      // XVideos 通常使用 HLS 流
      for (final script in document.querySelectorAll('script')) {
        final content = script.text;
        if (content.contains('hls') || content.contains('m3u8')) {
          final hlsPattern = RegExp(r'["\']([^"\']*\.m3u8[^"\']*)["\']');
          final matches = hlsPattern.allMatches(content);
          
          for (final match in matches) {
            final url = match.group(1);
            if (url != null) {
              videos.add(VideoInfo(
                url: _resolveUrl(url, pageUrl),
                type: VideoType.hls,
                title: 'XVideos HLS Stream',
              ));
            }
          }
        }
      }
    } catch (e) {
      print('VideoSnifferService: XVideos 处理失败: $e');
    }
    
    return videos;
  }

  /// YouTube 特殊处理
  static Future<List<VideoInfo>> _extractFromYoutube(String pageUrl, Document document) async {
    final videos = <VideoInfo>[];
    
    try {
      // YouTube 需要特殊处理，通常需要解析播放器配置
      for (final script in document.querySelectorAll('script')) {
        final content = script.text;
        if (content.contains('ytInitialPlayerResponse')) {
          final jsonPattern = RegExp(r'ytInitialPlayerResponse\s*=\s*({.*?});');
          final match = jsonPattern.firstMatch(content);
          
          if (match != null) {
            try {
              final jsonData = json.decode(match.group(1)!);
              // 这里需要进一步解析 YouTube 的播放器配置
              // 由于 YouTube 的反爬虫机制，可能需要更复杂的处理
            } catch (e) {
              print('VideoSnifferService: YouTube JSON 解析失败: $e');
            }
          }
        }
      }
    } catch (e) {
      print('VideoSnifferService: YouTube 处理失败: $e');
    }
    
    return videos;
  }

  /// Bilibili 特殊处理
  static Future<List<VideoInfo>> _extractFromBilibili(String pageUrl, Document document) async {
    final videos = <VideoInfo>[];
    
    try {
      // Bilibili 通常需要解析播放器配置
      for (final script in document.querySelectorAll('script')) {
        final content = script.text;
        if (content.contains('window.__INITIAL_STATE__')) {
          final jsonPattern = RegExp(r'window\.__INITIAL_STATE__\s*=\s*({.*?});');
          final match = jsonPattern.firstMatch(content);
          
          if (match != null) {
            try {
              final jsonData = json.decode(match.group(1)!);
              // 这里需要进一步解析 Bilibili 的播放器配置
            } catch (e) {
              print('VideoSnifferService: Bilibili JSON 解析失败: $e');
            }
          }
        }
      }
    } catch (e) {
      print('VideoSnifferService: Bilibili 处理失败: $e');
    }
    
    return videos;
  }

  /// 去重视频列表
  static List<VideoInfo> _deduplicateVideos(List<VideoInfo> videos) {
    final seen = <String>{};
    final unique = <VideoInfo>[];
    
    for (final video in videos) {
      if (!seen.contains(video.url)) {
        seen.add(video.url);
        unique.add(video);
      }
    }
    
    return unique;
  }

  /// 判断是否为视频URL
  static bool _isVideoUrl(String url) {
    if (url.isEmpty) return false;
    
    // 视频文件扩展名
    final videoExtensions = [
      '.mp4', '.webm', '.mov', '.avi', '.mkv', '.flv', '.wmv', '.m4v',
      '.m3u8', '.mpd', '.ts', '.mts', '.m2ts'
    ];
    
    final lowerUrl = url.toLowerCase();
    
    // 检查文件扩展名
    for (final ext in videoExtensions) {
      if (lowerUrl.contains(ext)) return true;
    }
    
    // 检查特殊域名
    final specialDomains = [
      'googlevideo.com', // YouTube
      'blob:', // Blob URL
      'data:video/', // Data URL
    ];
    
    for (final domain in specialDomains) {
      if (lowerUrl.contains(domain)) return true;
    }
    
    return false;
  }

  /// 解析相对URL为绝对URL
  static String _resolveUrl(String url, String baseUrl) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    
    if (url.startsWith('//')) {
      return 'https:$url';
    }
    
    if (url.startsWith('/')) {
      final uri = Uri.parse(baseUrl);
      return '${uri.scheme}://${uri.host}$url';
    }
    
    return Uri.parse(baseUrl).resolve(url).toString();
  }

  /// 解析整数
  static int? _parseInt(String? value) {
    if (value == null) return null;
    return int.tryParse(value);
  }
}

/// 视频信息
class VideoInfo {
  final String url;
  final VideoType type;
  final String title;
  final String? mimeType;
  final int? width;
  final int? height;

  VideoInfo({
    required this.url,
    required this.type,
    required this.title,
    this.mimeType,
    this.width,
    this.height,
  });

  @override
  String toString() {
    return 'VideoInfo(url: $url, type: $type, title: $title)';
  }
}

/// 视频类型
enum VideoType {
  direct,    // 直接视频文件
  hls,       // HLS 流
  dash,      // DASH 流
  meta,      // Meta 标签
  jsonLd,    // JSON-LD 数据
  link,      // 链接
  special,   // 特殊网站
  thumbnail, // 缩略图
}
