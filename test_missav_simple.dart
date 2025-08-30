import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart' as html_parser;

void main() async {
  print('=== MissAV 简单测试 ===');
  
  final url = 'https://missav.ws/fr/abw-182-uncensored-leak';
  
  print('测试URL: $url');
  
  try {
    // 使用Python cloudscraper获取页面
    final result = await Process.run('python', [
      '-c', '''
import cloudscraper
import json

try:
    scraper = cloudscraper.create_scraper()
    response = scraper.get("$url")
    
    if response.status_code == 200:
        # 返回JSON格式的结果
        result = {
            "success": True,
            "content": response.text,
            "status_code": response.status_code
        }
        print(json.dumps(result, ensure_ascii=False))
    else:
        result = {
            "success": False,
            "error": f"HTTP {response.status_code}",
            "status_code": response.status_code
        }
        print(json.dumps(result, ensure_ascii=False))
        
except Exception as e:
    result = {
        "success": False,
        "error": str(e)
    }
    print(json.dumps(result, ensure_ascii=False))
''',
    ]);
    
    if (result.exitCode == 0) {
      final output = result.stdout.toString().trim();
      
      try {
        final jsonResult = json.decode(output);
        
        if (jsonResult['success'] == true) {
          final content = jsonResult['content'];
          print('页面获取成功，长度: ${content.length} 字符');
          
          // 分析页面内容
          await analyzeContent(content, url);
        } else {
          print('页面获取失败: ${jsonResult['error']}');
        }
      } catch (e) {
        print('JSON解析失败: $e');
        print('原始输出: $output');
      }
    } else {
      print('Python脚本执行失败: ${result.stderr}');
    }
    
  } catch (e) {
    print('测试失败: $e');
  }
}

Future<void> analyzeContent(String content, String baseUrl) async {
  final document = html_parser.parse(content);
  
  // 1. 查找所有包含视频相关关键词的script
  print('\n=== 视频相关Script分析 ===');
  final scripts = document.querySelectorAll('script');
  print('找到 ${scripts.length} 个script标签');
  
  for (int i = 0; i < scripts.length; i++) {
    final script = scripts[i];
    final scriptContent = script.text;
    
    // 查找包含视频相关关键词的script
    final keywords = ['video', 'player', 'm3u8', 'mp4', 'stream', 'source', 'hls'];
    final foundKeywords = keywords.where((keyword) => scriptContent.toLowerCase().contains(keyword)).toList();
    
    if (foundKeywords.isNotEmpty) {
      print('\nScript ${i + 1} 包含关键词: ${foundKeywords.join(', ')}');
      
      // 查找可能的视频URL
      final videoPatterns = [
        RegExp(r'"([^"]*\.m3u8[^"]*)"'),
        RegExp(r"'([^']*\.m3u8[^']*)'"),
        RegExp(r'"([^"]*\.mp4[^"]*)"'),
        RegExp(r"'([^']*\.mp4[^']*)'"),
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
      
      // 显示script内容的前200个字符
      if (scriptContent.length > 200) {
        print('  内容预览: ${scriptContent.substring(0, 200)}...');
      } else {
        print('  内容: $scriptContent');
      }
    }
  }
  
  // 2. 全局搜索m3u8和mp4文件
  print('\n=== 全局视频文件搜索 ===');
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
  
  // 3. 查找JSON数据中的视频信息
  print('\n=== JSON数据搜索 ===');
  final jsonPatterns = [
    RegExp(r'\{[^{}]*"url"[^{}]*"([^"]*\.m3u8[^"]*)"[^{}]*\}'),
    RegExp(r'\{[^{}]*"src"[^{}]*"([^"]*\.m3u8[^"]*)"[^{}]*\}'),
    RegExp(r'\{[^{}]*"source"[^{}]*"([^"]*\.m3u8[^"]*)"[^{}]*\}'),
  ];
  
  for (final pattern in jsonPatterns) {
    final matches = pattern.allMatches(content);
    for (final match in matches) {
      final url = match.group(1);
      if (url != null && url.length > 10) {
        print('JSON中找到URL: $url');
      }
    }
  }
}
