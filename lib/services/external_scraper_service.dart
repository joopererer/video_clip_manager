import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'config_service.dart';

/// 外部 Scraper 服务
/// 集成各种开源 scraper 来获取视频信息
class ExternalScraperService {
  
  /// 使用 yt-dlp 获取视频信息
  static Future<Map<String, dynamic>?> getVideoInfoWithYtDlp(String url) async {
    try {
      print('ExternalScraper: Using yt-dlp for URL: $url');
      
      final result = await Process.run('yt-dlp', [
        '--dump-json',
        '--no-playlist',
        '--no-warnings',
        url,
      ]);
      
      if (result.exitCode == 0 && result.stdout.toString().isNotEmpty) {
        final jsonData = json.decode(result.stdout.toString());
        print('ExternalScraper: yt-dlp success for $url');
        return jsonData;
      } else {
        print('ExternalScraper: yt-dlp failed for $url: ${result.stderr}');
      }
    } catch (e) {
      print('ExternalScraper: yt-dlp error for $url: $e');
    }
    return null;
  }
  
  /// 使用 JAV Scraper (Python) 获取 JAV 信息 - 修复版本
  static Future<Map<String, dynamic>?> getJavInfoWithScraper(String code) async {
    try {
      print('ExternalScraper: Using JAV Scraper for code: $code');
      
      // 检查是否安装了 javscraper
      final checkResult = await Process.run('pip', ['show', 'javscraper']);
      if (checkResult.exitCode != 0) {
        print('ExternalScraper: javscraper not installed, skipping');
        return null;
      }
      
      // 使用正确的 javscraper API - 修复所有问题
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
        '            ',
        '            # 尝试所有可用的 scraper',
        '            for name, scraper in scrapers:',
        '                try:',
        '                    info = scraper.search(code)',
        '                    if info:',
        '                        # 检查返回的数据是否有效',
        '                        if isinstance(info, list):',
        '                            if len(info) == 0:',
        '                                continue  # 空列表，跳过',
        '                            first_item = info[0]',
        '                            if isinstance(first_item, str):',
        '                                # 如果是字符串（如地区限制页面），跳过',
        '                                if "not-available" in first_item or "region" in first_item:',
        '                                    continue',
        '                                # 如果是URL字符串，也跳过（可能是重定向页面）',
        '                                if first_item.startswith("http"):',
        '                                    continue',
        '                        ',
        '                        # 解析数据并返回标准格式',
        '                        if isinstance(info, list) and len(info) > 0:',
        '                            first_item = info[0]',
        '                            if isinstance(first_item, dict):',
        '                                # 提取有用信息',
        '                                title = first_item.get("title", "")',
        '                                poster = first_item.get("poster", "")',
        '                                thumbnail = first_item.get("thumbnail", "")',
        '                                cover = first_item.get("cover", "")',
        '                                image = first_item.get("image", "")',
        '                                ',
        '                                result = {',
        '                                    "source": name,',
        '                                    "title": title,',
        '                                    "poster": poster or thumbnail or cover or image,',
        '                                    "thumbnail": poster or thumbnail or cover or image,',
        '                                    "data": info',
        '                                }',
        '                            else:',
        '                                result = {',
        '                                    "source": name,',
        '                                    "data": info',
        '                                }',
        '                        else:',
        '                            result = {',
        '                                "source": name,',
        '                                "data": info',
        '                            }',
        '                        ',
        '                        print(json.dumps(result, ensure_ascii=False))',
        '                        return',
        '                except Exception:',
        '                    continue',
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
      
      // 创建临时Python脚本文件
      final tempDir = await Directory.systemTemp.createTemp('javscraper_');
      final scriptFile = File('${tempDir.path}/javscraper_script.py');
      await scriptFile.writeAsString(pythonScript);
      
      try {
        final result = await Process.run('python', [scriptFile.path, code], 
          environment: {'PYTHONIOENCODING': 'utf-8'});
        
        if (result.exitCode == 0 && result.stdout.toString().isNotEmpty) {
          final stdout = result.stdout.toString().trim();
          print('ExternalScraper: Raw output: $stdout');
          
          try {
            final jsonData = json.decode(stdout);
            if (jsonData.containsKey('error')) {
              print('ExternalScraper: JAV Scraper error: ${jsonData['error']}');
              return null;
            }
            print('ExternalScraper: JAV Scraper success for $code from ${jsonData['source']}');
            return jsonData;
          } catch (e) {
            print('ExternalScraper: JSON parse error: $e');
            print('ExternalScraper: Raw output was: $stdout');
            return null;
          }
        } else {
          print('ExternalScraper: JAV Scraper failed: ${result.stderr}');
        }
      } finally {
        // 清理临时文件
        await tempDir.delete(recursive: true);
      }
    } catch (e) {
      print('ExternalScraper: JAV Scraper error for $code: $e');
    }
    return null;
  }
  
  /// 使用 TMDB API 获取电影信息
  static Future<Map<String, dynamic>?> getMovieInfoWithTmdb(String title) async {
    try {
      print('ExternalScraper: Using TMDB for title: $title');
      
      // 从配置服务获取 TMDB API Key
      final apiKey = await ConfigService.getTmdbApiKey();
      if (apiKey == null) {
        print('ExternalScraper: TMDB API key not configured');
        return null;
      }
      
      final response = await http.get(
        Uri.parse('https://api.themoviedb.org/3/search/movie?api_key=$apiKey&query=${Uri.encodeComponent(title)}'),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['results'] != null && data['results'].isNotEmpty) {
          final movie = data['results'][0];
          print('ExternalScraper: TMDB success for $title');
          return {
            'title': movie['title'],
            'overview': movie['overview'],
            'poster_path': movie['poster_path'] != null 
                ? 'https://image.tmdb.org/t/p/w500${movie['poster_path']}' 
                : null,
            'release_date': movie['release_date'],
            'vote_average': movie['vote_average'],
            'source': 'tmdb',
          };
        }
      }
    } catch (e) {
      print('ExternalScraper: TMDB error for $title: $e');
    }
    return null;
  }
  
  /// 使用自定义 Python 脚本获取信息
  static Future<Map<String, dynamic>?> getInfoWithCustomScript(
    String scriptPath, 
    List<String> arguments
  ) async {
    try {
      print('ExternalScraper: Using custom script: $scriptPath');
      
      final result = await Process.run('python', [scriptPath, ...arguments]);
      
      if (result.exitCode == 0 && result.stdout.toString().isNotEmpty) {
        final jsonData = json.decode(result.stdout.toString());
        print('ExternalScraper: Custom script success');
        return jsonData;
      } else {
        print('ExternalScraper: Custom script failed: ${result.stderr}');
      }
    } catch (e) {
      print('ExternalScraper: Custom script error: $e');
    }
    return null;
  }
  
  /// 获取所有可用的 scraper 信息
  static Future<Map<String, bool>> getAvailableScrapers() async {
    return await ConfigService.checkExternalScrapersAvailability();
  }
  
  /// 安装依赖
  static Future<bool> installDependencies() async {
    try {
      print('ExternalScraper: Installing dependencies...');
      
      // 安装 javscraper
      final javResult = await Process.run('pip', ['install', 'javscraper']);
      if (javResult.exitCode != 0) {
        print('ExternalScraper: Failed to install javscraper: ${javResult.stderr}');
        return false;
      }
      
      // 安装其他依赖
      final requirements = [
        'requests',
        'beautifulsoup4',
        'lxml',
        'tmdbv3api',
      ];
      
      for (final package in requirements) {
        final result = await Process.run('pip', ['install', package]);
        if (result.exitCode != 0) {
          print('ExternalScraper: Failed to install $package: ${result.stderr}');
          return false;
        }
      }
      
      print('ExternalScraper: Dependencies installed successfully');
      return true;
    } catch (e) {
      print('ExternalScraper: Error installing dependencies: $e');
      return false;
    }
  }

  /// 使用 cloudscraper 获取 MissAV 页面内容
  static Future<Map<String, dynamic>?> getMissavPageContent(String url) async {
    try {
      print('ExternalScraper: Getting MissAV page content with cloudscraper: $url');
      
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

      final scriptFile = await _createTempScript(scriptContent);
      
      try {
        // 执行 Python 脚本
        final result = await Process.run('python', [scriptFile.path, url], 
          environment: {'PYTHONIOENCODING': 'utf-8'});
        
        if (result.exitCode != 0) {
          print('ExternalScraper: MissAV cloudscraper failed with exit code: ${result.exitCode}');
          print('ExternalScraper: Error: ${result.stderr}');
          return null;
        }
        
        final output = result.stdout.toString().trim();
        if (output.isEmpty) {
          print('ExternalScraper: MissAV cloudscraper returned empty output');
          return null;
        }
        
        try {
          final data = json.decode(output) as Map<String, dynamic>;
          
          print('ExternalScraper: Parsed data: $data');
          
          if (data['success'] == true || data['success'] == 'true') {
                    print('ExternalScraper: MissAV cloudscraper success, content length: ${data['content_length']}');
        print('ExternalScraper: Extracted title: ${data['title']}');
        print('ExternalScraper: Title length: ${data['title']?.length ?? 0}');
            return data;
          } else {
            print('ExternalScraper: MissAV cloudscraper failed: ${data['error']}');
            return null;
          }
        } catch (e) {
          print('ExternalScraper: Failed to parse MissAV cloudscraper output: $e');
          print('ExternalScraper: Raw output: $output');
          return null;
        }
      } finally {
        // 清理临时文件
        await scriptFile.delete();
      }
      
    } catch (e) {
      print('ExternalScraper: MissAV cloudscraper error: $e');
      return null;
    }
  }

  /// 创建临时 Python 脚本文件
  static Future<File> _createTempScript(String content) async {
    final tempDir = await Directory.systemTemp.createTemp('external_scraper_');
    final scriptFile = File('${tempDir.path}/temp_script.py');
    await scriptFile.writeAsString(content);
    return scriptFile;
  }
}
