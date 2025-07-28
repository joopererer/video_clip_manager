import 'package:flutter/foundation.dart';
import 'dart:collection';
import 'package:path/path.dart' as p;

import 'models.dart';
import 'data_service.dart';

class AppState extends ChangeNotifier {
  final DataService _dataService = DataService();
  List<OriginalVideo> _originalVideos = [];
  List<VideoClip> _clips = [];
  final List<Playlist> _playlists = [];

  UnmodifiableListView<OriginalVideo> get originalVideos =>
      UnmodifiableListView(_originalVideos);
  UnmodifiableListView<VideoClip> get clips => UnmodifiableListView(_clips);
  UnmodifiableListView<Playlist> get playlists =>
      UnmodifiableListView(_playlists);

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  Future<String> loadClipsFromFile() async {
    _setLoading(true);
    try {
      final loadedClips = await _dataService.loadClipsFromFile();
      if (loadedClips != null) {
        _clips = loadedClips;
        _generateOriginalVideos();
        notifyListeners();
        return "${loadedClips.length} clips loaded successfully.";
      }
      return "No file selected or file was empty.";
    } catch (e) {
      return "Error loading file: $e";
    } finally {
      _setLoading(false);
    }
  }

  Future<String> saveClipsToFile() async {
    _setLoading(true);
    try {
      return await _dataService.saveClipsToFile(_clips);
    } catch (e) {
      return "Error saving file: $e";
    } finally {
      _setLoading(false);
    }
  }

  void _generateOriginalVideos() {
    final videoMap = <String, List<VideoClip>>{};
    for (var clip in _clips) {
      (videoMap[clip.videoPath] ??= []).add(clip);
    }

    _originalVideos = videoMap.entries.map((entry) {
      final path = entry.key;
      return OriginalVideo(
        // Use a consistent ID based on the path
        id: 'vid_${path.hashCode}',
        path: path,
        name: p.basename(path), // Get filename from path
      );
    }).toList();
  }

  void addClip(VideoClip clip) {
    _clips.add(clip);
    _generateOriginalVideos();
    notifyListeners();
  }

  void updateClip(VideoClip updatedClip) {
    final index = _clips.indexWhere((c) => c.id == updatedClip.id);
    if (index != -1) {
      _clips[index] = updatedClip;
      // Video path might change, so regenerate
      _generateOriginalVideos();
      notifyListeners();
    }
  }

  void deleteClip(String clipId) {
    _clips.removeWhere((c) => c.id == clipId);
    _generateOriginalVideos();
    notifyListeners();
  }

  void addVideo(OriginalVideo video) {
    if (!_originalVideos.any((v) => v.path == video.path)) {
      _originalVideos.add(video);
      notifyListeners();
    }
  }

  void deleteVideo(String videoId) {
    final video = getVideoById(videoId);
    if (video == null) return;

    // Prevent deletion if clips are associated
    if (_clips.any((clip) => clip.videoPath == video.path)) {
      debugPrint("Cannot delete video with associated clips.");
      return;
    }
    _originalVideos.removeWhere((v) => v.id == videoId);
    notifyListeners();
  }

  OriginalVideo? getVideoById(String id) {
    try {
      return _originalVideos.firstWhere((v) => v.id == id);
    } catch (e) {
      return null;
    }
  }

  VideoClip? getClipById(String id) {
    try {
      return _clips.firstWhere((c) => c.id == id);
    } catch (e) {
      return null;
    }
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }
}
