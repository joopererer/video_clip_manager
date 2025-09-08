import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:http/http.dart' as http;
import 'video_sniffer_service.dart';
import 'yt_dlp_service.dart';

/// 混合视频嗅探服务
/// 结合 yt-dlp 和自定义方法，支持更多视频网站
class HybridVideoSnifferService {
  
  /// 从URL中提取视频信息
  static Future<VideoInfo?> extractVideoInfo(String url) async {
    try {
      print('HybridVideoSnifferService: 开始提取视频信息: $url');
      
      // 首先尝试使用 yt-dlp
      final ytDlpInfo = await _tryYtDlp(url);
      if (ytDlpInfo != null) {
        print('HybridVideoSnifferService: yt-dlp 提取成功');
        return ytDlpInfo;
      }
      
      // 如果 yt-dlp 失败，尝试自定义方法
      print('HybridVideoSnifferService: yt-dlp 失败，尝试自定义方法');
      final customInfo = await _tryCustomMethod(url);
      if (customInfo != null) {
        print('HybridVideoSnifferService: 自定义方法提取成功');
        return customInfo;
      }
      
      print('HybridVideoSnifferService: 所有方法都失败');
      return null;
      
    } catch (e) {
      print('HybridVideoSnifferService: 提取视频信息失败: $e');
      return null;
    }
  }
  
  /// 尝试使用 yt-dlp 提取
  static Future<VideoInfo?> _tryYtDlp(String url) async {
    try {
      // 检查 yt-dlp 是否可用
      if (!await YtDlpService.isAvailable()) {
        print('HybridVideoSnifferService: yt-dlp 不可用');
        return null;
      }
      
      // 检查是否支持该网站
      if (!_isYtDlpSupported(url)) {
        print('HybridVideoSnifferService: yt-dlp 不支持该网站');
        return null;
      }
      
      final ytDlpInfo = await YtDlpService.extractVideoInfo(url);
      if (ytDlpInfo == null) return null;
      
      // 转换为通用格式
      return _convertYtDlpToVideoInfo(ytDlpInfo);
      
    } catch (e) {
      print('HybridVideoSnifferService: yt-dlp 提取失败: $e');
      return null;
    }
  }
  
  /// 尝试使用自定义方法提取
  static Future<VideoInfo?> _tryCustomMethod(String url) async {
    try {
      // 使用现有的 VideoSnifferService
      final videos = await VideoSnifferService.sniffVideoUrls(url);
      if (videos.isEmpty) return null;
      
      // 选择最佳视频
      final bestVideo = _selectBestVideo(videos);
      
      return VideoInfo(
        title: bestVideo.title,
        duration: null, // 自定义方法可能无法获取时长
        thumbnail: null, // 自定义方法可能无法获取封面
        videoUrl: bestVideo.url,
        sourceUrl: url,
        streams: [
          VideoStream(
            url: bestVideo.url,
            formatId: 'custom',
            formatNote: 'Custom Extraction',
            ext: 'mp4',
            protocol: 'https',
            width: null,
            height: null,
            fps: null,
            vcodec: 'h264',
            acodec: 'aac',
            tbr: null,
            vbr: null,
            abr: null,
            resolution: null,
            aspectRatio: null,
            httpHeaders: null,
            rawData: {},
          ),
        ],
        rawData: {},
      );
      
    } catch (e) {
      print('HybridVideoSnifferService: 自定义方法提取失败: $e');
      return null;
    }
  }
  
  /// 选择最佳视频
  static dynamic _selectBestVideo(List<dynamic> videos) {
    // 按优先级排序：HLS > 直接视频 > 其他
    videos.sort((a, b) {
      // HLS 流优先
      if (a.type == VideoType.hls && b.type != VideoType.hls) return -1;
      if (a.type != VideoType.hls && b.type == VideoType.hls) return 1;
      
      // 然后按类型排序
      return a.type.index.compareTo(b.type.index);
    });
    
    return videos.first;
  }
  
  /// 检查 yt-dlp 是否支持该网站
  static bool _isYtDlpSupported(String url) {
    final supportedDomains = [
      'youtube.com',
      'youtu.be',
      'bilibili.com',
      'xvideos.com',
      'missav.com',
      'missav.ws',
      'pornhub.com',
      'redtube.com',
      'youporn.com',
      'tube8.com',
      'spankbang.com',
      'xhamster.com',
      'xnxx.com',
    ];
    
    return supportedDomains.any((domain) => url.contains(domain));
  }
  
  /// 将 yt-dlp 信息转换为通用格式
  static VideoInfo _convertYtDlpToVideoInfo(YtDlpVideoInfo ytDlpInfo) {
    return VideoInfo(
      title: ytDlpInfo.title,
      duration: ytDlpInfo.duration,
      thumbnail: ytDlpInfo.thumbnail,
      videoUrl: ytDlpInfo.getBestVideoUrl() ?? '', // 处理可能的 null 值
      sourceUrl: ytDlpInfo.webpageUrl,
      streams: ytDlpInfo.formats,
      rawData: ytDlpInfo.rawData,
    );
  }
  
  /// 获取最佳视频流URL
  static Future<String?> getBestVideoUrl(String url) async {
    try {
      final videoInfo = await extractVideoInfo(url);
      return videoInfo?.videoUrl;
    } catch (e) {
      print('HybridVideoSnifferService: 获取最佳视频URL失败: $e');
      return null;
    }
  }
  
  /// 获取所有可用的视频流
  static Future<List<dynamic>> getAllVideoStreams(String url) async {
    try {
      final videoInfo = await extractVideoInfo(url);
      return videoInfo?.streams ?? [];
    } catch (e) {
      print('HybridVideoSnifferService: 获取视频流失败: $e');
      return [];
    }
  }
  
  /// 获取视频元数据
  static Future<VideoMetadata?> getVideoMetadata(String url) async {
    try {
      final videoInfo = await extractVideoInfo(url);
      if (videoInfo == null) return null;
      
      return VideoMetadata(
        title: videoInfo.title,
        duration: videoInfo.duration,
        thumbnail: videoInfo.thumbnail,
        width: videoInfo.streams.isNotEmpty ? videoInfo.streams.first.width : null,
        height: videoInfo.streams.isNotEmpty ? videoInfo.streams.first.height : null,
        fps: videoInfo.streams.isNotEmpty ? videoInfo.streams.first.fps : null,
        resolution: videoInfo.streams.isNotEmpty ? videoInfo.streams.first.resolutionString : null,
        rawData: videoInfo.rawData,
      );
    } catch (e) {
      print('HybridVideoSnifferService: 获取视频元数据失败: $e');
      return null;
    }
  }
}

/// 通用视频信息
class VideoInfo {
  final String title;
  final Duration? duration;
  final String? thumbnail;
  final String? videoUrl;
  final String? sourceUrl;
  final List<dynamic> streams;
  final Map<String, dynamic> rawData;
  
  VideoInfo({
    required this.title,
    this.duration,
    this.thumbnail,
    this.videoUrl,
    this.sourceUrl,
    required this.streams,
    required this.rawData,
  });
}

/// 视频元数据
class VideoMetadata {
  final String title;
  final Duration? duration;
  final String? thumbnail;
  final int? width;
  final int? height;
  final double? fps;
  final String? resolution;
  final Map<String, dynamic> rawData;
  
  VideoMetadata({
    required this.title,
    this.duration,
    this.thumbnail,
    this.width,
    this.height,
    this.fps,
    this.resolution,
    required this.rawData,
  });
}
