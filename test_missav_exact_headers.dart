import 'dart:io';
import 'dart:convert';

void main() async {
  print('=== MissAV 完全匹配浏览器头测试 ===');
  
  final url = 'https://missav.ws/fr/abw-126-uncensored-leak';
  
  // 使用完全一样的浏览器头
  await testExactBrowserHeaders(url);
}

Future<void> testExactBrowserHeaders(String url) async {
  try {
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(url));
    
    // 完全匹配浏览器头的请求头
    request.headers.set('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7');
    request.headers.set('Accept-Encoding', 'gzip, deflate, br, zstd');
    request.headers.set('Accept-Language', 'zh-MO,zh;q=0.9,fr-FR;q=0.8,fr;q=0.7,zh-TW;q=0.6,en-US;q=0.5,en;q=0.4,zh-CN;q=0.3');
    request.headers.set('Cache-Control', 'max-age=0');
    request.headers.set('Cookie', r'user_uuid=1fdef756-0a87-417e-8f8b-7ebd147d6c46; _ga=GA1.1.1072313755.1756247166; dom3ic8zudi28v8lr6fgphwffqoz0j6c=2f4d8d6e-22ae-4222-8455-96eea35b85fa%3A3%3A1; sb_main_62bdca270715b3b43fbac98597c038f1=1; cf_clearance=sEJUYq1c7IPLKOW8XH6cM3IhvlM7TsJXfmmKB6.xuxY-1756419025-1.2.1.1-gRjh7R6p88rvJ9oNc6ZQjgJchQfHZkX3dl1gpQqR_LbDtpwsvcWE4FtxYcY2faypA46fk811CddkEQnPljzjiMTRd.nBG_naHZEMRRnOIDcccCxtW4R0WZ2XpJce610IVHTm8x0.2bw4Oav5naeCK68zia4PvzTjb.sPQnsGkiCp_3y1TeutCgvwmxNMcrsChfVXI0Vy3sMaHdYENxVNcnoiOwRTnMmZWIsWzZzD8sI; _ga_9FFNX13PHD=GS2.1.s1756416070$o4$g1$t1756419032$j34$l0$h0; XSRF-TOKEN=eyJpdiI6ImoyRDVBWEs1Y2w0dVl1WEV4VjU4emc9PSIsInZhbHVlIjoiemsyUGRPL2xDZkRHYUoxOVR6YXpCVHd4S1ZvSFJRNTgyWWhkSlFTeWdZVGg0QWIwdDJhSVIyMjBzZTBCbXNiMkFEL2RqamFJNkxkQkFLOFhXOFVlUGpVZzU2TFpIT3pnWVRnQ1F5d0Q4OFY4VmFkS2s4bzJ6S1F5dk5SQjM4OXoiLCJtYWMiOiIyZmVkZDE2ZDE5YTIxMTE4YTI4NGE5MTI1NTg4MDBiNzUzZTcxZWVmNjY3ODBiNWM1NzhmMjRlMDhhZjdjNGM4IiwidGFnIjoiIn0%3D; missav_session=eyJpdiI6Im54a1BrSnFnZXEvcEN0SVhGZGpMV2c9PSIsInZhbHVlIjoiNCs5QkZvbFZmanhOZXNEcC9zN2g2dVJXc1JZalJkL1RKNlR4N1ZBUVc4czVWcWhHaGxhcE1WY1cvWDd6WUJqT2kwT3NKQ0FoNHQzN21MQ0lrMFRkT1FLNVMyZjFoWWZWRVU1QjVVUVVaZWxRQkJMdmtJVnBxalZZNmREYWJnN00iLCJtYWMiOiI4YzU3ZTMwYzBjMTUzMTkyYTRkZmNiMmNkOWNlZmFiNjBlOWE2ZjY2YWMwNGRkM2MxZjBjMzU4NDMzOGIwZjRlIiwidGFnIjoiIn0%3D; C3GPp0pe9xV2kA9yzolqPoObJHtt55NN3WpeSOlI=eyJpdiI6IlhKdVBxRDl5Q3l4ejFPYmYZEN1SlE9PSIsInZhbHVlIjoiaGQyQnNKQkt3a0NNU3lmcFpxQ2JvelV5Uno0dlJUUmQ2eVdGS25TUThGVmQ2V0wyWVBWYTZQL251NlZBcysxUXZqL284WFdMMnp6VllHMllRcThsTkFsaEF5Z1VjQytONGRJbXFpN0tsaHhBZDMzZmNRb0dydXdRakdNMzYvL1VCNjB5Mmx4V283R2xld0VqMUE0T0VHc0V4VHd6azVXbVdIaENkV3ZNM2F3Y0RhTkZEWnR2Mld3VStoenFoT2pmYXh6aFF3ZngxNjA5dEFlT2lnY0g2dW1ReWoxZWZKVVBKNVlCS3BkT0lWeldEL1d0MG1wZnN4aTJDZ01vbGxROUh2RkpOblZicWhsMjJ2VUpGSFlpdnVPWFNEMDZuSDdHaU9sWC9VZGVodU9aWll4am94Z0R6ajdNUjNkc043WTZWd2hYbllhSmhlZWhtbGRNaGtkRy9kS1VaczFBQk5DVEVOaHppL3dXTUE0TFJWRE9jSG1pZndIS0JmVjYxRGtlcHFnanlFaFg0Q3Bzb2NqVVRoQWRLZz09IiwibWFjIjoiOWQ0NjRmN2E2YTViZTFhZGY4YTViMTljOGM0ZWEzZGI2NmVlMGU4NmNlNjkyMGIyMWU4YTAwZDllMzEzYjliMSIsInRhZyI6IiJ9; sb_page_62bdca270715b3b43fbac98597c038f1=4; sb_count_62bdca270715b3b43fbac98597c038f1=4');
    request.headers.set('If-Modified-Since', 'Thu, 28 Aug 2025 13:14:59 GMT');
    request.headers.set('Referer', 'https://missav.ws/dm14/fr');
    request.headers.set('Sec-Ch-Ua', '"Not;A=Brand";v="99", "Google Chrome";v="139", "Chromium";v="139"');
    request.headers.set('Sec-Ch-Ua-Mobile', '?0');
    request.headers.set('Sec-Ch-Ua-Platform', '"Windows"');
    request.headers.set('Sec-Fetch-Dest', 'document');
    request.headers.set('Sec-Fetch-Mode', 'navigate');
    request.headers.set('Sec-Fetch-Site', 'same-origin');
    request.headers.set('Sec-Fetch-User', '?1');
    request.headers.set('Upgrade-Insecure-Requests', '1');
    request.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36');
    
    print('发送请求到: $url');
    print('使用完全匹配的浏览器头...');
    
    final response = await request.close();
    print('状态码: ${response.statusCode}');
    print('响应头: ${response.headers}');
    
    if (response.statusCode == 200) {
      final content = await response.transform(utf8.decoder).join();
      print('✅ 成功! 内容长度: ${content.length}');
      
      // 尝试提取标题
      final titlePatterns = [
        RegExp(r'<meta[^>]*property="og:title"[^>]*content="([^"]+)"', caseSensitive: false),
        RegExp(r'<meta[^>]*name="twitter:title"[^>]*content="([^"]+)"', caseSensitive: false),
        RegExp(r'<h1[^>]*class="[^"]*title[^"]*"[^>]*>([^<]+)</h1>', caseSensitive: false),
        RegExp(r'<h1[^>]*>([^<]+)</h1>', caseSensitive: false),
        RegExp(r'<title[^>]*>([^<]+)</title>', caseSensitive: false),
      ];
      
      for (int i = 0; i < titlePatterns.length; i++) {
        final match = titlePatterns[i].firstMatch(content);
        if (match != null && match.group(1) != null) {
          final title = match.group(1)!.trim();
          if (title.isNotEmpty) {
            print('找到标题 (模式 $i): $title');
            break;
          }
        }
      }
      
      if (content.length > 200) {
        print('内容预览: ${content.substring(0, 200)}...');
      }
    } else if (response.statusCode == 304) {
      print('⚠️ 304 Not Modified - 内容未更改');
    } else {
      print('❌ 失败，状态码: ${response.statusCode}');
      
      // 尝试读取错误响应内容
      try {
        final errorContent = await response.transform(utf8.decoder).join();
        if (errorContent.isNotEmpty) {
          print('错误响应内容: ${errorContent.substring(0, 500)}...');
        }
      } catch (e) {
        print('无法读取错误响应内容: $e');
      }
    }
    client.close();
  } catch (e) {
    print('❌ 请求错误: $e');
  }
}

