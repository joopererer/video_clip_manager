import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  print('=== 测试自定义 JavLibrary ===');
  
  await testCustomJavLibrary();
}

Future<void> testCustomJavLibrary() async {
  try {
    final code = 'ABW-182';
    print('搜索番号: $code');
    
    // 测试我们的自定义 JavLibrary 实现
    final url = 'https://www.javlibrary.com/cn/vl_searchbyid.php?keyword=$code';
    print('请求URL: $url');
    
    final client = http.Client();
    try {
      final response = await client.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
          'Accept-Language': 'en-US,en;q=0.9',
          'Accept-Encoding': 'gzip, deflate, br',
          'Connection': 'keep-alive',
          'Upgrade-Insecure-Requests': '1',
          'Sec-Fetch-Dest': 'document',
          'Sec-Fetch-Mode': 'navigate',
          'Sec-Fetch-Site': 'cross-site',
          'Sec-Fetch-User': '?1',
          'Cache-Control': 'max-age=0',
          'Sec-Ch-Ua': '"Google Chrome";v="119", "Chromium";v="119", "Not?A_Brand";v="24"',
          'Sec-Ch-Ua-Mobile': '?0',
          'Sec-Ch-Ua-Platform': '"Windows"',
          'DNT': '1',
          'Referer': 'https://www.google.com/search?q=javlibrary',
          'Origin': 'https://www.google.com',
        },
      );
      
      print('状态码: ${response.statusCode}');
      print('响应长度: ${response.body.length}');
      
      if (response.statusCode == 200) {
        final html = response.body;
        
        // 检查是否包含搜索结果
        if (html.contains('video_title') || html.contains('video_title_tr')) {
          print('✅ 找到搜索结果');
          
          // 提取标题
          final titleMatch = RegExp(r'<div class="video_title"[^>]*>([^<]+)</div>').firstMatch(html);
          final titleTrMatch = RegExp(r'<div class="video_title_tr"[^>]*>([^<]+)</div>').firstMatch(html);
          
          final title = titleMatch?.group(1)?.trim() ?? titleTrMatch?.group(1)?.trim() ?? 'Unknown Title';
          print('标题: $title');
          
          // 提取封面
          final coverMatch = RegExp(r'<img[^>]*id="video_jacket_img"[^>]*src="([^"]+)"').firstMatch(html);
          if (coverMatch != null) {
            final coverUrl = coverMatch.group(1)!;
            print('封面URL: $coverUrl');
          } else {
            print('❌ 未找到封面');
          }
        } else {
          print('❌ 未找到搜索结果');
          print('页面内容片段: ${html.substring(0, html.length > 500 ? 500 : html.length)}...');
        }
      } else {
        print('❌ HTTP请求失败');
      }
    } finally {
      client.close();
    }
  } catch (e) {
    print('❌ 测试异常: $e');
  }
}
