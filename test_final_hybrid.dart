import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:http/http.dart' as http;
import 'lib/services/hybrid_video_sniffer_service.dart';

/// 最终混合服务测试
void main() async {
  print('=== 最终混合视频嗅探服务测试 ===\n');
  
  // 测试URL列表
  final testUrls = [
    'https://missav.ws/fr/abw-182-uncensored-leak',
    'https://fr.xvideos.com/video.efofpm3060/sexy_etudiante_francaise_amateur_noire_anale_dure_branchee_sur_un_bureau_a_l_ecole',
    'https://www.bilibili.com/video/BV1hdhyzrE4S',
    'https://www.youtube.com/watch?v=QTDgI8meEOo',
  ];
  
  // 测试每个URL
  for (int i = 0; i < testUrls.length; i++) {
    final url = testUrls[i];
    print('${i + 1}. 测试URL: $url');
    await testHybridService(url);
    print('');
  }
}

/// 测试混合服务
Future<void> testHybridService(String url) async {
  try {
    print('  开始提取视频信息...');
    
    // 使用混合服务提取视频信息
    final videoInfo = await HybridVideoSnifferService.extractVideoInfo(url);
    
    if (videoInfo == null) {
      print('  错误: 无法提取视频信息');
      return;
    }
    
    // 显示基本信息
    print('  标题: ${videoInfo.title}');
    print('  时长: ${videoInfo.duration != null ? '${videoInfo.duration!.inSeconds}秒' : 'Unknown'}');
    print('  封面: ${videoInfo.thumbnail ?? 'None'}');
    print('  视频URL: ${videoInfo.videoUrl ?? 'None'}');
    print('  可用流数量: ${videoInfo.streams.length}');
    
    // 分析视频流
    if (videoInfo.streams.isNotEmpty) {
      await analyzeStreams(videoInfo.streams);
    }
    
    // 获取元数据
    final metadata = await HybridVideoSnifferService.getVideoMetadata(url);
    if (metadata != null) {
      print('  元数据:');
      print('    分辨率: ${metadata.resolution ?? 'Unknown'}');
      print('    帧率: ${metadata.fps ?? 'Unknown'}fps');
    }
    
  } catch (e) {
    print('  错误: $e');
  }
}

/// 分析视频流
Future<void> analyzeStreams(List<dynamic> streams) async {
  print('  流分析:');
  
  final videoStreams = <dynamic>[];
  final audioStreams = <dynamic>[];
  final hlsStreams = <dynamic>[];
  final dashStreams = <dynamic>[];
  
  for (final stream in streams) {
    final url = stream.url ?? '';
    final protocol = stream.protocol ?? '';
    final vcodec = stream.vcodec ?? '';
    final acodec = stream.acodec ?? '';
    
    // 分类流
    if (stream.hasVideo) {
      videoStreams.add(stream);
    }
    
    if (stream.hasAudio && !stream.hasVideo) {
      audioStreams.add(stream);
    }
    
    if (stream.isHls) {
      hlsStreams.add(stream);
    }
    
    if (stream.isDash) {
      dashStreams.add(stream);
    }
  }
  
  print('    视频流: ${videoStreams.length}个');
  print('    音频流: ${audioStreams.length}个');
  print('    HLS流: ${hlsStreams.length}个');
  print('    DASH流: ${dashStreams.length}个');
  
  // 显示最佳视频流信息
  if (videoStreams.isNotEmpty) {
    videoStreams.sort((a, b) {
      final aRes = (a.width ?? 0) * (a.height ?? 0);
      final bRes = (b.width ?? 0) * (b.height ?? 0);
      return bRes.compareTo(aRes);
    });
    
    final best = videoStreams.first;
    final width = best.width;
    final height = best.height;
    final fps = best.fps;
    final tbr = best.tbr;
    final formatNote = best.formatNote ?? '';
    final protocol = best.protocol ?? '';
    
    print('    最佳视频流:');
    print('      分辨率: ${width}x$height');
    print('      帧率: ${fps ?? 'Unknown'}fps');
    print('      比特率: ${tbr != null ? '${(tbr / 1024).toStringAsFixed(1)}kbps' : 'Unknown'}');
    print('      格式: $formatNote');
    print('      协议: $protocol');
  }
  
  // 显示HLS流信息
  if (hlsStreams.isNotEmpty) {
    print('    HLS流可用: 是');
  }
}
