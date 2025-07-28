
class VideoClip {
  final String id;
  final String videoId;
  String name;
  Duration startTime;
  Duration endTime;
  List<String> tags;
  String? notes;
  int rating; // 0-5 stars
  bool isFavorite;

  VideoClip({
    required this.id,
    required this.videoId,
    required this.name,
    required this.startTime,
    required this.endTime,
    this.tags = const [],
    this.notes,
    this.rating = 0,
    this.isFavorite = false,
  });
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
