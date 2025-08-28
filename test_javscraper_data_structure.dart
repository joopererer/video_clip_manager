import 'dart:convert';
import 'dart:io';

void main() async {
  print('=== 测试 javscraper 数据结构 ===');
  
  await testJavScraperDataStructure();
}

Future<void> testJavScraperDataStructure() async {
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
      '        # 尝试导入不同的 scraper',
      '        scrapers = []',
      '        ',
      '        try:',
      '            from javscraper import JAVLibrary',
      '            scrapers.append(("JAVLibrary", JAVLibrary()))',
      '        except ImportError:',
      '            pass',
      '        ',
      '        try:',
      '            from javscraper import DMM',
      '            scrapers.append(("DMM", DMM()))',
      '        except ImportError:',
      '            pass',
      '        ',
      '        try:',
      '            from javscraper import MGStage',
      '            scrapers.append(("MGStage", MGStage()))',
      '        except ImportError:',
      '            pass',
      '        ',
      '        if not scrapers:',
      '            print(\'{"error": "No scrapers available"}\')',
      '            return',
      '        ',
      '        if len(sys.argv) > 1:',
      '            code = sys.argv[1]',
      '            print("Searching for code: " + code)',
      '            ',
      '            # 尝试所有可用的 scraper',
      '            for name, scraper in scrapers:',
      '                try:',
      '                    print("Trying " + name + "...")',
      '                    info = scraper.search(code)',
      '                    if info:',
      '                        print(name + " search successful")',
      '                        print("Raw data type: " + str(type(info)))',
      '                        print("Raw data: " + str(info))',
      '                        ',
      '                        # 尝试解析数据结构',
      '                        if isinstance(info, list) and len(info) > 0:',
      '                            first_item = info[0]',
      '                            print("First item type: " + str(type(first_item)))',
      '                            print("First item: " + str(first_item))',
      '                            ',
      '                            if isinstance(first_item, dict):',
      '                                print("Available keys: " + str(list(first_item.keys())))',
      '                                ',
      '                                # 提取有用信息',
      '                                title = first_item.get("title", "Unknown Title")',
      '                                cover = first_item.get("cover", "")',
      '                                poster = first_item.get("poster", "")',
      '                                image = first_item.get("image", "")',
      '                                ',
      '                                result = {',
      '                                    "source": name,',
      '                                    "title": title,',
      '                                    "cover": cover or poster or image,',
      '                                    "raw_data": first_item',
      '                                }',
      '                                print(json.dumps(result, ensure_ascii=False))',
      '                                return',
      '                        ',
      '                        # 如果数据结构不同，返回原始数据',
      '                        result = {',
      '                            "source": name,',
      '                            "raw_data": info',
      '                        }',
      '                        print(json.dumps(result, ensure_ascii=False))',
      '                        return',
      '                    else:',
      '                        print(name + " search returned empty result")',
      '                except Exception as e:',
      '                    print(name + " search exception: " + str(e))',
      '            ',
      '            # 如果所有 scraper 都失败',
      '            print(\'{"error": "All scrapers failed"}\')',
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
    
    final tempDir = await Directory.systemTemp.createTemp('javscraper_data_');
    final scriptFile = File('${tempDir.path}/data_test.py');
    await scriptFile.writeAsString(pythonScript);
    
    try {
      print('执行javscraper数据结构测试...');
      
      final result = await Process.run('python', [scriptFile.path, 'ABW-182'], 
        environment: {'PYTHONIOENCODING': 'utf-8'});
      
      print('退出码: ${result.exitCode}');
      print('标准输出: ${result.stdout}');
      print('错误输出: ${result.stderr}');
      
      if (result.exitCode == 0 && result.stdout.toString().isNotEmpty) {
        try {
          final jsonData = json.decode(result.stdout.toString());
          if (jsonData.containsKey('error')) {
            print('❌ javscraper 错误: ${jsonData['error']}');
          } else {
            print('✅ javscraper 成功获取数据');
            print('数据来源: ${jsonData['source']}');
            print('标题: ${jsonData['title'] ?? 'N/A'}');
            print('封面: ${jsonData['cover'] ?? 'N/A'}');
            print('原始数据结构: ${jsonData['raw_data']}');
          }
        } catch (e) {
          print('❌ JSON 解析错误: $e');
          print('原始输出: ${result.stdout}');
        }
      } else {
        print('❌ javscraper 执行失败');
      }
    } finally {
      await tempDir.delete(recursive: true);
    }
  } catch (e) {
    print('❌ javscraper数据结构测试异常: $e');
  }
}
