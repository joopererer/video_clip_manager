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
    );
  }

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
