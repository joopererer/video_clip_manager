import 'dart:convert';
import 'dart:io';

void main() async {
  print('=== YouTube 测试 ===');
  
  final url = 'https://www.youtube.com/watch?v=QTDgI8meEOo';
  
  print('测试URL: $url');
  
  try {
    final result = await Process.run('yt-dlp', [
      '--dump-json',
      '--no-playlist',
      '--no-warnings',
      url,
    ]);
    
    if (result.exitCode == 0) {
      print('YouTube测试成功');
      
      // 解析JSON输出
      final jsonData = json.decode(result.stdout.toString().trim());
      
      // 提取基本信息
      final title = jsonData['title'] ?? 'Unknown Title';
      final duration = jsonData['duration'];
      final thumbnail = jsonData['thumbnail'];
      final formats = jsonData['formats'] as List?;
      
      print('标题: $title');
      print('时长: ${duration != null ? '${duration}秒' : 'Unknown'}');
      print('封面: ${thumbnail ?? 'None'}');
      print('可用格式数量: ${formats?.length ?? 0}');
      
      // 分析格式
      if (formats != null && formats.isNotEmpty) {
        print('\n格式分析:');
        
        final videoStreams = <Map<String, dynamic>>[];
        final audioStreams = <Map<String, dynamic>>[];
        final hlsStreams = <Map<String, dynamic>>[];
        
        for (final format in formats) {
          final url = format['url'] ?? '';
          final protocol = format['protocol'] ?? '';
          final vcodec = format['vcodec'] ?? '';
          final acodec = format['acodec'] ?? '';
          final width = format['width'];
          final height = format['height'];
          final fps = format['fps'];
          final tbr = format['tbr'];
          final formatNote = format['format_note'] ?? '';
          
          // 分类格式
          if (vcodec != 'none' && vcodec.isNotEmpty) {
            videoStreams.add(format);
          }
          
          if (acodec != 'none' && acodec.isNotEmpty && vcodec == 'none') {
            audioStreams.add(format);
          }
          
          if (protocol == 'm3u8_native' || url.contains('.m3u8')) {
            hlsStreams.add(format);
          }
        }
        
        print('视频流: ${videoStreams.length}个');
        print('音频流: ${audioStreams.length}个');
        print('HLS流: ${hlsStreams.length}个');
        
        // 显示最佳视频流信息
        if (videoStreams.isNotEmpty) {
          print('\n最佳视频流:');
          videoStreams.sort((a, b) {
            final aRes = (a['width'] ?? 0) * (a['height'] ?? 0);
            final bRes = (b['width'] ?? 0) * (b['height'] ?? 0);
            return bRes.compareTo(aRes);
          });
          
          final best = videoStreams.first;
          final width = best['width'];
          final height = best['height'];
          final fps = best['fps'];
          final tbr = best['tbr'];
          final formatNote = best['format_note'] ?? '';
          final protocol = best['protocol'] ?? '';
          
          print('分辨率: ${width}x$height');
          print('帧率: ${fps ?? 'Unknown'}fps');
          print('比特率: ${tbr != null ? '${(tbr / 1024).toStringAsFixed(1)}kbps' : 'Unknown'}');
          print('格式: $formatNote');
          print('协议: $protocol');
        }
        
        // 显示HLS流信息
        if (hlsStreams.isNotEmpty) {
          print('\nHLS流详情:');
          for (int i = 0; i < hlsStreams.length && i < 3; i++) {
            final stream = hlsStreams[i];
            final width = stream['width'];
            final height = stream['height'];
            final fps = stream['fps'];
            final tbr = stream['tbr'];
            final formatNote = stream['format_note'] ?? '';
            
            print('  ${i + 1}. 分辨率: ${width}x$height, 帧率: ${fps ?? 'Unknown'}fps, 比特率: ${tbr != null ? '${(tbr / 1024).toStringAsFixed(1)}kbps' : 'Unknown'}, 格式: $formatNote');
          }
        }
      }
      
    } else {
      print('YouTube测试失败: ${result.stderr}');
    }
  } catch (e) {
    print('YouTube测试错误: $e');
  }
}
