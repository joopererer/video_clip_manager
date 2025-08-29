import 'dart:io';
import 'package:video_clip_manager/services/platform_support.dart';
import 'package:video_clip_manager/services/external_scraper_service.dart';

void main() async {
  print('=== MissAV Cloudscraper 集成测试 ===');
  
  final url = 'https://missav.ws/fr/abw-126-uncensored-leak';
  
  // 测试1: 直接测试 ExternalScraperService
  print('\n1. 测试 ExternalScraperService.getMissavPageContent:');
  final result = await ExternalScraperService.getMissavPageContent(url);
  if (result != null) {
    print('✅ 成功获取页面内容');
    print('状态码: ${result['status_code']}');
    print('内容长度: ${result['content_length']}');
    print('提取的标题: ${result['title']}');
  } else {
    print('❌ 获取页面内容失败');
  }
  
  // 测试2: 测试 MissAVSupport 的标题提取
  print('\n2. 测试 MissAVSupport 标题提取:');
  final missavSupport = MissAVSupport();
  final title = await missavSupport._fetchMissavTitle(url);
  if (title != null) {
    print('✅ 成功提取标题: $title');
  } else {
    print('❌ 标题提取失败');
  }
  
  // 测试3: 测试完整的视频信息提取
  print('\n3. 测试完整的视频信息提取:');
  try {
    final videoInfo = await missavSupport.extractVideoInfo(url);
    print('✅ 成功提取视频信息:');
    print('  ID: ${videoInfo.id}');
    print('  标题: ${videoInfo.title}');
    print('  缩略图: ${videoInfo.thumbnailUrl}');
    print('  平台: ${videoInfo.platform}');
    print('  元数据: ${videoInfo.metadata}');
  } catch (e) {
    print('❌ 视频信息提取失败: $e');
  }
}
