import 'dart:io';
import 'package:flutter/foundation.dart';
import 'dart:collection';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async'; // Added for Timer

import 'models.dart';
import 'data_service.dart';
import '../services/path_service.dart';
import '../services/thumbnail_service.dart';
import '../services/video_metadata_service.dart';
import '../services/video_metadata_cache.dart';

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
  String _playlistsSortBy = 'name'; // 播放列表排序方式

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
  UnmodifiableListView<Playlist> get playlists =>
      UnmodifiableListView(_playlists);

  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isGeneratingThumbnails => _isGeneratingThumbnails;
  String get currentDbPath => _currentDbPath != null
      ? p.basename(_currentDbPath!)
      : 'No Database Loaded';
  String? get currentDbFullPath => _currentDbPath;
  ThumbnailService get thumbnailService => _thumbnailService;
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
  }) : _prefs = prefs,
       _pathService = pathService,
       _thumbnailService = thumbnailService {
    _dataService = DataService(pathService: _pathService);
    _videoMetadataService = VideoMetadataService(
      thumbnailService: _thumbnailService,
    );
    _clipsIsGridView = _prefs.getBool('clipsIsGridView') ?? false;
    _videosIsGridView = _prefs.getBool('videosIsGridView') ?? false;
    _playlistsIsGridView = _prefs.getBool('playlistsIsGridView') ?? false;
    _playlistsSortBy = _prefs.getString('playlistsSortBy') ?? 'name';
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

      final result = await _dataService.loadDataFromPath(_currentDbPath!);
      _clips = result.clips ?? [];

      if (result.videos != null) {
        _originalVideos = result.videos!;
      } else {
        // 兼容旧格式，从clips生成videos
        _generateOriginalVideos();
      }

      if (result.playlists != null) {
        _playlists = result.playlists!;
      }

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

        if (result.videos != null) {
          _originalVideos = result.videos!;
        } else {
          _generateOriginalVideos();
        }

        if (result.playlists != null) {
          _playlists = result.playlists!;
        }

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
    // 防止重复调用
    if (_isGeneratingThumbnails) {
      debugPrint('forceRefreshThumbnails: Already in progress, skipping');
      return;
    }
    
    _isGeneratingThumbnails = true;
    notifyListeners();

    try {
      debugPrint('=== Starting forceRefreshThumbnails ===');
      debugPrint('Clips count: ${_clips.length}');
      debugPrint('Videos count: ${_originalVideos.length}');

      // 1. 清空 Thumbnail 目录
      debugPrint('Step 1: Clearing thumbnail directories...');

      // 清除默认缩略图目录
      await _thumbnailService.clearCache();

      // 清除当前数据库对应的缩略图目录
      if (_currentDbPath != null) {
        final thumbDir = _thumbnailService.getThumbnailDirForDatabase(
          _currentDbPath!,
        );
        final dir = Directory(thumbDir);
        if (await dir.exists()) {
          final files = dir.list();
          await for (final file in files) {
            try {
              await file.delete();
              debugPrint('Deleted thumbnail file: ${file.path}');
            } catch (e) {
              debugPrint('Failed to delete file ${file.path}: $e');
            }
          }
        }
      }

      // 2. 重新生成 clip 封面图
      debugPrint('Step 2: Generating clip thumbnails...');
      if (_clips.isNotEmpty) {
        await _thumbnailService.generateThumbnailsInBatch(_clips, () {
          notifyListeners();
        });
      }

      // 3. 重新生成 video 封面图
      debugPrint('Step 3: Generating video thumbnails...');
      if (_originalVideos.isNotEmpty) {
        // 创建新的视频列表，重置所有元数据
        final resetVideos = <OriginalVideo>[];
        for (int i = 0; i < _originalVideos.length; i++) {
          final originalVideo = _originalVideos[i];
          final resetVideo = OriginalVideo(
            id: originalVideo.id,
            path: originalVideo.path,
            name: originalVideo.name,
            duration: null,
            thumbnailPath: null,
            metadata: originalVideo.metadata,
          );
          resetVideos.add(resetVideo);
          debugPrint(
            'Reset video ${resetVideo.name}: thumbnailPath=null, duration=null',
          );
        }

        // 使用新的批量方法生成video缩略图
        final videoEntries = resetVideos.map((video) => MapEntry(video.id, video.path)).toList();
        await _thumbnailService.generateVideoThumbnailsInBatch(videoEntries, () {
          notifyListeners();
        });

        // 更新video的缩略图路径
        for (int i = 0; i < resetVideos.length; i++) {
          final video = resetVideos[i];
          final thumbnailFileName = _thumbnailService.getThumbnailFileName(video.id);
          final thumbPath = _thumbnailService.getThumbnailPath(video.id);
          
          // 检查缩略图文件是否存在
          if (await File(thumbPath).exists()) {
            final updatedVideo = video.copyWith(thumbnailPath: thumbnailFileName);
            _originalVideos[i] = updatedVideo;
            debugPrint(
              'Updated video ${updatedVideo.name} with thumbnail: ${updatedVideo.thumbnailPath}',
            );
          }
        }
      }

      // 4. 通知界面刷新
      debugPrint('Step 4: Notifying UI to refresh...');
      notifyListeners();

      debugPrint('=== Finished forceRefreshThumbnails ===');
    } catch (e) {
      debugPrint('Error in forceRefreshThumbnails: $e');
      debugPrint('Error stack trace: ${StackTrace.current}');
    } finally {
      _isGeneratingThumbnails = false;
      notifyListeners();
    }
  }

  Future<void> _populateAllThumbnails() async {
    debugPrint('=== Starting _populateAllThumbnails ===');

    final clipsToGenerate = <VideoClip>[];
    final videosToGenerate = <OriginalVideo>[];

    // 处理 clips 的缩略图
    for (final clip in _clips) {
      if (clip.thumbnailPath == null) {
        // 没有缩略图，需要生成
        clipsToGenerate.add(clip);
        debugPrint('Clip ${clip.name} needs thumbnail generation');
      } else {
        // 检查现有缩略图是否存在
        String fullThumbPath;
        if (!clip.thumbnailPath!.contains('\\') &&
            !clip.thumbnailPath!.contains('/')) {
          // 相对路径，构建完整路径
          fullThumbPath = _thumbnailService.buildThumbnailPath(
            _currentDbPath!,
            clip.thumbnailPath!,
          );
        } else {
          // 完整路径，直接使用
          fullThumbPath = clip.thumbnailPath!;
        }

        if (await File(fullThumbPath).exists()) {
          // 缩略图存在，更新为相对路径
          final index = _clips.indexWhere((c) => c.id == clip.id);
          if (index != -1) {
            final thumbnailFileName = _thumbnailService.getThumbnailFileName(
              clip.id,
            );
            _clips[index] = _clips[index].copyWith(
              thumbnailPath: thumbnailFileName,
            );
            debugPrint('Clip ${clip.name} thumbnail exists, updated path');
          }
        } else {
          // 缩略图不存在，需要生成
          clipsToGenerate.add(clip);
          debugPrint('Clip ${clip.name} thumbnail missing, needs generation');
        }
      }
    }

    // 处理 originalVideos 的缩略图
    for (final video in _originalVideos) {
      if (video.thumbnailPath == null) {
        // 没有缩略图，需要生成
        videosToGenerate.add(video);
        debugPrint('Video ${video.name} needs thumbnail generation');
      } else {
        // 检查现有缩略图是否存在
        String fullThumbPath;
        if (!video.thumbnailPath!.contains('\\') &&
            !video.thumbnailPath!.contains('/')) {
          // 相对路径，构建完整路径
          fullThumbPath = _thumbnailService.buildThumbnailPath(
            _currentDbPath!,
            video.thumbnailPath!,
          );
        } else {
          // 完整路径，直接使用
          fullThumbPath = video.thumbnailPath!;
        }

        if (await File(fullThumbPath).exists()) {
          // 缩略图存在，更新为相对路径
          final index = _originalVideos.indexWhere((v) => v.id == video.id);
          if (index != -1) {
            final thumbnailFileName = _thumbnailService.getThumbnailFileName(
              video.id,
            );
            _originalVideos[index] = _originalVideos[index].copyWith(
              thumbnailPath: thumbnailFileName,
            );
            debugPrint('Video ${video.name} thumbnail exists, updated path');
          }
        } else {
          // 缩略图不存在，需要生成
          videosToGenerate.add(video);
          debugPrint('Video ${video.name} thumbnail missing, needs generation');
        }
      }
    }

    debugPrint('Clips to generate: ${clipsToGenerate.length}');
    debugPrint('Videos to generate: ${videosToGenerate.length}');

    // 立即更新那些已经有缓存的缩略图
    notifyListeners();

    // 生成缺失的 clips 缩略图
    if (clipsToGenerate.isNotEmpty) {
      debugPrint('Generating clips thumbnails...');
      await _thumbnailService.generateThumbnailsInBatch(clipsToGenerate, () {
        notifyListeners();
      });
    }

    // 生成缺失的 videos 缩略图
    if (videosToGenerate.isNotEmpty) {
      debugPrint('Generating videos thumbnails...');
      await _videoMetadataService.processVideoMetadataBatch(videosToGenerate, (
        result,
      ) {
        // 找到对应的 video 在 _originalVideos 中的索引
        final videoIndex = _originalVideos.indexWhere(
          (v) => v.id == result.videoId,
        );
        if (videoIndex != -1 && result.success) {
          final video = _originalVideos[videoIndex];
          final updatedVideo = video.copyWith(
            duration: result.duration,
            thumbnailPath: result.thumbnailPath,
          );
          _originalVideos[videoIndex] = updatedVideo;
          debugPrint(
            'Updated video ${updatedVideo.name} with thumbnail: ${updatedVideo.thumbnailPath}',
          );
          notifyListeners();
        }
      });
    }

    debugPrint('=== Finished _populateAllThumbnails ===');
  }

  Future<void> _save() async {
    if (_currentDbPath == null) return;
    _isSaving = true;
    notifyListeners();
    await _dataService.saveDataToPath(
      _clips,
      _originalVideos,
      _playlists,
      _currentDbPath!,
    );
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

    // 创建新的视频列表，但保留现有的元数据
    final newVideos = <OriginalVideo>[];
    for (final entry in videoMap.entries) {
      final path = entry.key;
      final videoId = 'vid_${path.hashCode}';

      // 查找现有的视频对象，保留其元数据
      final existingVideo = _originalVideos
          .where((v) => v.path == path)
          .firstOrNull;

      if (existingVideo != null) {
        // 保留现有的元数据
        newVideos.add(existingVideo);
      } else {
        // 创建新的视频对象
        newVideos.add(
          OriginalVideo(id: videoId, path: path, name: p.basename(path)),
        );
      }
    }

    _originalVideos = newVideos;
  }

  Future<void> addClip(VideoClip clip) async {
    _clips.add(clip);
    _generateOriginalVideos();
    await _save();
    notifyListeners();
  }

  /// 检查视频是否有可用的元数据
  bool hasVideoMetadata(OriginalVideo video) {
    return video.duration != null &&
        video.duration != Duration.zero &&
        video.thumbnailPath != null;
  }

  /// 将整个视频创建为一个clip
  Future<void> createClipFromWholeVideo(OriginalVideo video) async {
    // 生成唯一的clip ID
    final clipId = 'clip_${DateTime.now().millisecondsSinceEpoch}_${video.id}';

    // 如果视频还没有元数据，先获取
    Duration? videoDuration = video.duration;
    String? thumbnailPath = video.thumbnailPath;

    if (videoDuration == null || thumbnailPath == null) {
      debugPrint(
        'VideoMetadataService: Getting metadata for whole video clip: ${video.name}',
      );
      try {
        // 获取视频元数据 - 使用新的处理方式
        await _videoMetadataService.processVideoMetadataBatch([video], (
          result,
        ) {
          // 找到对应的 video 在 _originalVideos 中的索引
          final videoIndex = _originalVideos.indexWhere(
            (v) => v.id == result.videoId,
          );
          if (videoIndex != -1 && result.success) {
            final video = _originalVideos[videoIndex];
            final updatedVideo = video.copyWith(
              duration: result.duration,
              thumbnailPath: result.thumbnailPath,
            );
            _originalVideos[videoIndex] = updatedVideo;
            videoDuration = updatedVideo.duration;
            thumbnailPath = updatedVideo.thumbnailPath;
            debugPrint(
              'Updated video ${updatedVideo.name} with duration: ${updatedVideo.duration}, thumbnail: ${updatedVideo.thumbnailPath}',
            );
            notifyListeners();
          }
        });

        // 更新原始视频的元数据
        final videoIndex = _originalVideos.indexWhere((v) => v.id == video.id);
        if (videoIndex != -1) {
          _originalVideos[videoIndex] = video.copyWith(
            duration: videoDuration,
            thumbnailPath: thumbnailPath,
          );
          notifyListeners();
        }
      } catch (e) {
        debugPrint('Error getting metadata for whole video clip: $e');
        // 如果获取失败，使用默认值，但不创建clip
        debugPrint('无法获取视频 "${video.name}" 的元数据，请稍后重试');
        return; // 不创建clip，等待元数据处理完成
      }
    }

    // 如果还是没有时长信息，不创建clip
    if (videoDuration == null || videoDuration == Duration.zero) {
      debugPrint('视频 "${video.name}" 的时长信息不可用，请稍后重试');
      return;
    }

    // 创建clip，整个视频作为片段
    final clip = VideoClip(
      id: clipId,
      name: video.name,
      videoPath: video.path,
      startTime: Duration.zero, // 从视频开始
      endTime: videoDuration!, // 到视频结束
      coverFrameTime: Duration.zero, // 封面时间设为开始
      tags: [],
      notes: '整个视频作为片段',
      rating: 0,
      isFavorite: false,
      thumbnailPath: thumbnailPath,
    );

    // 添加到clips列表
    await addClip(clip);
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
      // 文本搜索匹配
      bool textMatch = true;
      if (searchQuery.isNotEmpty) {
        final query = searchQuery.toLowerCase();
        textMatch =
            clip.name.toLowerCase().contains(query) ||
            (clip.notes?.toLowerCase().contains(query) ?? false) ||
            clip.videoPath.toLowerCase().contains(query);
      }

      // 标签匹配
      final tagMatch =
          tags.isEmpty || tags.every((tag) => clip.tags.contains(tag));

      // 星级匹配逻辑：
      // rating == null: 不过滤星级
      // rating == 0: 只显示无星级的clips
      // rating == 1-5: 只显示对应星级的clips
      final ratingMatch = rating == null || clip.rating == rating;

      final favoriteMatch = favorite == null || clip.isFavorite == favorite;

      return textMatch && tagMatch && ratingMatch && favoriteMatch;
    }).toList();
  }

  // 获取过滤后的视频列表
  List<OriginalVideo> getFilteredVideos({String searchQuery = ''}) {
    if (searchQuery.isEmpty) {
      return _originalVideos;
    }

    final query = searchQuery.toLowerCase();
    return _originalVideos.where((video) {
      return video.name.toLowerCase().contains(query) ||
          video.path.toLowerCase().contains(query);
    }).toList();
  }

  // 处理视频元数据（非阻塞）
  Future<void> processVideoMetadata() async {
    _videoMetadataService.processVideoMetadataBatch(_originalVideos, (result) {
      final index = _originalVideos.indexWhere((v) => v.id == result.videoId);
      if (index != -1) {
        final video = _originalVideos[index];
        final updatedVideo = video.copyWith(
          duration: result.duration,
          thumbnailPath: result.thumbnailPath,
        );
        _originalVideos[index] = updatedVideo;
        notifyListeners();
        _scheduleSave();
      }
    });
  }

  // 更新单个视频的元数据
  Future<void> updateVideoMetadata(String videoId) async {
    final index = _originalVideos.indexWhere((v) => v.id == videoId);
    if (index != -1) {
      final video = _originalVideos[index];
      debugPrint('Updating metadata for video: ${video.name}');
      debugPrint('Current thumbnailPath: ${video.thumbnailPath}');

      _videoMetadataService.processVideoMetadata(video.id, video.path, (result) {
        final updatedVideo = video.copyWith(
          duration: result.duration,
          thumbnailPath: result.thumbnailPath,
        );

        debugPrint('Updated video thumbnailPath: ${updatedVideo.thumbnailPath}');

        _originalVideos[index] = updatedVideo;
        notifyListeners();
        _scheduleSave();
      });
    }
  }

  // 强制重新处理所有视频
  Future<void> forceReprocessAllVideos() async {
    await _videoMetadataService.forceReprocessAll();
    await processVideoMetadata();
  }

  // 强制重新处理失败的视频
  Future<void> forceReprocessFailedVideos() async {
    await _videoMetadataService.forceReprocessFailed();
    await processVideoMetadata();
  }

  // 获取视频的处理状态
  VideoMetadataStatus? getVideoStatus(String videoId) {
    return _videoMetadataService.getVideoStatus(videoId);
  }

  // 添加原始视频
  void addOriginalVideo(OriginalVideo video) {
    // 检查是否已存在
    if (!_originalVideos.any((v) => v.path == video.path)) {
      _originalVideos.add(video);
      notifyListeners();
    }
  }

  // 更新原始视频
  void updateOriginalVideo(int index, OriginalVideo updatedVideo) {
    if (index >= 0 && index < _originalVideos.length) {
      _originalVideos[index] = updatedVideo;
      notifyListeners();
    }
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  // ========== Playlist 管理方法 ==========

  /// 创建新的播放列表
  void createPlaylist(String name, {String? description}) {
    final playlist = Playlist.create(name: name, description: description);
    _playlists.add(playlist);
    notifyListeners();
    _scheduleSave();
  }

  /// 更新播放列表
  void updatePlaylist(String playlistId, {String? name, String? description}) {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      final playlist = _playlists[index];

      final updatedPlaylist = playlist.copyWith(
        name: name ?? playlist.name,
        description: description, // 直接使用传入的 description，允许设置为 null
        updatedAt: DateTime.now(),
      );

      _playlists[index] = updatedPlaylist;
      notifyListeners();
      _scheduleSave();
    }
  }

  /// 删除播放列表
  void deletePlaylist(String playlistId) {
    _playlists.removeWhere((p) => p.id == playlistId);
    notifyListeners();
    _scheduleSave();
  }

  /// 添加 clip 到播放列表
  void addClipToPlaylist(
    String playlistId,
    String clipId, {
    Duration? customStartTime,
    Duration? customEndTime,
  }) {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      final playlist = _playlists[index];

      // 找到对应的 clip 来计算时长
      final clip = _clips.firstWhere((c) => c.id == clipId);
      final clipDuration = clip.endTime - clip.startTime;

      // 计算实际播放时长
      Duration actualDuration;
      if (customStartTime != null && customEndTime != null) {
        actualDuration = customEndTime - customStartTime;
      } else {
        actualDuration = clipDuration;
      }

      // 创建 PlaylistItem 并手动设置时长
      final newItem = PlaylistItem(
        id: 'item_${DateTime.now().millisecondsSinceEpoch}',
        clipId: clipId,
        order: playlist.items.length,
        customStartTime: customStartTime,
        customEndTime: customEndTime,
        duration: actualDuration,
      );

      final updatedPlaylist = playlist.copyWith(
        items: [...playlist.items, newItem],
        updatedAt: DateTime.now(),
      );

      _playlists[index] = updatedPlaylist;
      notifyListeners();
      _scheduleSave();
    }
  }

  /// 从播放列表移除 clip
  void removeClipFromPlaylist(String playlistId, String clipId) {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      final playlist = _playlists[index];
      final updatedPlaylist = playlist.removeClip(clipId);
      _playlists[index] = updatedPlaylist;
      notifyListeners();
      _scheduleSave();
    }
  }

  /// 从播放列表移除特定的播放列表项
  void removePlaylistItem(String playlistId, String itemId) {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      final playlist = _playlists[index];
      final updatedPlaylist = playlist.removeItem(itemId);
      _playlists[index] = updatedPlaylist;
      notifyListeners();
      _scheduleSave();
    }
  }

  /// 重新排序播放列表项
  void reorderPlaylistItems(String playlistId, int oldIndex, int newIndex) {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      final playlist = _playlists[index];
      final updatedPlaylist = playlist.reorderItems(oldIndex, newIndex);
      _playlists[index] = updatedPlaylist;
      notifyListeners();
      _scheduleSave();
    }
  }

  /// 获取播放列表中的 clips
  List<VideoClip> getPlaylistClips(String playlistId) {
    final playlist = _playlists.firstWhere((p) => p.id == playlistId);
    return playlist.items
        .map((item) {
          return _clips.firstWhereOrNull((clip) => clip.id == item.clipId);
        })
        .whereType<VideoClip>()
        .toList();
  }

  /// 获取播放列表项（包含 clip 信息）
  List<PlaylistItemWithClip> getPlaylistItemsWithClips(String playlistId) {
    final playlist = _playlists.firstWhere((p) => p.id == playlistId);
    return playlist.items
        .map((item) {
          final clip = _clips.firstWhereOrNull(
            (clip) => clip.id == item.clipId,
          );
          if (clip != null) {
            return PlaylistItemWithClip(item: item, clip: clip);
          }
          return null;
        })
        .whereType<PlaylistItemWithClip>()
        .toList();
  }

  /// 导入播放列表
  void importPlaylist(Map<String, dynamic> playlistData) {
    final name = playlistData['name'] as String? ?? '导入的播放列表';
    final description = playlistData['description'] as String?;
    final itemsData = playlistData['items'] as List<dynamic>? ?? [];

    // 创建新的播放列表
    final playlist = Playlist.create(name: name, description: description);

    // 处理播放列表项
    final List<PlaylistItem> importedItems = [];
    for (int i = 0; i < itemsData.length; i++) {
      final itemData = itemsData[i] as Map<String, dynamic>;
      final clipId = itemData['clipId'] as String?;

      // 检查 clip 是否存在
      if (clipId != null && _clips.any((clip) => clip.id == clipId)) {
        final item = PlaylistItem(
          id: 'item_${DateTime.now().millisecondsSinceEpoch}_$i',
          clipId: clipId,
          order: i,
          customStartTime: _parseDuration(itemData['customStartTime']),
          customEndTime: _parseDuration(itemData['customEndTime']),
          duration: _parseDuration(itemData['duration']),
        );
        importedItems.add(item);
      }
    }

    // 创建包含导入项的播放列表
    final importedPlaylist = playlist.copyWith(items: importedItems);
    _playlists.add(importedPlaylist);

    notifyListeners();
    _scheduleSave();
  }

  /// 解析时长数据
  Duration? _parseDuration(dynamic value) {
    if (value == null) return null;
    if (value is int) return Duration(milliseconds: value);
    if (value is String) {
      try {
        // 尝试解析 ISO 8601 格式
        return Duration(microseconds: int.parse(value));
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _videoMetadataService.dispose();
    super.dispose();
  }
}
