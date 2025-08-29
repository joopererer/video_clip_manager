import 'dart:io';
import 'dart:convert';

void main() async {
  print('=== 简单 Cloudscraper 测试 ===');
  
  final url = 'https://missav.ws/fr/abw-126-uncensored-leak';
  
  // 直接调用 Python 脚本
  await testCloudscraperDirect(url);
}

Future<void> testCloudscraperDirect(String url) async {
  try {
    print('正在测试 cloudscraper 直接调用...');
    
    // 创建临时 Python 脚本
    final scriptContent = '''
import sys
import json
import cloudscraper

def get_missav_content(url):
    try:
        scraper = cloudscraper.create_scraper(
            browser={
                'browser': 'chrome',
                'platform': 'windows',
                'desktop': True
            }
        )
        
        response = scraper.get(url)
        
        if response.status_code == 200:
            content = response.text
            
            # 尝试提取标题
            import re
            title_patterns = [
                r'<meta[^>]*property="og:title"[^>]*content="([^"]+)"',
                r'<meta[^>]*name="twitter:title"[^>]*content="([^"]+)"',
                r'<h1[^>]*class="[^"]*title[^"]*"[^>]*>([^<]+)</h1>',
                r'<h1[^>]*>([^<]+)</h1>',
                r'<title[^>]*>([^<]+)</title>',
            ]
            
            extracted_title = None
            for pattern in title_patterns:
                match = re.search(pattern, content, re.IGNORECASE)
                if match:
                    title = match.group(1).strip()
                    if title:
                        extracted_title = title
                        break
            
            return {
                'success': True,
                'status_code': response.status_code,
                'content': content,
                'content_length': len(content),
                'title': extracted_title
            }
        else:
            return {
                'success': False,
                'status_code': response.status_code,
                'error': response.text[:500]
            }
            
    except Exception as e:
        return {
            'success': False,
            'error': str(e)
        }

if __name__ == "__main__":
    url = sys.argv[1] if len(sys.argv) > 1 else ""
    result = get_missav_content(url)
    print(json.dumps(result, ensure_ascii=False))
''';

    // 创建临时文件
    final tempDir = await Directory.systemTemp.createTemp('cloudscraper_test_');
    final scriptFile = File('${tempDir.path}/cloudscraper_test.py');
    await scriptFile.writeAsString(scriptContent);
    
    try {
      print('执行 Python 脚本...');
      final result = await Process.run('python', [scriptFile.path, url], 
        environment: {'PYTHONIOENCODING': 'utf-8'});
      
      if (result.exitCode == 0) {
        final output = result.stdout.toString().trim();
        print('Python 脚本输出: $output');
        
        if (output.isNotEmpty) {
          try {
            final data = json.decode(output) as Map<String, dynamic>;
            
            if (data['success'] == true) {
              print('✅ Cloudscraper 成功!');
              print('状态码: ${data['status_code']}');
              print('内容长度: ${data['content_length']}');
              print('提取的标题: ${data['title']}');
            } else {
              print('❌ Cloudscraper 失败: ${data['error']}');
            }
          } catch (e) {
            print('❌ JSON 解析失败: $e');
            print('原始输出: $output');
          }
        } else {
          print('❌ Python 脚本返回空输出');
        }
      } else {
        print('❌ Python 脚本执行失败: ${result.stderr}');
      }
    } finally {
      // 清理临时文件
      await tempDir.delete(recursive: true);
    }
  } catch (e) {
    print('❌ 测试错误: $e');
  }
}
