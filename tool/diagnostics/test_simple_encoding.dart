import 'dart:convert';
import 'dart:io';

void main() async {
  print('Testing simple encoding...');
  
  final url = 'https://missav.ws/fr/abw-182-uncensored-leak';
  
  // 使用 Python cloudscraper 获取标题并分析
  print('\n=== Test: Simple Encoding Analysis ===');
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
            
            # 查找标题
            import re
            title_match = re.search(r'<title[^>]*>([^<]+)</title>', content, re.IGNORECASE)
            title = title_match.group(1).strip() if title_match else None
            
            # 分析标题中的字符
            if title:
                char_analysis = []
                for i, char in enumerate(title):
                    if ord(char) > 127:  # 非ASCII字符
                        char_analysis.append({
                            'position': i,
                            'char': char,
                            'unicode': f'U+{ord(char):04X}',
                            'hex': hex(ord(char))
                        })
            
            return {
                'success': True,
                'title': title,
                'char_analysis': char_analysis if title else [],
                'response_encoding': response.encoding
            }
        else:
            return {
                'success': False,
                'status_code': response.status_code
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

    final scriptFile = File('test_simple_encoding.py');
    await scriptFile.writeAsString(scriptContent);
    
    final result = await Process.run('python', [scriptFile.path, url], 
      environment: {'PYTHONIOENCODING': 'utf-8'});
    
    if (result.exitCode == 0) {
      final output = result.stdout.toString().trim();
      print('Python output: $output');
      
      try {
        final data = json.decode(output) as Map<String, dynamic>;
        print('Title: ${data['title']}');
        print('Response encoding: ${data['response_encoding']}');
        print('Character analysis:');
        for (final charInfo in data['char_analysis']) {
          print('  Position ${charInfo['position']}: "${charInfo['char']}" (${charInfo['unicode']}, ${charInfo['hex']})');
        }
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
