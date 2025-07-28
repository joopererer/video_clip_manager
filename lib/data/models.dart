class VideoClip {
  final String id;
  String name;
  String videoPath;
  Duration startTime;
  Duration endTime;
  Duration coverFrameTime;
  List<String> tags; // This property itself is fine.
  String? notes;
  int rating;
  bool isFavorite;

  String? thumbnailPath;

  // MODIFIED: The constructor is changed to ensure `tags` is always a modifiable list.
  VideoClip({
    required this.id,
    required this.name,
    required this.videoPath,
    required this.startTime,
    required this.endTime,
    required this.coverFrameTime,
    List<String> tags = const [], // The parameter can have a const default...
    this.notes,
    this.rating = 0,
    this.isFavorite = false,
    this.thumbnailPath,
  }) : tags = List.from(
         tags,
       ); // ...but the property is initialized with a NEW, MODIFIABLE list.

  factory VideoClip.fromJson(Map<String, dynamic> json) {
    final startTime = Duration(milliseconds: json['start'] ?? 0);
    return VideoClip(
      id:
          json['id'] ??
          'clip_${DateTime.now().millisecondsSinceEpoch}_${json['videoPath']?.hashCode}',
      name: json['label'] ?? 'Untitled Clip',
      videoPath: json['videoPath'] ?? '',
      startTime: startTime,
      endTime: Duration(milliseconds: json['end'] ?? 0),
      coverFrameTime: Duration(
        milliseconds: json['coverFrameTime'] ?? startTime.inMilliseconds,
      ),
      // This already correctly creates a modifiable list from JSON.
      tags: List<String>.from(json['tags'] ?? []),
      notes: json['note'],
      rating: json['rating'] ?? 0,
      isFavorite: json['isFavorite'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': name,
      'videoPath': videoPath,
      'start': startTime.inMilliseconds,
      'end': endTime.inMilliseconds,
      'coverFrameTime': coverFrameTime.inMilliseconds,
      'tags': tags,
      'note': notes,
      'rating': rating,
      'isFavorite': isFavorite,
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
    return VideoClip(
      id: id ?? this.id,
      name: name ?? this.name,
      videoPath: videoPath ?? this.videoPath,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      coverFrameTime: coverFrameTime ?? this.coverFrameTime,
      // When copying, we also ensure the list is new and modifiable.
      tags: tags ?? List.from(this.tags),
      notes: notes ?? this.notes,
      rating: rating ?? this.rating,
      isFavorite: isFavorite ?? this.isFavorite,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    );
  }
}

class OriginalVideo {
  final String id;
  final String path;
  String name;

  OriginalVideo({required this.id, required this.path, required this.name});
}

class Playlist {
  final String id;
  String name;
  List<String> clipIds;

  Playlist({required this.id, required this.name, this.clipIds = const []});
}
