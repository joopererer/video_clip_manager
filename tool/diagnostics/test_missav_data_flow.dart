import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  print('=== 测试 MissAV 完整数据流 ===');
  
  await testMissAVDataFlow();
}

Future<void> testMissAVDataFlow() async {
  try {
    final url = 'https://missav.ws/fr/abw-182-uncensored-leak';
    print('测试URL: $url');
    
    // 1. 提取番号
    final code = extractCodeFromUrl(url);
    print('提取的番号: $code');
    
    if (code != null) {
      // 2. 测试 javscraper
      print('\n=== 测试 javscraper ===');
      final javInfo = await testJavScraper(code);
      
      if (javInfo != null) {
        print('javscraper 返回数据:');
        print(json.encode(javInfo));
        
        // 3. 测试数据解析
        print('\n=== 测试数据解析 ===');
        final title = javInfo['title'] ?? 'Unknown Title';
        final thumbnailUrl = javInfo['poster'] ?? javInfo['thumbnail'];
        
        print('解析的标题: $title');
        print('解析的封面: $thumbnailUrl');
        
        // 4. 测试第三方数据库回退
        if (title == 'Unknown Title' || thumbnailUrl == null) {
          print('\n=== 测试第三方数据库回退 ===');
          final fallbackThumbnail = await testThirdPartyDatabase(code);
          print('第三方数据库封面: $fallbackThumbnail');
        }
      } else {
        print('javscraper 失败，测试第三方数据库...');
        final fallbackThumbnail = await testThirdPartyDatabase(code);
        print('第三方数据库封面: $fallbackThumbnail');
      }
    }
  } catch (e) {
    print('❌ 测试异常: $e');
  }
}

String? extractCodeFromUrl(String url) {
  final codeMatch = RegExp(r'([A-Z]{2,4}-\d{2,4})', caseSensitive: false).firstMatch(url);
  return codeMatch?.group(1)?.toUpperCase();
}

Future<Map<String, dynamic>?> testJavScraper(String code) async {
  try {
    final scriptLines = [
      'import sys',
      'import json',
      'import os',
      '',
      '# 设置UTF-8编码',
      'os.environ["PYTHONIOENCODING"] = "utf-8"',
      '',
      'def main():',
      '    try:',
      '        from javscraper import JAVLibrary',
      '        scraper = JAVLibrary()',
      '        ',
      '        if len(sys.argv) > 1:',
      '            code = sys.argv[1]',
      '            print("Searching for code: " + code)',
      '            ',
      '            info = scraper.search(code)',
      '            print("Raw data: " + str(info))',
      '            ',
      '            if info and isinstance(info, list) and len(info) > 0:',
      '                first_item = info[0]',
      '                if isinstance(first_item, dict):',
      '                    title = first_item.get("title", "")',
      '                    poster = first_item.get("poster", "")',
      '                    thumbnail = first_item.get("thumbnail", "")',
      '                    cover = first_item.get("cover", "")',
      '                    image = first_item.get("image", "")',
      '                    ',
      '                    result = {',
      '                        "source": "JAVLibrary",',
      '                        "title": title,',
      '                        "poster": poster or thumbnail or cover or image,',
      '                        "thumbnail": poster or thumbnail or cover or image,',
      '                        "data": info',
      '                    }',
      '                    print(json.dumps(result, ensure_ascii=False))',
      '                    return',
      '            ',
      '            print(\'{"error": "No valid data found"}\')',
      '        else:',
      '            print(\'{"error": "No code provided"}\')',
      '            ',
      '    except Exception as e:',
      '        error_msg = "General error: " + str(e)',
      '        print(\'{"error": "\' + error_msg + \'"}\')',
      '',
      'if __name__ == "__main__":',
      '    main()',
    ];
    
    final pythonScript = scriptLines.join('\n');
    
    final tempDir = await Directory.systemTemp.createTemp('javscraper_test_');
    final scriptFile = File('${tempDir.path}/javscraper_test.py');
    await scriptFile.writeAsString(pythonScript);
    
    try {
      final result = await Process.run('python', [scriptFile.path, code], 
        environment: {'PYTHONIOENCODING': 'utf-8'});
      
      if (result.exitCode == 0 && result.stdout.toString().isNotEmpty) {
        final jsonData = json.decode(result.stdout.toString());
        if (jsonData.containsKey('error')) {
          print('❌ javscraper 错误: ${jsonData['error']}');
          return null;
        }
        print('✅ javscraper 成功');
        return jsonData;
      } else {
        print('❌ javscraper 执行失败: ${result.stderr}');
        return null;
      }
    } finally {
      await tempDir.delete(recursive: true);
    }
  } catch (e) {
    print('❌ javscraper 异常: $e');
    return null;
  }
}

Future<String?> testThirdPartyDatabase(String code) async {
  try {
    // 测试 JavBus
    final url = 'https://www.javbus.com/search/$code';
    print('测试 JavBus: $url');
    
    // 使用 dart:io HttpClient 避免头部问题
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      // 不设置任何headers，避免malformed headers问题
      
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      
            if (response.statusCode == 200) {
        final html = responseBody;
        print('JavBus 响应长度: ${html.length}');
        
        // 检查是否包含搜索结果
        if (html.contains('movie-box')) {
          print('✅ JavBus 找到搜索结果');
          
          // 尝试多种封面提取模式
          final patterns = [
            RegExp(r'<img[^>]*class="[^"]*img-responsive[^"]*"[^>]*src="([^"]+)"'),
            RegExp(r'<img[^>]*src="([^"]*\.jpg[^"]*)"'),
            RegExp(r'<img[^>]*src="([^"]*\.png[^"]*)"'),
            RegExp(r'<img[^>]*data-src="([^"]+)"'),
          ];
          
          for (int i = 0; i < patterns.length; i++) {
            final pattern = patterns[i];
            final coverMatch = pattern.firstMatch(html);
            if (coverMatch != null) {
              final coverUrl = coverMatch.group(1)!;
              print('✅ JavBus 找到封面 (模式$i): $coverUrl');
              return coverUrl;
            }
          }
          
          print('❌ JavBus 未找到封面图片');
        } else {
          print('❌ JavBus 未找到搜索结果');
          print('页面内容片段: ${html.substring(0, html.length > 500 ? 500 : html.length)}...');
        }
      } else {
        print('❌ JavBus HTTP状态码: ${response.statusCode}');
      }
    } finally {
      client.close();
    }
    
    print('❌ JavBus 未找到封面');
    return null;
  } catch (e) {
    print('❌ 第三方数据库异常: $e');
    return null;
  }
}
