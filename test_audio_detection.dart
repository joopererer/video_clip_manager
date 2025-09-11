import 'lib/services/yt_dlp_service.dart';
import 'lib/services/audio_detection_service.dart';

void main() async {
  print('🎵 测试音频检测改进...\n');

  // 测试YouTube视频
  final testUrls = [
    'https://www.youtube.com/watch?v=dsOuo7aOV60',
    'https://fr.xvideos.com/video.kiflbvkc550/yumi_etudiante_de_18_ans',
  ];

  for (final url in testUrls) {
    print('🔍 测试URL: $url');
    
    try {
      final videoInfo = await YtDlpService.extractVideoInfo(url);
      
      if (videoInfo != null) {
        print('✅ 成功获取视频信息');
        print('   标题: ${videoInfo.title}');
        print('   总流数: ${videoInfo.formats.length}');
        
        // 显示音频检测摘要
        final audioSummary = AudioDetectionService.getAudioDetectionSummary(videoInfo.formats);
        print('📊 音频检测摘要:');
        print('   总流数: ${audioSummary['totalStreams']}');
        print('   音频流数: ${audioSummary['audioStreams']}');
        print('   视频流数: ${audioSummary['videoStreams']}');
        print('   组合流数: ${audioSummary['combinedStreams']}');
        print('   纯音频流数: ${audioSummary['audioOnlyStreams']}');
        print('   纯视频流数: ${audioSummary['videoOnlyStreams']}');
        print('   音频检测率: ${audioSummary['audioDetectionRate']}%');
        print('   推荐: ${audioSummary['recommendation']}');
        
        // 显示最佳流信息
        final bestCombined = AudioDetectionService.getBestCombinedStream(videoInfo.formats);
        final bestAudio = AudioDetectionService.getBestAudioStream(videoInfo.formats);
        
        if (bestCombined != null) {
          print('🏆 最佳组合流:');
          print('   格式ID: ${bestCombined.formatId}');
          print('   分辨率: ${bestCombined.resolutionString}');
          print('   音频编解码器: ${bestCombined.acodec}');
          print('   音频比特率: ${bestCombined.abr}kbps');
          print('   总比特率: ${bestCombined.tbr}kbps');
        }
        
        if (bestAudio != null) {
          print('🎧 最佳音频流:');
          print('   格式ID: ${bestAudio.formatId}');
          print('   音频编解码器: ${bestAudio.acodec}');
          print('   音频比特率: ${bestAudio.abr}kbps');
          print('   格式说明: ${bestAudio.formatNote}');
        }
        
        // 显示前几个流的详细信息
        print('📋 流详情 (前5个):');
        for (int i = 0; i < videoInfo.formats.length && i < 5; i++) {
          final stream = videoInfo.formats[i];
          final audioStatus = stream.hasAudio ? '🔊' : '🔇';
          final videoStatus = stream.hasVideo ? '📹' : '  ';
          print('   ${i+1}. $audioStatus$videoStatus [${stream.formatId}] ${stream.resolutionString} '
                '(acodec: ${stream.acodec}, abr: ${stream.abr}, tbr: ${stream.tbr})');
        }
        
      } else {
        print('❌ 无法获取视频信息');
      }
    } catch (e) {
      print('💥 错误: $e');
    }
    
    print(''); // 空行分隔
  }
  
  print('🎯 音频检测测试完成');
}
