import 'dart:io';
import 'dart:convert';

void main() async {
  print('=== 简单 MissAV 测试 ===');
  
  final url = 'https://missav.ws/fr/abw-126-uncensored-leak';
  
  // 直接测试 Python 脚本
  await testSimplePython(url);
}

Future<void> testSimplePython(String url) async {
  try {
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
            
            result = {
                'success': True,
                'status_code': response.status_code,
                'content_length': len(content),
                'title': extracted_title
            }
            
            return result
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
    json_output = json.dumps(result, ensure_ascii=False)
    print(json_output)
''';

    final tempDir = await Directory.systemTemp.createTemp('simple_test_');
    final scriptFile = File('${tempDir.path}/simple_script.py');
    await scriptFile.writeAsString(scriptContent);
    
    try {
      print('执行 Python 脚本...');
      final result = await Process.run('python', [scriptFile.path, url], 
        environment: {'PYTHONIOENCODING': 'utf-8'});
      
      print('Python 退出码: ${result.exitCode}');
      
      if (result.exitCode == 0) {
        final output = result.stdout.toString().trim();
        print('Python 输出长度: ${output.length}');
        
        if (output.isNotEmpty) {
          try {
            final data = json.decode(output) as Map<String, dynamic>;
            print('✅ JSON 解析成功');
            print('  成功: ${data['success']}');
            print('  状态码: ${data['status_code']}');
            print('  内容长度: ${data['content_length']}');
            print('  标题: ${data['title']}');
            print('  标题长度: ${data['title']?.length ?? 0}');
          } catch (e) {
            print('❌ JSON 解析失败: $e');
            print('输出前100字符: ${output.substring(0, output.length > 100 ? 100 : output.length)}');
          }
        } else {
          print('❌ Python 脚本返回空输出');
        }
      } else {
        print('❌ Python 脚本执行失败: ${result.stderr}');
      }
    } finally {
      await tempDir.delete(recursive: true);
    }
  } catch (e) {
    print('❌ 测试错误: $e');
  }
}
