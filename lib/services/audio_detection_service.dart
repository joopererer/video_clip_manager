import 'yt_dlp_service.dart';

/// 音频检测服务
/// 提供更准确的音频检测功能
class AudioDetectionService {
  /// 为流列表提供音频检测结果的摘要
  static Map<String, dynamic> getAudioDetectionSummary(
    List<VideoStream> streams,
  ) {
    int totalStreams = streams.length;
    int audioStreams = streams.where((s) => s.hasAudio).length;
    int videoStreams = streams.where((s) => s.hasVideo).length;
    int combinedStreams = streams.where((s) => s.hasAudio && s.hasVideo).length;
    int audioOnlyStreams = streams
        .where((s) => s.hasAudio && !s.hasVideo)
        .length;
    int videoOnlyStreams = streams
        .where((s) => !s.hasAudio && s.hasVideo)
        .length;

    return {
      'totalStreams': totalStreams,
      'audioStreams': audioStreams,
      'videoStreams': videoStreams,
      'combinedStreams': combinedStreams,
      'audioOnlyStreams': audioOnlyStreams,
      'videoOnlyStreams': videoOnlyStreams,
      'audioDetectionRate': totalStreams > 0
          ? (audioStreams / totalStreams * 100).toStringAsFixed(1)
          : '0.0',
      'recommendation': _getRecommendation(
        combinedStreams,
        audioOnlyStreams,
        videoOnlyStreams,
      ),
    };
  }

  static String _getRecommendation(int combined, int audioOnly, int videoOnly) {
    if (combined > 0) {
      return 'Found ${combined} combined audio+video streams. Recommended for direct playback.';
    } else if (audioOnly > 0 && videoOnly > 0) {
      return 'Found separate audio (${audioOnly}) and video (${videoOnly}) streams. Use Playlist for combined playback.';
    } else if (videoOnly > 0) {
      return 'Only video streams found (${videoOnly}). No audio available.';
    } else if (audioOnly > 0) {
      return 'Only audio streams found (${audioOnly}). Audio-only content.';
    } else {
      return 'No valid streams detected.';
    }
  }

  /// 获取最佳音频流（用于与视频流配对）
  static VideoStream? getBestAudioStream(List<VideoStream> streams) {
    final audioStreams = streams
        .where((s) => s.hasAudio && !s.hasVideo)
        .toList();

    if (audioStreams.isEmpty) return null;

    // 按音频质量排序
    audioStreams.sort((a, b) {
      // 优先比较音频比特率
      final aAbr = a.abr ?? 0;
      final bAbr = b.abr ?? 0;
      if (aAbr != bAbr) return bAbr.compareTo(aAbr);

      // 其次比较总比特率
      final aTbr = a.tbr ?? 0;
      final bTbr = b.tbr ?? 0;
      return bTbr.compareTo(aTbr);
    });

    return audioStreams.first;
  }

  /// 获取最佳组合流（既有视频又有音频）
  static VideoStream? getBestCombinedStream(List<VideoStream> streams) {
    final combinedStreams = streams
        .where((s) => s.hasAudio && s.hasVideo)
        .toList();

    if (combinedStreams.isEmpty) return null;

    // 过滤掉真正没有音频编解码器的流
    final trueCombinedStreams = combinedStreams
        .where(
          (s) => s.acodec != null && s.acodec!.isNotEmpty && s.acodec != 'none',
        )
        .toList();

    if (trueCombinedStreams.isNotEmpty) {
      return VideoStreamSelector.selectBestStream(trueCombinedStreams);
    }

    // 如果没有真正的组合流，返回null让调用者使用分离流
    return null;
  }
}
