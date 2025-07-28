import 'package:flutter/foundation.dart';
import 'dart:collection';

import 'models.dart';

class AppState extends ChangeNotifier {
  final List<OriginalVideo> _originalVideos = [];
  final List<VideoClip> _clips = [];
  final List<Playlist> _playlists = [];

  UnmodifiableListView<OriginalVideo> get originalVideos =>
      UnmodifiableListView(_originalVideos);
  UnmodifiableListView<VideoClip> get clips => UnmodifiableListView(_clips);
  UnmodifiableListView<Playlist> get playlists =>
      UnmodifiableListView(_playlists);

  // Sample Data for demonstration
  AppState() {
    final video1 = OriginalVideo(
      id: 'vid1',
      path:
          '[https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4](https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4)',
      name: 'Big Buck Bunny',
    );
    final video2 = OriginalVideo(
      id: 'vid2',
      path:
          '[https://user-images.githubusercontent.com/28951144/229373709-603a7a89-2105-4e1b-a5a5-a6c3567c9a59.mp4](https://user-images.githubusercontent.com/28951144/229373709-603a7a89-2105-4e1b-a5a5-a6c3567c9a59.mp4)',
      name: 'Tears of Steel',
    );
    _originalVideos.addAll([video1, video2]);

    _clips.addAll([
      VideoClip(
        id: 'clip1',
        videoId: 'vid1',
        name: 'Bunny Intro',
        startTime: const Duration(seconds: 5),
        endTime: const Duration(seconds: 15),
        tags: ['intro', 'funny'],
        rating: 3,
      ),
      VideoClip(
        id: 'clip2',
        videoId: 'vid1',
        name: 'Butterfly Scene',
        startTime: const Duration(seconds: 30),
        endTime: const Duration(seconds: 40),
        tags: ['nature', 'animation'],
        rating: 5,
        isFavorite: true,
      ),
      VideoClip(
        id: 'clip3',
        videoId: 'vid2',
        name: 'Robot Hand',
        startTime: const Duration(seconds: 60),
        endTime: const Duration(seconds: 75),
        tags: ['sci-fi', 'vfx'],
        notes: "Cool visual effects here.",
      ),
    ]);
  }

  void addClip(VideoClip clip) {
    _clips.add(clip);
    notifyListeners();
  }

  void updateClip(VideoClip updatedClip) {
    final index = _clips.indexWhere((c) => c.id == updatedClip.id);
    if (index != -1) {
      _clips[index] = updatedClip;
      notifyListeners();
    }
  }

  void deleteClip(String clipId) {
    _clips.removeWhere((c) => c.id == clipId);
    notifyListeners();
  }

  void addVideo(OriginalVideo video) {
    if (!_originalVideos.any((v) => v.path == video.path)) {
      _originalVideos.add(video);
      notifyListeners();
    }
  }

  void deleteVideo(String videoId) {
    // Prevent deletion if clips are associated
    if (_clips.any((clip) => clip.videoId == videoId)) {
      // In a real app, show a dialog to the user
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

  void createPlaylist(Playlist playlist) {
    _playlists.add(playlist);
    notifyListeners();
  }

  void updatePlaylist(Playlist updatedPlaylist) {
    final index = _playlists.indexWhere((p) => p.id == updatedPlaylist.id);
    if (index != -1) {
      _playlists[index] = updatedPlaylist;
      notifyListeners();
    }
  }

  void deletePlaylist(String playlistId) {
    _playlists.removeWhere((p) => p.id == playlistId);
    notifyListeners();
  }
}
