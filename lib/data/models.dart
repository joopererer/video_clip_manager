
class VideoClip {
  final String id;
  String name; // 'label' in JSON
  String videoPath;
  Duration startTime;
  Duration endTime;
  List<String> tags;
  String? notes; // 'note' in JSON
  int rating;
  bool isFavorite;

  VideoClip({
    required this.id,
    required this.name,
    required this.videoPath,
    required this.startTime,
    required this.endTime,
    this.tags = const [],
    this.notes,
    this.rating = 0,
    this.isFavorite = false,
  });

  // Factory constructor to create a VideoClip from JSON
  factory VideoClip.fromJson(Map<String, dynamic> json) {
    return VideoClip(
      // Generate a unique ID if not present
      id:
          json['id'] ??
          'clip_${DateTime.now().millisecondsSinceEpoch}_${json['videoPath']?.hashCode}',
      name: json['label'] ?? 'Untitled Clip',
      videoPath: json['videoPath'] ?? '',
      startTime: Duration(milliseconds: json['start'] ?? 0),
      endTime: Duration(milliseconds: json['end'] ?? 0),
      tags: List<String>.from(json['tags'] ?? []),
      notes: json['note'],
      rating: json['rating'] ?? 0,
      isFavorite: json['isFavorite'] ?? false,
    );
  }

  // Method to convert a VideoClip instance to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': name,
      'videoPath': videoPath,
      'start': startTime.inMilliseconds,
      'end': endTime.inMilliseconds,
      'tags': tags,
      'note': notes,
      'rating': rating,
      'isFavorite': isFavorite,
    };
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
  List<String> clipIds; // Ordered list of clip IDs

  Playlist({required this.id, required this.name, this.clipIds = const []});
}
