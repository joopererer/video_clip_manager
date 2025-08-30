import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  print('=== 视频格式支持测试 ===\n');
  
  // 测试不同的视频格式
  final testUrls = [
    // MP4 格式
    'https://sample-videos.com/zip/10/mp4/SampleVideo_1280x720_1mb.mp4',
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
    
    // M3U8 (HLS) 格式
    'https://bitdash-a.akamaihd.net/content/sintel/hls/playlist.m3u8',
    'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
    
    // WebM 格式
    'https://sample-videos.com/zip/10/webm/SampleVideo_1280x720_1mb.webm',
    
    // 其他格式
    'https://sample-videos.com/zip/10/avi/SampleVideo_1280x720_1mb.avi',
  ];
  
  for (int i = 0; i < testUrls.length; i++) {
    final url = testUrls[i];
    print('${i + 1}. 测试URL: $url');
    await testVideoFormat(url);
    print('');
  }
}

Future<void> testVideoFormat(String url) async {
  try {
    print('  开始测试...');
    
    // 1. 检查URL格式
    final uri = Uri.parse(url);
    final extension = _getFileExtension(uri.path);
    print('  文件扩展名: $extension');
    
    // 2. 检查HTTP响应
    final response = await http.head(Uri.parse(url));
    print('  HTTP状态码: ${response.statusCode}');
    
    if (response.statusCode == 200) {
      print('  ✅ URL可访问');
      
      // 3. 检查Content-Type
      final contentType = response.headers['content-type'];
      print('  Content-Type: $contentType');
      
      // 4. 检查文件大小
      final contentLength = response.headers['content-length'];
      if (contentLength != null) {
        final sizeInMB = (int.parse(contentLength) / (1024 * 1024)).toStringAsFixed(2);
        print('  文件大小: ${sizeInMB}MB');
      }
      
      // 5. 分析格式支持
      final isSupported = _isFormatSupported(extension, contentType);
      print('  格式支持: ${isSupported ? '✅ 支持' : '❌ 不支持'}');
      
      // 6. 对于M3U8文件，检查播放列表内容
      if (extension == '.m3u8') {
        await _analyzeM3u8Playlist(url);
      }
      
    } else {
      print('  ❌ URL不可访问');
    }
    
  } catch (e) {
    print('  ❌ 测试失败: $e');
  }
}

String _getFileExtension(String path) {
  final lastDot = path.lastIndexOf('.');
  if (lastDot != -1) {
    return path.substring(lastDot).toLowerCase();
  }
  return '';
}

bool _isFormatSupported(String extension, String? contentType) {
  // MediaKit支持的格式
  final supportedExtensions = [
    '.mp4', '.m4v', '.mov', '.3gp', '.3g2',
    '.avi', '.mkv', '.webm', '.flv', '.wmv',
    '.m3u8', '.m3u', '.ts', '.mts', '.m2ts',
    '.mpg', '.mpeg', '.vob', '.ogv', '.ogx',
    '.asf', '.rm', '.rmvb', '.divx', '.xvid'
  ];
  
  final supportedContentTypes = [
    'video/mp4',
    'video/x-m4v',
    'video/quicktime',
    'video/3gpp',
    'video/3gpp2',
    'video/x-msvideo',
    'video/x-matroska',
    'video/webm',
    'video/x-flv',
    'video/x-ms-wmv',
    'application/x-mpegurl',
    'application/vnd.apple.mpegurl',
    'video/mp2t',
    'video/mpeg',
    'video/x-ms-asf',
    'application/vnd.rn-realmedia',
    'video/divx',
    'video/xvid'
  ];
  
  final hasSupportedExtension = supportedExtensions.contains(extension);
  final hasSupportedContentType = contentType != null && 
      supportedContentTypes.any((type) => contentType.toLowerCase().contains(type));
  
  return hasSupportedExtension || hasSupportedContentType;
}

Future<void> _analyzeM3u8Playlist(String url) async {
  try {
    print('  分析M3U8播放列表...');
    
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final content = response.body;
      final lines = content.split('\n');
      
      // 检查播放列表类型
      bool isMasterPlaylist = false;
      bool hasSegments = false;
      int segmentCount = 0;
      
      for (final line in lines) {
        final trimmedLine = line.trim();
        if (trimmedLine.startsWith('#EXTM3U')) {
          print('    ✅ 有效的M3U8文件');
        } else if (trimmedLine.startsWith('#EXT-X-STREAM-INF')) {
          isMasterPlaylist = true;
        } else if (trimmedLine.startsWith('#EXTINF')) {
          hasSegments = true;
        } else if (trimmedLine.endsWith('.ts') || trimmedLine.endsWith('.m4s')) {
          segmentCount++;
        }
      }
      
      if (isMasterPlaylist) {
        print('    📋 主播放列表 (包含多个质量选项)');
      } else if (hasSegments) {
        print('    📋 媒体播放列表 (包含 $segmentCount 个片段)');
      } else {
        print('    ⚠️ 未知播放列表类型');
      }
      
      // 显示前几行内容
      print('    播放列表预览:');
      for (int i = 0; i < lines.length && i < 10; i++) {
        final line = lines[i].trim();
        if (line.isNotEmpty) {
          print('      ${i + 1}: $line');
        }
      }
      
    } else {
      print('    ❌ 无法获取播放列表内容');
    }
  } catch (e) {
    print('    ❌ 播放列表分析失败: $e');
  }
}
