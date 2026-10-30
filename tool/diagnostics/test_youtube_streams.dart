import 'dart:io';
import 'package:video_clip_manager/services/yt_dlp_service.dart';

/// 测试 YouTube 视频流嗅探
/// 
/// 此测试用于验证：
/// 1. YouTube 视频能检测到多少个流
/// 2. 哪些流有音频，哪些没有
/// 3. 流的质量分组情况
/// 4. 最佳流选择逻辑
void main() async {
  // 测试的 YouTube 视频 URL
  const testUrl = 'https://www.youtube.com/watch?v=dsOuo7aOV60';
  
  print('=== YouTube 流嗅探测试 ===');
  print('测试视频: $testUrl');
  print('');
  
  try {
    // 1. 基本信息提取
    print('1. 提取视频基本信息...');
    final videoInfo = await YtDlpService.extractVideoInfo(testUrl);
    
    if (videoInfo == null) {
      print('❌ 无法提取视频信息');
      exit(1);
    }
    
    print('✅ 视频信息提取成功:');
    print('   标题: ${videoInfo.title}');
    print('   时长: ${videoInfo.duration}');
    print('   缩略图: ${videoInfo.thumbnail}');
    print('   最佳视频URL: ${videoInfo.getBestVideoUrl()}');
    print('');
    
    // 2. 流详细分析
    print('2. 分析所有可用流...');
    final streams = videoInfo.formats;
    print('   总流数: ${streams.length}');
    
    if (streams.isEmpty) {
      print('❌ 没有找到任何流');
      exit(1);
    }
    
    // 分类统计
    final videoStreams = streams.where((s) => s.hasVideo).toList();
    final audioStreams = streams.where((s) => s.hasAudio).toList();
    final videoWithAudio = streams.where((s) => s.hasVideo && s.hasAudio).toList();
    final videoOnly = streams.where((s) => s.hasVideo && !s.hasAudio).toList();
    final audioOnly = streams.where((s) => !s.hasVideo && s.hasAudio).toList();
    
    print('   视频流数: ${videoStreams.length}');
    print('   音频流数: ${audioStreams.length}');
    print('   视频+音频流数: ${videoWithAudio.length}');
    print('   纯视频流数: ${videoOnly.length}');
    print('   纯音频流数: ${audioOnly.length}');
    print('');
    
    // 3. 详细流信息
    print('3. 详细流信息:');
    for (int i = 0; i < streams.length; i++) {
      final stream = streams[i];
      final audioIcon = stream.hasAudio ? '🔊' : '🔇';
      final videoIcon = stream.hasVideo ? '📹' : '🎵';
      
      print('   [$i] $videoIcon$audioIcon ${stream.formatId} - ${stream.resolutionString}');
      print('       格式说明: ${stream.formatNote ?? 'N/A'}');
      print('       比特率: 总=${stream.tbr ?? 'N/A'} 视频=${stream.vbr ?? 'N/A'} 音频=${stream.abr ?? 'N/A'}');
      print('       编解码器: 视频=${stream.vcodec ?? 'N/A'} 音频=${stream.acodec ?? 'N/A'}');
      print('       协议: ${stream.protocol ?? 'N/A'}');
      print('       类型: ${stream.isHls ? 'HLS' : stream.isDash ? 'DASH' : 'Direct'}');
      print('       URL: ${stream.url.substring(0, stream.url.length > 100 ? 100 : stream.url.length)}...');
      print('');
    }
    
    // 4. 质量选项分析
    print('4. 质量选项分析:');
    final qualities = VideoStreamSelector.getQualityOptions(videoStreams);
    print('   质量选项数: ${qualities.length}');
    
    for (int i = 0; i < qualities.length; i++) {
      final quality = qualities[i];
      final audioIcon = quality.hasAudio ? '🔊' : '🔇';
      
      print('   [$i] $audioIcon ${quality.displayName}');
      print('       分辨率: ${quality.resolution}');
      print('       比特率: ${quality.bitrate.toInt()}kbps');
      print('       分组键: ${quality.key}');
      print('       流ID: ${quality.stream.formatId}');
      print('');
    }
    
    // 5. 最佳流选择测试
    print('5. 最佳流选择测试:');
    final bestStream = VideoStreamSelector.selectBestStream(videoStreams);
    
    if (bestStream == null) {
      print('❌ 无法选择最佳流');
    } else {
      final audioIcon = bestStream.hasAudio ? '🔊' : '🔇';
      print('   ✅ 最佳流: $audioIcon ${bestStream.formatId} - ${bestStream.resolutionString}');
      print('      有音频: ${bestStream.hasAudio}');
      print('      比特率: ${bestStream.tbr ?? bestStream.vbr ?? 'N/A'}');
      print('      编解码器: 视频=${bestStream.vcodec} 音频=${bestStream.acodec}');
    }
    print('');
    
    // 6. 音频流专门分析
    print('6. 音频流专门分析:');
    if (audioStreams.isEmpty) {
      print('   ❌ 没有找到任何音频流');
    } else {
      print('   找到 ${audioStreams.length} 个音频流:');
      for (final stream in audioStreams) {
        print('   - ${stream.formatId}: ${stream.acodec} ${stream.abr ?? 'N/A'}kbps');
      }
    }
    print('');
    
    // 7. 建议
    print('7. 建议:');
    if (videoWithAudio.isEmpty) {
      print('   ⚠️  没有找到包含音频的视频流');
      print('   💡 可能需要分别下载视频流和音频流然后合并');
      
      if (videoOnly.isNotEmpty && audioOnly.isNotEmpty) {
        print('   📋 推荐组合:');
        final bestVideo = VideoStreamSelector.selectBestStream(videoOnly);
        final bestAudio = audioOnly.first; // 选择第一个音频流
        
        if (bestVideo != null) {
          print('      视频: ${bestVideo.formatId} (${bestVideo.resolutionString})');
          print('      音频: ${bestAudio.formatId} (${bestAudio.acodec} ${bestAudio.abr}kbps)');
        }
      }
    } else {
      print('   ✅ 找到 ${videoWithAudio.length} 个包含音频的视频流');
      print('   💡 可以直接使用这些流进行播放');
    }
    
  } catch (e, stackTrace) {
    print('❌ 测试失败: $e');
    print('堆栈跟踪: $stackTrace');
    exit(1);
  }
  
  print('');
  print('=== 测试完成 ===');
}
