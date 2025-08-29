import 'dart:io';
import 'dart:convert';

void main() async {
  print('=== MissAV 访问测试 ===');
  
  final url = 'https://missav.ws/fr/abw-182-uncensored-leak';
  
  // 测试1: 最简单的请求
  print('\n1. 测试最简单的请求:');
  await testSimpleRequest(url);
  
  // 测试2: 使用完整的浏览器头
  print('\n2. 测试完整浏览器头:');
  await testFullBrowserHeaders(url);
  
  // 测试3: 使用不同的 User-Agent
  print('\n3. 测试不同的 User-Agent:');
  await testDifferentUserAgents(url);
  
  // 测试4: 测试日文页面
  print('\n4. 测试日文页面:');
  final jaUrl = url.replaceFirst(RegExp(r'/[a-z]{2}/'), '/ja/');
  await testSimpleRequest(jaUrl);
  
  // 测试5: 测试英文页面
  print('\n5. 测试英文页面:');
  final enUrl = url.replaceFirst(RegExp(r'/[a-z]{2}/'), '/en/');
  await testSimpleRequest(enUrl);
}

Future<void> testSimpleRequest(String url) async {
  try {
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');
    
    final response = await request.close();
    print('状态码: ${response.statusCode}');
    print('响应头: ${response.headers}');
    
    if (response.statusCode == 200) {
      final content = await response.transform(utf8.decoder).join();
      print('内容长度: ${content.length}');
      if (content.length > 100) {
        print('内容预览: ${content.substring(0, 100)}...');
      }
    }
  } catch (e) {
    print('错误: $e');
  }
}

Future<void> testFullBrowserHeaders(String url) async {
  try {
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(url));
    
    // 完整的浏览器头
    request.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36');
    request.headers.set('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7');
    request.headers.set('Accept-Language', 'zh-MO,zh;q=0.9,fr-FR;q=0.8,fr;q=0.7,zh-TW;q=0.6,en-US;q=0.5,en;q=0.4,zh-CN;q=0.3');
    request.headers.set('Accept-Encoding', 'gzip, deflate, br, zstd');
    request.headers.set('Connection', 'keep-alive');
    request.headers.set('Upgrade-Insecure-Requests', '1');
    request.headers.set('Sec-Fetch-Dest', 'document');
    request.headers.set('Sec-Fetch-Mode', 'navigate');
    request.headers.set('Sec-Fetch-Site', 'same-origin');
    request.headers.set('Sec-Fetch-User', '?1');
    request.headers.set('Cache-Control', 'max-age=0');
    request.headers.set('Sec-Ch-Ua', '"Not;A=Brand";v="99", "Google Chrome";v="139", "Chromium";v="139"');
    request.headers.set('Sec-Ch-Ua-Mobile', '?0');
    request.headers.set('Sec-Ch-Ua-Platform', '"Windows"');
    request.headers.set('DNT', '1');
    request.headers.set('Referer', 'https://missav.ws/dm14/fr');
    
    final response = await request.close();
    print('状态码: ${response.statusCode}');
    print('响应头: ${response.headers}');
    
    if (response.statusCode == 200) {
      final content = await response.transform(utf8.decoder).join();
      print('内容长度: ${content.length}');
      if (content.length > 100) {
        print('内容预览: ${content.substring(0, 100)}...');
      }
    }
  } catch (e) {
    print('错误: $e');
  }
}

Future<void> testDifferentUserAgents(String url) async {
  final userAgents = [
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/119.0',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  ];
  
  for (int i = 0; i < userAgents.length; i++) {
    try {
      print('User-Agent $i: ${userAgents[i].substring(0, 50)}...');
      
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', userAgents[i]);
      request.headers.set('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
      
      final response = await request.close();
      print('  状态码: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        print('  ✅ 成功!');
        break;
      }
    } catch (e) {
      print('  错误: $e');
    }
  }
}

