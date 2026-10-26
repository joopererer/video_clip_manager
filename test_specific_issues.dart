import 'lib/services/yt_dlp_service.dart';
import 'lib/services/hybrid_video_sniffer_service.dart';
import 'lib/services/audio_detection_service.dart';

void main() async {
  print('🔍 测试特定问题...\n');

  // 测试 Bilibili 视频
  final bilibiliUrl = 'https://www.bilibili.com/video/BV1aoYPziEYL';
  print('📺 测试 Bilibili: $bilibiliUrl');
  
  try {
    final videoInfo = await YtDlpService.extractVideoInfo(bilibiliUrl);
    
    if (videoInfo != null) {
      print('✅ 成功获取 Bilibili 视频信息');
      print('   标题: ${videoInfo.title}');
      print('   总流数: ${videoInfo.formats.length}');
      
      // 显示音频检测摘要
      final audioSummary = AudioDetectionService.getAudioDetectionSummary(videoInfo.formats);
      print('📊 音频检测摘要:');
      print('   总流数: ${audioSummary['totalStreams']}');
      print('   音频流数: ${audioSummary['audioStreams']}');
      print('   组合流数: ${audioSummary['combinedStreams']}');
      print('   推荐: ${audioSummary['recommendation']}');
      
      // 显示前几个流的详细信息
      print('📋 流详情 (前10个):');
      for (int i = 0; i < videoInfo.formats.length && i < 10; i++) {
        final stream = videoInfo.formats[i];
        final audioStatus = stream.hasAudio ? '🔊' : '🔇';
        final videoStatus = stream.hasVideo ? '📹' : '  ';
        print('   ${i+1}. $audioStatus$videoStatus [${stream.formatId}] ${stream.resolutionString}');
        print('      URL: ${stream.url.substring(0, 100)}...');
        print('      Protocol: ${stream.protocol}');
        print('      Extension: ${stream.ext}');
        print('      Audio codec: ${stream.acodec}');
        print('      Video codec: ${stream.vcodec}');
        print('      Audio bitrate: ${stream.abr}');
        print('      Total bitrate: ${stream.tbr}');
        print('');
      }
    } else {
      print('❌ 无法获取 Bilibili 视频信息');
    }
  } catch (e) {
    print('💥 Bilibili 错误: $e');
  }
  
  print('\n' + '='*50 + '\n');
  
  // 测试 YouTube 视频的音频分离问题
  final youtubeUrl = 'https://www.youtube.com/watch?v=dsOuo7aOV60';
  print('🎵 测试 YouTube 音频分离: $youtubeUrl');
  
  try {
    final videoInfo = await YtDlpService.extractVideoInfo(youtubeUrl);
    
    if (videoInfo != null) {
      print('✅ 成功获取 YouTube 视频信息');
      print('   标题: ${videoInfo.title}');
      
      final allStreams = videoInfo.formats;
      final videoStreams = allStreams.where((s) => s.hasVideo).toList();
      final audioStreams = allStreams.where((s) => s.hasAudio && !s.hasVideo).toList();
      final combinedStreams = allStreams.where((s) => s.hasAudio && s.hasVideo).toList();
      
      print('📊 流分析:');
      print('   总流数: ${allStreams.length}');
      print('   视频流数: ${videoStreams.length}');
      print('   纯音频流数: ${audioStreams.length}');
      print('   组合流数: ${combinedStreams.length}');
      
      if (combinedStreams.isNotEmpty) {
        print('🏆 最佳组合流:');
        final best = AudioDetectionService.getBestCombinedStream(allStreams);
        if (best != null) {
          print('   格式ID: ${best.formatId}');
          print('   分辨率: ${best.resolutionString}');
          print('   音频编解码器: ${best.acodec}');
          print('   视频编解码器: ${best.vcodec}');
          print('   音频比特率: ${best.abr}');
          print('   URL: ${best.url.substring(0, 100)}...');
        }
      }
      
      if (audioStreams.isNotEmpty) {
        print('🎧 最佳音频流:');
        final bestAudio = AudioDetectionService.getBestAudioStream(allStreams);
        if (bestAudio != null) {
          print('   格式ID: ${bestAudio.formatId}');
          print('   音频编解码器: ${bestAudio.acodec}');
          print('   音频比特率: ${bestAudio.abr}');
          print('   URL: ${bestAudio.url.substring(0, 100)}...');
        }
      }
      
      if (videoStreams.isNotEmpty) {
        print('📹 最佳视频流:');
        final bestVideo = videoStreams.first;
        print('   格式ID: ${bestVideo.formatId}');
        print('   分辨率: ${bestVideo.resolutionString}');
        print('   视频编解码器: ${bestVideo.vcodec}');
        print('   视频比特率: ${bestVideo.vbr}');
        print('   URL: ${bestVideo.url.substring(0, 100)}...');
      }
      
    } else {
      print('❌ 无法获取 YouTube 视频信息');
    }
  } catch (e) {
    print('💥 YouTube 错误: $e');
  }
  
  print('\n🎯 测试完成');
}
