import 'dart:typed_data';
import 'dart:async';
import 'package:media_kit/media_kit.dart';

/// 使用media_kit生成视频预览图的服务
/// 预生成关键帧预览图，避免播放时的卡顿
class PreviewService {
  static final PreviewService _instance = PreviewService._internal();
  factory PreviewService() => _instance;
  PreviewService._internal();

  // 预生成的关键帧预览图缓存
  final Map<String, Map<Duration, Uint8List>> _keyframeCache = {};
  
  // 正在处理的预览请求
  final Set<String> _processingRequests = {};
  
  // 预生成状态
  final Map<String, bool> _preGenerating = {};

  /// 预生成关键帧预览图
  /// [player] 播放器实例
  /// [videoPath] 视频文件路径
  /// [totalDuration] 视频总时长
  Future<void> preGenerateKeyFrames(
    Player player,
    String videoPath,
    Duration totalDuration,
  ) async {
    final cacheKey = _getCacheKey(videoPath);
    
    // 如果已经在预生成或已有缓存，跳过
    if (_preGenerating[cacheKey] == true || _keyframeCache.containsKey(cacheKey)) {
      return;
    }
    
    _preGenerating[cacheKey] = true;
    print('PreviewService: Pre-generating keyframes for $videoPath');
    
    try {
      // 保存当前播放状态
      final wasPlaying = player.state.playing;
      final currentPosition = player.state.position;
      
      // 初始化缓存
      _keyframeCache[cacheKey] = {};
      
      // 生成关键帧时间点（每10秒一个，最多20个）
      final keyframeTimes = <Duration>[];
      final interval = Duration(seconds: 10);
      final maxKeyframes = 20;
      
      for (int i = 0; i < maxKeyframes; i++) {
        final time = Duration(seconds: i * 10);
        if (time >= totalDuration) break;
        keyframeTimes.add(time);
      }
      
      // 为每个关键帧生成预览图
      for (final time in keyframeTimes) {
        try {
          // 暂停播放器
          if (wasPlaying) {
            await player.pause();
          }
          
          // 跳转到关键帧时间
          await player.seek(time);
          await Future.delayed(Duration(milliseconds: 200));
          
          // 生成截图
          final screenshot = await player.screenshot();
          if (screenshot != null) {
            _keyframeCache[cacheKey]![time] = screenshot;
            print('PreviewService: Generated keyframe at $time');
          }
        } catch (e) {
          print('PreviewService: Error generating keyframe at $time: $e');
        }
      }
      
      // 恢复播放状态
      try {
        if (wasPlaying) {
          await player.play();
        } else {
          await player.seek(currentPosition);
        }
      } catch (e) {
        print('PreviewService: Error restoring player state: $e');
      }
      
      print('PreviewService: Pre-generated ${_keyframeCache[cacheKey]!.length} keyframes');
      
    } catch (e) {
      print('PreviewService: Error pre-generating keyframes: $e');
    } finally {
      _preGenerating[cacheKey] = false;
    }
  }

  /// 获取最近的关键帧预览图
  /// [videoPath] 视频文件路径
  /// [time] 目标时间
  Uint8List? getNearestKeyframe(String videoPath, Duration time) {
    final cacheKey = _getCacheKey(videoPath);
    final keyframes = _keyframeCache[cacheKey];
    
    if (keyframes == null || keyframes.isEmpty) {
      return null;
    }
    
    // 找到最近的关键帧
    Duration? nearestTime;
    Duration? minDifference;
    
    for (final keyframeTime in keyframes.keys) {
      final difference = (keyframeTime - time).abs();
      if (minDifference == null || difference < minDifference!) {
        minDifference = difference;
        nearestTime = keyframeTime;
      }
    }
    
    if (nearestTime != null) {
      print('PreviewService: Using keyframe at $nearestTime for time $time (diff: ${minDifference!.inSeconds}s)');
      return keyframes[nearestTime];
    }
    
    return null;
  }

  /// 检查是否有预生成的预览图
  bool hasKeyframes(String videoPath) {
    final cacheKey = _getCacheKey(videoPath);
    return _keyframeCache.containsKey(cacheKey) && _keyframeCache[cacheKey]!.isNotEmpty;
  }

  /// 清除指定视频的缓存
  void clearCache(String videoPath) {
    final cacheKey = _getCacheKey(videoPath);
    _keyframeCache.remove(cacheKey);
    print('PreviewService: Cleared cache for $videoPath');
  }

  /// 清除所有缓存
  void clearAllCache() {
    _keyframeCache.clear();
    print('PreviewService: Cleared all cache');
  }

  /// 获取缓存统计信息
  Map<String, dynamic> getCacheStats() {
    final stats = <String, dynamic>{};
    for (final entry in _keyframeCache.entries) {
      stats[entry.key] = entry.value.length;
    }
    return stats;
  }

  /// 生成缓存键
  String _getCacheKey(String videoPath) {
    return videoPath.hashCode.toString();
  }

  /// 释放资源
  void dispose() {
    _keyframeCache.clear();
    _processingRequests.clear();
    _preGenerating.clear();
    print('PreviewService: Disposed');
  }
}
