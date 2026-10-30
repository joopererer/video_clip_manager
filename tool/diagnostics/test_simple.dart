import 'dart:io';

void main() async {
  print('=== 简单测试 ===');
  
  // 检查 yt-dlp 是否可用
  print('检查 yt-dlp 是否可用...');
  try {
    final result = await Process.run('yt-dlp', ['--version']);
    if (result.exitCode == 0) {
      print('yt-dlp 版本: ${result.stdout.toString().trim()}');
    } else {
      print('yt-dlp 不可用');
    }
  } catch (e) {
    print('yt-dlp 检查失败: $e');
  }
  
  // 测试一个简单的URL
  print('\n测试YouTube URL...');
  try {
    final result = await Process.run('yt-dlp', [
      '--dump-json',
      '--no-playlist',
      '--no-warnings',
      'https://www.youtube.com/watch?v=QTDgI8meEOo',
    ]);
    
    if (result.exitCode == 0) {
      print('YouTube测试成功');
      print('输出长度: ${result.stdout.toString().length} 字符');
    } else {
      print('YouTube测试失败: ${result.stderr}');
    }
  } catch (e) {
    print('YouTube测试错误: $e');
  }
}
