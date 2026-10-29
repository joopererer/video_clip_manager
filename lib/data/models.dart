import 'package:equatable/equatable.dart';

class VideoClip extends Equatable {
  final String id;
  final String name;
  final String videoPath;
  final Duration startTime;
  final Duration endTime;
  final Duration coverFrameTime;
  final List<String> tags;
  final String? notes;
  final int rating;
  final bool isFavorite;
  final String? thumbnailPath;
  final String? aiSummary;
  final String? aiScene;
  final List<String> aiActions;
  final int? hitTimestampMs;

  const VideoClip({
    required this.id,
    this.name = '',
    required this.videoPath,
    this.startTime = Duration.zero,
    this.endTime = Duration.zero,
    this.coverFrameTime = Duration.zero,
    this.tags = const [],
    this.notes,
    this.rating = 0,
    this.isFavorite = false,
    this.thumbnailPath,
    this.aiSummary,
    this.aiScene,
    this.aiActions = const [],
    this.hitTimestampMs,
  });

  factory VideoClip.fromJson(Map<String, dynamic> json) {
    final startTime = Duration(milliseconds: json['start'] ?? 0);
    return VideoClip(
      id:
          json['id'] ??
          'clip_${DateTime.now().millisecondsSinceEpoch}_${json['videoPath']?.hashCode}',
      name: json['label'] ?? json['name'] ?? 'Untitled Clip',
      videoPath: json['videoPath'] ?? '',
      startTime: startTime,
      endTime: Duration(milliseconds: json['end'] ?? 0),
      coverFrameTime: Duration(
        milliseconds: json['coverFrameTime'] ?? startTime.inMilliseconds,
      ),
      tags: List<String>.from(json['tags'] ?? []),
      notes: json['notes'] ?? json['note'],
      rating: json['rating'] ?? 0,
      isFavorite: json['isFavorite'] ?? false,
      thumbnailPath: json['thumbnailPath'],
      aiSummary: json['aiSummary'] as String?,
      aiScene: json['aiScene'] as String?,
      aiActions: List<String>.from(json['aiActions'] ?? []),
      hitTimestampMs: json['hitTimestampMs'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'videoPath': videoPath,
      'start': startTime.inMilliseconds,
      'end': endTime.inMilliseconds,
      'coverFrameTime': coverFrameTime.inMilliseconds,
      'tags': tags,
      'notes': notes,
      'rating': rating,
      'isFavorite': isFavorite,
      'thumbnailPath': thumbnailPath,
      'aiSummary': aiSummary,
      'aiScene': aiScene,
      'aiActions': aiActions,
      'hitTimestampMs': hitTimestampMs,
    };
  }

  VideoClip copyWith({
    String? id,
    String? name,
    String? videoPath,
    Duration? startTime,
    Duration? endTime,
    Duration? coverFrameTime,
    List<String>? tags,
    String? notes,
    int? rating,
    bool? isFavorite,
    String? thumbnailPath,
    String? aiSummary,
    String? aiScene,
    List<String>? aiActions,
    int? hitTimestampMs,
  }) {
    // Return a new instance, handling nullable values for notes and thumbnailPath
    return VideoClip(
      id: id ?? this.id,
      name: name ?? this.name,
      videoPath: videoPath ?? this.videoPath,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      coverFrameTime: coverFrameTime ?? this.coverFrameTime,
      tags: tags ?? this.tags,
      notes: notes ?? this.notes,
      rating: rating ?? this.rating,
      isFavorite: isFavorite ?? this.isFavorite,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      aiSummary: aiSummary ?? this.aiSummary,
      aiScene: aiScene ?? this.aiScene,
      aiActions: aiActions ?? this.aiActions,
      hitTimestampMs: hitTimestampMs ?? this.hitTimestampMs,
    );
  }

  /// A copy without the transient semantic HIT timestamp.
  ///
  /// HIT is a view-only artifact of the current semantic search result set; it
  /// must never be written back to the user database, otherwise an old search
  /// keeps showing a HIT marker after the query changed or the app restarted.
  VideoClip withoutSemanticHit() => VideoClip(
    id: id,
    name: name,
    videoPath: videoPath,
    startTime: startTime,
    endTime: endTime,
    coverFrameTime: coverFrameTime,
    tags: tags,
    notes: notes,
    rating: rating,
    isFavorite: isFavorite,
    thumbnailPath: thumbnailPath,
    aiSummary: aiSummary,
    aiScene: aiScene,
    aiActions: aiActions,
  );

  @override
  List<Object?> get props => [
    id,
    name,
    videoPath,
    startTime,
    endTime,
    coverFrameTime,
    tags,
    notes,
    rating,
    isFavorite,
    thumbnailPath,
    aiSummary,
    aiScene,
    aiActions,
    hitTimestampMs,
  ];
}

class OriginalVideo extends Equatable {
  final String id;
  final String path;
  final String name;
  final Duration? duration;
  final String? thumbnailPath;

  const OriginalVideo({
    required this.id,
    required this.path,
    required this.name,
    this.duration,
    this.thumbnailPath,
  });

  OriginalVideo copyWith({
    String? id,
    String? path,
    String? name,
    Duration? duration,
    String? thumbnailPath,
  }) {
    return OriginalVideo(
      id: id ?? this.id,
      path: path ?? this.path,
      name: name ?? this.name,
      duration: duration ?? this.duration,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'path': path,
      'name': name,
      'duration': duration?.inMilliseconds,
      'thumbnailPath': thumbnailPath,
    };
  }

  factory OriginalVideo.fromJson(Map<String, dynamic> json) {
    return OriginalVideo(
      id: json['id'] ?? 'vid_${json['path']?.hashCode}',
      path: json['path'] ?? '',
      name: json['name'] ?? '',
      duration: json['duration'] != null
          ? Duration(milliseconds: json['duration'])
          : null,
      thumbnailPath: json['thumbnailPath'],
    );
  }

  @override
  List<Object?> get props => [id, path, name, duration, thumbnailPath];
}

class Playlist extends Equatable {
  final String id;
  final String name;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<PlaylistItem> items;

  const Playlist({
    required this.id,
    required this.name,
    this.description,
    required this.createdAt,
    required this.updatedAt,
    this.items = const [],
  });

  /// 计算播放列表的总时长
  Duration get totalDuration {
    return items.fold<Duration>(
      Duration.zero,
      (total, item) => total + (item.duration ?? Duration.zero),
    );
  }

  /// 获取播放列表中的 clip 数量
  int get clipCount => items.length;

  factory Playlist.create({required String name, String? description}) {
    final now = DateTime.now();
    return Playlist(
      id: 'playlist_${now.millisecondsSinceEpoch}',
      name: name,
      description: description,
      createdAt: now,
      updatedAt: now,
    );
  }

  Playlist copyWith({
    String? id,
    String? name,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<PlaylistItem>? items,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      items: items ?? this.items,
    );
  }

  Playlist removeItem(String itemId) {
    final newItems = items.where((item) => item.id != itemId).toList();
    for (int i = 0; i < newItems.length; i++) {
      newItems[i] = newItems[i].copyWith(order: i);
    }
    return copyWith(items: newItems, updatedAt: DateTime.now());
  }

  Playlist reorderItems(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex -= 1;
    final newItems = List<PlaylistItem>.from(items);
    final item = newItems.removeAt(oldIndex);
    newItems.insert(newIndex, item);
    for (int i = 0; i < newItems.length; i++) {
      newItems[i] = newItems[i].copyWith(order: i);
    }
    return copyWith(items: newItems, updatedAt: DateTime.now());
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'items': items.map((item) => item.toJson()).toList(),
    };
  }

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] ?? 0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] ?? 0),
      items:
          (json['items'] as List<dynamic>?)
              ?.map((item) => PlaylistItem.fromJson(item))
              .toList() ??
          [],
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    description,
    createdAt,
    updatedAt,
    items,
  ];
}

class PlaylistItem extends Equatable {
  final String id;
  final String clipId;
  final int order;
  final Duration? customStartTime;
  final Duration? customEndTime;
  final Duration? duration; // 缓存时长，避免重复计算

  const PlaylistItem({
    required this.id,
    required this.clipId,
    required this.order,
    this.customStartTime,
    this.customEndTime,
    this.duration,
  });

  Duration getDuration(VideoClip clip) {
    if (customStartTime != null && customEndTime != null) {
      return customEndTime! - customStartTime!;
    }
    return clip.endTime - clip.startTime;
  }

  factory PlaylistItem.fromClip(VideoClip clip, int order) {
    return PlaylistItem(
      id: 'item_${DateTime.now().millisecondsSinceEpoch}',
      clipId: clip.id,
      order: order,
      customStartTime: clip.startTime,
      customEndTime: clip.endTime,
      duration: clip.endTime - clip.startTime,
    );
  }

  PlaylistItem copyWith({
    String? id,
    String? clipId,
    int? order,
    Duration? customStartTime,
    Duration? customEndTime,
    Duration? duration,
  }) {
    return PlaylistItem(
      id: id ?? this.id,
      clipId: clipId ?? this.clipId,
      order: order ?? this.order,
      customStartTime: customStartTime ?? this.customStartTime,
      customEndTime: customEndTime ?? this.customEndTime,
      duration: duration ?? this.duration,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'clipId': clipId,
      'order': order,
      'customStartTime': customStartTime?.inMilliseconds,
      'customEndTime': customEndTime?.inMilliseconds,
      'duration': duration?.inMilliseconds,
    };
  }

  factory PlaylistItem.fromJson(Map<String, dynamic> json) {
    return PlaylistItem(
      id: json['id'] ?? '',
      clipId: json['clipId'] ?? '',
      order: json['order'] ?? 0,
      customStartTime: json['customStartTime'] != null
          ? Duration(milliseconds: json['customStartTime'])
          : null,
      customEndTime: json['customEndTime'] != null
          ? Duration(milliseconds: json['customEndTime'])
          : null,
      duration: json['duration'] != null
          ? Duration(milliseconds: json['duration'])
          : null,
    );
  }

  @override
  List<Object?> get props => [
    id,
    clipId,
    order,
    customStartTime,
    customEndTime,
    duration,
  ];
}

class PlaylistItemWithClip extends Equatable {
  final PlaylistItem item;
  final VideoClip clip;

  const PlaylistItemWithClip({required this.item, required this.clip});

  Duration get effectiveDuration => item.getDuration(clip);

  @override
  List<Object?> get props => [item, clip];
}

class OnlineVideo extends Equatable {
  final String id;
  final String url;
  final String title;
  final String? description;
  final Duration? duration;
  final String? thumbnailUrl;
  final String? localPath; // 下载后的本地路径
  final String platform; // 'youtube', 'bilibili', 'missav', 'xvideos'
  final Map<String, dynamic> metadata; // 平台特定的元数据
  final DateTime? downloadedAt;
  final bool isDownloaded;

  const OnlineVideo({
    required this.id,
    required this.url,
    required this.title,
    this.description,
    this.duration,
    this.thumbnailUrl,
    this.localPath,
    required this.platform,
    this.metadata = const {},
    this.downloadedAt,
    this.isDownloaded = false,
  });

  factory OnlineVideo.fromJson(Map<String, dynamic> json) {
    return OnlineVideo(
      id: json['id'] ?? 'online_${json['url']?.hashCode}',
      url: json['url'] ?? '',
      title: json['title'] ?? '',
      description: json['description'],
      duration: json['duration'] != null
          ? Duration(milliseconds: json['duration'])
          : null,
      thumbnailUrl: json['thumbnailUrl'],
      localPath: json['localPath'],
      platform: json['platform'] ?? 'unknown',
      metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
      downloadedAt: json['downloadedAt'] != null
          ? DateTime.parse(json['downloadedAt'])
          : null,
      isDownloaded: json['isDownloaded'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'title': title,
      'description': description,
      'duration': duration?.inMilliseconds,
      'thumbnailUrl': thumbnailUrl,
      'localPath': localPath,
      'platform': platform,
      'metadata': metadata,
      'downloadedAt': downloadedAt?.toIso8601String(),
      'isDownloaded': isDownloaded,
    };
  }

  OnlineVideo copyWith({
    String? id,
    String? url,
    String? title,
    String? description,
    Duration? duration,
    String? thumbnailUrl,
    String? localPath,
    String? platform,
    Map<String, dynamic>? metadata,
    DateTime? downloadedAt,
    bool? isDownloaded,
  }) {
    return OnlineVideo(
      id: id ?? this.id,
      url: url ?? this.url,
      title: title ?? this.title,
      description: description ?? this.description,
      duration: duration ?? this.duration,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      localPath: localPath ?? this.localPath,
      platform: platform ?? this.platform,
      metadata: metadata ?? this.metadata,
      downloadedAt: downloadedAt ?? this.downloadedAt,
      isDownloaded: isDownloaded ?? this.isDownloaded,
    );
  }

  @override
  List<Object?> get props => [
    id,
    url,
    title,
    description,
    duration,
    thumbnailUrl,
    localPath,
    platform,
    metadata,
    downloadedAt,
    isDownloaded,
  ];
}

class OnlineVideoClip extends Equatable {
  final String id;
  final String name;
  final String onlineVideoId; // 关联的在线视频ID
  final String? localVideoPath; // 如果已下载，本地视频路径
  final Duration startTime;
  final Duration endTime;
  final Duration coverFrameTime;
  final List<String> tags;
  final String? notes;
  final int rating;
  final bool isFavorite;
  final String? thumbnailPath;
  final bool isDownloaded; // 是否已下载到本地

  const OnlineVideoClip({
    required this.id,
    this.name = '',
    required this.onlineVideoId,
    this.localVideoPath,
    this.startTime = Duration.zero,
    this.endTime = Duration.zero,
    this.coverFrameTime = Duration.zero,
    this.tags = const [],
    this.notes,
    this.rating = 0,
    this.isFavorite = false,
    this.thumbnailPath,
    this.isDownloaded = false,
  });

  factory OnlineVideoClip.fromJson(Map<String, dynamic> json) {
    final startTime = Duration(milliseconds: json['start'] ?? 0);
    return OnlineVideoClip(
      id: json['id'] ?? 'online_clip_${DateTime.now().millisecondsSinceEpoch}',
      name: json['label'] ?? json['name'] ?? 'Untitled Online Clip',
      onlineVideoId: json['onlineVideoId'] ?? '',
      localVideoPath: json['localVideoPath'],
      startTime: startTime,
      endTime: Duration(milliseconds: json['end'] ?? 0),
      coverFrameTime: Duration(
        milliseconds: json['coverFrameTime'] ?? startTime.inMilliseconds,
      ),
      tags: List<String>.from(json['tags'] ?? []),
      notes: json['notes'] ?? json['note'],
      rating: json['rating'] ?? 0,
      isFavorite: json['isFavorite'] ?? false,
      thumbnailPath: json['thumbnailPath'],
      isDownloaded: json['isDownloaded'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'onlineVideoId': onlineVideoId,
      'localVideoPath': localVideoPath,
      'start': startTime.inMilliseconds,
      'end': endTime.inMilliseconds,
      'coverFrameTime': coverFrameTime.inMilliseconds,
      'tags': tags,
      'notes': notes,
      'rating': rating,
      'isFavorite': isFavorite,
      'thumbnailPath': thumbnailPath,
      'isDownloaded': isDownloaded,
    };
  }

  OnlineVideoClip copyWith({
    String? id,
    String? name,
    String? onlineVideoId,
    String? localVideoPath,
    Duration? startTime,
    Duration? endTime,
    Duration? coverFrameTime,
    List<String>? tags,
    String? notes,
    int? rating,
    bool? isFavorite,
    String? thumbnailPath,
    bool? isDownloaded,
  }) {
    return OnlineVideoClip(
      id: id ?? this.id,
      name: name ?? this.name,
      onlineVideoId: onlineVideoId ?? this.onlineVideoId,
      localVideoPath: localVideoPath ?? this.localVideoPath,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      coverFrameTime: coverFrameTime ?? this.coverFrameTime,
      tags: tags ?? this.tags,
      notes: notes ?? this.notes,
      rating: rating ?? this.rating,
      isFavorite: isFavorite ?? this.isFavorite,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      isDownloaded: isDownloaded ?? this.isDownloaded,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    onlineVideoId,
    localVideoPath,
    startTime,
    endTime,
    coverFrameTime,
    tags,
    notes,
    rating,
    isFavorite,
    thumbnailPath,
    isDownloaded,
  ];
}

/// 多源搜索结果 - 改进版本
class EnhancedMultiSourceResult {
  final String code;
  final List<String> titles; // 多个标题来源
  final List<String> thumbnailUrls; // 多个封面图来源
  final Map<String, dynamic> metadata; // 其他元数据
  final Map<String, double> sourceConfidence; // 每个来源的置信度

  EnhancedMultiSourceResult({
    required this.code,
    required this.titles,
    required this.thumbnailUrls,
    required this.metadata,
    required this.sourceConfidence,
  });

  /// 获取最佳标题（置信度最高的）
  String? get bestTitle {
    if (titles.isEmpty) return null;
    if (titles.length == 1) return titles.first;

    // 如果有多个标题，返回第一个非空的
    return titles.firstWhere(
      (title) => title.isNotEmpty && title != 'Unknown Title',
      orElse: () => titles.first,
    );
  }

  /// 获取最佳封面图（置信度最高的）
  String? get bestThumbnail {
    if (thumbnailUrls.isEmpty) return null;
    if (thumbnailUrls.length == 1) return thumbnailUrls.first;

    // 如果有多个封面图，返回第一个有效的
    return thumbnailUrls.firstWhere(
      (url) => url.isNotEmpty,
      orElse: () => thumbnailUrls.first,
    );
  }

  /// 检查是否有多个选择
  bool get hasMultipleChoices {
    return titles.length > 1 || thumbnailUrls.length > 1;
  }

  /// 获取所有标题来源
  List<String> get titleSources {
    final sources = <String>[];
    if (titles.isNotEmpty) {
      sources.addAll(metadata['title_sources'] ?? []);
    }
    return sources;
  }

  /// 获取所有封面图来源
  List<String> get thumbnailSources {
    final sources = <String>[];
    if (thumbnailUrls.isNotEmpty) {
      sources.addAll(metadata['thumbnail_sources'] ?? []);
    }
    return sources;
  }

  @override
  String toString() {
    return 'EnhancedMultiSourceResult(code: $code, titles: $titles, thumbnails: ${thumbnailUrls.length})';
  }
}

/// 搜索结果项
class SearchResultItem {
  final String value;
  final String source;
  final double confidence;
  final Map<String, dynamic>? additionalData;

  SearchResultItem({
    required this.value,
    required this.source,
    required this.confidence,
    this.additionalData,
  });

  @override
  String toString() {
    return 'SearchResultItem(value: $value, source: $source, confidence: $confidence)';
  }
}

/// 聚合搜索结果
class AggregatedSearchResult {
  final String code;
  final List<SearchResultItem> titles;
  final List<SearchResultItem> thumbnails;
  final Map<String, dynamic> metadata;

  AggregatedSearchResult({
    required this.code,
    required this.titles,
    required this.thumbnails,
    required this.metadata,
  });

  /// 转换为增强的多源结果
  EnhancedMultiSourceResult toEnhancedResult() {
    final titleSources = titles.map((t) => t.source).toList();
    final thumbnailSources = thumbnails.map((t) => t.source).toList();

    final sourceConfidence = <String, double>{};
    for (final title in titles) {
      sourceConfidence['${title.source}_title'] = title.confidence;
    }
    for (final thumbnail in thumbnails) {
      sourceConfidence['${thumbnail.source}_thumbnail'] = thumbnail.confidence;
    }

    return EnhancedMultiSourceResult(
      code: code,
      titles: titles.map((t) => t.value).toList(),
      thumbnailUrls: thumbnails.map((t) => t.value).toList(),
      metadata: {
        ...metadata,
        'title_sources': titleSources,
        'thumbnail_sources': thumbnailSources,
      },
      sourceConfidence: sourceConfidence,
    );
  }

  @override
  String toString() {
    return 'AggregatedSearchResult(code: $code, titles: ${titles.length}, thumbnails: ${thumbnails.length})';
  }
}
