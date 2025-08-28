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
  
  /// 使用 JAV Scraper (Python) 获取 JAV 信息
  static Future<Map<String, dynamic>?> getJavInfoWithScraper(String code) async {
    try {
      print('ExternalScraper: Using JAV Scraper for code: $code');
      
      // 检查是否安装了 javscraper
      final checkResult = await Process.run('pip', ['show', 'javscraper']);
      if (checkResult.exitCode != 0) {
        print('ExternalScraper: javscraper not installed, skipping');
        return null;
      }
      
             // 使用 javscraper 获取信息
       final result = await Process.run('python', [
         '-c',
         '''
import sys
import json
try:
    from javscraper import JavScraper
    scraper = JavScraper()
    info = scraper.search('$code')
    if info:
        print(json.dumps(info, ensure_ascii=False))
    else:
        print("{}")
except ImportError as e:
    print(f'{{"error": "Import error: {e}"}}')
except Exception as e:
    print(f'{{"error": str(e)}}')
''',
       ]);
      
      if (result.exitCode == 0 && result.stdout.toString().isNotEmpty) {
        final jsonData = json.decode(result.stdout.toString());
        if (jsonData.containsKey('error')) {
          print('ExternalScraper: JAV Scraper error: ${jsonData['error']}');
          return null;
        }
        print('ExternalScraper: JAV Scraper success for $code');
        return jsonData;
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
}
