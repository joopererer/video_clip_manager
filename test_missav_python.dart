import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart' as html_parser;

void main() async {
  print('=== MissAV Python 脚本分析 ===');
  
  final url = 'https://missav.ws/fr/abw-182-uncensored-leak';
  
  print('分析URL: $url');
  
  try {
    // 使用Python脚本获取页面内容
    final result = await Process.run('python', [
      '-c', '''
import cloudscraper
import sys
import re

try:
    scraper = cloudscraper.create_scraper()
    response = scraper.get("$url")
    
    if response.status_code == 200:
        content = response.text
        print("SUCCESS_START")
        # 使用UTF-8编码输出
        sys.stdout.buffer.write(content.encode('utf-8'))
        print("SUCCESS_END")
    else:
        print(f"ERROR: HTTP {response.status_code}")
        
except Exception as e:
    print(f"ERROR: {str(e)}")
''',
    ]);
    
    if (result.exitCode == 0) {
      final output = result.stdout.toString();
      
      // 提取页面内容
      final successStart = output.indexOf('SUCCESS_START');
      final successEnd = output.indexOf('SUCCESS_END');
      
      if (successStart != -1 && successEnd != -1) {
        final content = output.substring(successStart + 13, successEnd).trim();
        print('页面获取成功，长度: ${content.length} 字符');
        
        // 分析页面内容
        await analyzeContent(content, url);
      } else {
        print('Python脚本输出: $output');
      }
    } else {
      print('Python脚本执行失败: ${result.stderr}');
    }
    
  } catch (e) {
    print('分析失败: $e');
  }
}

Future<void> analyzeContent(String content, String baseUrl) async {
  final document = html_parser.parse(content);
  
  // 1. 分析所有script标签
  print('\n=== Script 标签分析 ===');
  final scripts = document.querySelectorAll('script');
  print('找到 ${scripts.length} 个script标签');
  
  for (int i = 0; i < scripts.length; i++) {
    final script = scripts[i];
    final scriptContent = script.text;
    final src = script.attributes['src'];
    
    print('\nScript ${i + 1}:');
    if (src != null) {
      print('  src: $src');
    }
    print('  内容长度: ${scriptContent.length} 字符');
    
    // 查找包含视频相关关键词的script
    final keywords = ['video', 'player', 'm3u8', 'mp4', 'stream', 'source', 'hls'];
    final foundKeywords = keywords.where((keyword) => scriptContent.toLowerCase().contains(keyword)).toList();
    
    if (foundKeywords.isNotEmpty) {
      print('  包含关键词: ${foundKeywords.join(', ')}');
      
      // 查找可能的视频URL
      final videoPatterns = [
        RegExp(r'"([^"]*\.m3u8[^"]*)"'),
        RegExp(r"'([^']*\.m3u8[^']*)'"),
        RegExp(r'"([^"]*\.mp4[^"]*)"'),
        RegExp(r"'([^']*\.mp4[^']*)'"),
        RegExp(r'"([^"]*video[^"]*)"'),
        RegExp(r"'([^']*video[^']*)'"),
        RegExp(r'"([^"]*player[^"]*)"'),
        RegExp(r"'([^']*player[^']*)'"),
        // 查找JSON中的视频URL
        RegExp(r'"url"\s*:\s*"([^"]*\.m3u8[^"]*)"'),
        RegExp(r'"src"\s*:\s*"([^"]*\.m3u8[^"]*)"'),
        RegExp(r'"source"\s*:\s*"([^"]*\.m3u8[^"]*)"'),
      ];
      
      for (final pattern in videoPatterns) {
        final matches = pattern.allMatches(scriptContent);
        for (final match in matches) {
          final url = match.group(1);
          if (url != null && url.length > 10) {
            print('    找到URL: $url');
          }
        }
      }
      
      // 如果内容很长，显示前500个字符
      if (scriptContent.length > 500) {
        print('  内容预览: ${scriptContent.substring(0, 500)}...');
      }
    }
  }
  
  // 2. 分析所有iframe标签
  print('\n=== Iframe 标签分析 ===');
  final iframes = document.querySelectorAll('iframe');
  print('找到 ${iframes.length} 个iframe标签');
  
  for (int i = 0; i < iframes.length; i++) {
    final iframe = iframes[i];
    final src = iframe.attributes['src'];
    final dataSrc = iframe.attributes['data-src'];
    
    print('\nIframe ${i + 1}:');
    if (src != null) {
      print('  src: $src');
    }
    if (dataSrc != null) {
      print('  data-src: $dataSrc');
    }
  }
  
  // 3. 分析所有video标签
  print('\n=== Video 标签分析 ===');
  final videos = document.querySelectorAll('video');
  print('找到 ${videos.length} 个video标签');
  
  for (int i = 0; i < videos.length; i++) {
    final video = videos[i];
    final src = video.attributes['src'];
    final poster = video.attributes['poster'];
    
    print('\nVideo ${i + 1}:');
    if (src != null) {
      print('  src: $src');
    }
    if (poster != null) {
      print('  poster: $poster');
    }
    
    // 查找source标签
    final sources = video.querySelectorAll('source');
    for (int j = 0; j < sources.length; j++) {
      final source = sources[j];
      final sourceSrc = source.attributes['src'];
      final sourceType = source.attributes['type'];
      
      print('  source ${j + 1}:');
      if (sourceSrc != null) {
        print('    src: $sourceSrc');
      }
      if (sourceType != null) {
        print('    type: $sourceType');
      }
    }
  }
  
  // 4. 查找所有可能的视频URL
  print('\n=== 全局视频URL搜索 ===');
  final globalPatterns = [
    RegExp(r'https?://[^"\s]+\.m3u8[^"\s]*'),
    RegExp(r'https?://[^"\s]+\.mp4[^"\s]*'),
  ];
  
  for (final pattern in globalPatterns) {
    final matches = pattern.allMatches(content);
    for (final match in matches) {
      final url = match.group(0);
      if (url != null && url.length > 20) {
        print('找到URL: $url');
      }
    }
  }
}
