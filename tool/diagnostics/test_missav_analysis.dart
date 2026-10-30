import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

void main() async {
  print('=== MissAV 页面结构分析 ===');
  
  final url = 'https://missav.ws/fr/abw-182-uncensored-leak';
  
  print('分析URL: $url');
  
  try {
    // 使用与ExternalScraperService相同的headers
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
        'Accept-Language': 'en-US,en;q=0.9',
        'Accept-Encoding': 'gzip, deflate, br',
        'Connection': 'keep-alive',
        'Upgrade-Insecure-Requests': '1',
        'Sec-Fetch-Dest': 'document',
        'Sec-Fetch-Mode': 'navigate',
        'Sec-Fetch-Site': 'none',
        'Sec-Fetch-User': '?1',
        'Cache-Control': 'max-age=0',
      },
    );
    
    if (response.statusCode == 200) {
      print('页面获取成功，状态码: ${response.statusCode}');
      print('响应长度: ${response.body.length} 字符');
      
      final document = html_parser.parse(response.body);
      
      // 1. 分析所有script标签
      print('\n=== Script 标签分析 ===');
      final scripts = document.querySelectorAll('script');
      print('找到 ${scripts.length} 个script标签');
      
      for (int i = 0; i < scripts.length; i++) {
        final script = scripts[i];
        final content = script.text;
        final src = script.attributes['src'];
        
        print('\nScript ${i + 1}:');
        if (src != null) {
          print('  src: $src');
        }
        print('  内容长度: ${content.length} 字符');
        
        // 查找包含视频相关关键词的script
        final keywords = ['video', 'player', 'm3u8', 'mp4', 'stream', 'source', 'hls'];
        final foundKeywords = keywords.where((keyword) => content.toLowerCase().contains(keyword)).toList();
        
        if (foundKeywords.isNotEmpty) {
          print('  包含关键词: ${foundKeywords.join(', ')}');
          
          // 查找可能的视频URL
          final videoPatterns = [
            RegExp(r'"([^"]*\.m3u8[^"]*)"'),
            RegExp(r"'([^']*\.m3u8[^']*)'"),
            RegExp(r'"([^"]*\.mp4[^"]*)"'),
            RegExp(r"'([^']*\.mp4[^']*)'"),
            RegExp(r'"([^"]*video[^"]*)"'),
            RegExp(r"'([^']*video[^']*)'"),
            RegExp(r'"([^"]*player[^"]*)"'),
            RegExp(r"'([^']*player[^']*)'"),
          ];
          
          for (final pattern in videoPatterns) {
            final matches = pattern.allMatches(content);
            for (final match in matches) {
              final url = match.group(1);
              if (url != null && url.length > 10) {
                print('    找到URL: $url');
              }
            }
          }
        }
      }
      
      // 2. 分析所有iframe标签
      print('\n=== Iframe 标签分析 ===');
      final iframes = document.querySelectorAll('iframe');
      print('找到 ${iframes.length} 个iframe标签');
      
      for (int i = 0; i < iframes.length; i++) {
        final iframe = iframes[i];
        final src = iframe.attributes['src'];
        final dataSrc = iframe.attributes['data-src'];
        
        print('\nIframe ${i + 1}:');
        if (src != null) {
          print('  src: $src');
        }
        if (dataSrc != null) {
          print('  data-src: $dataSrc');
        }
      }
      
      // 3. 分析所有video标签
      print('\n=== Video 标签分析 ===');
      final videos = document.querySelectorAll('video');
      print('找到 ${videos.length} 个video标签');
      
      for (int i = 0; i < videos.length; i++) {
        final video = videos[i];
        final src = video.attributes['src'];
        final poster = video.attributes['poster'];
        
        print('\nVideo ${i + 1}:');
        if (src != null) {
          print('  src: $src');
        }
        if (poster != null) {
          print('  poster: $poster');
        }
        
        // 查找source标签
        final sources = video.querySelectorAll('source');
        for (int j = 0; j < sources.length; j++) {
          final source = sources[j];
          final sourceSrc = source.attributes['src'];
          final sourceType = source.attributes['type'];
          
          print('  source ${j + 1}:');
          if (sourceSrc != null) {
            print('    src: $sourceSrc');
          }
          if (sourceType != null) {
            print('    type: $sourceType');
          }
        }
      }
      
      // 4. 分析所有data属性
      print('\n=== Data 属性分析 ===');
      final dataElements = document.querySelectorAll('[data-*]');
      print('找到 ${dataElements.length} 个带data属性的元素');
      
      final videoDataElements = dataElements.where((el) {
        final attrs = el.attributes.keys.where((key) => key.toString().startsWith('data-')).toList();
        return attrs.any((attr) => attr.toString().toLowerCase().contains('video') || 
                                   attr.toString().toLowerCase().contains('player') ||
                                   attr.toString().toLowerCase().contains('src'));
      }).toList();
      
      print('其中 ${videoDataElements.length} 个可能与视频相关');
      
      for (int i = 0; i < videoDataElements.length && i < 10; i++) {
        final element = videoDataElements[i];
        final tagName = element.localName;
        final attrs = element.attributes.keys.where((key) => key.toString().startsWith('data-')).toList();
        
        print('\nElement ${i + 1} ($tagName):');
        for (final attr in attrs) {
          final value = element.attributes[attr];
          if (value != null && value.length > 5) {
            print('  $attr: $value');
          }
        }
      }
      
    } else {
      print('页面获取失败，状态码: ${response.statusCode}');
    }
    
  } catch (e) {
    print('分析失败: $e');
  }
}
