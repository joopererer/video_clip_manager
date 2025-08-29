import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  print('Testing webpage encoding detection...');
  
  final url = 'https://missav.ws/fr/abw-182-uncensored-leak';
  
  // 测试1: 检查HTTP响应头中的编码信息
  print('\n=== Test 1: HTTP Headers ===');
  try {
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
    );
    
    print('Status: ${response.statusCode}');
    print('Content-Type: ${response.headers['content-type']}');
    print('Content-Encoding: ${response.headers['content-encoding']}');
    print('All headers: ${response.headers}');
    
  } catch (e) {
    print('HTTP request failed: $e');
  }
  
  // 测试2: Python cloudscraper 详细编码信息
  print('\n=== Test 2: Python Cloudscraper Encoding Details ===');
  try {
    final scriptContent = '''
import sys
import json
import cloudscraper
import chardet

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
            raw_content = response.content
            
            # 检测编码
            detected = chardet.detect(raw_content)
            
            # 尝试不同的编码方式
            encodings = ['utf-8', 'latin-1', 'cp1252', 'iso-8859-1', 'windows-1252']
            decoded_contents = {}
            
            for encoding in encodings:
                try:
                    decoded = raw_content.decode(encoding)
                    decoded_contents[encoding] = decoded
                except:
                    decoded_contents[encoding] = None
            
            # 提取标题
            import re
            title_patterns = [
                r'<title[^>]*>([^<]+)</title>',
            ]
            
            extracted_titles = {}
            for encoding, decoded_content in decoded_contents.items():
                if decoded_content:
                    for pattern in title_patterns:
                        match = re.search(pattern, decoded_content, re.IGNORECASE)
                        if match:
                            title = match.group(1).strip()
                            if title:
                                extracted_titles[encoding] = title
                                break
            
            return {
                'success': True,
                'status_code': response.status_code,
                'content_length': len(content),
                'response_encoding': response.encoding,
                'detected_encoding': detected,
                'extracted_titles': extracted_titles,
                'sample_title_utf8': extracted_titles.get('utf-8', 'Not found'),
                'sample_title_latin1': extracted_titles.get('latin-1', 'Not found'),
                'sample_title_cp1252': extracted_titles.get('cp1252', 'Not found'),
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

    final scriptFile = File('test_encoding_detection.py');
    await scriptFile.writeAsString(scriptContent);
    
    final result = await Process.run('python', [scriptFile.path, url], 
      environment: {'PYTHONIOENCODING': 'utf-8'});
    
    if (result.exitCode == 0) {
      final output = result.stdout.toString().trim();
      print('Python output: $output');
      
      try {
        final data = json.decode(output) as Map<String, dynamic>;
        print('Parsed data: $data');
        print('Response encoding: ${data['response_encoding']}');
        print('Detected encoding: ${data['detected_encoding']}');
        print('Sample title (UTF-8): ${data['sample_title_utf8']}');
        print('Sample title (Latin-1): ${data['sample_title_latin1']}');
        print('Sample title (CP1252): ${data['sample_title_cp1252']}');
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
  
  print('\n=== Test Complete ===');
}
