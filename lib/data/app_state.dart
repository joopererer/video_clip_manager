import 'dart:io';
import 'package:flutter/foundation.dart';
import 'dart:collection';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async'; // Added for Timer

import 'models.dart';
import 'data_service.dart';
import '../services/path_service.dart';
import '../services/thumbnail_service.dart';

const String _prefsKeyDbPath = 'db_path';

class AppState extends ChangeNotifier {
  final SharedPreferences _prefs;
  final PathService _pathService;
  final ThumbnailService _thumbnailService;
  late final DataService _dataService;

  List<VideoClip> _clips = [];
  List<OriginalVideo> _originalVideos = [];

  String? _currentDbPath;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isGeneratingThumbnails = false;

  bool _clipsIsGridView = false;
  bool _videosIsGridView = false;
  
  // 标签过滤相关
  List<String> _selectedTags = [];
  
  // 星级过滤相关
  int? _selectedRating; // null表示不过滤星级，1-5表示过滤特定星级
  
  // 爱心收藏过滤相关
  bool? _selectedFavorite; // null表示不过滤收藏状态，true表示只显示收藏的，false表示只显示未收藏的
  
  // 批量更新和延迟保存相关
  Timer? _saveTimer;
  bool _hasUnsavedChanges = false;

  UnmodifiableListView<VideoClip> get clips => UnmodifiableListView(_clips);
  UnmodifiableListView<OriginalVideo> get originalVideos =>
      UnmodifiableListView(_originalVideos);

  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isGeneratingThumbnails => _isGeneratingThumbnails;
  String get currentDbPath => _currentDbPath != null
      ? p.basename(_currentDbPath!)
      : 'No Database Loaded';
  bool get clipsIsGridView => _clipsIsGridView;
  bool get videosIsGridView => _videosIsGridView;
  List<String> get selectedTags => List.unmodifiable(_selectedTags);
  int? get selectedRating => _selectedRating;
  bool? get selectedFavorite => _selectedFavorite;

  AppState({
    required SharedPreferences prefs,
    required PathService pathService,
    required ThumbnailService thumbnailService,
  }) : _prefs = prefs,
       _pathService = pathService,
       _thumbnailService = thumbnailService {
    _dataService = DataService(pathService: _pathService);
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

  // 标签过滤相关方法
  void setSelectedTags(List<String> tags) {
    _selectedTags = List.from(tags);
    notifyListeners();
  }

  void addSelectedTag(String tag) {
    if (!_selectedTags.contains(tag)) {
      _selectedTags.add(tag);
      notifyListeners();
    }
  }

  void removeSelectedTag(String tag) {
    if (_selectedTags.remove(tag)) {
      notifyListeners();
    }
  }

  void clearSelectedTags() {
    if (_selectedTags.isNotEmpty) {
      _selectedTags.clear();
      notifyListeners();
    }
  }

  // 星级过滤相关方法
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

  // 爱心收藏过滤相关方法
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

  // 清除所有过滤条件
  void clearAllFilters() {
    bool hasChanges = false;
    
    if (_selectedTags.isNotEmpty) {
      _selectedTags.clear();
      hasChanges = true;
    }
    
    if (_selectedRating != null) {
      _selectedRating = null;
      hasChanges = true;
    }
    
    if (_selectedFavorite != null) {
      _selectedFavorite = null;
      hasChanges = true;
    }
    
    if (hasChanges) {
      notifyListeners();
    }
  }

  Future<void> loadInitialClips() async {
    _setLoading(true);
    try {
      _currentDbPath = _prefs.getString(_prefsKeyDbPath);
      if (_currentDbPath == null) {
        _currentDbPath = _pathService.getDefaultDbPath();
        await _prefs.setString(_prefsKeyDbPath, _currentDbPath!);
        debugPrint("Default database path created at: $_currentDbPath");
      }
      debugPrint("Loading database from: $_currentDbPath");

      final loadedClips = await _dataService.loadClipsFromPath(_currentDbPath!);
      _clips = loadedClips;
      _generateOriginalVideos();
      await _populateAllThumbnails();
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
        await _populateAllThumbnails();
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
        await _populateAllThumbnails();
        return "$newClipsCount new clips imported and merged.";
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
      await _thumbnailService.clearCache();
      for (final clip in _clips) {
        clip.copyWith(thumbnailPath: null);
      }
      // 注意：这里需要一个 notifyListeners() 来让UI立即移除旧图片，显示加载指示器
      notifyListeners();

      await _populateAllThumbnails();
    } catch (e) {
      debugPrint("Error forcing thumbnail refresh: $e");
      // 这里可以添加一个向用户显示错误的功能
    } finally {
      _isGeneratingThumbnails = false;
      notifyListeners();
    }
  }

  Future<void> _populateAllThumbnails() async {
    // 这个函数不应该管理 _isGeneratingThumbnails 状态
    final clipsToGenerate = <VideoClip>[];
    for (final clip in _clips) {
      final thumbPath = _thumbnailService.getThumbnailPath(clip.id);
      if (await File(thumbPath).exists()) {
        // Trouvez l'index du clip dans votre liste `_clips`
        final index = _clips.indexWhere((c) => c.id == clip.id);
        if (index != -1) {
          // Créez une nouvelle instance avec le thumbnailPath mis à jour
          final updatedClip = _clips[index].copyWith(thumbnailPath: thumbPath);
          // Remplacez l'ancien clip par le nouveau dans la liste
          _clips[index] = updatedClip;
        }
      } else {
        clipsToGenerate.add(clip);
      }
    }

    // 立即更新那些已经有缓存的缩略图
    notifyListeners();

    if (clipsToGenerate.isNotEmpty) {
      await _thumbnailService.generateThumbnailsInBatch(clipsToGenerate, () {
        notifyListeners();
      });
    }
  }

  Future<void> _save() async {
    if (_currentDbPath == null) return;
    _isSaving = true;
    notifyListeners();
    await _dataService.saveClipsToPath(_clips, _currentDbPath!);
    _isSaving = false;
    _hasUnsavedChanges = false;
    notifyListeners();
  }
  
  // 延迟保存方法，避免频繁保存
  void _scheduleSave() {
    _hasUnsavedChanges = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () {
      if (_hasUnsavedChanges) {
        _save();
      }
    });
  }
  
  // 强制立即保存，用于应用退出时
  Future<void> forceSave() async {
    if (_hasUnsavedChanges) {
      _saveTimer?.cancel();
      await _save();
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
      notifyListeners(); // 立即更新UI
      _scheduleSave(); // 延迟保存，避免频繁的保存操作
    }
  }

  // 静默更新clip，不触发保存提示，用于播放界面等场景
  void updateClipSilently(VideoClip updatedClip) {
    final index = _clips.indexWhere((c) => c.id == updatedClip.id);
    if (index != -1) {
      _clips[index] = updatedClip;
      _generateOriginalVideos();
      notifyListeners(); // 立即更新UI
      // 不调用_scheduleSave()，避免触发保存提示
      // 但标记有未保存的更改，以便后续保存
      _hasUnsavedChanges = true;
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

  // 获取过滤后的clip列表，用于播放界面的导航
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
      final textMatch =
          query.isEmpty ||
              clip.name.toLowerCase().contains(query) ||
              (clip.notes?.toLowerCase().contains(query) ?? false) ||
              clip.videoPath.toLowerCase().contains(query);

      final tagMatch =
          tags.isEmpty ||
              tags.every((tag) => clip.tags.contains(tag));

      // 星级匹配逻辑：
      // rating == null: 不过滤星级
      // rating == 0: 只显示无星级的clips
      // rating == 1-5: 只显示对应星级的clips
      final ratingMatch = rating == null || clip.rating == rating;
      
      final favoriteMatch = favorite == null || clip.isFavorite == favorite;

      return textMatch && tagMatch && ratingMatch && favoriteMatch;
    }).toList();
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }
  
  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
