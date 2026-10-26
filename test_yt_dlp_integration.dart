import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:http/http.dart' as http;

/// 测试 yt-dlp 对不同视频网站的支持
void main() async {
  print('=== YT-DLP 集成测试 ===\n');
  
  // 测试URL列表
  final testUrls = [
    'https://missav.ws/fr/abw-182-uncensored-leak',
    'https://fr.xvideos.com/video.efofpm3060/sexy_etudiante_francaise_amateur_noire_anale_dure_branchee_sur_un_bureau_a_l_ecole',
    'https://www.bilibili.com/video/BV1hdhyzrE4S',
    'https://www.youtube.com/watch?v=QTDgI8meEOo',
  ];
  
  // 检查 yt-dlp 是否可用
  print('1. 检查 yt-dlp 是否可用...');
  final isAvailable = await checkYtDlpAvailability();
  print('yt-dlp 可用: $isAvailable\n');
  
  if (!isAvailable) {
    print('错误: yt-dlp 不可用，请先安装 yt-dlp');
    return;
  }
  
  // 测试每个URL
  for (int i = 0; i < testUrls.length; i++) {
    final url = testUrls[i];
    print('${i + 2}. 测试URL: $url');
    await testUrl(url);
    print('');
  }
}

/// 检查 yt-dlp 是否可用
Future<bool> checkYtDlpAvailability() async {
  try {
    final result = await Process.run('yt-dlp', ['--version']);
    if (result.exitCode == 0) {
      print('yt-dlp 版本: ${result.stdout.toString().trim()}');
      return true;
    }
  } catch (e) {
    print('yt-dlp 检查失败: $e');
  }
  return false;
}

/// 测试单个URL
Future<void> testUrl(String url) async {
  try {
    print('  开始提取视频信息...');
    
    List<String> args = [
      '--dump-json',
      '--no-playlist',
      '--no-warnings',
    ];
    
    // 根据网站类型添加特殊参数
    if (url.contains('missav')) {
      print('  检测到MissAV网站，使用特殊参数...');
      args.addAll([
        '--extractor-args', 'generic:impersonate',
        '--user-agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
      ]);
    } else if (url.contains('xvideos')) {
      print('  检测到XVideos网站，使用XVideos提取器...');
      // XVideos有专门的提取器，不需要特殊参数
    }
    
    args.add(url);
    
    // 使用 yt-dlp 获取视频信息
    final result = await Process.run('yt-dlp', args);
    
    if (result.exitCode != 0) {
      print('  错误: yt-dlp 执行失败');
      print('  错误信息: ${result.stderr}');
      
      // 如果是MissAV，尝试使用自定义方法
      if (url.contains('missav')) {
        print('  尝试使用自定义MissAV处理方法...');
        await testMissavCustom(url);
      }
      return;
    }
    
    // 解析JSON输出
    final jsonData = json.decode(result.stdout.toString().trim());
    
    // 提取基本信息
    final title = jsonData['title'] ?? 'Unknown Title';
    final duration = jsonData['duration'];
    final thumbnail = jsonData['thumbnail'];
    final formats = jsonData['formats'] as List?;
    
    print('  标题: $title');
    print('  时长: ${duration != null ? '${duration}秒' : 'Unknown'}');
    print('  封面: ${thumbnail ?? 'None'}');
    print('  可用格式数量: ${formats?.length ?? 0}');
    
    // 分析视频格式
    if (formats != null && formats.isNotEmpty) {
      await analyzeFormats(formats);
    }
    
  } catch (e) {
    print('  错误: $e');
  }
}

/// 测试MissAV自定义处理方法
Future<void> testMissavCustom(String url) async {
  try {
    print('  使用自定义MissAV处理方法...');
    
    // 这里可以集成之前的VideoSnifferService
    // 暂时先测试基本的HTTP请求
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
        'Accept-Encoding': 'gzip, deflate',
        'Connection': 'keep-alive',
        'Upgrade-Insecure-Requests': '1',
      },
    );
    
    if (response.statusCode == 200) {
      print('  自定义请求成功，状态码: ${response.statusCode}');
      print('  响应长度: ${response.body.length} 字符');
      
      // 简单检查是否包含视频相关信息
      final body = response.body.toLowerCase();
      if (body.contains('video') || body.contains('player') || body.contains('source')) {
        print('  检测到可能的视频内容');
      }
    } else {
      print('  自定义请求失败，状态码: ${response.statusCode}');
    }
    
  } catch (e) {
    print('  自定义处理错误: $e');
  }
}

/// 分析视频格式
Future<void> analyzeFormats(List formats) async {
  print('  格式分析:');
  
  final videoStreams = <Map<String, dynamic>>[];
  final audioStreams = <Map<String, dynamic>>[];
  final hlsStreams = <Map<String, dynamic>>[];
  final dashStreams = <Map<String, dynamic>>[];
  
  for (final format in formats) {
    final url = format['url'] ?? '';
    final protocol = format['protocol'] ?? '';
    final vcodec = format['vcodec'] ?? '';
    final acodec = format['acodec'] ?? '';
    final width = format['width'];
    final height = format['height'];
    final fps = format['fps'];
    final tbr = format['tbr'];
    final formatNote = format['format_note'] ?? '';
    
    // 分类格式
    if (vcodec != 'none' && vcodec.isNotEmpty) {
      videoStreams.add(format);
    }
    
    if (acodec != 'none' && acodec.isNotEmpty && vcodec == 'none') {
      audioStreams.add(format);
    }
    
    if (protocol == 'm3u8_native' || url.contains('.m3u8')) {
      hlsStreams.add(format);
    }
    
    if (protocol == 'http_dash_segments' || url.contains('.mpd')) {
      dashStreams.add(format);
    }
  }
  
  print('    视频流: ${videoStreams.length}个');
  print('    音频流: ${audioStreams.length}个');
  print('    HLS流: ${hlsStreams.length}个');
  print('    DASH流: ${dashStreams.length}个');
  
  // 显示最佳视频流信息
  if (videoStreams.isNotEmpty) {
    videoStreams.sort((a, b) {
      final aRes = (a['width'] ?? 0) * (a['height'] ?? 0);
      final bRes = (b['width'] ?? 0) * (b['height'] ?? 0);
      return bRes.compareTo(aRes);
    });
    
    final best = videoStreams.first;
    final width = best['width'];
    final height = best['height'];
    final fps = best['fps'];
    final tbr = best['tbr'];
    final formatNote = best['format_note'] ?? '';
    final protocol = best['protocol'] ?? '';
    
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
