import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:http/http.dart' as http;

/// YT-DLP 视频嗅探服务
/// 使用 yt-dlp 工具从各种视频平台提取视频链接和元数据
class YtDlpService {
  static const String _ytDlpCommand = 'yt-dlp';
  
  /// 从URL中提取视频信息
  static Future<YtDlpVideoInfo?> extractVideoInfo(String url) async {
    try {
      print('YtDlpService: 开始提取视频信息: $url');
      
      // 使用 yt-dlp 获取视频信息
      final result = await Process.run(_ytDlpCommand, [
        '--dump-json',
        '--no-playlist',
        '--no-warnings',
        url,
      ]);
      
      if (result.exitCode != 0) {
        print('YtDlpService: yt-dlp 执行失败: ${result.stderr}');
        return null;
      }
      
      final jsonData = json.decode(result.stdout.toString().trim());
      return YtDlpVideoInfo.fromJson(jsonData);
      
    } catch (e) {
      print('YtDlpService: 提取视频信息失败: $e');
      return null;
    }
  }
  
  /// 获取最佳视频流URL
  static Future<String?> getBestVideoUrl(String url) async {
    try {
      final videoInfo = await extractVideoInfo(url);
      if (videoInfo == null) return null;
      
      return videoInfo.getBestVideoUrl();
    } catch (e) {
      print('YtDlpService: 获取最佳视频URL失败: $e');
      return null;
    }
  }
  
  /// 获取所有可用的视频流
  static Future<List<VideoStream>> getAllVideoStreams(String url) async {
    try {
      final videoInfo = await extractVideoInfo(url);
      if (videoInfo == null) return [];
      
      return videoInfo.getAllVideoStreams();
    } catch (e) {
      print('YtDlpService: 获取视频流失败: $e');
      return [];
    }
  }
  
  /// 检查 yt-dlp 是否可用
  static Future<bool> isAvailable() async {
    try {
      final result = await Process.run(_ytDlpCommand, ['--version']);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }
}

/// YT-DLP 视频信息
class YtDlpVideoInfo {
  final String id;
  final String title;
  final String? description;
  final Duration? duration;
  final String? thumbnail;
  final String? uploader;
  final String? webpageUrl;
  final List<VideoStream> formats;
  final Map<String, dynamic> rawData;
  
  YtDlpVideoInfo({
    required this.id,
    required this.title,
    this.description,
    this.duration,
    this.thumbnail,
    this.uploader,
    this.webpageUrl,
    required this.formats,
    required this.rawData,
  });
  
  factory YtDlpVideoInfo.fromJson(Map<String, dynamic> json) {
    final formats = <VideoStream>[];
    
    // 解析视频格式
    if (json['formats'] != null) {
      for (final format in json['formats']) {
        formats.add(VideoStream.fromJson(format));
      }
    }
    
    // 解析时长
    Duration? duration;
    if (json['duration'] != null) {
      final seconds = json['duration'] is int 
          ? json['duration'].toDouble() 
          : double.tryParse(json['duration'].toString());
      if (seconds != null) {
        duration = Duration(seconds: seconds.toInt());
      }
    }
    
    return YtDlpVideoInfo(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'],
      duration: duration,
      thumbnail: json['thumbnail'],
      uploader: json['uploader'],
      webpageUrl: json['webpage_url'],
      formats: formats,
      rawData: json,
    );
  }
  
  /// 获取最佳视频URL
  String? getBestVideoUrl() {
    final videoStreams = getAllVideoStreams();
    if (videoStreams.isEmpty) return null;
    
    // 按优先级排序：HLS > 直接视频 > 其他
    videoStreams.sort((a, b) {
      // HLS 流优先
      if (a.isHls && !b.isHls) return -1;
      if (!a.isHls && b.isHls) return 1;
      
      // 然后按分辨率排序
      final aRes = (a.width ?? 0) * (a.height ?? 0);
      final bRes = (b.width ?? 0) * (b.height ?? 0);
      return bRes.compareTo(aRes);
    });
    
    return videoStreams.first.url;
  }
  
  /// 获取所有视频流（排除纯音频）
  List<VideoStream> getAllVideoStreams() {
    return formats.where((format) => 
      format.hasVideo && 
      format.url.isNotEmpty
    ).toList();
  }
  
  /// 获取所有音频流
  List<VideoStream> getAllAudioStreams() {
    return formats.where((format) => 
      format.hasAudio && 
      !format.hasVideo && 
      format.url.isNotEmpty
    ).toList();
  }
  
  /// 获取HLS流
  List<VideoStream> getHlsStreams() {
    return formats.where((format) => 
      format.isHls && 
      format.url.isNotEmpty
    ).toList();
  }
  
  /// 获取直接视频文件流
  List<VideoStream> getDirectVideoStreams() {
    return formats.where((format) => 
      format.hasVideo && 
      !format.isHls && 
      format.url.isNotEmpty
    ).toList();
  }
}

/// 视频流信息
class VideoStream {
  final String url;
  final String? formatId;
  final String? formatNote;
  final String? ext;
  final String? protocol;
  final int? width;
  final int? height;
  final double? fps;
  final String? vcodec;
  final String? acodec;
  final double? tbr; // 总比特率
  final double? vbr; // 视频比特率
  final double? abr; // 音频比特率
  final String? resolution;
  final String? aspectRatio;
  final Map<String, String>? httpHeaders;
  final Map<String, dynamic> rawData;
  
  VideoStream({
    required this.url,
    this.formatId,
    this.formatNote,
    this.ext,
    this.protocol,
    this.width,
    this.height,
    this.fps,
    this.vcodec,
    this.acodec,
    this.tbr,
    this.vbr,
    this.abr,
    this.resolution,
    this.aspectRatio,
    this.httpHeaders,
    required this.rawData,
  });
  
  factory VideoStream.fromJson(Map<String, dynamic> json) {
    // 解析HTTP头
    Map<String, String>? headers;
    if (json['http_headers'] != null) {
      headers = Map<String, String>.from(json['http_headers']);
    }
    
    return VideoStream(
      url: json['url'] ?? '',
      formatId: json['format_id']?.toString(),
      formatNote: json['format_note']?.toString(),
      ext: json['ext']?.toString(),
      protocol: json['protocol']?.toString(),
      width: json['width'] is int ? json['width'] : null,
      height: json['height'] is int ? json['height'] : null,
      fps: json['fps']?.toDouble(),
      vcodec: json['vcodec']?.toString(),
      acodec: json['acodec']?.toString(),
      tbr: json['tbr']?.toDouble(),
      vbr: json['vbr']?.toDouble(),
      abr: json['abr']?.toDouble(),
      resolution: json['resolution']?.toString(),
      aspectRatio: json['aspect_ratio']?.toString(),
      httpHeaders: headers,
      rawData: json,
    );
  }
  
  /// 是否有视频
  bool get hasVideo {
    // 检查vcodec字段
    if (vcodec != null && vcodec != 'none' && vcodec!.isNotEmpty) return true;
    
    // 检查分辨率信息
    if (width != null && height != null && width! > 0 && height! > 0) return true;
    
    // 检查HLS流
    if (isHls) return true;
    
    // 检查format_id是否包含视频标识
    final id = formatId?.toLowerCase() ?? '';
    if (id.contains('video') || id.contains('hls') || 
        id.endsWith('p') || id.contains('x')) return true;
    
    return false;
  }
  
  /// 是否有音频
  bool get hasAudio => acodec != null && acodec != 'none';
  
  /// 是否为HLS流
  bool get isHls => protocol == 'm3u8_native' || url.contains('.m3u8');
  
  /// 是否为DASH流
  bool get isDash => protocol == 'http_dash_segments' || url.contains('.mpd');
  
  /// 是否为直接视频文件
  bool get isDirectVideo => hasVideo && !isHls && !isDash;
  
  /// 获取分辨率字符串
  String get resolutionString {
    if (width != null && height != null) {
      return '${width}x$height';
    }
    return resolution ?? 'Unknown';
  }
  
  /// 获取质量描述
  String get qualityDescription {
    final parts = <String>[];
    
    if (formatNote != null && formatNote!.isNotEmpty) {
      parts.add(formatNote!);
    }
    
    if (width != null && height != null) {
      parts.add('${width}x$height');
    }
    
    if (fps != null) {
      parts.add('${fps!.toInt()}fps');
    }
    
    if (tbr != null) {
      parts.add('${(tbr! / 1024).toStringAsFixed(1)}kbps');
    }
    
    return parts.isEmpty ? 'Unknown' : parts.join(' ');
  }
  
  /// 获取完整描述
  String get fullDescription {
    final parts = <String>[];
    
    if (formatId != null) {
      parts.add('ID: $formatId');
    }
    
    parts.add(qualityDescription);
    
    if (ext != null) {
      parts.add('Format: $ext');
    }
    
    if (isHls) {
      parts.add('Type: HLS Stream');
    } else if (isDash) {
      parts.add('Type: DASH Stream');
    } else if (isDirectVideo) {
      parts.add('Type: Direct Video');
    }
    
    return parts.join(' | ');
  }
}

/// 视频流选择器
class VideoStreamSelector {
  /// 按优先级选择最佳视频流
  static VideoStream? selectBestStream(List<VideoStream> streams) {
    if (streams.isEmpty) return null;
    
    // 按优先级排序
    streams.sort((a, b) {
      // 1. 优先选择有视频的流
      if (a.hasVideo && !b.hasVideo) return -1;
      if (!a.hasVideo && b.hasVideo) return 1;
      
      // 2. 优先选择HLS流（更好的自适应）
      if (a.isHls && !b.isHls) return -1;
      if (!a.isHls && b.isHls) return 1;
      
      // 3. 按分辨率排序（高分辨率优先）
      final aRes = (a.width ?? 0) * (a.height ?? 0);
      final bRes = (b.width ?? 0) * (b.height ?? 0);
      if (aRes != bRes) return bRes.compareTo(aRes);
      
      // 4. 按比特率排序（高比特率优先）
      final aBitrate = a.tbr ?? a.vbr ?? 0;
      final bBitrate = b.tbr ?? b.vbr ?? 0;
      return bBitrate.compareTo(aBitrate);
      
      // 5. 按帧率排序（高帧率优先）
      final aFps = a.fps ?? 0;
      final bFps = b.fps ?? 0;
      return bFps.compareTo(aFps);
    });
    
    return streams.first;
  }
  
  /// 选择指定分辨率的流
  static VideoStream? selectByResolution(List<VideoStream> streams, int targetWidth, int targetHeight) {
    final candidates = streams.where((stream) => 
      stream.width == targetWidth && stream.height == targetHeight
    ).toList();
    
    if (candidates.isEmpty) return null;
    
    // 在相同分辨率中选择最佳质量
    candidates.sort((a, b) {
      final aBitrate = a.tbr ?? a.vbr ?? 0;
      final bBitrate = b.tbr ?? b.vbr ?? 0;
      return bBitrate.compareTo(aBitrate);
    });
    
    return candidates.first;
  }
  
  /// 选择HLS流
  static VideoStream? selectHlsStream(List<VideoStream> streams) {
    final hlsStreams = streams.where((stream) => stream.isHls).toList();
    return selectBestStream(hlsStreams);
  }
  
  /// 选择直接视频文件
  static VideoStream? selectDirectVideo(List<VideoStream> streams) {
    final directStreams = streams.where((stream) => stream.isDirectVideo).toList();
    return selectBestStream(directStreams);
  }
}

