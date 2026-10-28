import 'dart:convert';
import '../data/models.dart';
import '../services/yt_dlp_service.dart';

/// 在线视频缓存管理服务
/// 负责管理视频链接的缓存、过期检测和自动刷新
class OnlineVideoCacheService {
  // 默认链接过期时间（小时）
  static const int _defaultExpirationHours = 6;

  // 不同平台的过期时间配置
  static const Map<String, int> _platformExpirationHours = {
    'youtube': 6, // YouTube 链接通常6小时过期
    'bilibili': 12, // B站链接相对稳定
    'xvideos': 24, // XVideos 链接较长时间有效
    'missav': 4, // MissAV 链接过期较快
  };

  /// 检查视频链接是否过期
  static bool isVideoUrlExpired(OnlineVideo video) {
    final metadata = video.metadata;

    // 检查是否有缓存的视频链接
    if (!metadata.containsKey('videoUrl') ||
        metadata['videoUrl'] == null ||
        metadata['videoUrl'].toString().isEmpty) {
      return true; // 没有缓存链接，需要嗅探
    }

    // 检查时间戳
    if (!metadata.containsKey('urlTimestamp')) {
      return true; // 没有时间戳，认为已过期
    }

    try {
      final timestampStr = metadata['urlTimestamp'] as String;
      final timestamp = DateTime.parse(timestampStr);
      final expirationHours = _getExpirationHours(video.platform);
      final expirationTime = timestamp.add(Duration(hours: expirationHours));

      return DateTime.now().isAfter(expirationTime);
    } catch (e) {
      print('Error parsing timestamp for video ${video.id}: $e');
      return true; // 解析失败，认为已过期
    }
  }

  /// 获取平台特定的过期时间
  static int _getExpirationHours(String platform) {
    return _platformExpirationHours[platform.toLowerCase()] ??
        _defaultExpirationHours;
  }

  /// 检查链接是否即将过期（在30分钟内过期）
  static bool isVideoUrlExpiringSoon(OnlineVideo video) {
    final metadata = video.metadata;

    if (!metadata.containsKey('urlTimestamp')) {
      return false; // 没有时间戳，无法判断
    }

    try {
      final timestampStr = metadata['urlTimestamp'] as String;
      final timestamp = DateTime.parse(timestampStr);
      final expirationHours = _getExpirationHours(video.platform);
      final expirationTime = timestamp.add(Duration(hours: expirationHours));
      final warnTime = expirationTime.subtract(const Duration(minutes: 30));

      return DateTime.now().isAfter(warnTime) &&
          DateTime.now().isBefore(expirationTime);
    } catch (e) {
      return false;
    }
  }

  /// 更新视频链接缓存信息
  static OnlineVideo updateVideoCache({
    required OnlineVideo video,
    required String videoUrl,
    Map<String, String>? httpHeaders,
    List<VideoStream>? allStreams,
    List<StreamQuality>? qualityOptions,
  }) {
    final updatedMetadata = Map<String, dynamic>.from(video.metadata);

    // 更新基础缓存信息
    updatedMetadata['videoUrl'] = videoUrl;
    updatedMetadata['urlTimestamp'] = DateTime.now().toIso8601String();
    updatedMetadata['urlExpirationHours'] = _getExpirationHours(video.platform);

    if (httpHeaders != null) {
      updatedMetadata['httpHeaders'] = httpHeaders;
    }

    // 存储所有流信息（序列化）
    if (allStreams != null && allStreams.isNotEmpty) {
      updatedMetadata['allStreams'] = allStreams
          .map(
            (stream) => {
              'formatId': stream.formatId,
              'url': stream.url,
              'width': stream.width,
              'height': stream.height,
              'fps': stream.fps,
              'vcodec': stream.vcodec,
              'acodec': stream.acodec,
              'tbr': stream.tbr,
              'vbr': stream.vbr,
              'abr': stream.abr,
              'formatNote': stream.formatNote,
              'protocol': stream.protocol,
              'httpHeaders': stream.httpHeaders,
            },
          )
          .toList();
    }

    // 存储质量选项
    if (qualityOptions != null && qualityOptions.isNotEmpty) {
      updatedMetadata['qualityOptions'] = qualityOptions
          .map(
            (quality) => {
              'key': quality.key,
              'displayName': quality.displayName,
              'hasAudio': quality.hasAudio,
              'resolution': quality.resolution,
              'bitrate': quality.bitrate,
              'streamFormatId': quality.stream.formatId, // 关联到流ID
            },
          )
          .toList();
    }

    return video.copyWith(metadata: updatedMetadata);
  }

  /// 从缓存中恢复流信息
  static List<VideoStream>? getCachedStreams(OnlineVideo video) {
    final metadata = video.metadata;

    if (!metadata.containsKey('allStreams')) {
      return null;
    }

    try {
      final streamData = metadata['allStreams'] as List;
      return streamData
          .map(
            (data) => VideoStream(
              formatId: data['formatId']?.toString() ?? '',
              url: data['url']?.toString() ?? '',
              width: data['width'] as int?,
              height: data['height'] as int?,
              fps: data['fps'] as double?,
              vcodec: data['vcodec']?.toString(),
              acodec: data['acodec']?.toString(),
              tbr: data['tbr'] as double?,
              vbr: data['vbr'] as double?,
              abr: data['abr'] as double?,
              formatNote: data['formatNote']?.toString(),
              protocol: data['protocol']?.toString(),
              httpHeaders: data['httpHeaders'] != null
                  ? Map<String, String>.from(data['httpHeaders'])
                  : null,
              rawData: data,
            ),
          )
          .toList();
    } catch (e) {
      print('Error parsing cached streams for video ${video.id}: $e');
      return null;
    }
  }

  /// 从缓存中恢复质量选项
  static List<StreamQuality>? getCachedQualityOptions(OnlineVideo video) {
    final metadata = video.metadata;

    if (!metadata.containsKey('qualityOptions') ||
        !metadata.containsKey('allStreams')) {
      return null;
    }

    try {
      final qualityData = metadata['qualityOptions'] as List;
      final cachedStreams = getCachedStreams(video);

      if (cachedStreams == null) return null;

      return qualityData.map((data) {
        final streamFormatId = data['streamFormatId']?.toString();
        final stream = cachedStreams.firstWhere(
          (s) => s.formatId == streamFormatId,
          orElse: () => cachedStreams.first, // 回退到第一个流
        );

        return StreamQuality(
          key: data['key']?.toString() ?? '',
          displayName: data['displayName']?.toString() ?? '',
          hasAudio: data['hasAudio'] as bool? ?? false,
          resolution: data['resolution']?.toString() ?? '',
          bitrate: (data['bitrate'] as num?)?.toDouble() ?? 0.0,
          stream: stream,
        );
      }).toList();
    } catch (e) {
      print('Error parsing cached quality options for video ${video.id}: $e');
      return null;
    }
  }

  /// 获取缓存状态信息
  static Map<String, dynamic> getCacheStatus(OnlineVideo video) {
    final metadata = video.metadata;
    final isExpired = isVideoUrlExpired(video);
    final isExpiringSoon = isVideoUrlExpiringSoon(video);

    String? timestampStr;
    DateTime? cacheTime;
    Duration? timeUntilExpiration;

    if (metadata.containsKey('urlTimestamp')) {
      try {
        timestampStr = metadata['urlTimestamp'] as String;
        cacheTime = DateTime.parse(timestampStr);
        final expirationHours = _getExpirationHours(video.platform);
        final expirationTime = cacheTime.add(Duration(hours: expirationHours));
        timeUntilExpiration = expirationTime.difference(DateTime.now());
      } catch (e) {
        // 忽略解析错误
      }
    }

    return {
      'hasCache':
          metadata.containsKey('videoUrl') &&
          metadata['videoUrl'] != null &&
          metadata['videoUrl'].toString().isNotEmpty,
      'isExpired': isExpired,
      'isExpiringSoon': isExpiringSoon,
      'cacheTime': cacheTime,
      'timeUntilExpiration': timeUntilExpiration,
      'expirationHours': _getExpirationHours(video.platform),
      'hasStreamsCache': metadata.containsKey('allStreams'),
      'hasQualityOptionsCache': metadata.containsKey('qualityOptions'),
    };
  }
}
