import 'package:equatable/equatable.dart';

// 2. La classe hérite de Equatable
class VideoClip extends Equatable {
  // 3. Toutes les propriétés sont maintenant 'final'
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

  // Le constructeur devient 'const'
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
      id: json['id'] ?? 'clip_${DateTime.now().millisecondsSinceEpoch}_${json['videoPath']?.hashCode}',
      name: json['label'] ?? 'Untitled Clip',
      videoPath: json['videoPath'] ?? '',
      startTime: startTime,
      endTime: Duration(milliseconds: json['end'] ?? 0),
      coverFrameTime: Duration(milliseconds: json['coverFrameTime'] ?? startTime.inMilliseconds),
      tags: List<String>.from(json['tags'] ?? []),
      notes: json['note'],
      rating: json['rating'] ?? 0,
      isFavorite: json['isFavorite'] ?? false,
      thumbnailPath: json['thumbnailPath'], // Assurez-vous que le thumbnailPath est aussi dans fromJson si besoin
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
      'thumbnailPath': thumbnailPath, // Et dans toJson
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
      tags: tags ?? this.tags,
      notes: notes ?? this.notes,
      rating: rating ?? this.rating,
      isFavorite: isFavorite ?? this.isFavorite,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    );
  }

  // 4. On définit la liste des propriétés pour la comparaison
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
