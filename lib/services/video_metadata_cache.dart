import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 视频元数据处理状态
class VideoMetadataStatus {
  final DateTime lastAttempt;
  final bool isSuccess;
  final String? error;
  final int retryCount;
  final Duration? duration;
  final String? thumbnailPath;

  VideoMetadataStatus({
    required this.lastAttempt,
    required this.isSuccess,
    this.error,
    this.retryCount = 0,
    this.duration,
    this.thumbnailPath,
  });

  Map<String, dynamic> toJson() {
    return {
      'lastAttempt': lastAttempt.toIso8601String(),
      'isSuccess': isSuccess,
      'error': error,
      'retryCount': retryCount,
      'duration': duration?.inMilliseconds,
      'thumbnailPath': thumbnailPath,
    };
  }

  factory VideoMetadataStatus.fromJson(Map<String, dynamic> json) {
    return VideoMetadataStatus(
      lastAttempt: DateTime.parse(json['lastAttempt']),
      isSuccess: json['isSuccess'] ?? false,
      error: json['error'],
      retryCount: json['retryCount'] ?? 0,
      duration: json['duration'] != null 
          ? Duration(milliseconds: json['duration'])
          : null,
      thumbnailPath: json['thumbnailPath'],
    );
  }

  VideoMetadataStatus copyWith({
    DateTime? lastAttempt,
    bool? isSuccess,
    String? error,
    int? retryCount,
    Duration? duration,
    String? thumbnailPath,
  }) {
    return VideoMetadataStatus(
      lastAttempt: lastAttempt ?? this.lastAttempt,
      isSuccess: isSuccess ?? this.isSuccess,
      error: error ?? this.error,
      retryCount: retryCount ?? this.retryCount,
      duration: duration ?? this.duration,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    );
  }
}

/// 视频元数据缓存管理类
class VideoMetadataCache {
  static const String _cacheKey = 'video_metadata_cache';
  static const Duration _successCacheDuration = Duration(hours: 24);
  static const Duration _initialRetryDelay = Duration(minutes: 1);
  static const int _maxRetryCount = 5;

  Map<String, VideoMetadataStatus> _cache = {};
  bool _isLoaded = false;

  /// 检查视频是否需要处理
  bool shouldProcessVideo(String videoId, String videoPath) {
    _ensureLoaded();
    
    final status = _cache[videoId];
    if (status == null) {
      debugPrint('VideoMetadataCache: No cache entry for $videoId, should process');
      return true;
    }

    // 如果上次成功，且时间间隔足够，跳过
    if (status.isSuccess && _isRecentEnough(status.lastAttempt)) {
      debugPrint('VideoMetadataCache: $videoId recently processed successfully, skipping');
      return false;
    }

    // 如果上次失败，检查重试间隔
    if (!status.isSuccess && _shouldRetry(status)) {
      debugPrint('VideoMetadataCache: $videoId should retry (attempt ${status.retryCount + 1})');
      return true;
    }

    // 如果重试次数过多，跳过
    if (status.retryCount >= _maxRetryCount) {
      debugPrint('VideoMetadataCache: $videoId exceeded max retry count, skipping');
      return false;
    }

    debugPrint('VideoMetadataCache: $videoId should not process now');
    return false;
  }

  /// 记录处理结果
  Future<void> recordResult(
    String videoId, 
    bool success, 
    {String? error, Duration? duration, String? thumbnailPath}
  ) async {
    _ensureLoaded();
    
    final currentStatus = _cache[videoId];
    final newRetryCount = success ? 0 : (currentStatus?.retryCount ?? 0) + 1;
    
    _cache[videoId] = VideoMetadataStatus(
      lastAttempt: DateTime.now(),
      isSuccess: success,
      error: error,
      retryCount: newRetryCount,
      duration: duration,
      thumbnailPath: thumbnailPath,
    );

    await _saveCache();
    
    debugPrint('VideoMetadataCache: Recorded result for $videoId - success: $success, retryCount: $newRetryCount');
  }

  /// 获取视频的处理状态
  VideoMetadataStatus? getStatus(String videoId) {
    _ensureLoaded();
    return _cache[videoId];
  }

  /// 获取所有需要重试的视频
  List<String> getVideosToRetry() {
    _ensureLoaded();
    return _cache.entries
        .where((entry) => !entry.value.isSuccess && _shouldRetry(entry.value))
        .map((entry) => entry.key)
        .toList();
  }

  /// 获取所有失败次数过多的视频
  List<String> getFailedVideos() {
    _ensureLoaded();
    return _cache.entries
        .where((entry) => entry.value.retryCount >= _maxRetryCount)
        .map((entry) => entry.key)
        .toList();
  }

  /// 清除所有缓存
  Future<void> clearCache() async {
    _cache.clear();
    await _saveCache();
    debugPrint('VideoMetadataCache: Cache cleared');
  }

  /// 强制重新处理所有视频
  Future<void> forceReprocessAll() async {
    _ensureLoaded();
    for (final entry in _cache.entries) {
      _cache[entry.key] = entry.value.copyWith(
        lastAttempt: DateTime.now().subtract(_successCacheDuration),
        retryCount: 0,
      );
    }
    await _saveCache();
    debugPrint('VideoMetadataCache: Force reprocess all videos');
  }

  /// 强制重新处理失败的视频
  Future<void> forceReprocessFailed() async {
    _ensureLoaded();
    for (final entry in _cache.entries) {
      if (!entry.value.isSuccess) {
        _cache[entry.key] = entry.value.copyWith(
          lastAttempt: DateTime.now().subtract(_successCacheDuration),
          retryCount: 0,
        );
      }
    }
    await _saveCache();
    debugPrint('VideoMetadataCache: Force reprocess failed videos');
  }

  /// 检查是否应该重试
  bool _shouldRetry(VideoMetadataStatus status) {
    if (status.retryCount >= _maxRetryCount) return false;
    
    final delay = _getRetryDelay(status.retryCount);
    final timeSinceLastAttempt = DateTime.now().difference(status.lastAttempt);
    
    return timeSinceLastAttempt >= delay;
  }

  /// 获取重试延迟时间（指数退避）
  Duration _getRetryDelay(int retryCount) {
    final baseDelay = _initialRetryDelay.inMinutes;
    final delayMinutes = baseDelay * (1 << retryCount); // 指数退避
    return Duration(minutes: delayMinutes);
  }

  /// 检查是否在有效期内
  bool _isRecentEnough(DateTime lastAttempt) {
    final timeSinceLastAttempt = DateTime.now().difference(lastAttempt);
    return timeSinceLastAttempt < _successCacheDuration;
  }

  /// 确保缓存已加载
  void _ensureLoaded() {
    if (!_isLoaded) {
      _loadCache();
    }
  }

  /// 加载缓存
  void _loadCache() {
    try {
      final prefs = SharedPreferences.getInstance();
      prefs.then((prefs) {
        final cacheJson = prefs.getString(_cacheKey);
        if (cacheJson != null) {
          final cacheMap = json.decode(cacheJson) as Map<String, dynamic>;
          _cache = cacheMap.map((key, value) => MapEntry(
            key, 
            VideoMetadataStatus.fromJson(value as Map<String, dynamic>)
          ));
          debugPrint('VideoMetadataCache: Loaded ${_cache.length} cache entries');
        }
        _isLoaded = true;
      });
    } catch (e) {
      debugPrint('VideoMetadataCache: Error loading cache: $e');
      _cache = {};
      _isLoaded = true;
    }
  }

  /// 保存缓存
  Future<void> _saveCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = json.encode(_cache.map((key, value) => MapEntry(key, value.toJson())));
      await prefs.setString(_cacheKey, cacheJson);
      debugPrint('VideoMetadataCache: Saved ${_cache.length} cache entries');
    } catch (e) {
      debugPrint('VideoMetadataCache: Error saving cache: $e');
    }
  }
} 