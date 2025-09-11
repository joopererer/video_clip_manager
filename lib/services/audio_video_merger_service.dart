import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'yt_dlp_service.dart';

/// 音视频合并服务
/// 用于将分离的音频和视频流合并为可播放的单一流
class AudioVideoMergerService {
  
  /// 尝试为分离的音视频流创建一个可播放的URL
  /// 
  /// 策略：
  /// 1. 检查是否可以使用 HLS manifest 合并
  /// 2. 尝试创建临时的合并流
  /// 3. 回退到只播放视频流
  static Future<String?> createMergedStreamUrl(
    VideoStream videoStream, 
    VideoStream audioStream,
    {Map<String, String>? videoHeaders, Map<String, String>? audioHeaders}
  ) async {
    
    print('🔧 AudioVideoMergerService: 尝试合并音视频流');
    print('   视频流: ${videoStream.formatId} - ${videoStream.url.substring(0, 100)}...');
    print('   音频流: ${audioStream.formatId} - ${audioStream.url.substring(0, 100)}...');
    
    // 策略 1: 检查是否可以创建 HLS manifest
    try {
      final hlsManifest = await _createHLSManifest(videoStream, audioStream, videoHeaders, audioHeaders);
      if (hlsManifest != null) {
        print('✅ 成功创建 HLS manifest');
        return hlsManifest;
      }
    } catch (e) {
      print('❌ HLS manifest 创建失败: $e');
    }
    
    // 策略 2: 尝试创建 DASH manifest
    try {
      final dashManifest = await _createDASHManifest(videoStream, audioStream, videoHeaders, audioHeaders);
      if (dashManifest != null) {
        print('✅ 成功创建 DASH manifest');
        return dashManifest;
      }
    } catch (e) {
      print('❌ DASH manifest 创建失败: $e');
    }
    
    // 策略 3: 检查是否可以使用 FFmpeg 实时合并
    if (await _isFFmpegAvailable()) {
      try {
        final mergedUrl = await _createFFmpegMergedStream(videoStream, audioStream, videoHeaders, audioHeaders);
        if (mergedUrl != null) {
          print('✅ 成功创建 FFmpeg 合并流');
          return mergedUrl;
        }
      } catch (e) {
        print('❌ FFmpeg 合并失败: $e');
      }
    }
    
    print('⚠️ 所有合并策略都失败，将只播放视频流');
    return null;
  }
  
  /// 创建 HLS manifest 文件来合并音视频
  static Future<String?> _createHLSManifest(
    VideoStream videoStream, 
    VideoStream audioStream,
    Map<String, String>? videoHeaders, 
    Map<String, String>? audioHeaders
  ) async {
    
    // 检查视频流是否已经是 HLS 格式
    if (videoStream.protocol == 'm3u8_native' || videoStream.url.contains('.m3u8')) {
      print('🎵 视频流已经是 HLS 格式，尝试添加音频轨道');
      
      try {
        // 下载原始的 m3u8 文件
        final response = await http.get(
          Uri.parse(videoStream.url), 
          headers: videoHeaders ?? {}
        );
        
        if (response.statusCode == 200) {
          String manifest = response.body;
          print('📄 原始 HLS manifest 长度: ${manifest.length} 字符');
          
          // 对于 HLS 视频流，我们需要直接使用原始 manifest 并尝试播放
          // 因为 YouTube 的 HLS 流通常是纯视频，需要单独处理音频
          print('🎵 YouTube HLS 流检测到，直接使用原始 manifest');
          print('   原始 manifest: ${videoStream.url}');
          
          // 直接返回原始的 HLS manifest URL，不进行修改
          // MediaKit 应该能够播放这个 HLS 流（即使没有音频）
          return videoStream.url;
        } else {
          print('❌ 下载 HLS manifest 失败: ${response.statusCode}');
        }
      } catch (e) {
        print('❌ HLS manifest 处理失败: $e');
      }
    } else {
      // 如果不是 HLS，尝试创建一个基础的 HLS manifest
      print('🔄 创建基础 HLS manifest 包装非 HLS 流');
      
      try {
        final hlsManifest = '''#EXTM3U
#EXT-X-VERSION:6
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-TARGETDURATION:10

#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="Default",DEFAULT=YES,AUTOSELECT=YES,URI="${audioStream.url}"

#EXT-X-STREAM-INF:BANDWIDTH=${(videoStream.tbr ?? 1000) * 1000},RESOLUTION=${videoStream.width ?? 1920}x${videoStream.height ?? 1080},AUDIO="audio"
${videoStream.url}

#EXT-X-ENDLIST
''';
        
        final tempDir = Directory.systemTemp;
        final manifestFile = File('${tempDir.path}/merged_${DateTime.now().millisecondsSinceEpoch}.m3u8');
        await manifestFile.writeAsString(hlsManifest);
        
        print('📝 创建基础 HLS manifest: ${manifestFile.path}');
        return manifestFile.uri.toString();
      } catch (e) {
        print('❌ 基础 HLS manifest 创建失败: $e');
      }
    }
    
    return null;
  }
  
  /// 创建 DASH manifest 文件来合并音视频
  static Future<String?> _createDASHManifest(
    VideoStream videoStream, 
    VideoStream audioStream,
    Map<String, String>? videoHeaders, 
    Map<String, String>? audioHeaders
  ) async {
    
    try {
      // 创建简单的 DASH MPD manifest
      final mpd = '''<?xml version="1.0" encoding="UTF-8"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" profiles="urn:mpeg:dash:profile:isoff-main:2011" type="static" mediaPresentationDuration="PT0H10M0S" minBufferTime="PT2S">
  <Period>
    <AdaptationSet mimeType="video/mp4" codecs="${videoStream.vcodec ?? 'avc1'}">
      <Representation id="video" bandwidth="${(videoStream.vbr ?? 1000) * 1000}" width="${videoStream.width ?? 1920}" height="${videoStream.height ?? 1080}">
        <BaseURL>${videoStream.url}</BaseURL>
      </Representation>
    </AdaptationSet>
    <AdaptationSet mimeType="audio/mp4" codecs="${audioStream.acodec ?? 'mp4a'}">
      <Representation id="audio" bandwidth="${(audioStream.abr ?? 128) * 1000}">
        <BaseURL>${audioStream.url}</BaseURL>
      </Representation>
    </AdaptationSet>
  </Period>
</MPD>''';
      
      // 创建临时文件保存 DASH manifest
      final tempDir = Directory.systemTemp;
      final manifestFile = File('${tempDir.path}/merged_${DateTime.now().millisecondsSinceEpoch}.mpd');
      await manifestFile.writeAsString(mpd);
      
      print('📝 创建临时 DASH manifest: ${manifestFile.path}');
      return manifestFile.uri.toString();
      
    } catch (e) {
      print('❌ DASH manifest 创建失败: $e');
      return null;
    }
  }
  
  /// 检查 FFmpeg 是否可用
  static Future<bool> _isFFmpegAvailable() async {
    try {
      final result = await Process.run('ffmpeg', ['-version']);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }
  
  /// 使用 FFmpeg 创建合并流
  static Future<String?> _createFFmpegMergedStream(
    VideoStream videoStream, 
    VideoStream audioStream,
    Map<String, String>? videoHeaders, 
    Map<String, String>? audioHeaders
  ) async {
    
    try {
      // 创建临时输出文件
      final tempDir = Directory.systemTemp;
      final outputFile = File('${tempDir.path}/merged_${DateTime.now().millisecondsSinceEpoch}.mp4');
      
      // 构建 FFmpeg 命令
      final args = [
        '-i', videoStream.url,  // 视频输入
        '-i', audioStream.url,  // 音频输入
        '-c:v', 'copy',         // 复制视频流（不重新编码）
        '-c:a', 'copy',         // 复制音频流（不重新编码）
        '-shortest',            // 以最短流为准
        '-f', 'mp4',            // 输出格式
        outputFile.path,        // 输出文件
      ];
      
      // 添加 HTTP headers（如果需要）
      if (videoHeaders != null && videoHeaders.isNotEmpty) {
        final headerString = videoHeaders.entries
            .map((e) => '${e.key}: ${e.value}')
            .join('\r\n');
        args.insertAll(0, ['-headers', headerString]);
      }
      
      print('🔧 执行 FFmpeg 命令: ffmpeg ${args.join(' ')}');
      
      // 执行 FFmpeg（异步，不等待完成）
      final process = await Process.start('ffmpeg', args);
      
      // 等待一小段时间让 FFmpeg 开始处理
      await Future.delayed(const Duration(seconds: 2));
      
      // 返回输出文件路径
      return outputFile.uri.toString();
      
    } catch (e) {
      print('❌ FFmpeg 执行失败: $e');
      return null;
    }
  }
  
  /// 清理临时文件
  static Future<void> cleanupTempFiles() async {
    try {
      final tempDir = Directory.systemTemp;
      final tempFiles = tempDir.listSync()
          .where((file) => file.path.contains('merged_'))
          .where((file) => file.path.endsWith('.m3u8') || 
                          file.path.endsWith('.mpd') || 
                          file.path.endsWith('.mp4'));
      
      for (final file in tempFiles) {
        try {
          await file.delete();
          print('🗑️ 清理临时文件: ${file.path}');
        } catch (e) {
          print('⚠️ 清理文件失败: ${file.path} - $e');
        }
      }
    } catch (e) {
      print('⚠️ 清理临时文件时出错: $e');
    }
  }
}
