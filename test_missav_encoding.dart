import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  print('Testing MissAV encoding and thumbnail issues...');
  
  final url = 'https://missav.ws/fr/abw-182-uncensored-leak';
  final code = 'ABW-182';
  
  // 测试1: 直接HTTP请求
  print('\n=== Test 1: Direct HTTP Request ===');
  try {
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language': 'fr-FR,fr;q=0.9,en;q=0.8',
        'Accept-Encoding': 'gzip, deflate',
        'Connection': 'keep-alive',
        'Upgrade-Insecure-Requests': '1',
      },
    );
    
    print('Status: ${response.statusCode}');
    print('Content-Type: ${response.headers['content-type']}');
    
    // 尝试不同编码方式
    final content1 = utf8.decode(response.bodyBytes, allowMalformed: true);
    final content2 = response.body;
    
    print('Content length (utf8.decode): ${content1.length}');
    print('Content length (response.body): ${content2.length}');
    
    // 提取标题
    final titleMatch1 = RegExp(r'<title[^>]*>([^<]+)</title>').firstMatch(content1);
    final titleMatch2 = RegExp(r'<title[^>]*>([^<]+)</title>').firstMatch(content2);
    
    print('Title (utf8.decode): ${titleMatch1?.group(1)?.trim()}');
    print('Title (response.body): ${titleMatch2?.group(1)?.trim()}');
    
  } catch (e) {
    print('HTTP request failed: $e');
  }
  
  // 测试2: Python cloudscraper
  print('\n=== Test 2: Python Cloudscraper ===');
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
            
            return {
                'success': True,
                'status_code': response.status_code,
                'content_length': len(content),
                'title': extracted_title,
                'encoding': response.encoding
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

    final scriptFile = File('test_cloudscraper.py');
    await scriptFile.writeAsString(scriptContent);
    
    final result = await Process.run('python', [scriptFile.path, url], 
      environment: {'PYTHONIOENCODING': 'utf-8'});
    
    if (result.exitCode == 0) {
      final output = result.stdout.toString().trim();
      print('Python output: $output');
      
      try {
        final data = json.decode(output) as Map<String, dynamic>;
        print('Parsed data: $data');
        print('Title: ${data['title']}');
        print('Encoding: ${data['encoding']}');
      } catch (e) {
        print('JSON parse error: $e');
      }
    } else {
      print('Python script failed: ${result.stderr}');
    }
    
    await scriptFile.delete();
    
  } catch (e) {
    print('Python test failed: $e');
  }
  
  // 测试3: 第三方数据库
  print('\n=== Test 3: Third Party Database ===');
  try {
    final dbUrl = 'https://javdb.com/search?q=$code';
    final response = await http.get(
      Uri.parse(dbUrl),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
        'Accept-Encoding': 'gzip, deflate',
        'Connection': 'keep-alive',
        'Upgrade-Insecure-Requests': '1',
      },
    );
    
    print('JavDB Status: ${response.statusCode}');
    
    if (response.statusCode == 200) {
      final html = utf8.decode(response.bodyBytes, allowMalformed: true);
      
      // 查找缩略图
      final patterns = [
        RegExp(r'<img[^>]*class="[^"]*thumbnail[^"]*"[^>]*src="([^"]+)"'),
        RegExp(r'<img[^>]*class="[^"]*preview[^"]*"[^>]*src="([^"]+)"'),
        RegExp(r'<img[^>]*class="[^"]*poster[^"]*"[^>]*src="([^"]+)"'),
        RegExp(r'<img[^>]*class="[^"]*cover[^"]*"[^>]*src="([^"]+)"'),
      ];
      
      for (int i = 0; i < patterns.length; i++) {
        final match = patterns[i].firstMatch(html);
        if (match != null) {
          print('Found thumbnail with pattern $i: ${match.group(1)}');
          break;
        }
      }
    }
    
  } catch (e) {
    print('Third party test failed: $e');
  }
  
  print('\n=== Test Complete ===');
}
