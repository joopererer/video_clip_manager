import 'dart:io';
import 'package:video_clip_manager/services/video_sniffer_service.dart';

void main() async {
  print('开始测试视频嗅探功能...\n');

  // 测试URL列表
  final testUrls = [
    'https://missav.ws/fr/abw-182-uncensored-leak',
    'https://www.xvideos.com/video123456/test_video',
    'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    'https://www.bilibili.com/video/BV1xx411c7mu',
  ];

  for (final url in testUrls) {
    print('测试URL: $url');
    print('-' * 50);
    
    try {
      final videos = await VideoSnifferService.sniffVideoUrls(url);
      
      if (videos.isEmpty) {
        print('❌ 未找到视频链接');
      } else {
        print('✅ 找到 ${videos.length} 个视频链接:');
        for (int i = 0; i < videos.length; i++) {
          final video = videos[i];
          print('  ${i + 1}. ${video.title}');
          print('     类型: ${video.type}');
          print('     链接: ${video.url}');
          if (video.width != null && video.height != null) {
            print('     分辨率: ${video.width}x${video.height}');
          }
          if (video.mimeType != null) {
            print('     MIME: ${video.mimeType}');
          }
          print('');
        }
      }
    } catch (e) {
      print('❌ 嗅探失败: $e');
    }
    
    print('=' * 60);
    print('');
  }

  print('测试完成！');
}


