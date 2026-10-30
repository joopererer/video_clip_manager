import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  print('=== MissAV 测试 ===');
  
  final url = 'https://missav.ws/fr/abw-182-uncensored-leak';
  
  print('测试URL: $url');
  
  // 首先尝试 yt-dlp
  print('\n1. 尝试使用 yt-dlp...');
  try {
    final result = await Process.run('yt-dlp', [
      '--dump-json',
      '--no-playlist',
      '--no-warnings',
      '--extractor-args', 'generic:impersonate',
      '--user-agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
      url,
    ]);
    
    if (result.exitCode == 0) {
      print('yt-dlp 成功提取');
      final jsonData = json.decode(result.stdout.toString().trim());
      final title = jsonData['title'] ?? 'Unknown Title';
      print('标题: $title');
    } else {
      print('yt-dlp 失败: ${result.stderr}');
    }
  } catch (e) {
    print('yt-dlp 错误: $e');
  }
  
  // 然后尝试自定义方法
  print('\n2. 尝试使用自定义方法...');
  try {
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
      print('自定义请求成功，状态码: ${response.statusCode}');
      print('响应长度: ${response.body.length} 字符');
      
      // 简单检查是否包含视频相关信息
      final body = response.body.toLowerCase();
      if (body.contains('video') || body.contains('player') || body.contains('source')) {
        print('检测到可能的视频内容');
      }
      
      // 尝试提取标题
      final titleMatch = RegExp(r'<title[^>]*>([^<]+)</title>', caseSensitive: false).firstMatch(response.body);
      if (titleMatch != null) {
        print('页面标题: ${titleMatch.group(1)}');
      }
      
    } else {
      print('自定义请求失败，状态码: ${response.statusCode}');
    }
    
  } catch (e) {
    print('自定义方法错误: $e');
  }
}
