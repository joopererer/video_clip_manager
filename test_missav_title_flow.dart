import 'dart:io';
import 'dart:convert';

void main() async {
  print('=== MissAV 标题获取流程测试 ===');
  
  final url = 'https://missav.ws/fr/abw-126-uncensored-leak';
  
  // 测试1: 直接测试 Python 脚本
  print('\n1. 测试 Python 脚本:');
  await testPythonScript(url);
  
  // 测试2: 测试 ExternalScraperService
  print('\n2. 测试 ExternalScraperService:');
  await testExternalScraperService(url);
  
  // 测试3: 测试完整的标题提取流程
  print('\n3. 测试完整流程:');
  await testFullTitleFlow(url);
}

Future<Map<String, dynamic>?> testPythonScript(String url) async {
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
                'content': content,
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
    print(json.dumps(result, ensure_ascii=False))
''';

    final tempDir = await Directory.systemTemp.createTemp('test_');
    final scriptFile = File('${tempDir.path}/test_script.py');
    await scriptFile.writeAsString(scriptContent);
    
    try {
      final result = await Process.run('python', [scriptFile.path, url], 
        environment: {'PYTHONIOENCODING': 'utf-8'});
      
      if (result.exitCode == 0) {
        final output = result.stdout.toString().trim();
        if (output.isNotEmpty) {
          final data = json.decode(output) as Map<String, dynamic>;
          print('✅ Python 脚本成功');
          print('  状态码: ${data['status_code']}');
          print('  内容长度: ${data['content_length']}');
          print('  提取的标题: ${data['title']}');
          return data;
        }
      }
      print('❌ Python 脚本失败: ${result.stderr}');
      return null;
    } finally {
      await tempDir.delete(recursive: true);
    }
  } catch (e) {
    print('❌ Python 脚本错误: $e');
    return null;
  }
}

Future<Map<String, dynamic>?> testExternalScraperService(String url) async {
  try {
    // 模拟 ExternalScraperService.getMissavPageContent 的逻辑
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

    final tempDir = await Directory.systemTemp.createTemp('external_scraper_');
    final scriptFile = File('${tempDir.path}/temp_script.py');
    await scriptFile.writeAsString(scriptContent);
    
    try {
      final result = await Process.run('python', [scriptFile.path, url], 
        environment: {'PYTHONIOENCODING': 'utf-8'});
      
      if (result.exitCode != 0) {
        print('❌ ExternalScraperService 失败: ${result.stderr}');
        return null;
      }
      
      final output = result.stdout.toString().trim();
      if (output.isEmpty) {
        print('❌ ExternalScraperService 返回空输出');
        return null;
      }
      
      final data = json.decode(output) as Map<String, dynamic>;
      
      if (data['success'] == true || data['success'] == 'true') {
        print('✅ ExternalScraperService 成功');
        print('  状态码: ${data['status_code']}');
        print('  内容长度: ${data['content_length']}');
        print('  提取的标题: ${data['title']}');
        return data;
      } else {
        print('❌ ExternalScraperService 失败: ${data['error']}');
        return null;
      }
    } finally {
      await tempDir.delete(recursive: true);
    }
  } catch (e) {
    print('❌ ExternalScraperService 错误: $e');
    return null;
  }
}

Future<String?> testFullTitleFlow(String url) async {
  try {
    // 模拟完整的标题提取流程
    print('开始完整流程测试...');
    
    // 步骤1: 调用 ExternalScraperService
    final result = await testExternalScraperService(url);
    
    if (result != null && (result['success'] == true || result['success'] == 'true')) {
      final title = result['title'] as String?;
      print('✅ 完整流程成功');
      print('  最终获取的标题: $title');
      
      if (title != null && title.isNotEmpty) {
        print('✅ 标题有效，长度: ${title.length}');
        return title;
      } else {
        print('❌ 标题为空或无效');
        return null;
      }
    } else {
      print('❌ ExternalScraperService 返回 null 或失败');
      return null;
    }
  } catch (e) {
    print('❌ 完整流程错误: $e');
    return null;
  }
}
