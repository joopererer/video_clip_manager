import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';

/// 第三方数据库服务
/// 用于从多个数据库网站获取视频信息和缩略图
class ThirdPartyDatabaseService {
  static final Map<String, DatabaseConfig> _databases = {
    'javbus': DatabaseConfig(
      name: 'JavBus',
      baseUrl: 'https://www.javbus.com',
      searchUrl: 'https://www.javbus.com/search/{code}',
      thumbnailPatterns: [
        RegExp(r'<img[^>]*class="[^"]*movie-box[^"]*"[^>]*src="([^"]+)"'),
        RegExp(r'<img[^>]*class="[^"]*cover[^"]*"[^>]*src="([^"]+)"'),
        RegExp(r'<img[^>]*src="([^"]*\.jpg[^"]*)"'),
        RegExp(r'<img[^>]*data-src="([^"]*\.jpg[^"]*)"'),
      ],
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
        'Accept-Encoding': 'gzip, deflate, br',
        'Connection': 'keep-alive',
        'Upgrade-Insecure-Requests': '1',
        'Sec-Fetch-Dest': 'document',
        'Sec-Fetch-Mode': 'navigate',
        'Sec-Fetch-Site': 'none',
        'Sec-Fetch-User': '?1',
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
      },
    ),
                   'javlibrary': DatabaseConfig(
        name: 'JavLibrary',
        baseUrl: 'https://www.javlibrary.com',
        searchUrl: 'https://www.javlibrary.com/cn/vl_searchbyid.php?keyword={code}',
        thumbnailPatterns: [
          RegExp(r'<img[^>]*class="[^"]*video[^"]*"[^>]*src="([^"]+)"'),
          RegExp(r'<img[^>]*class="[^"]*cover[^"]*"[^>]*src="([^"]+)"'),
          RegExp(r'<img[^>]*src="([^"]*\.jpg[^"]*)"'),
          RegExp(r'<img[^>]*data-src="([^"]*\.jpg[^"]*)"'),
        ],
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
          'Accept-Encoding': 'gzip, deflate, br',
          'Connection': 'keep-alive',
          'Upgrade-Insecure-Requests': '1',
          'Sec-Fetch-Dest': 'document',
          'Sec-Fetch-Mode': 'navigate',
          'Sec-Fetch-Site': 'none',
          'Sec-Fetch-User': '?1',
          'Cache-Control': 'no-cache',
          'Pragma': 'no-cache',
          'Sec-Ch-Ua': '"Not_A Brand";v="8", "Chromium";v="120", "Google Chrome";v="120"',
          'Sec-Ch-Ua-Mobile': '?0',
          'Sec-Ch-Ua-Platform': '"Windows"',
          'DNT': '1',
          'Referer': 'https://www.google.com/',
          'Origin': 'https://www.javlibrary.com',
        },
      ),
    'javdb': DatabaseConfig(
      name: 'JavDB',
      baseUrl: 'https://javdb.com',
      searchUrl: 'https://javdb.com/search?q={code}',
      thumbnailPatterns: [
        RegExp(r'<img[^>]*class="[^"]*box[^"]*"[^>]*src="([^"]+)"'),
        RegExp(r'<img[^>]*class="[^"]*cover[^"]*"[^>]*src="([^"]+)"'),
        RegExp(r'<img[^>]*src="([^"]*\.jpg[^"]*)"'),
        RegExp(r'<img[^>]*data-src="([^"]*\.jpg[^"]*)"'),
      ],
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
        'Accept-Encoding': 'gzip, deflate, br',
        'Connection': 'keep-alive',
        'Upgrade-Insecure-Requests': '1',
        'Sec-Fetch-Dest': 'document',
        'Sec-Fetch-Mode': 'navigate',
        'Sec-Fetch-Site': 'none',
        'Sec-Fetch-User': '?1',
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
      },
    ),
         'javmost': DatabaseConfig(
       name: 'JavMost',
       baseUrl: 'https://javmost.com',
       searchUrl: 'https://javmost.com/search/{code}',
       thumbnailPatterns: [
         // 搜索结果页面的缩略图
         RegExp(r'<img[^>]*class="[^"]*thumb[^"]*"[^>]*src="([^"]+)"'),
         RegExp(r'<img[^>]*class="[^"]*cover[^"]*"[^>]*src="([^"]+)"'),
         // 详情页面的封面图
         RegExp(r'<img[^>]*class="[^"]*poster[^"]*"[^>]*src="([^"]+)"'),
         RegExp(r'<img[^>]*class="[^"]*movie[^"]*"[^>]*src="([^"]+)"'),
         RegExp(r'<img[^>]*src="([^"]*\.jpg[^"]*)"'),
         RegExp(r'<img[^>]*data-src="([^"]*\.jpg[^"]*)"'),
       ],
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
        'Accept-Encoding': 'gzip, deflate, br',
        'Connection': 'keep-alive',
        'Upgrade-Insecure-Requests': '1',
        'Sec-Fetch-Dest': 'document',
        'Sec-Fetch-Mode': 'navigate',
        'Sec-Fetch-Site': 'none',
        'Sec-Fetch-User': '?1',
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
      },
    ),
  };

  /// 从所有数据库获取缩略图
  static Future<String?> getThumbnailFromAllDatabases(String code) async {
    print('ThirdPartyDB: Searching for code: $code');
    
    // 基于测试结果，调整数据库优先级：JavDB > JavMost > JavLibrary
    final priorityOrder = ['javdb', 'javmost', 'javlibrary'];
    
    for (final databaseName in priorityOrder) {
      if (_databases.containsKey(databaseName)) {
        final config = _databases[databaseName]!;
        
        try {
          final thumbnailUrl = await _getThumbnailFromDatabase(code, databaseName, config);
          if (thumbnailUrl != null) {
            print('ThirdPartyDB: Found thumbnail from $databaseName: $thumbnailUrl');
            return thumbnailUrl;
          }
        } catch (e) {
          print('ThirdPartyDB: Error searching $databaseName: $e');
        }
      }
    }
    
    print('ThirdPartyDB: No thumbnail found from any database');
    return null;
  }

    /// 从数据库获取完整信息（包括缩略图和标题）
  static Future<Map<String, dynamic>?> getThumbnailFromDatabase(String code) async {
    print('ThirdPartyDB: Getting full info for code: $code');
    
    // 基于测试结果，调整数据库优先级：JavDB > JavMost > JavLibrary
    final priorityOrder = ['javdb', 'javmost', 'javlibrary'];
    
    for (final databaseName in priorityOrder) {
      if (_databases.containsKey(databaseName)) {
        final config = _databases[databaseName]!;
        
        try {
          final result = await _getFullInfoFromDatabase(code, databaseName, config);
          if (result != null && result['thumbnail'] != null) {
            print('ThirdPartyDB: Found info from $databaseName');
            return result;
          }
        } catch (e) {
          print('ThirdPartyDB: Error searching $databaseName: $e');
        }
      }
    }
    
    print('ThirdPartyDB: No info found from any database');
    return null;
  }

  /// 从指定数据库获取完整信息
  static Future<Map<String, dynamic>?> _getFullInfoFromDatabase(
    String code,
    String databaseName,
    DatabaseConfig config,
  ) async {
    try {
      final searchUrl = config.searchUrl.replaceAll('{code}', code);
      print('ThirdPartyDB: Searching $databaseName: $searchUrl');
      
      // 添加随机延迟避免被反爬虫
      await Future.delayed(Duration(milliseconds: 500 + (DateTime.now().millisecond % 1000)));
      
      // 使用简化的HTTP客户端
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      
      final request = await client.getUrl(Uri.parse(searchUrl));
      
      // 设置基本的headers
      request.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
      request.headers.set('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
      request.headers.set('Accept-Language', 'en-US,en;q=0.9');
      request.headers.set('Accept-Encoding', 'gzip, deflate');
      request.headers.set('Connection', 'keep-alive');
      request.headers.set('Upgrade-Insecure-Requests', '1');
      
             final response = await request.close();
      
      if (response.statusCode == 200) {
        final html = await response.transform(utf8.decoder).join();
        print('ThirdPartyDB: $databaseName response success, content length: ${html.length}');
        
        // 尝试所有缩略图模式
        for (int i = 0; i < config.thumbnailPatterns.length; i++) {
          final pattern = config.thumbnailPatterns[i];
          final matches = pattern.allMatches(html);
          
          for (final match in matches) {
            if (match.group(1) != null) {
              final thumbnailUrl = match.group(1)!;
              print('ThirdPartyDB: Found $databaseName thumbnail with pattern $i: $thumbnailUrl');
              
              // 过滤掉用户头像等无关图片
              if (_isValidThumbnailUrl(thumbnailUrl, databaseName)) {
                // 不从数据库页面提取标题（特别是 JavDB 搜索页），标题交由站点本身或上层逻辑决定
                String? title;
                // Restore normalized URL
                final normalizedUrl = _normalizeUrl(thumbnailUrl, config.baseUrl);
                
                return {
                  'thumbnail': normalizedUrl,
                  'title': title ?? 'Unknown Title',
                  'source': databaseName,
                  'code': code,
                };
              }
            }
          }
        }
      } else {
        print('ThirdPartyDB: $databaseName HTTP error: ${response.statusCode}');
      }
    } catch (e) {
      print('ThirdPartyDB: Error with $databaseName: $e');
    }
    
    return null;
  }

  /// 从指定数据库获取缩略图 - 完全重写，使用不同的HTTP客户端策略
  static Future<String?> _getThumbnailFromDatabase(
    String code,
    String databaseName,
    DatabaseConfig config,
  ) async {
    try {
      final searchUrl = config.searchUrl.replaceAll('{code}', code);
      print('ThirdPartyDB: Searching $databaseName: $searchUrl');
      
      // 添加随机延迟避免被反爬虫
      await Future.delayed(Duration(milliseconds: 500 + (DateTime.now().millisecond % 1000)));
      
      // 使用不同的HTTP客户端策略
      final response = await _makeHttpRequest(searchUrl, databaseName);
      
      if (response == null) {
        print('ThirdPartyDB: $databaseName request failed');
        return null;
      }
      
      print('ThirdPartyDB: $databaseName response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final html = response.body;
        print('ThirdPartyDB: $databaseName HTML content length: ${html.length}');
        
        // 检查是否被重定向到验证页面
        if (html.contains('captcha') || html.contains('verify') || html.contains('robot')) {
          print('ThirdPartyDB: $databaseName requires verification, skipping');
          return null;
        }
        
        // 对于某些数据库，需要先获取搜索结果链接，然后访问详情页面
        if (databaseName == 'javmost' || databaseName == 'javbus' || databaseName == 'javdb') {
          print('ThirdPartyDB: Attempting to extract detail URL from $databaseName');
          final detailUrl = await _extractDetailUrl(html, config.baseUrl, databaseName);
          if (detailUrl != null) {
            print('ThirdPartyDB: Found detail URL for $databaseName: $detailUrl');
            final thumbnailUrl = await _getThumbnailFromDetailPage(detailUrl, config, databaseName);
            if (thumbnailUrl != null) {
              return thumbnailUrl;
            }
          } else {
            print('ThirdPartyDB: No detail URL found for $databaseName');
          }
        }
        
        // 尝试所有缩略图模式
        for (int i = 0; i < config.thumbnailPatterns.length; i++) {
          final pattern = config.thumbnailPatterns[i];
          final matches = pattern.allMatches(html);
          
          for (final match in matches) {
            if (match.group(1) != null) {
              final thumbnailUrl = match.group(1)!;
              print('ThirdPartyDB: Found $databaseName thumbnail with pattern $i: $thumbnailUrl');
              
              // 过滤掉用户头像等无关图片
              if (_isValidThumbnailUrl(thumbnailUrl, databaseName)) {
                // 验证缩略图URL是否有效
                final normalizedUrl = _normalizeUrl(thumbnailUrl, config.baseUrl);
                if (await _validateThumbnailUrl(normalizedUrl)) {
                  print('ThirdPartyDB: Validated $databaseName thumbnail: $normalizedUrl');
                  return normalizedUrl;
                } else {
                  print('ThirdPartyDB: Invalid thumbnail URL: $normalizedUrl');
                }
              } else {
                print('ThirdPartyDB: Skipping invalid thumbnail URL: $thumbnailUrl');
              }
            }
          }
        }
        
        print('ThirdPartyDB: No valid thumbnails found in $databaseName');
      } else if (response.statusCode == 403) {
        print('ThirdPartyDB: $databaseName access forbidden (403)');
      } else if (response.statusCode == 404) {
        print('ThirdPartyDB: $databaseName not found (404)');
      } else {
        print('ThirdPartyDB: $databaseName HTTP error: ${response.statusCode}');
      }
    } catch (e) {
      print('ThirdPartyDB: Error fetching $databaseName thumbnail: $e');
    }
    return null;
  }

  /// 使用不同的HTTP客户端策略进行请求 - 优化版本
  static Future<http.Response?> _makeHttpRequest(String url, String databaseName) async {
    print('ThirdPartyDB: Using HttpClient for $databaseName');
    
    // 策略1: 优先使用 dart:io HttpClient (更底层，避免http包的头部解析问题)
    try {
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(url));
        
        // 根据数据库设置不同的headers
        switch (databaseName) {
          case 'javbus':
            // JavBus: 完全不设置headers，避免malformed headers问题
            print('ThirdPartyDB: JavBus - 不设置任何headers');
            break;
          case 'javlibrary':
            // JavLibrary: 使用完整的浏览器headers
            print('ThirdPartyDB: JavLibrary - 设置完整浏览器headers');
            request.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36');
            request.headers.set('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7');
            request.headers.set('Accept-Language', 'en-US,en;q=0.9');
            request.headers.set('Accept-Encoding', 'gzip, deflate, br');
            request.headers.set('Connection', 'keep-alive');
            request.headers.set('Upgrade-Insecure-Requests', '1');
            request.headers.set('Sec-Fetch-Dest', 'document');
            request.headers.set('Sec-Fetch-Mode', 'navigate');
            request.headers.set('Sec-Fetch-Site', 'cross-site');
            request.headers.set('Sec-Fetch-User', '?1');
            request.headers.set('Cache-Control', 'max-age=0');
            request.headers.set('Sec-Ch-Ua', '"Google Chrome";v="119", "Chromium";v="119", "Not?A_Brand";v="24"');
            request.headers.set('Sec-Ch-Ua-Mobile', '?0');
            request.headers.set('Sec-Ch-Ua-Platform', '"Windows"');
            request.headers.set('DNT', '1');
            request.headers.set('Referer', 'https://www.google.com/search?q=javlibrary');
            request.headers.set('Origin', 'https://www.google.com');
            break;
          default:
            // 其他数据库: 使用基本headers
            print('ThirdPartyDB: $databaseName - 设置基本headers');
            request.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');
            break;
        }
        
        final response = await request.close();
        final responseBody = await response.transform(utf8.decoder).join();
        
        print('ThirdPartyDB: HttpClient 成功 - 状态码: ${response.statusCode}, 长度: ${responseBody.length}');
        
        // 创建http.Response对象
        return http.Response(responseBody, response.statusCode);
      } finally {
        client.close();
      }
    } catch (e) {
      print('ThirdPartyDB: HttpClient failed for $databaseName: $e');
      
                      // 策略2: 如果HttpClient失败，回退到http包（但避免JavBus的malformed headers问题）
                if (databaseName == 'javbus') {
                  print('ThirdPartyDB: JavBus HttpClient失败，跳过http.Client回退（避免malformed headers）');
                  return null;
                }
                
                // 对于其他数据库，也优先使用HttpClient，避免头部问题
                print('ThirdPartyDB: HttpClient失败，但继续尝试其他方法');
                return null;
      
      print('ThirdPartyDB: 回退到http.Client for $databaseName');
      try {
        final client = http.Client();
        try {
          Map<String, String> headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          };
          
          final response = await client.get(Uri.parse(url), headers: headers);
          print('ThirdPartyDB: http.Client 成功 - 状态码: ${response.statusCode}');
          return response;
        } finally {
          client.close();
        }
      } catch (e2) {
        print('ThirdPartyDB: http.Client also failed for $databaseName: $e2');
        return null;
      }
    }
  }

  /// 验证缩略图URL是否有效
  static Future<bool> _validateThumbnailUrl(String url) async {
    try {
      final client = http.Client();
      try {
        // 添加超时和重试机制
        final response = await client.head(
          Uri.parse(url),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept': 'image/webp,image/apng,image/*,*/*;q=0.8',
            'Accept-Language': 'en-US,en;q=0.9',
            'Referer': 'https://www.google.com/',
          },
        ).timeout(Duration(seconds: 10));
        
        print('ThirdPartyDB: Thumbnail validation for $url: ${response.statusCode}');
        return response.statusCode == 200;
      } finally {
        client.close();
      }
    } catch (e) {
      print('ThirdPartyDB: Thumbnail validation error for $url: $e');
      return false;
    }
  }

     /// 检查缩略图URL是否有效（过滤掉用户头像等）
   static bool _isValidThumbnailUrl(String url, String databaseName) {
     final lowerUrl = url.toLowerCase();
     
     // 过滤掉用户头像、图标等无关图片
     final invalidPatterns = [
       'user-', 'avatar', 'icon', 'logo', 'profile',
       'assets/img/user', 'assets/img/avatar',
       'thumbnails/user', 'images/user',
       'user-13.jpg', 'user-14.jpg', 'user-15.jpg', // 常见的用户头像
       'preload.webp', 'preload.jpg', 'preload.png', // 预加载图片
       'loading.gif', 'loading.jpg', 'loading.png', // 加载图片
       'placeholder', 'default', 'blank', // 占位符图片
       'favicon', 'webp', // 图标文件
       'syndication.exosrv.com', // 广告图片
     ];
     
     for (final pattern in invalidPatterns) {
       if (lowerUrl.contains(pattern)) {
         return false;
       }
     }
     
     // 确保是图片文件
     final imageExtensions = ['.jpg', '.jpeg', '.png'];
     final hasImageExtension = imageExtensions.any((ext) => lowerUrl.contains(ext));
     
     // 对于 JavMost，需要更严格的过滤
     if (databaseName == 'javmost') {
       // 必须包含图片扩展名
       if (!hasImageExtension) {
         return false;
       }
       
       // 如果URL包含番号（如 ABW-182），优先选择
       if (lowerUrl.contains('abw-182') || lowerUrl.contains('abw182')) {
         return true;
       }
       
       // 如果URL包含常见的封面图路径，也选择
       if (lowerUrl.contains('cover') || lowerUrl.contains('poster') || 
           lowerUrl.contains('thumb') || lowerUrl.contains('image')) {
         return true;
       }
       
       // 如果URL看起来像真实的图片路径（不包含用户相关词汇）
       if (!lowerUrl.contains('user') && !lowerUrl.contains('avatar') && 
           !lowerUrl.contains('profile') && !lowerUrl.contains('icon') &&
           !lowerUrl.contains('assets/img/')) {
         return true;
       }
       
       return false; // 其他情况都拒绝
     }
     
     return hasImageExtension;
   }

  /// 从搜索结果页面提取详情页面URL
  static Future<String?> _extractDetailUrl(String html, String baseUrl, String databaseName) async {
    try {
      RegExp? linkPattern;
      
      switch (databaseName) {
        case 'javbus':
          // JavBus: 查找第一个搜索结果链接
          linkPattern = RegExp(r'<a[^>]*href="([^"]*movie/[^"]*)"[^>]*>');
          break;
        case 'javmost':
          // JavMost: 查找第一个搜索结果链接 - 根据实际页面结构调整
          print('ThirdPartyDB: Searching for JavMost detail links...');
          
          // 先尝试查找所有链接，看看页面结构
          final allLinks = RegExp(r'<a[^>]*href="([^"]*)"[^>]*>').allMatches(html);
          print('ThirdPartyDB: Found ${allLinks.length} total links in JavMost page');
          
          // 查找包含 ABW-182 的链接
          for (final link in allLinks) {
            final href = link.group(1);
            if (href != null && href.contains('ABW-182')) {
              print('ThirdPartyDB: Found JavMost link containing ABW-182: $href');
              return _normalizeUrl(href, baseUrl);
            }
          }
          
          // 尝试多种链接模式
          final linkPatterns = [
            RegExp(r'<a[^>]*href="([^"]*movie/[^"]*)"[^>]*class="[^"]*thumb[^"]*"[^>]*>'),
            RegExp(r'<a[^>]*href="([^"]*movie/[^"]*)"[^>]*>'),
            RegExp(r'<a[^>]*href="([^"]*video/[^"]*)"[^>]*>'),
            RegExp(r'<a[^>]*href="([^"]*title/[^"]*)"[^>]*>'),
          ];
          
          for (int i = 0; i < linkPatterns.length; i++) {
            final pattern = linkPatterns[i];
            final match = pattern.firstMatch(html);
            if (match != null && match.group(1) != null) {
              print('ThirdPartyDB: Found JavMost link with pattern $i: ${match.group(1)}');
              final detailUrl = match.group(1)!;
              return _normalizeUrl(detailUrl, baseUrl);
            }
          }
          
          print('ThirdPartyDB: No JavMost detail links found with any pattern');
          return null;
        case 'javdb':
          // JavDB: 搜索结果通常链接到 /v/xxxx
          final linkPatternsJavdb = [
            RegExp(r'<a[^>]*class="[^"]*box[^"]*"[^>]*href="([^"]*?/v/[^"]+)"'),
            RegExp(r'<a[^>]*href="([^"]*?/v/[^"]+)"[^>]*class="[^"]*box[^"]*"'),
            RegExp(r'<a[^>]*href="([^"]*?/v/[^"]+)"[^>]*>'),
          ];
          for (int i = 0; i < linkPatternsJavdb.length; i++) {
            final pm = linkPatternsJavdb[i].firstMatch(html);
            if (pm != null && pm.group(1) != null) {
              final detailUrl = pm.group(1)!;
              print('ThirdPartyDB: Found JavDB link with pattern $i: $detailUrl');
              return _normalizeUrl(detailUrl, baseUrl);
            }
          }
          return null;
        default:
          return null;
      }
      
      if (linkPattern != null) {
        final match = linkPattern.firstMatch(html);
        if (match != null && match.group(1) != null) {
          final detailUrl = match.group(1)!;
          return _normalizeUrl(detailUrl, baseUrl);
        }
      }
    } catch (e) {
      print('ThirdPartyDB: Error extracting detail URL from $databaseName: $e');
    }
    return null;
  }

  // 获取详情页标题（用于提升准确度，尤其是 JavDB）
  static Future<String?> _getTitleFromDetailPage(
    String detailUrl,
    DatabaseConfig config,
    String databaseName,
  ) async {
    try {
      final client = http.Client();
      try {
        final response = await client.get(
          Uri.parse(detailUrl),
          headers: {
            ...config.headers,
            'Referer': config.baseUrl,
          },
        );
        if (response.statusCode != 200) return null;
        final html = response.body;
        // 常见标题位置：h1/h2.title 或 <title>
        final titlePatterns = [
          RegExp(r'<h1[^>]*class="[^"]*title[^"]*"[^>]*>([^<]+)</h1>'),
          RegExp(r'<h2[^>]*class="[^"]*title[^"]*"[^>]*>([^<]+)</h2>'),
          RegExp(r'<h1[^>]*>([^<]+)</h1>'),
          RegExp(r'<h2[^>]*>([^<]+)</h2>'),
          RegExp(r'<title[^>]*>([^<]+)</title>'),
        ];
        for (final p in titlePatterns) {
          final m = p.firstMatch(html);
          if (m != null && m.group(1) != null) {
            final t = m.group(1)!.trim();
            if (t.isNotEmpty) return t;
          }
        }
      } finally {
        client.close();
      }
    } catch (e) {
      print('ThirdPartyDB: Error extracting title from $databaseName detail page: $e');
    }
    return null;
  }

  /// 从详情页面获取缩略图
  static Future<String?> _getThumbnailFromDetailPage(String detailUrl, DatabaseConfig config, String databaseName) async {
    try {
      print('ThirdPartyDB: Fetching detail page: $detailUrl');
      
      // 使用更安全的HTTP客户端配置，避免编码错误
      final client = http.Client();
      try {
        final response = await client.get(
          Uri.parse(detailUrl),
          headers: {
            ...config.headers,
            'Referer': config.baseUrl,
            'Accept-Encoding': 'gzip, deflate', // 简化编码头
          },
        );
        
        if (response.statusCode == 200) {
          final html = response.body;
          print('ThirdPartyDB: Detail page HTML length: ${html.length}');
          
          // 使用更精确的缩略图模式
          final detailPatterns = _getDetailPagePatterns(databaseName);
          
          // 先查找所有图片，看看页面结构
          final allImages = RegExp(r'<img[^>]*src="([^"]*)"[^>]*>').allMatches(html);
          print('ThirdPartyDB: Found ${allImages.length} total images in detail page');
          
          // 查找 data-src 属性的图片（懒加载）
          final lazyImages = RegExp(r'<img[^>]*data-src="([^"]*)"[^>]*>').allMatches(html);
          print('ThirdPartyDB: Found ${lazyImages.length} lazy-loaded images in detail page');
          
          // 简化日志，避免过多输出
          
          // 检查懒加载图片
          for (final img in lazyImages) {
            final src = img.group(1);
            if (src != null) {
              print('ThirdPartyDB: Lazy image: $src');
              if (_isValidThumbnailUrl(src, databaseName)) {
                final normalizedUrl = _normalizeUrl(src, config.baseUrl);
                if (await _validateThumbnailUrl(normalizedUrl)) {
                  print('ThirdPartyDB: Validated lazy image: $normalizedUrl');
                  return normalizedUrl;
                }
              }
            }
          }
          

          
                     // 查找包含 ABW-182 的图片
           for (final img in allImages) {
             final src = img.group(1);
             if (src != null && src.contains('ABW-182')) {
               print('ThirdPartyDB: Found detail page image containing ABW-182: $src');
               if (_isValidThumbnailUrl(src, databaseName)) {
                 final normalizedUrl = _normalizeUrl(src, config.baseUrl);
                 if (await _validateThumbnailUrl(normalizedUrl)) {
                   print('ThirdPartyDB: Validated detail page image: $normalizedUrl');
                   return normalizedUrl;
                 }
               }
             }
           }
           
           // 对于 JavMost，尝试查找更大的封面图片
           if (databaseName == 'javmost') {
             // 查找包含 "large" 或 "big" 的图片
             for (final img in allImages) {
               final src = img.group(1);
               if (src != null && (src.contains('large') || src.contains('big') || src.contains('cover'))) {
                 print('ThirdPartyDB: Found JavMost large image: $src');
                 if (_isValidThumbnailUrl(src, databaseName)) {
                   final normalizedUrl = _normalizeUrl(src, config.baseUrl);
                   if (await _validateThumbnailUrl(normalizedUrl)) {
                     print('ThirdPartyDB: Validated JavMost large image: $normalizedUrl');
                     return normalizedUrl;
                   }
                 }
               }
             }
             
             // 查找不包含 "assets/img/" 的图片
             for (final img in allImages) {
               final src = img.group(1);
               if (src != null && !src.contains('assets/img/') && src.contains('.jpg')) {
                 print('ThirdPartyDB: Found JavMost non-assets image: $src');
                 if (_isValidThumbnailUrl(src, databaseName)) {
                   final normalizedUrl = _normalizeUrl(src, config.baseUrl);
                   if (await _validateThumbnailUrl(normalizedUrl)) {
                     print('ThirdPartyDB: Validated JavMost non-assets image: $normalizedUrl');
                     return normalizedUrl;
                   }
                 }
               }
             }
           }
          
          for (int i = 0; i < detailPatterns.length; i++) {
            final pattern = detailPatterns[i];
            final match = pattern.firstMatch(html);
            if (match != null && match.group(1) != null) {
              final thumbnailUrl = match.group(1)!;
              print('ThirdPartyDB: Found detail page thumbnail with pattern $i: $thumbnailUrl');
              
              if (_isValidThumbnailUrl(thumbnailUrl, databaseName)) {
                final normalizedUrl = _normalizeUrl(thumbnailUrl, config.baseUrl);
                if (await _validateThumbnailUrl(normalizedUrl)) {
                  print('ThirdPartyDB: Validated detail page thumbnail: $normalizedUrl');
                  return normalizedUrl;
                }
              }
            }
          }
        } else {
          print('ThirdPartyDB: Detail page HTTP error: ${response.statusCode}');
        }
      } finally {
        client.close();
      }
    } catch (e) {
      print('ThirdPartyDB: Error fetching detail page from $databaseName: $e');
      
      // 如果是编码错误，尝试使用不同的编码方式
      if (e.toString().contains('extension byte')) {
        print('ThirdPartyDB: Trying alternative encoding approach for $databaseName');
        return await _getThumbnailFromDetailPageAlternative(detailUrl, config, databaseName);
      }
    }
    return null;
  }

  /// 备用方法：使用不同的编码方式获取详情页面缩略图
  static Future<String?> _getThumbnailFromDetailPageAlternative(String detailUrl, DatabaseConfig config, String databaseName) async {
    try {
      print('ThirdPartyDB: Trying alternative method for detail page: $detailUrl');
      
      final client = http.Client();
      try {
        final response = await client.get(
          Uri.parse(detailUrl),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'en-US,en;q=0.9',
            'Connection': 'keep-alive',
            'Referer': config.baseUrl,
          },
        );
        
        if (response.statusCode == 200) {
          final html = response.body;
          print('ThirdPartyDB: Alternative method - Detail page HTML length: ${html.length}');
          
          // 使用更精确的缩略图模式
          final detailPatterns = _getDetailPagePatterns(databaseName);
          
          for (final pattern in detailPatterns) {
            final match = pattern.firstMatch(html);
            if (match != null && match.group(1) != null) {
              final thumbnailUrl = match.group(1)!;
              print('ThirdPartyDB: Alternative method - Found detail page thumbnail: $thumbnailUrl');
              
              if (_isValidThumbnailUrl(thumbnailUrl, databaseName)) {
                final normalizedUrl = _normalizeUrl(thumbnailUrl, config.baseUrl);
                if (await _validateThumbnailUrl(normalizedUrl)) {
                  print('ThirdPartyDB: Alternative method - Validated detail page thumbnail: $normalizedUrl');
                  return normalizedUrl;
                }
              }
            }
          }
        }
      } finally {
        client.close();
      }
    } catch (e) {
      print('ThirdPartyDB: Alternative method also failed for $databaseName: $e');
    }
    return null;
  }

  /// 获取详情页面的缩略图模式
  static List<RegExp> _getDetailPagePatterns(String databaseName) {
    switch (databaseName) {
      case 'javdb':
        return [
          // JavDB 详情页封面
          RegExp(r'<img[^>]*class="[^"]*cover[^"]*"[^>]*src="([^"]+)"'),
          RegExp(r'<img[^>]*class="[^"]*box[^"]*"[^>]*src="([^"]+)"'),
          RegExp(r'<img[^>]*src="([^"]*\\.jpg[^"]*)"'),
        ];
      case 'javbus':
        return [
          RegExp(r'<img[^>]*class="[^"]*movie-box[^"]*"[^>]*src="([^"]+)"'),
          RegExp(r'<img[^>]*class="[^"]*cover[^"]*"[^>]*src="([^"]+)"'),
          RegExp(r'<img[^>]*id="[^"]*movie[^"]*"[^>]*src="([^"]+)"'),
        ];
      case 'javmost':
        return [
          // JavMost 详情页面的缩略图模式
          RegExp(r'<img[^>]*class="[^"]*poster[^"]*"[^>]*src="([^"]+)"'),
          RegExp(r'<img[^>]*class="[^"]*movie[^"]*"[^>]*src="([^"]+)"'),
          RegExp(r'<img[^>]*class="[^"]*cover[^"]*"[^>]*src="([^"]+)"'),
          RegExp(r'<img[^>]*class="[^"]*thumb[^"]*"[^>]*src="([^"]+)"'),
          RegExp(r'<img[^>]*class="[^"]*image[^"]*"[^>]*src="([^"]+)"'),
          // 更通用的模式
          RegExp(r'<img[^>]*src="([^"]*\.jpg[^"]*)"[^>]*class="[^"]*"[^>]*>'),
          RegExp(r'<img[^>]*src="([^"]*\.jpg[^"]*)"[^>]*>'),
        ];
      default:
        return [];
    }
  }

  /// 标准化URL
  static String _normalizeUrl(String url, String baseUrl) {
    if (url.startsWith('http')) {
      return url;
    } else if (url.startsWith('//')) {
      return 'https:${url}';
    } else if (url.startsWith('/')) {
      return '$baseUrl${url}';
    } else {
      return '$baseUrl/${url}';
    }
  }

  /// 从URL中提取番号
  static String? extractCodeFromUrl(String url) {
    // 尝试多种番号格式
    final patterns = [
      RegExp(r'([A-Z]{2,4}-\d{2,4})', caseSensitive: false), // ABW-182
      RegExp(r'([A-Z]{2,4}\d{2,4})', caseSensitive: false),  // ABW182
      RegExp(r'([A-Z]{2,4}_\d{2,4})', caseSensitive: false), // ABW_182
    ];
    
    for (final pattern in patterns) {
      final match = pattern.firstMatch(url);
      if (match != null) {
        final code = match.group(1)!.toUpperCase();
        // 标准化格式为 XX-XXX
        if (code.contains('-')) {
          return code;
        } else if (code.contains('_')) {
          return code.replaceAll('_', '-');
        } else {
          // 尝试在字母和数字之间插入连字符
          final letterMatch = RegExp(r'([A-Z]+)(\d+)').firstMatch(code);
          if (letterMatch != null) {
            return '${letterMatch.group(1)}-${letterMatch.group(2)}';
          }
        }
      }
    }
    return null;
  }

  /// 获取支持的数据库列表
  static List<String> getSupportedDatabases() {
    return _databases.keys.toList();
  }

  /// 获取数据库配置
  static DatabaseConfig? getDatabaseConfig(String databaseName) {
    return _databases[databaseName];
  }
}

/// 数据库配置
class DatabaseConfig {
  final String name;
  final String baseUrl;
  final String searchUrl;
  final List<RegExp> thumbnailPatterns;
  final Map<String, String> headers;

  const DatabaseConfig({
    required this.name,
    required this.baseUrl,
    required this.searchUrl,
    required this.thumbnailPatterns,
    required this.headers,
  });
}
