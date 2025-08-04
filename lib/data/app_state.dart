import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/path_service.dart';
import '../services/thumbnail_service.dart';
import '../services/video_metadata_service.dart';
import 'data_service.dart';
import 'models.dart';

const String _prefsKeyDbPath = 'db_path';

class AppState extends ChangeNotifier {
  final SharedPreferences _prefs;
  final PathService _pathService;
  final ThumbnailService _thumbnailService;
  late final DataService _dataService;
  late final VideoMetadataService _videoMetadataService;

  List<VideoClip> _clips = [];
  List<OriginalVideo> _originalVideos = [];
  List<Playlist> _playlists = [];

  String? _currentDbPath;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isGeneratingThumbnails = false;

  bool _clipsIsGridView = false;
  bool _videosIsGridView = false;
  bool _playlistsIsGridView = false;
  String _playlistsSortBy = 'name';

  List<String> _selectedTags = [];
  int? _selectedRating;
  bool? _selectedFavorite;

  Timer? _saveTimer;
  bool _hasUnsavedChanges = false;

  UnmodifiableListView<VideoClip> get clips => UnmodifiableListView(_clips);
  UnmodifiableListView<OriginalVideo> get originalVideos =>
      UnmodifiableListView(_originalVideos);
  UnmodifiableListView<Playlist> get playlists =>
      UnmodifiableListView(_playlists);

  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isGeneratingThumbnails => _isGeneratingThumbnails;
  String get currentDbPath =>
      _currentDbPath != null ? p.basename(_currentDbPath!) : 'No Database Loaded';
  String? get currentDbFullPath => _currentDbPath;
  bool get clipsIsGridView => _clipsIsGridView;
  bool get videosIsGridView => _videosIsGridView;
  bool get playlistsIsGridView => _playlistsIsGridView;
  String get playlistsSortBy => _playlistsSortBy;
  List<String> get selectedTags => List.unmodifiable(_selectedTags);
  int? get selectedRating => _selectedRating;
  bool? get selectedFavorite => _selectedFavorite;

  AppState({
    required SharedPreferences prefs,
    required PathService pathService,
    required ThumbnailService thumbnailService,
  })  : _prefs = prefs,
        _pathService = pathService,
        _thumbnailService = thumbnailService {
    _dataService = DataService(pathService: _pathService);
    _videoMetadataService = VideoMetadataService();
    _clipsIsGridView = _prefs.getBool('clipsIsGridView') ?? false;
    _videosIsGridView = _prefs.getBool('videosIsGridView') ?? false;
    _playlistsIsGridView = _prefs.getBool('playlistsIsGridView') ?? false;
    _playlistsSortBy = _prefs.getString('playlistsSortBy') ?? 'name';
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  // --- UI State Methods ---
  void setClipsViewMode(bool isGrid) {
    _clipsIsGridView = isGrid;
    _prefs.setBool('clipsIsGridView', isGrid);
    notifyListeners();
  }

  void setVideosViewMode(bool isGrid) {
    _videosIsGridView = isGrid;
    _prefs.setBool('videosIsGridView', isGrid);
    notifyListeners();
  }

  void setPlaylistsViewMode(bool isGrid) {
    _playlistsIsGridView = isGrid;
    _prefs.setBool('playlistsIsGridView', isGrid);
    notifyListeners();
  }

  void setPlaylistsSortBy(String sortBy) {
    _playlistsSortBy = sortBy;
    _prefs.setString('playlistsSortBy', sortBy);
    notifyListeners();
  }

  // --- Filter Methods ---
  void setSelectedTags(List<String> tags) {
    _selectedTags = List.from(tags);
    notifyListeners();
  }

  void clearSelectedTags() {
    if (_selectedTags.isNotEmpty) {
      _selectedTags.clear();
      notifyListeners();
    }
  }

  void setSelectedRating(int? rating) {
    _selectedRating = rating;
    notifyListeners();
  }

  void clearSelectedRating() {
    if (_selectedRating != null) {
      _selectedRating = null;
      notifyListeners();
    }
  }

  void setSelectedFavorite(bool? favorite) {
    _selectedFavorite = favorite;
    notifyListeners();
  }

  void clearSelectedFavorite() {
    if (_selectedFavorite != null) {
      _selectedFavorite = null;
      notifyListeners();
    }
  }

  void clearAllFilters() {
    bool hasChanges = _selectedTags.isNotEmpty ||
        _selectedRating != null ||
        _selectedFavorite != null;
    if (hasChanges) {
      _selectedTags.clear();
      _selectedRating = null;
      _selectedFavorite = null;
      notifyListeners();
    }
  }

  // --- Data Loading and Initialization ---
  Future<void> loadInitialData() async {
    _setLoading(true);
    try {
      _currentDbPath = _prefs.getString(_prefsKeyDbPath);
      if (_currentDbPath == null || !await File(_currentDbPath!).exists()) {
        _currentDbPath = _pathService.getDefaultDbPath();
        await _prefs.setString(_prefsKeyDbPath, _currentDbPath!);
        debugPrint("Default database path created at: $_currentDbPath");
      }
      debugPrint("Loading database from: $_currentDbPath");

      final result = await _dataService.loadDataFromPath(_currentDbPath!);
      _clips = result.clips ?? [];
      _originalVideos = result.videos ?? [];
      _playlists = result.playlists ?? [];

      _generateOriginalVideosIfNeeded();
      notifyListeners();

      await _populateMissingMetadataAndThumbnails();
    } catch (e) {
      debugPrint("Error during initial load: $e");
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _populateMissingMetadataAndThumbnails() async {
    _isGeneratingThumbnails = true;
    notifyListeners();

    try {
      final videosNeedingMetadata =
          _originalVideos.where((v) => v.duration == null).toList();
      if (videosNeedingMetadata.isNotEmpty) {
        debugPrint('Populating metadata for ${videosNeedingMetadata.length} videos...');
        await Future.wait(
            videosNeedingMetadata.map((v) => updateVideoMetadata(v.id)));
      }

      final clipsNeedingThumbnails = <VideoClip>[];
      if (currentDbFullPath != null) {
        for (final clip in _clips) {
          final thumbPath = _thumbnailService.getThumbnailPathForDatabase(currentDbFullPath!, clip.id);
          if (!await File(thumbPath).exists()) {
            clipsNeedingThumbnails.add(clip);
          }
        }
      }

      if (clipsNeedingThumbnails.isNotEmpty) {
        debugPrint('Populating thumbnails for ${clipsNeedingThumbnails.length} clips...');
        final futures = clipsNeedingThumbnails.map((clip) async {
          final thumbnailFileName = await _thumbnailService.generateThumbnail(
              clip.videoPath, clip.coverFrameTime, clip.id, dbPath: _currentDbPath!);
          if (thumbnailFileName != null) {
            updateClipThumbnail(clip.id, thumbnailFileName);
          }
        });
        await Future.wait(futures);
      }
    } catch (e) {
      debugPrint("Error populating metadata and thumbnails: $e");
    } finally {
      _isGeneratingThumbnails = false;
      notifyListeners();
      _scheduleSave();
    }
  }

  void _generateOriginalVideosIfNeeded() {
    if (_originalVideos.isNotEmpty && _originalVideos.every((v) => v.id.isNotEmpty)) {
      return;
    }

    final videoMap = <String, List<VideoClip>>{};
    for (var clip in _clips) {
      (videoMap[clip.videoPath] ??= []).add(clip);
    }

    final existingVideosByPath = {for (var v in _originalVideos) v.path: v};
    
    _originalVideos = videoMap.entries.map((entry) {
      final path = entry.key;
      if (existingVideosByPath.containsKey(path)) {
        return existingVideosByPath[path]!;
      }
      final videoId = 'vid_${path.hashCode}';
      return OriginalVideo(id: videoId, path: path, name: p.basename(path));
    }).toList();
  }

  // --- Database and File Operations ---
  Future<String> switchDatabase() async {
    _setLoading(true);
    try {
      final result = await _dataService.pickAndLoadClips();
      if (result.path != null) {
        _currentDbPath = result.path;
        await _prefs.setString(_prefsKeyDbPath, _currentDbPath!);
        await loadInitialData();
        return "${_clips.length} clips loaded from ${p.basename(result.path!)}.";
      }
      return "No file selected or file was empty.";
    } catch (e) {
      return "Error loading file: $e";
    } finally {
      _setLoading(false);
    }
  }

  Future<String> importAndMergeClips() async {
    _setLoading(true);
    try {
      final result = await _dataService.pickAndLoadClips();
      if (result.clips != null) {
        int newClipsCount = 0;
        int existingClipsCount = 0;

        for (var newClip in result.clips!) {
          if (!_clips.any((c) => c.id == newClip.id)) {
            _clips.add(newClip);
            newClipsCount++;
          } else {
            existingClipsCount++;
          }
        }
        
        if (newClipsCount > 0) {
          _generateOriginalVideosIfNeeded();
          await _populateMissingMetadataAndThumbnails();
          await _save();
        }

        return "$newClipsCount new clips imported. $existingClipsCount clips already existed.";
      }
      return "No file selected or file was empty.";
    } catch (e) {
      return "Error importing file: $e";
    } finally {
      _setLoading(false);
    }
  }

  Future<void> forceRefreshThumbnails() async {
    _isGeneratingThumbnails = true;
    notifyListeners();
    try {
      debugPrint('--- Force Refreshing All Thumbnails & Metadata ---');
      if (currentDbFullPath != null) {
         final thumbDir = _thumbnailService.getThumbnailDirForDatabase(currentDbFullPath!);
         final dir = Directory(thumbDir);
         if (await dir.exists()) {
           try {
             await dir.delete(recursive: true);
           } catch (e) {
             debugPrint('Warning: Could not delete thumbnail directory: $e');
             // Continue anyway, we'll overwrite existing thumbnails
           }
         }
      }

      for (int i = 0; i < _clips.length; i++) {
        _clips[i] = _clips[i].copyWith(thumbnailPath: null);
      }
      for (int i = 0; i < _originalVideos.length; i++) {
        _originalVideos[i] = _originalVideos[i].copyWith(thumbnailPath: null, duration: null);
      }
      notifyListeners();

      // Regenerate thumbnails for clips
      if (_clips.isNotEmpty) {
        debugPrint('Regenerating thumbnails for ${_clips.length} clips...');
        final futures = _clips.map((clip) async {
          final thumbnailFileName = await _thumbnailService.generateThumbnail(
              clip.videoPath, clip.coverFrameTime, clip.id, dbPath: _currentDbPath!);
          if (thumbnailFileName != null) {
            updateClipThumbnail(clip.id, thumbnailFileName);
          }
        });
        await Future.wait(futures);
      }

      // Regenerate metadata and thumbnails for videos
      if (_originalVideos.isNotEmpty) {
        debugPrint('Regenerating metadata and thumbnails for ${_originalVideos.length} videos...');
        final futures = _originalVideos.map((video) => updateVideoMetadata(video.id));
        await Future.wait(futures);
      }

    } catch (e) {
      debugPrint('Error in forceRefreshThumbnails: $e');
    } finally {
      _isGeneratingThumbnails = false;
      notifyListeners();
    }
  }

  // --- Save Operations ---
  Future<void> _save() async {
    if (_currentDbPath == null) return;
    _isSaving = true;
    notifyListeners();
    try {
      await _dataService.saveDataToPath(
        _clips,
        _originalVideos,
        _playlists,
        _currentDbPath!,
      );
      _hasUnsavedChanges = false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  void _scheduleSave() {
    _hasUnsavedChanges = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () {
      if (_hasUnsavedChanges) {
        _save();
      }
    });
  }
  
  Future<void> forceSave() async {
    if (_hasUnsavedChanges) {
      _saveTimer?.cancel();
      await _save();
    }
  }

  // --- Video & Metadata Methods ---
  void addOriginalVideo(OriginalVideo video) {
    if (!_originalVideos.any((v) => v.path == video.path)) {
      _originalVideos.add(video);
      notifyListeners();
      _scheduleSave();
      updateVideoMetadata(video.id);
    }
  }

  Future<void> updateVideoMetadata(String videoId) async {
    final index = _originalVideos.indexWhere((v) => v.id == videoId);
    if (index == -1) return;

    final video = _originalVideos[index];
    debugPrint('Updating metadata for video: ${video.name}');

    final duration = await _videoMetadataService.getVideoDuration(video.path);
    if (duration != null) {
      // Generate thumbnail for video
      String? thumbnailPath;
      if (_currentDbPath != null) {
        thumbnailPath = await _thumbnailService.generateThumbnail(
          video.path,
          Duration(milliseconds: duration.inMilliseconds ~/ 2),
          video.id,
          dbPath: _currentDbPath!,
        );
      }
      
      _originalVideos[index] = video.copyWith(
        duration: duration,
        thumbnailPath: thumbnailPath,
      );
      notifyListeners();
      _scheduleSave();
      debugPrint('Updated video ${video.name} with duration: $duration and thumbnail: $thumbnailPath');
    } else {
      debugPrint('Failed to get duration for video: ${video.name}');
    }
  }
  
  Future<OriginalVideo?> getVideoById(String videoId) async {
     final video = _originalVideos.firstWhereOrNull((v) => v.id == videoId);
     if (video != null && video.duration == null) {
       await updateVideoMetadata(videoId);
       return _originalVideos.firstWhereOrNull((v) => v.id == videoId);
     }
     return video;
  }

  // --- Clip Methods ---
  Future<void> addClip(VideoClip clip) async {
    final thumbnailFileName = await _thumbnailService.generateThumbnail(
        clip.videoPath, clip.coverFrameTime, clip.id, dbPath: _currentDbPath!);
    
    final clipWithThumbnail = clip.copyWith(thumbnailPath: thumbnailFileName);

    _clips.add(clipWithThumbnail);
    _generateOriginalVideosIfNeeded();
    notifyListeners();
    _scheduleSave();
  }
  
  Future<void> createClipFromWholeVideo(OriginalVideo video) async {
    // First try to get video with metadata
    final videoWithMeta = await getVideoById(video.id);
    
    // If still no duration, try to update metadata directly
    if (videoWithMeta?.duration == null || videoWithMeta!.duration! <= Duration.zero) {
      debugPrint("Attempting to get metadata for video: ${video.name}");
      await updateVideoMetadata(video.id);
      
      // Get the updated video
      final updatedVideo = _originalVideos.firstWhereOrNull((v) => v.id == video.id);
      if (updatedVideo?.duration == null || updatedVideo!.duration! <= Duration.zero) {
        debugPrint("Cannot create clip from video with no duration: ${video.name}");
        return;
      }
      
      final clipId = 'clip_${DateTime.now().millisecondsSinceEpoch}_${video.id}';
      final clip = VideoClip(
        id: clipId,
        name: video.name,
        videoPath: video.path,
        startTime: Duration.zero,
        endTime: updatedVideo.duration!,
        coverFrameTime: Duration.zero,
      );
      await addClip(clip);
    } else {
      final clipId = 'clip_${DateTime.now().millisecondsSinceEpoch}_${video.id}';
      final clip = VideoClip(
        id: clipId,
        name: video.name,
        videoPath: video.path,
        startTime: Duration.zero,
        endTime: videoWithMeta.duration!,
        coverFrameTime: Duration.zero,
      );
      await addClip(clip);
    }
  }

  Future<void> updateClip(VideoClip updatedClip) async {
    final index = _clips.indexWhere((c) => c.id == updatedClip.id);
    if (index != -1) {
      _clips[index] = updatedClip;
      notifyListeners();
      _scheduleSave();
    }
  }
  
  void updateClipSilently(VideoClip updatedClip) {
    final index = _clips.indexWhere((c) => c.id == updatedClip.id);
    if (index != -1) {
      _clips[index] = updatedClip;
      _hasUnsavedChanges = true;
      notifyListeners();
    }
  }

  void updateClipThumbnail(String clipId, String thumbnailFileName) {
    final index = _clips.indexWhere((c) => c.id == clipId);
    if (index != -1) {
      _clips[index] = _clips[index].copyWith(thumbnailPath: thumbnailFileName);
    }
  }

  Future<void> deleteClip(String clipId) async {
    _clips.removeWhere((c) => c.id == clipId);
    notifyListeners();
    await _save();
  }
  
  UnmodifiableListView<String> get allTags {
    final allTagsSet = <String>{};
    for (var clip in _clips) {
      allTagsSet.addAll(clip.tags);
    }
    return UnmodifiableListView(allTagsSet.toList()..sort());
  }

  // --- Getters with Filtering ---
  List<VideoClip> getFilteredClips({
    String searchQuery = '',
    List<String>? selectedTags,
    int? selectedRating,
    bool? selectedFavorite,
  }) {
    final tags = selectedTags ?? _selectedTags;
    final rating = selectedRating ?? _selectedRating;
    final favorite = selectedFavorite ?? _selectedFavorite;

    return _clips.where((clip) {
      final query = searchQuery.toLowerCase();
      final textMatch = query.isEmpty ||
          clip.name.toLowerCase().contains(query) ||
          (clip.notes?.toLowerCase().contains(query) ?? false);
      final tagMatch = tags.isEmpty || tags.every((tag) => clip.tags.contains(tag));
      final ratingMatch = rating == null || clip.rating == rating;
      final favoriteMatch = favorite == null || clip.isFavorite == favorite;
      return textMatch && tagMatch && ratingMatch && favoriteMatch;
    }).toList();
  }

  List<OriginalVideo> getFilteredVideos({String searchQuery = ''}) {
    if (searchQuery.isEmpty) return _originalVideos;
    final query = searchQuery.toLowerCase();
    return _originalVideos.where((video) => video.name.toLowerCase().contains(query)).toList();
  }

  // --- Playlist Methods ---
  void createPlaylist(String name, {String? description}) {
    final playlist = Playlist.create(name: name, description: description);
    _playlists.add(playlist);
    notifyListeners();
    _scheduleSave();
  }

  void updatePlaylist(String playlistId, {String? name, String? description, List<PlaylistItem>? items}) {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      final playlist = _playlists[index];
      _playlists[index] = playlist.copyWith(
        name: name,
        description: description,
        items: items,
        updatedAt: DateTime.now(),
      );
      notifyListeners();
      _scheduleSave();
    }
  }

  void deletePlaylist(String playlistId) {
    _playlists.removeWhere((p) => p.id == playlistId);
    notifyListeners();
    _scheduleSave();
  }

  void addClipToPlaylist(String playlistId, String clipId) {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      final playlist = _playlists[index];
      if (playlist.items.any((item) => item.clipId == clipId)) return;
      
      final clip = _clips.firstWhere((c) => c.id == clipId);
      final newItem = PlaylistItem.fromClip(clip, playlist.items.length);
      
      _playlists[index] = playlist.copyWith(
        items: [...playlist.items, newItem],
        updatedAt: DateTime.now(),
      );
      notifyListeners();
      _scheduleSave();
    }
  }
  
  void removePlaylistItem(String playlistId, String itemId) {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      final playlist = _playlists[index];
      final newItems = playlist.items.where((item) => item.id != itemId).toList();
      _playlists[index] = playlist.copyWith(items: newItems, updatedAt: DateTime.now());
      notifyListeners();
      _scheduleSave();
    }
  }

  void reorderPlaylistItems(String playlistId, int oldIndex, int newIndex) {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      final playlist = _playlists[index];
      final items = List.of(playlist.items);
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final item = items.removeAt(oldIndex);
      items.insert(newIndex, item);
      
      final reorderedItems = items.map((item) => item.copyWith(order: items.indexOf(item))).toList();
      
      _playlists[index] = playlist.copyWith(items: reorderedItems, updatedAt: DateTime.now());
      notifyListeners();
      _scheduleSave();
    }
  }

  List<PlaylistItemWithClip> getPlaylistItemsWithClips(String playlistId) {
    final playlist = _playlists.firstWhereOrNull((p) => p.id == playlistId);
    if (playlist == null) return [];
    return playlist.items
        .map((item) {
          final clip = _clips.firstWhereOrNull((c) => c.id == item.clipId);
          return clip != null ? PlaylistItemWithClip(item: item, clip: clip) : null;
        })
        .whereType<PlaylistItemWithClip>()
        .toList();
  }

  void importPlaylist(Map<String, dynamic> data) {
    final playlist = Playlist.fromJson(data);
    _playlists.add(playlist);
    notifyListeners();
    _scheduleSave();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
