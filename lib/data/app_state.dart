import 'dart:io';
import 'package:flutter/foundation.dart';
import 'dart:collection';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'data_service.dart';
import '../services/thumbnail_service.dart';

const String _prefsKeyDbPath = 'db_path';

class AppState extends ChangeNotifier {
  final SharedPreferences _prefs;
  final ThumbnailService _thumbnailService;
  late final DataService _dataService;

  List<VideoClip> _clips = [];
  List<OriginalVideo> _originalVideos = [];

  String? _currentDbPath;
  bool _isLoading = false;
  bool _isSaving = false;

  bool _clipsIsGridView = false;
  bool _videosIsGridView = false;

  UnmodifiableListView<VideoClip> get clips => UnmodifiableListView(_clips);
  UnmodifiableListView<OriginalVideo> get originalVideos =>
      UnmodifiableListView(_originalVideos);

  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String get currentDbPath => _currentDbPath != null
      ? p.basename(_currentDbPath!)
      : 'No Database Loaded';
  bool get clipsIsGridView => _clipsIsGridView;
  bool get videosIsGridView => _videosIsGridView;

  AppState({
    required SharedPreferences prefs,
    required ThumbnailService thumbnailService,
  }) : _prefs = prefs,
       _thumbnailService = thumbnailService {
    _dataService = DataService(thumbnailService: _thumbnailService);
    _clipsIsGridView = _prefs.getBool('clipsIsGridView') ?? false;
    _videosIsGridView = _prefs.getBool('videosIsGridView') ?? false;
  }

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

  Future<void> loadInitialClips() async {
    _setLoading(true);
    try {
      _currentDbPath = _prefs.getString(_prefsKeyDbPath);
      if (_currentDbPath == null) {
        _currentDbPath = await _dataService.getDefaultDbPath();
        await _prefs.setString(_prefsKeyDbPath, _currentDbPath!);
      }

      await _dataService.ensureDirectoryExists(p.dirname(_currentDbPath!));

      final loadedClips = await _dataService.loadClipsFromPath(_currentDbPath!);
      _clips = loadedClips;
      _generateOriginalVideos();
    } catch (e) {
      debugPrint("Error during initial load: $e");
    } finally {
      _setLoading(false);
    }
  }

  Future<String> switchDatabase() async {
    _setLoading(true);
    try {
      final result = await _dataService.pickAndLoadClips();
      if (result.clips != null && result.path != null) {
        _clips = result.clips!;
        _currentDbPath = result.path;
        await _prefs.setString(_prefsKeyDbPath, _currentDbPath!);
        _generateOriginalVideos();
        notifyListeners();
        return "${result.clips!.length} clips loaded from ${p.basename(result.path!)}.";
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
        for (var newClip in result.clips!) {
          if (!_clips.any((c) => c.id == newClip.id)) {
            _clips.add(newClip);
            newClipsCount++;
          }
        }
        _generateOriginalVideos();
        await _save();
        return "$newClipsCount new clips imported and merged.";
      }
      return "No file selected or file was empty.";
    } catch (e) {
      return "Error importing file: $e";
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _save() async {
    if (_currentDbPath == null) {
      debugPrint("Save failed: current DB path is null.");
      return;
    }
    _isSaving = true;
    notifyListeners();
    await _dataService.saveClipsToPath(_clips, _currentDbPath!);
    _isSaving = false;
    notifyListeners();
  }

  void _generateOriginalVideos() {
    final videoMap = <String, List<VideoClip>>{};
    for (var clip in _clips) {
      (videoMap[clip.videoPath] ??= []).add(clip);
    }
    _originalVideos = videoMap.entries.map((entry) {
      final path = entry.key;
      return OriginalVideo(
        id: 'vid_${path.hashCode}',
        path: path,
        name: p.basename(path),
      );
    }).toList();
  }

  Future<void> addClip(VideoClip clip) async {
    _clips.add(clip);
    _generateOriginalVideos();
    await _save();
    notifyListeners();
  }

  Future<void> updateClip(VideoClip updatedClip) async {
    final index = _clips.indexWhere((c) => c.id == updatedClip.id);
    if (index != -1) {
      _clips[index] = updatedClip;
      _generateOriginalVideos();
      await _save();
      notifyListeners();
    }
  }

  Future<void> deleteClip(String clipId) async {
    _clips.removeWhere((c) => c.id == clipId);
    _generateOriginalVideos();
    await _save();
    notifyListeners();
  }

  UnmodifiableListView<String> get allTags {
    final allTagsSet = <String>{};
    for (var clip in _clips) {
      allTagsSet.addAll(clip.tags);
    }
    return UnmodifiableListView(allTagsSet.toList()..sort());
  }

  OriginalVideo? getVideoById(String id) {
    try {
      return _originalVideos.firstWhere((v) => v.id == id);
    } catch (e) {
      return null;
    }
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }
}
