import 'dart:typed_data';
import 'dart:async';
import 'dart:io';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart';
import 'dart:convert';

/// 使用media_kit生成视频预览图的服务
/// 预生成关键帧预览图，避免播放时的卡顿
/// 支持本地文件缓存，持久化存储预览图
class PreviewService {
  static final PreviewService _instance = PreviewService._internal();
  factory PreviewService() => _instance;
  
  // 预生成的关键帧预览图缓存（内存）
  final Map<String, Map<Duration, Uint8List>> _keyframeCache = {};
  
  // 正在处理的预览请求
  final Set<String> _processingRequests = {};
  
  // 预生成状态
  final Map<String, bool> _preGenerating = {};
  
  // 全局预生成状态
  bool _globalPreGenerating = false;
  
  // 缓存目录
  Directory? _cacheDir;
  
  // 使用单个播放器实例（类似ThumbnailService）
  final Player _player = Player();
  late final VideoController _videoController;
  String? _currentlyOpenVideoPath;
  
  // 失败重试机制
  final Map<String, int> _failureCount = {}; // 记录每个视频的失败次数
  final Map<String, DateTime> _lastFailureTime = {}; // 记录最后失败时间
  static const int _maxFailures = 3; // 最大失败次数
  static const Duration _failureResetDuration = Duration(hours: 24); // 失败记录重置时间
  
  PreviewService._internal() {
    _videoController = VideoController(_player);
  }
  
  /// 获取VideoController，用于在UI中创建Video widget
  VideoController get videoController => _videoController;
  
  /// 初始化缓存目录
  Future<void> _initCacheDir() async {
    if (_cacheDir != null) return;
    
    final appDir = await getApplicationDocumentsDirectory();
    _cacheDir = Directory(path.join(appDir.path, 'preview_cache'));
    
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
    
    print('PreviewService: Cache directory initialized: ${_cacheDir!.path}');
  }
  
  /// 加载已有的缓存文件到内存（启动时调用）
  Future<void> loadExistingCache() async {
    try {
      await _initCacheDir();
      final files = _cacheDir!.listSync();
      
      print('PreviewService: Loading existing cache files...');
      
      // 按视频路径分组缓存文件
      final videoGroups = <String, List<File>>{};
      
      for (final file in files) {
        if (file is File && file.path.endsWith('.png')) {
          final fileName = path.basename(file.path);
          final parts = fileName.split('_');
          if (parts.length >= 2) {
            final videoHash = parts[0];
            videoGroups.putIfAbsent(videoHash, () => []).add(file);
          }
        }
      }
      
      // 加载每个视频的缓存到内存
      for (final entry in videoGroups.entries) {
        final videoHash = entry.key;
        final cacheFiles = entry.value;
        
        // 创建临时的缓存映射
        final tempCache = <Duration, Uint8List>{};
        
        for (final file in cacheFiles) {
          try {
            final fileName = path.basename(file.path);
            final parts = fileName.split('_');
            if (parts.length >= 2) {
              final timeStr = parts[1].replaceAll('.png', '');
              final timeSeconds = int.tryParse(timeStr);
              if (timeSeconds != null) {
                final time = Duration(seconds: timeSeconds);
                final data = await file.readAsBytes();
                tempCache[time] = data;
              }
            }
          } catch (e) {
            print('PreviewService: Error loading cache file ${file.path}: $e');
          }
        }
        
        if (tempCache.isNotEmpty) {
          // 使用hash作为key，这样getNearestKeyframe和getVideoProgress都能找到
          _keyframeCache[videoHash] = tempCache;
          print('PreviewService: Loaded ${tempCache.length} cached keyframes for hash $videoHash');
        }
      }
      
      print('PreviewService: Cache loading completed');
    } catch (e) {
      print('PreviewService: Error loading existing cache: $e');
    }
  }
  
  /// 生成缓存文件名
  String _getCacheFileName(String videoPath, Duration time) {
    final videoHash = md5.convert(utf8.encode(videoPath)).toString();
    final timeStr = time.inSeconds.toString();
    return '${videoHash}_${timeStr}.png';
  }
  
  /// 保存预览图到本地缓存
  Future<void> _saveToCache(String videoPath, Duration time, Uint8List data) async {
    try {
      await _initCacheDir();
      final fileName = _getCacheFileName(videoPath, time);
      final file = File(path.join(_cacheDir!.path, fileName));
      await file.writeAsBytes(data);
      print('PreviewService: Saved preview to cache: $fileName');
    } catch (e) {
      print('PreviewService: Error saving to cache: $e');
    }
  }
  
  /// 从本地缓存加载预览图
  Future<Uint8List?> _loadFromCache(String videoPath, Duration time) async {
    try {
      await _initCacheDir();
      final fileName = _getCacheFileName(videoPath, time);
      final file = File(path.join(_cacheDir!.path, fileName));
      
      if (await file.exists()) {
        final data = await file.readAsBytes();
        print('PreviewService: Loaded preview from cache: $fileName');
        return data;
      }
    } catch (e) {
      print('PreviewService: Error loading from cache: $e');
    }
    return null;
  }
  
  /// 检查本地缓存中是否有预览图
  Future<bool> _hasCache(String videoPath, Duration time) async {
    try {
      await _initCacheDir();
      final fileName = _getCacheFileName(videoPath, time);
      final file = File(path.join(_cacheDir!.path, fileName));
      return await file.exists();
    } catch (e) {
      return false;
    }
  }

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
    
    // 如果已经在预生成，跳过
    if (_preGenerating[cacheKey] == true) {
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
      
      // 生成关键帧时间点（优化策略：根据视频长度调整间隔）
      final keyframeTimes = <Duration>[];
      final videoLengthMinutes = totalDuration.inMinutes;
      
      // 根据视频长度调整关键帧间隔和数量
      int intervalSeconds;
      int maxKeyframes;
      
      if (videoLengthMinutes <= 5) {
        // 短视频（≤5分钟）：每5秒一个，最多30个
        intervalSeconds = 5;
        maxKeyframes = 30;
      } else if (videoLengthMinutes <= 15) {
        // 中等视频（5-15分钟）：每8秒一个，最多40个
        intervalSeconds = 8;
        maxKeyframes = 40;
      } else if (videoLengthMinutes <= 30) {
        // 长视频（15-30分钟）：每10秒一个，最多50个
        intervalSeconds = 10;
        maxKeyframes = 50;
      } else {
        // 超长视频（>30分钟）：每15秒一个，最多60个
        intervalSeconds = 15;
        maxKeyframes = 60;
      }
      
      print('PreviewService: Video length: ${videoLengthMinutes} minutes, interval: ${intervalSeconds}s, max keyframes: $maxKeyframes');
      
      for (int i = 0; i < maxKeyframes; i++) {
        final time = Duration(seconds: i * intervalSeconds);
        if (time >= totalDuration) break;
        keyframeTimes.add(time);
      }
      
      // 为每个关键帧生成预览图
      for (final time in keyframeTimes) {
        try {
          // 先检查本地缓存
          final cachedData = await _loadFromCache(videoPath, time);
          if (cachedData != null) {
            _keyframeCache[cacheKey]![time] = cachedData;
            print('PreviewService: Loaded keyframe from cache at $time');
            continue;
          }
          
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
            // 保存到本地缓存
            await _saveToCache(videoPath, time, screenshot);
            print('PreviewService: Generated and cached keyframe at $time');
          }
        } catch (e) {
          print('PreviewService: Error generating keyframe at $time: $e');
        }
      }
      
      // 恢复播放状态 - 改进版本
      try {
        // 先跳回原始位置
        await player.seek(currentPosition);
        await Future.delayed(Duration(milliseconds: 100));
        
        // 如果之前是播放状态，恢复播放
        if (wasPlaying) {
          await player.play();
        }
        
        print('PreviewService: Player state restored successfully');
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
  
  /// 检查指定时间点是否有预览图
  Future<bool> hasKeyframeAt(String videoPath, Duration time) async {
    // 先检查内存缓存
    final cacheKey = _getCacheKey(videoPath);
    final keyframes = _keyframeCache[cacheKey];
    if (keyframes != null && keyframes.containsKey(time)) {
      return true;
    }
    
    // 再检查本地缓存
    return await _hasCache(videoPath, time);
  }
  
  /// 获取预览图完成度百分比
  Future<double> getCompletionPercentage(String videoPath, Duration totalDuration) async {
    final cacheKey = _getCacheKey(videoPath);
    final keyframes = _keyframeCache[cacheKey];
    
    if (keyframes == null || keyframes.isEmpty) {
      return 0.0;
    }
    
    // 计算应该有的关键帧数量
    final expectedKeyframes = (totalDuration.inSeconds / 10).ceil();
    final actualKeyframes = keyframes.length;
    
    return (actualKeyframes / expectedKeyframes).clamp(0.0, 1.0);
  }
  
  /// 清除指定视频的缓存
  Future<void> clearCache(String videoPath) async {
    final cacheKey = _getCacheKey(videoPath);
    _keyframeCache.remove(cacheKey);
    
    // 清除本地缓存文件
    try {
      await _initCacheDir();
      final videoHash = md5.convert(utf8.encode(videoPath)).toString();
      final files = _cacheDir!.listSync();
      
      for (final file in files) {
        if (file is File && file.path.contains(videoHash)) {
          await file.delete();
        }
      }
      
      print('PreviewService: Cleared cache for $videoPath');
    } catch (e) {
      print('PreviewService: Error clearing cache: $e');
    }
  }
  
  /// 清除所有缓存
  Future<void> clearAllCache() async {
    _keyframeCache.clear();
    
    try {
      await _initCacheDir();
      final files = _cacheDir!.listSync();
      
      for (final file in files) {
        if (file is File) {
          await file.delete();
        }
      }
      
      print('PreviewService: Cleared all cache');
    } catch (e) {
      print('PreviewService: Error clearing all cache: $e');
    }
  }
  
  /// 获取缓存统计信息
  Future<Map<String, dynamic>> getCacheStats() async {
    final stats = <String, dynamic>{};
    
    // 内存缓存统计
    for (final entry in _keyframeCache.entries) {
      stats[entry.key] = entry.value.length;
    }
    
    // 本地缓存统计
    try {
      await _initCacheDir();
      final files = _cacheDir!.listSync();
      final fileCount = files.where((f) => f is File).length;
      stats['local_files'] = fileCount;
      
      // 计算缓存大小
      int totalSize = 0;
      for (final file in files) {
        if (file is File) {
          totalSize += await file.length();
        }
      }
      stats['total_size_bytes'] = totalSize;
      stats['total_size_mb'] = (totalSize / (1024 * 1024)).toStringAsFixed(2);
    } catch (e) {
      print('PreviewService: Error getting cache stats: $e');
    }
    
    return stats;
  }

  /// 启动全局预生成
  Future<void> startGlobalPreGeneration(List<String> videoPaths) async {
    if (_globalPreGenerating) {
      print('PreviewService: Global pre-generation already running');
      return;
    }
    
    _globalPreGenerating = true;
    print('PreviewService: Starting global pre-generation for ${videoPaths.length} videos');
    print('PreviewService: Video paths: ${videoPaths.map((p) => p.split('/').last).join(', ')}');
    
    try {
      for (int i = 0; i < videoPaths.length; i++) {
        if (!_globalPreGenerating) {
          print('PreviewService: Global pre-generation was interrupted');
          break;
        }
        
        final videoPath = videoPaths[i];
        final videoName = videoPath.split('/').last;
        
        print('PreviewService: Processing video ${i + 1}/${videoPaths.length}: $videoName');
        
        try {
          // 检查是否因为多次失败而被跳过
          final failureInfo = getVideoFailureInfo(videoPath);
          print('PreviewService: Failure info for $videoName: $failureInfo');
          
          if (_isVideoSkipped(videoPath)) {
            print('PreviewService: Skipping $videoName - too many previous failures');
            continue;
          }
          
          // 检查是否已经有足够的缓存
          print('PreviewService: Checking cache for $videoName...');
          final hasCache = await _hasSufficientCache(videoPath);
          print('PreviewService: Cache check result for $videoName: $hasCache');
          
          if (hasCache) {
            print('PreviewService: Skipping $videoName - sufficient cache exists');
            continue;
          }
          
          print('PreviewService: Starting pre-generation for $videoName');
          // 为单个视频预生成（不阻塞UI）
          await _preGenerateForVideo(videoPath);
          
          // 短暂延迟，避免过度占用资源
          await Future.delayed(Duration(milliseconds: 100));
        } catch (e) {
          print('PreviewService: Error pre-generating for $videoName: $e');
          // 记录失败
          _recordFailure(videoPath);
          // 继续处理下一个视频，不要因为一个视频失败而停止整个流程
        }
      }
    } catch (e) {
      print('PreviewService: Error in global pre-generation: $e');
    } finally {
      _globalPreGenerating = false;
      print('PreviewService: Global pre-generation completed');
    }
  }
  
  /// 停止全局预生成
  void stopGlobalPreGeneration() {
    _globalPreGenerating = false;
    print('PreviewService: Global pre-generation stopped');
  }
  
  /// 暂停全局预生成（用于播放时暂停）
  void pauseGlobalPreGeneration() {
    if (_globalPreGenerating) {
      _globalPreGenerating = false;
      print('PreviewService: Global pre-generation paused for playback');
    }
  }
  
  /// 恢复全局预生成（用于播放结束后恢复）
  void resumeGlobalPreGeneration() {
    if (!_globalPreGenerating) {
      print('PreviewService: Global pre-generation resumed');
      // 这里可以重新启动全局预生成
      // 暂时不自动重启，由main_screen控制
    }
  }
  
  /// 检查视频是否有足够的缓存
  Future<bool> _hasSufficientCache(String videoPath) async {
    try {
      print('PreviewService: _hasSufficientCache - checking for $videoPath');
      await _initCacheDir();
      final videoHash = md5.convert(utf8.encode(videoPath)).toString();
      print('PreviewService: _hasSufficientCache - video hash: $videoHash');
      
      final files = _cacheDir!.listSync();
      print('PreviewService: _hasSufficientCache - total files in cache: ${files.length}');
      
      // 计算该视频的缓存文件数量
      int cacheCount = 0;
      for (final file in files) {
        if (file is File && file.path.contains(videoHash)) {
          cacheCount++;
          print('PreviewService: _hasSufficientCache - found cache file: ${file.path.split('/').last}');
        }
      }
      
      print('PreviewService: _hasSufficientCache - cache count for $videoPath: $cacheCount');
      
      // 如果缓存数量超过10个，认为足够
      final result = cacheCount >= 10;
      print('PreviewService: _hasSufficientCache - result: $result (need >= 10, have $cacheCount)');
      return result;
    } catch (e) {
      print('PreviewService: _hasSufficientCache - error: $e');
      return false;
    }
  }
  
    /// 为单个视频预生成（后台执行）
  Future<void> _preGenerateForVideo(String videoPath) async {
    final cacheKey = _getCacheKey(videoPath);
    final videoName = videoPath.split('/').last;
    
    if (_preGenerating[cacheKey] == true) {
      print('PreviewService: Already pre-generating for $videoName');
      return;
    }
    
    _preGenerating[cacheKey] = true;
    print('PreviewService: Starting pre-generation for video: $videoName');
    
    try {
      // 检查文件是否存在
      final videoFile = File(videoPath);
      if (!await videoFile.exists()) {
        print('PreviewService: Video file does not exist: $videoPath');
        _recordFailure(videoPath);
        return;
      }
      
      // 检查文件大小
      final fileSize = await videoFile.length();
      if (fileSize == 0) {
        print('PreviewService: Video file is empty: $videoPath');
        _recordFailure(videoPath);
        return;
      }
      
      print('PreviewService: Video file size: ${(fileSize / (1024 * 1024)).toStringAsFixed(2)} MB');
      
      // 使用与ThumbnailService相同的模式
      if (_currentlyOpenVideoPath != videoPath) {
        print('PreviewService: Opening video: $videoName');
        
        try {
          await _player.open(Media(videoPath), play: false);
          _currentlyOpenVideoPath = videoPath;
          
          // 等待播放器初始化，使用与ThumbnailService相同的超时时间
          await _player.stream.buffer
              .firstWhere((e) => e > Duration.zero)
              .timeout(const Duration(seconds: 15)); // 与ThumbnailService一致
          await Future.delayed(const Duration(milliseconds: 500)); // 与ThumbnailService一致
        } catch (e) {
          print('PreviewService: Error opening video $videoName: $e');
          _currentlyOpenVideoPath = null; // 重置状态
          _recordFailure(videoPath);
          return;
        }
      }
      
      final duration = _player.state.duration;
      print('PreviewService: Video duration: ${duration.inSeconds} seconds');
      
      if (duration == Duration.zero) {
        print('PreviewService: Failed to get duration for $videoName - duration is zero');
        _currentlyOpenVideoPath = null; // 重置状态
        _recordFailure(videoPath);
        return;
      }
      
      // 初始化缓存
      _keyframeCache[cacheKey] = {};
      
      // 生成关键帧时间点（优化策略：根据视频长度调整间隔）
      final keyframeTimes = <Duration>[];
      final videoLengthMinutes = duration.inMinutes;
      
      // 根据视频长度调整关键帧间隔和数量
      int intervalSeconds;
      int maxKeyframes;
      
      if (videoLengthMinutes <= 5) {
        // 短视频（≤5分钟）：每5秒一个，最多30个
        intervalSeconds = 5;
        maxKeyframes = 30;
      } else if (videoLengthMinutes <= 15) {
        // 中等视频（5-15分钟）：每8秒一个，最多40个
        intervalSeconds = 8;
        maxKeyframes = 40;
      } else if (videoLengthMinutes <= 30) {
        // 长视频（15-30分钟）：每10秒一个，最多50个
        intervalSeconds = 10;
        maxKeyframes = 50;
      } else {
        // 超长视频（>30分钟）：每15秒一个，最多60个
        intervalSeconds = 15;
        maxKeyframes = 60;
      }
      
      print('PreviewService: Video length: ${videoLengthMinutes} minutes, interval: ${intervalSeconds}s, max keyframes: $maxKeyframes');
      
      for (int i = 0; i < maxKeyframes; i++) {
        final time = Duration(seconds: i * intervalSeconds);
        if (time >= duration) break;
        keyframeTimes.add(time);
      }
      
      print('PreviewService: Will generate ${keyframeTimes.length} keyframes for $videoName');
      
      // 为每个关键帧生成预览图
      for (int i = 0; i < keyframeTimes.length; i++) {
        if (!_globalPreGenerating) {
          print('PreviewService: Pre-generation interrupted for $videoName');
          break;
        }
        
        final time = keyframeTimes[i];
        final progress = ((i + 1) / keyframeTimes.length * 100).toStringAsFixed(1);
        
        print('PreviewService: Generating keyframe ${i + 1}/${keyframeTimes.length} (${progress}%) at ${time.inSeconds}s for $videoName');
        
        try {
          // 先检查本地缓存
          final cachedData = await _loadFromCache(videoPath, time);
          if (cachedData != null) {
            _keyframeCache[cacheKey]![time] = cachedData;
            print('PreviewService: Using cached keyframe at ${time.inSeconds}s for $videoName');
            continue;
          }
          
          // 跳转到关键帧时间（使用与ThumbnailService相同的模式）
          await _player.seek(time);
          await Future.delayed(const Duration(milliseconds: 500)); // 与ThumbnailService一致
          
          // 生成截图
          final screenshot = await _player.screenshot();
          if (screenshot != null) {
            _keyframeCache[cacheKey]![time] = screenshot;
            // 保存到本地缓存
            await _saveToCache(videoPath, time, screenshot);
            print('PreviewService: Generated keyframe at ${time.inSeconds}s for $videoName');
          } else {
            print('PreviewService: Failed to generate screenshot at ${time.inSeconds}s for $videoName');
            // 如果截图失败，记录为失败
            _recordFailure(videoPath);
            print('PreviewService: Recorded failure for $videoName due to screenshot failure, failure count: ${_failureCount[cacheKey]}');
            break; // 如果截图失败，停止生成更多关键帧
          }
        } catch (e) {
          print('PreviewService: Error generating keyframe at ${time.inSeconds}s for $videoName: $e');
          // 记录失败
          _recordFailure(videoPath);
          print('PreviewService: Recorded failure for $videoName due to keyframe error, failure count: ${_failureCount[cacheKey]}');
          break; // 如果出错，停止生成更多关键帧
        }
      }
      
      print('PreviewService: Completed pre-generation for $videoName - ${_keyframeCache[cacheKey]!.length} keyframes generated');
      
      // 记录成功生成
      _recordSuccess(videoPath);
      
    } catch (e) {
      print('PreviewService: Error pre-generating for $videoName: $e');
      _currentlyOpenVideoPath = null; // 重置，下次重新打开
      
      // 记录失败
      _recordFailure(videoPath);
      print('PreviewService: Recorded failure for $videoName, failure count: ${_failureCount[cacheKey]}');
    } finally {
      _preGenerating[cacheKey] = false;
    }
  }

  /// 生成缓存键
  String _getCacheKey(String videoPath) {
    // 使用MD5哈希作为缓存键，确保一致性
    return md5.convert(utf8.encode(videoPath)).toString();
  }

  /// 获取视频的预览生成进度
  Future<double> getVideoProgress(String videoPath) async {
    try {
      print('PreviewService: getVideoProgress - checking for $videoPath');
      await _initCacheDir();
      final videoHash = md5.convert(utf8.encode(videoPath)).toString();
      print('PreviewService: getVideoProgress - video hash: $videoHash');
      
      // 首先检查内存缓存
      final cacheKey = _getCacheKey(videoPath);
      final memoryKeyframes = _keyframeCache[cacheKey];
      int memoryCount = memoryKeyframes?.length ?? 0;
      
      // 然后检查文件缓存
      final files = _cacheDir!.listSync();
      print('PreviewService: getVideoProgress - total files in cache: ${files.length}');
      
      // 计算该视频的缓存文件数量
      int fileCount = 0;
      for (final file in files) {
        if (file is File && file.path.contains(videoHash)) {
          fileCount++;
          print('PreviewService: getVideoProgress - found cache file: ${file.path.split('/').last}');
        }
      }
      
      // 使用较大的数量作为实际缓存数量
      final actualCacheCount = memoryCount > fileCount ? memoryCount : fileCount;
      
      print('PreviewService: getVideoProgress - memory count: $memoryCount, file count: $fileCount, using: $actualCacheCount');
      
      // 如果正在生成中，显示更高的进度
      final isGenerating = _preGenerating[cacheKey] == true;
      
      // 如果有关键帧数据，直接计算进度
      if (memoryKeyframes != null && memoryKeyframes.isNotEmpty) {
        // 从已生成的关键帧时间推断视频时长和应该生成的数量
        final lastKeyframeTime = memoryKeyframes.keys.reduce((a, b) => a > b ? a : b);
        final videoLengthMinutes = lastKeyframeTime.inMinutes;
        
        // 根据视频长度计算应该生成的关键帧数量（与生成策略一致）
        int expectedKeyframes;
        if (videoLengthMinutes <= 5) {
          // 短视频：每5秒一个，最多30个
          expectedKeyframes = (lastKeyframeTime.inSeconds / 5).ceil().clamp(1, 30);
        } else if (videoLengthMinutes <= 15) {
          // 中等视频：每8秒一个，最多40个
          expectedKeyframes = (lastKeyframeTime.inSeconds / 8).ceil().clamp(1, 40);
        } else if (videoLengthMinutes <= 30) {
          // 长视频：每10秒一个，最多50个
          expectedKeyframes = (lastKeyframeTime.inSeconds / 10).ceil().clamp(1, 50);
        } else {
          // 超长视频：每15秒一个，最多60个
          expectedKeyframes = (lastKeyframeTime.inSeconds / 15).ceil().clamp(1, 60);
        }
        
        double progress;
        if (isGenerating && actualCacheCount > 0) {
          // 如果正在生成且有缓存，显示更高的进度
          progress = (actualCacheCount / expectedKeyframes).clamp(0.0, 0.95); // 最高95%，表示正在生成
        } else {
          progress = actualCacheCount / expectedKeyframes;
        }
        
        final clampedProgress = progress.clamp(0.0, 1.0);
        
        print('PreviewService: getVideoProgress - progress: ${(clampedProgress * 100).toStringAsFixed(1)}% ($actualCacheCount/$expectedKeyframes, generating: $isGenerating)');
        return clampedProgress;
      } else if (fileCount > 0) {
        // 如果内存中没有数据，但有文件缓存，基于文件数量估算
        final estimatedDurationSeconds = fileCount * 10; // 假设平均10秒间隔
        final estimatedMinutes = estimatedDurationSeconds / 60;
        
        int expectedKeyframes;
        if (estimatedMinutes <= 5) {
          expectedKeyframes = (estimatedDurationSeconds / 5).ceil().clamp(1, 30);
        } else if (estimatedMinutes <= 15) {
          expectedKeyframes = (estimatedDurationSeconds / 8).ceil().clamp(1, 40);
        } else if (estimatedMinutes <= 30) {
          expectedKeyframes = (estimatedDurationSeconds / 10).ceil().clamp(1, 50);
        } else {
          expectedKeyframes = (estimatedDurationSeconds / 15).ceil().clamp(1, 60);
        }
        
        final progress = actualCacheCount / expectedKeyframes;
        final clampedProgress = progress.clamp(0.0, 1.0);
        
        print('PreviewService: getVideoProgress - progress: ${(clampedProgress * 100).toStringAsFixed(1)}% ($actualCacheCount/$expectedKeyframes, from file cache)');
        return clampedProgress;
      } else {
        // 如果没有任何缓存信息，返回0
        print('PreviewService: getVideoProgress - no cache found, returning 0%');
        return 0.0;
      }
    } catch (e) {
      print('PreviewService: getVideoProgress - error: $e');
      return 0.0;
    }
  }

  /// 获取视频的预览生成状态
  Future<String> getVideoStatus(String videoPath) async {
    final cacheKey = _getCacheKey(videoPath);
    final isGenerating = _preGenerating[cacheKey] == true;
    final progress = await getVideoProgress(videoPath);
    
    // 检查是否因为多次失败而被跳过
    if (_isVideoSkipped(videoPath)) {
      final failureInfo = getVideoFailureInfo(videoPath);
      final timeUntilReset = failureInfo['timeUntilReset'] as Duration;
      final hoursUntilReset = timeUntilReset.inHours;
      final minutesUntilReset = (timeUntilReset.inMinutes % 60);
      
      if (hoursUntilReset > 0) {
        return '生成失败，${hoursUntilReset}小时${minutesUntilReset}分钟后重试';
      } else {
        return '生成失败，${minutesUntilReset}分钟后重试';
      }
    }
    
    if (isGenerating) {
      return '生成中... ${(progress * 100).toStringAsFixed(0)}%';
    } else if (progress >= 0.8) {
      return '已完成';
    } else if (progress >= 0.3) {
      return '部分完成 ${(progress * 100).toStringAsFixed(0)}%';
    } else {
      return '未生成';
    }
  }

  /// 释放资源
  void dispose() {
    _keyframeCache.clear();
    _processingRequests.clear();
    _preGenerating.clear();
    _player.dispose();
    print('PreviewService: Disposed');
  }

  /// 检查视频是否因为多次失败而被跳过
  bool _isVideoSkipped(String videoPath) {
    final cacheKey = _getCacheKey(videoPath);
    final failureCount = _failureCount[cacheKey] ?? 0;
    final lastFailure = _lastFailureTime[cacheKey];
    
    print('PreviewService: _isVideoSkipped - checking $videoPath, failureCount: $failureCount, maxFailures: $_maxFailures');
    
    // 如果失败次数超过限制
    if (failureCount >= _maxFailures) {
      // 检查是否已经过了重置时间
      if (lastFailure != null && DateTime.now().difference(lastFailure) > _failureResetDuration) {
        // 重置失败记录
        _failureCount.remove(cacheKey);
        _lastFailureTime.remove(cacheKey);
        print('PreviewService: Reset failure count for $videoPath after ${_failureResetDuration.inHours} hours');
        return false;
      }
      
      print('PreviewService: Skipping $videoPath due to ${failureCount} previous failures');
      return true;
    }
    
    print('PreviewService: Not skipping $videoPath (failureCount: $failureCount < $_maxFailures)');
    return false;
  }
  
  /// 记录视频生成失败
  void _recordFailure(String videoPath) {
    final cacheKey = _getCacheKey(videoPath);
    final currentCount = _failureCount[cacheKey] ?? 0;
    _failureCount[cacheKey] = currentCount + 1;
    _lastFailureTime[cacheKey] = DateTime.now();
    
    print('PreviewService: Recorded failure for $videoPath (count: ${currentCount + 1}/${_maxFailures})');
    print('PreviewService: Current failure records: ${getAllFailureInfo()}');
  }
  
  /// 记录视频生成成功（重置失败计数）
  void _recordSuccess(String videoPath) {
    final cacheKey = _getCacheKey(videoPath);
    if (_failureCount.containsKey(cacheKey)) {
      _failureCount.remove(cacheKey);
      _lastFailureTime.remove(cacheKey);
      print('PreviewService: Reset failure count for $videoPath after successful generation');
    }
  }
  
  /// 获取视频的失败状态信息
  Map<String, dynamic> getVideoFailureInfo(String videoPath) {
    final cacheKey = _getCacheKey(videoPath);
    final failureCount = _failureCount[cacheKey] ?? 0;
    final lastFailure = _lastFailureTime[cacheKey];
    
    return {
      'failureCount': failureCount,
      'isSkipped': _isVideoSkipped(videoPath),
      'lastFailureTime': lastFailure?.toIso8601String(),
      'timeUntilReset': lastFailure != null 
          ? _failureResetDuration - DateTime.now().difference(lastFailure)
          : Duration.zero,
    };
  }
  
  /// 获取所有失败记录（调试用）
  Map<String, dynamic> getAllFailureInfo() {
    final result = <String, dynamic>{};
    for (final entry in _failureCount.entries) {
      final videoHash = entry.key;
      final failureCount = entry.value;
      final lastFailure = _lastFailureTime[videoHash];
      
      result[videoHash] = {
        'failureCount': failureCount,
        'lastFailureTime': lastFailure?.toIso8601String(),
        'timeUntilReset': lastFailure != null 
            ? _failureResetDuration - DateTime.now().difference(lastFailure)
            : Duration.zero,
      };
    }
    return result;
  }
  
  /// 手动重置某个视频的失败记录（调试用）
  void resetFailureRecord(String videoPath) {
    final cacheKey = _getCacheKey(videoPath);
    _failureCount.remove(cacheKey);
    _lastFailureTime.remove(cacheKey);
    print('PreviewService: Manually reset failure record for $videoPath');
  }
}
