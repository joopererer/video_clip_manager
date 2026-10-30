import 'dart:convert';
import 'dart:io';

void main() async {
  print('=== 测试 JAVLibrary 数据结构 ===');
  
  await testJAVLibraryOnly();
}

Future<void> testJAVLibraryOnly() async {
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
      '            print("Raw data type: " + str(type(info)))',
      '            print("Raw data: " + str(info))',
      '            ',
      '            if info:',
      '                if isinstance(info, list) and len(info) > 0:',
      '                    first_item = info[0]',
      '                    print("First item type: " + str(type(first_item)))',
      '                    print("First item: " + str(first_item))',
      '                    ',
      '                    if isinstance(first_item, dict):',
      '                        print("Available keys: " + str(list(first_item.keys())))',
      '                        ',
      '                        # 提取有用信息',
      '                        title = first_item.get("title", "Unknown Title")',
      '                        cover = first_item.get("cover", "")',
      '                        poster = first_item.get("poster", "")',
      '                        image = first_item.get("image", "")',
      '                        ',
      '                        result = {',
      '                            "source": "JAVLibrary",',
      '                            "title": title,',
      '                            "cover": cover or poster or image,',
      '                            "raw_data": first_item',
      '                        }',
      '                        print(json.dumps(result, ensure_ascii=False))',
      '                    else:',
      '                        result = {',
      '                            "source": "JAVLibrary",',
      '                            "raw_data": info',
      '                        }',
      '                        print(json.dumps(result, ensure_ascii=False))',
      '                else:',
      '                    result = {',
      '                        "source": "JAVLibrary",',
      '                        "raw_data": info',
      '                    }',
      '                    print(json.dumps(result, ensure_ascii=False))',
      '            else:',
      '                print(\'{"error": "No data found"}\')',
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
    
    final tempDir = await Directory.systemTemp.createTemp('javlibrary_test_');
    final scriptFile = File('${tempDir.path}/javlibrary_test.py');
    await scriptFile.writeAsString(pythonScript);
    
    try {
      print('执行JAVLibrary测试...');
      
      final result = await Process.run('python', [scriptFile.path, 'ABW-182'], 
        environment: {'PYTHONIOENCODING': 'utf-8'});
      
      print('退出码: ${result.exitCode}');
      print('标准输出: ${result.stdout}');
      print('错误输出: ${result.stderr}');
      
      if (result.exitCode == 0 && result.stdout.toString().isNotEmpty) {
        try {
          final jsonData = json.decode(result.stdout.toString());
          if (jsonData.containsKey('error')) {
            print('❌ JAVLibrary 错误: ${jsonData['error']}');
          } else {
            print('✅ JAVLibrary 成功获取数据');
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
        print('❌ JAVLibrary 执行失败');
      }
    } finally {
      await tempDir.delete(recursive: true);
    }
  } catch (e) {
    print('❌ JAVLibrary测试异常: $e');
  }
}
