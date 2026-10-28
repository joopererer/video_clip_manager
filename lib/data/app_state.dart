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
import '../services/ai_service.dart';
import '../services/delta_engine.dart';
import '../services/frame_embedding_pool.dart';
import '../services/screenshot_service.dart';

const String _prefsKeyDbPath = 'db_path';

class AppState extends ChangeNotifier {
  // 静态实例，用于全局访问
  static AppState? _instance;
  static AppState? get instance => _instance;
  final SharedPreferences _prefs;
  final PathService _pathService;
  final ThumbnailService _thumbnailService;
  late final DataService _dataService;
  late final VideoMetadataService _videoMetadataService;
  late final AiService _aiService;
  late final FrameEmbeddingPool _framePool;
  late final DeltaEngine _deltaEngine;

  AiService get aiService => _aiService;
  FrameEmbeddingPool get framePool => _framePool;
  DeltaEngine get deltaEngine => _deltaEngine;

  final Map<String, MaxSimResult> _semanticScores = {};
  bool _isSemanticSearching = false;
  bool get isSemanticSearching => _isSemanticSearching;
  String? _searchStatus;
  String? get searchStatus => _searchStatus;
  Map<String, MaxSimResult> get semanticScores =>
      Map.unmodifiable(_semanticScores);
  String? _lastSemanticError;
  String? get lastSemanticError => _lastSemanticError;

  // 全局特征索引库状态
  bool _isIndexingEmbeddings = false;
  bool get isIndexingEmbeddings => _isIndexingEmbeddings;
  double _indexingProgress = 0.0;
  double get indexingProgress => _indexingProgress;
  String? _indexingStatus;
  String? get indexingStatus => _indexingStatus;

  // VLM 视觉大模型配置
  String get vlmMode => _prefs.getString('vlm_mode') ?? 'ollama';
  String get vlmApiUrl =>
      _prefs.getString('vlm_api_url') ?? 'http://localhost:11434/v1';
  String get vlmApiKey => _prefs.getString('vlm_api_key') ?? '';
  String get vlmModel => _prefs.getString('vlm_model') ?? 'qwen2-vl:2b';

  Future<void> saveVlmConfig({
    required String mode,
    required String apiUrl,
    required String apiKey,
    required String model,
  }) async {
    await _prefs.setString('vlm_mode', mode);
    await _prefs.setString('vlm_api_url', apiUrl);
    await _prefs.setString('vlm_api_key', apiKey);
    await _prefs.setString('vlm_model', model);
    notifyListeners();
  }

  List<VideoClip> _clips = [];
  List<OriginalVideo> _originalVideos = [];
  List<Playlist> _playlists = [];

  // 新增：在线视频相关状态
  List<OnlineVideo> _onlineVideos = [];
  List<OnlineVideoClip> _onlineVideoClips = [];

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

  // 新增：在线视频相关的getter
  UnmodifiableListView<OnlineVideo> get onlineVideos =>
      UnmodifiableListView(_onlineVideos);
  UnmodifiableListView<OnlineVideoClip> get onlineVideoClips =>
      UnmodifiableListView(_onlineVideoClips);

  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isGeneratingThumbnails => _isGeneratingThumbnails;
  String get currentDbPath => _currentDbPath != null
      ? p.basename(_currentDbPath!)
      : 'No Database Loaded';
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
  }) : _prefs = prefs,
       _pathService = pathService,
       _thumbnailService = thumbnailService {
    _dataService = DataService(pathService: _pathService);
    _videoMetadataService = VideoMetadataService();
    _aiService = AiService();
    _framePool = FrameEmbeddingPool();
    _deltaEngine = DeltaEngine(pool: _framePool, aiService: _aiService);
    _clipsIsGridView = _prefs.getBool('clipsIsGridView') ?? false;
    _videosIsGridView = _prefs.getBool('videosIsGridView') ?? false;
    _playlistsIsGridView = _prefs.getBool('playlistsIsGridView') ?? false;
    _playlistsSortBy = _prefs.getString('playlistsSortBy') ?? 'name';

    // Timeouts and other tunables (persisted)
    _openTimeoutSeconds = _prefs.getInt('timeout_open_seconds') ?? 10;
    _seekTimeoutSeconds = _prefs.getInt('timeout_seek_seconds') ?? 10;
    _playTimeoutSeconds = _prefs.getInt('timeout_play_seconds') ?? 5;
    _screenshotTimeoutSeconds =
        _prefs.getInt('timeout_screenshot_seconds') ?? 15;
    _markReadyDelayMs = _prefs.getInt('mark_ready_delay_ms') ?? 300;

    // 设置静态实例
    _instance = this;
  }

  // --- Tunable timeouts (persisted) ---
  late int _openTimeoutSeconds;
  late int _seekTimeoutSeconds;
  late int _playTimeoutSeconds;
  late int _screenshotTimeoutSeconds;
  late int _markReadyDelayMs;

  int get openTimeoutSeconds => _openTimeoutSeconds;
  int get seekTimeoutSeconds => _seekTimeoutSeconds;
  int get playTimeoutSeconds => _playTimeoutSeconds;
  int get screenshotTimeoutSeconds => _screenshotTimeoutSeconds;
  int get markReadyDelayMs => _markReadyDelayMs;

  void setOpenTimeoutSeconds(int secs) {
    _openTimeoutSeconds = secs;
    _prefs.setInt('timeout_open_seconds', secs);
    notifyListeners();
  }

  void setSeekTimeoutSeconds(int secs) {
    _seekTimeoutSeconds = secs;
    _prefs.setInt('timeout_seek_seconds', secs);
    notifyListeners();
  }

  void setPlayTimeoutSeconds(int secs) {
    _playTimeoutSeconds = secs;
    _prefs.setInt('timeout_play_seconds', secs);
    notifyListeners();
  }

  void setScreenshotTimeoutSeconds(int secs) {
    _screenshotTimeoutSeconds = secs;
    _prefs.setInt('timeout_screenshot_seconds', secs);
    notifyListeners();
  }

  void setMarkReadyDelayMs(int ms) {
    _markReadyDelayMs = ms;
    _prefs.setInt('mark_ready_delay_ms', ms);
    ScreenshotService().markReady();
    notifyListeners();
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
    bool hasChanges =
        _selectedTags.isNotEmpty ||
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
      _onlineVideos = result.onlineVideos ?? [];
      _onlineVideoClips = result.onlineVideoClips ?? [];

      _generateOriginalVideosIfNeeded();
      notifyListeners();

      // 异步预加载母视频已有的关键帧向量缓存
      for (final video in _originalVideos) {
        unawaited(_framePool.loadFromDisk(video.path));
      }

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
      // 处理缺少元数据的视频
      final videosNeedingMetadata = _originalVideos
          .where((v) => v.duration == null)
          .toList();
      if (videosNeedingMetadata.isNotEmpty) {
        debugPrint(
          'Populating metadata for ${videosNeedingMetadata.length} videos...',
        );
        await Future.wait(
          videosNeedingMetadata.map((v) => updateVideoMetadata(v.id)),
        );
      }

      // 处理缺少缩略图的视频（有duration但没有缩略图或缩略图文件不存在）
      final videosNeedingThumbnails = <OriginalVideo>[];
      if (currentDbFullPath != null) {
        for (final video in _originalVideos) {
          if (video.duration != null) {
            bool needsThumbnail = false;

            if (video.thumbnailPath == null) {
              // 没有缩略图路径
              needsThumbnail = true;
            } else {
              // 有缩略图路径，检查文件是否存在
              final thumbPath = _thumbnailService.getThumbnailPathForDatabase(
                currentDbFullPath!,
                video.id,
              );
              final fileExists = await File(thumbPath).exists();
              if (!fileExists) {
                needsThumbnail = true;
              }
            }

            if (needsThumbnail) {
              videosNeedingThumbnails.add(video);
            }
          }
        }
      }

      if (videosNeedingThumbnails.isNotEmpty) {
        debugPrint(
          'Populating thumbnails for ${videosNeedingThumbnails.length} videos...',
        );
        final futures = videosNeedingThumbnails.map((video) async {
          final thumbnailFileName = await _thumbnailService.generateThumbnail(
            video.path,
            Duration(milliseconds: video.duration!.inMilliseconds ~/ 2),
            video.id,
            dbPath: _currentDbPath!,
          );
          if (thumbnailFileName != null) {
            final index = _originalVideos.indexWhere((v) => v.id == video.id);
            if (index != -1) {
              _originalVideos[index] = video.copyWith(
                thumbnailPath: thumbnailFileName,
              );
            }
          }
        });
        await Future.wait(futures);
      }

      // 处理缺少缩略图的clips
      final clipsNeedingThumbnails = <VideoClip>[];
      if (currentDbFullPath != null) {
        for (final clip in _clips) {
          bool needsThumbnail = false;

          if (clip.thumbnailPath == null) {
            // 没有缩略图路径
            needsThumbnail = true;
          } else {
            // 有缩略图路径，检查文件是否存在
            final thumbPath = _thumbnailService.getThumbnailPathForDatabase(
              currentDbFullPath!,
              clip.id,
            );
            final fileExists = await File(thumbPath).exists();
            if (!fileExists) {
              needsThumbnail = true;
            }
          }

          if (needsThumbnail) {
            clipsNeedingThumbnails.add(clip);
          }
        }
      }

      if (clipsNeedingThumbnails.isNotEmpty) {
        debugPrint(
          'Populating thumbnails for ${clipsNeedingThumbnails.length} clips...',
        );
        final futures = clipsNeedingThumbnails.map((clip) async {
          final thumbnailFileName = await _thumbnailService.generateThumbnail(
            clip.videoPath,
            clip.coverFrameTime,
            clip.id,
            dbPath: _currentDbPath!,
          );
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
    if (_originalVideos.isNotEmpty &&
        _originalVideos.every((v) => v.id.isNotEmpty)) {
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
        final thumbDir = _thumbnailService.getThumbnailDirForDatabase(
          currentDbFullPath!,
        );
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
        _originalVideos[i] = _originalVideos[i].copyWith(
          thumbnailPath: null,
          duration: null,
        );
      }
      notifyListeners();

      // Regenerate thumbnails for clips
      if (_clips.isNotEmpty) {
        debugPrint('Regenerating thumbnails for ${_clips.length} clips...');
        final futures = _clips.map((clip) async {
          final thumbnailFileName = await _thumbnailService.generateThumbnail(
            clip.videoPath,
            clip.coverFrameTime,
            clip.id,
            dbPath: _currentDbPath!,
          );
          if (thumbnailFileName != null) {
            updateClipThumbnail(clip.id, thumbnailFileName);
          }
        });
        await Future.wait(futures);
      }

      // Regenerate metadata and thumbnails for videos
      if (_originalVideos.isNotEmpty) {
        debugPrint(
          'Regenerating metadata and thumbnails for ${_originalVideos.length} videos...',
        );
        final futures = _originalVideos.map(
          (video) => updateVideoMetadata(video.id),
        );
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
        _onlineVideos,
        _onlineVideoClips,
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

  void deleteOriginalVideo(String videoId) {
    _originalVideos.removeWhere((v) => v.id == videoId);
    // 同时删除相关的片段
    _clips.removeWhere(
      (c) =>
          c.videoPath ==
          _originalVideos.firstWhereOrNull((v) => v.id == videoId)?.path,
    );
    notifyListeners();
    _scheduleSave();
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
      debugPrint(
        'Updated video ${video.name} with duration: $duration and thumbnail: $thumbnailPath',
      );
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
      clip.videoPath,
      clip.coverFrameTime,
      clip.id,
      dbPath: _currentDbPath!,
    );

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
    if (videoWithMeta?.duration == null ||
        videoWithMeta!.duration! <= Duration.zero) {
      debugPrint("Attempting to get metadata for video: ${video.name}");
      await updateVideoMetadata(video.id);

      // Get the updated video
      final updatedVideo = _originalVideos.firstWhereOrNull(
        (v) => v.id == video.id,
      );
      if (updatedVideo?.duration == null ||
          updatedVideo!.duration! <= Duration.zero) {
        debugPrint(
          "Cannot create clip from video with no duration: ${video.name}",
        );
        return;
      }

      final clipId =
          'clip_${DateTime.now().millisecondsSinceEpoch}_${video.id}';
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
      final clipId =
          'clip_${DateTime.now().millisecondsSinceEpoch}_${video.id}';
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
    _deleteClip(clipId);
    notifyListeners();
    await _save();
  }

  Future<void> _deleteClip(String clipId) async {
    _clips.removeWhere((c) => c.id == clipId);
    // also remove from playlists
    for (var p in _playlists) {
      p.items.removeWhere((item) => item.clipId == clipId);
    }
    _thumbnailService.deleteThumbnail(_currentDbPath!, clipId);
  }

  Future<void> deleteVideo(String videoId, {bool deleteClips = false}) async {
    final video = _originalVideos.firstWhere((v) => v.id == videoId);
    final relatedClips = _clips
        .where((c) => c.videoPath == video.path)
        .toList();

    if (deleteClips) {
      // 删除所有相关clips
      for (var clip in relatedClips) {
        _deleteClip(clip.id);
      }
    }

    // 删除视频
    _originalVideos.removeWhere((v) => v.id == videoId);
    _thumbnailService.deleteThumbnail(_currentDbPath!, videoId);

    notifyListeners();
    await _save();
  }

  /// 执行跨片段语义检索
  Future<void> performSemanticSearch({
    required String query,
    required String modelDir,
    String? ortLib,
    double minScore = 0.28,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _semanticScores.clear();
      _lastSemanticError = null;
      _searchStatus = null;
      notifyListeners();
      return;
    }

    _lastSemanticError = null;
    _isSemanticSearching = true;
    _searchStatus = '正在将查询词转化为 768 维语义向量...';
    notifyListeners();

    try {
      final queryVec = await _aiService.embedText(
        text: trimmed,
        prefix: 'search_query: ',
        modelDir: modelDir,
        ortLib: ortLib,
      );

      _semanticScores.clear();

      for (int i = 0; i < _clips.length; i++) {
        final clip = _clips[i];

        // 1. 优先加载磁盘中的母视频帧池缓存
        if (_framePool.getCachedTimestamps(clip.videoPath).isEmpty) {
          await _framePool.loadFromDisk(clip.videoPath);
        }

        var frames = _framePool.getFramesInRange(
          clip.videoPath,
          clip.startTime.inMilliseconds,
          clip.endTime.inMilliseconds,
        );

        // 2. 若本地片段尚未抽取过帧嵌入，按需自动补全抽取并计算
        if (frames.isEmpty &&
            !clip.videoPath.startsWith('http://') &&
            !clip.videoPath.startsWith('https://') &&
            File(clip.videoPath).existsSync()) {
          _searchStatus = '正在提取未索引片段的画面特征 (${i + 1}/${_clips.length})...';
          notifyListeners();

          try {
            frames = await _deltaEngine.syncClipRange(
              videoPathOrUrl: clip.videoPath,
              startMs: clip.startTime.inMilliseconds,
              endMs: clip.endTime.inMilliseconds,
              modelDir: modelDir,
              ortLib: ortLib,
            );
          } catch (syncErr) {
            debugPrint(
              '[AppState] Auto-sync clip frames on search error: $syncErr',
            );
          }
        }

        // 3. 计算 MaxSim 相似度
        if (frames.isNotEmpty) {
          final maxSim = _deltaEngine.computeMaxSim(
            queryVector: queryVec,
            frames: frames,
          );
          if (maxSim.score >= minScore) {
            _semanticScores[clip.id] = maxSim;
          }
        }
      }
    } catch (e) {
      _lastSemanticError = e.toString().replaceFirst('Exception: ', '');
      debugPrint('[AppState] performSemanticSearch error: $e');
    } finally {
      _isSemanticSearching = false;
      _searchStatus = null;
      notifyListeners();
    }
  }

  /// 获取已完成语义特征构建的片段数量统计 (已索引数, 总片段数, 总缓存帧数)
  Map<String, int> getEmbeddingStats() {
    int indexed = 0;
    int totalFrames = 0;
    for (final clip in _clips) {
      final frames = _framePool.getFramesInRange(
        clip.videoPath,
        clip.startTime.inMilliseconds,
        clip.endTime.inMilliseconds,
      );
      if (frames.isNotEmpty) {
        indexed++;
        totalFrames += frames.length;
      }
    }
    return {
      'indexed': indexed,
      'total': _clips.length,
      'totalFrames': totalFrames,
    };
  }

  /// 全局一键为所有本地片段扫描并增量构建向量索引
  Future<void> indexAllClips({
    void Function(int current, int total, String clipName)? onProgress,
  }) async {
    if (_isIndexingEmbeddings) return;
    _isIndexingEmbeddings = true;
    _indexingProgress = 0.0;
    _indexingStatus = '准备构建语义特征向量库...';
    notifyListeners();

    try {
      final modelDir = await _aiService.resolveEmbeddingModelDir() ?? 'models';
      final localClips = _clips
          .where(
            (c) =>
                !c.videoPath.startsWith('http://') &&
                !c.videoPath.startsWith('https://') &&
                File(c.videoPath).existsSync(),
          )
          .toList();

      if (localClips.isEmpty) {
        _indexingStatus = '暂无需要索引的本地片段。';
        return;
      }

      for (int i = 0; i < localClips.length; i++) {
        final clip = localClips[i];
        _indexingProgress = (i + 1) / localClips.length;
        _indexingStatus =
            '正在提取关键帧特征 (${i + 1}/${localClips.length}): ${clip.name}';
        notifyListeners();
        onProgress?.call(i + 1, localClips.length, clip.name);

        // 先载入磁盘已有记录
        if (_framePool.getCachedTimestamps(clip.videoPath).isEmpty) {
          await _framePool.loadFromDisk(clip.videoPath);
        }

        // 增量规划与同步
        await _deltaEngine.syncClipRange(
          videoPathOrUrl: clip.videoPath,
          startMs: clip.startTime.inMilliseconds,
          endMs: clip.endTime.inMilliseconds,
          modelDir: modelDir,
        );
      }
      _indexingStatus = '所有本地片段语义向量构建完成！';
    } catch (e) {
      _indexingStatus = '索引构建中断: $e';
    } finally {
      _isIndexingEmbeddings = false;
      notifyListeners();
    }
  }

  /// 清除语义检索结果
  void clearSemanticSearch() {
    if (_semanticScores.isNotEmpty) {
      _semanticScores.clear();
      _searchStatus = null;
      notifyListeners();
    }
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
    final query = searchQuery.toLowerCase().trim();

    final filtered = <VideoClip>[];

    for (final clip in _clips) {
      final textMatch =
          query.isEmpty ||
          clip.name.toLowerCase().contains(query) ||
          (clip.notes?.toLowerCase().contains(query) ?? false) ||
          (clip.aiSummary?.toLowerCase().contains(query) ?? false) ||
          (clip.aiScene?.toLowerCase().contains(query) ?? false) ||
          clip.aiActions.any((a) => a.toLowerCase().contains(query));

      final semHit = _semanticScores[clip.id];
      final semanticMatch = semHit != null;

      final isMatch = textMatch || semanticMatch;
      final tagMatch =
          tags.isEmpty || tags.every((tag) => clip.tags.contains(tag));
      final ratingMatch = rating == null || clip.rating == rating;
      final favoriteMatch = favorite == null || clip.isFavorite == favorite;

      if (isMatch && tagMatch && ratingMatch && favoriteMatch) {
        if (semHit != null) {
          filtered.add(clip.copyWith(hitTimestampMs: semHit.hitTimestampMs));
        } else {
          filtered.add(clip);
        }
      }
    }

    if (_semanticScores.isNotEmpty) {
      filtered.sort((a, b) {
        final scoreA = _semanticScores[a.id]?.score ?? 0.0;
        final scoreB = _semanticScores[b.id]?.score ?? 0.0;
        return scoreB.compareTo(scoreA);
      });
    }

    return filtered;
  }

  List<OriginalVideo> getFilteredVideos({String searchQuery = ''}) {
    if (searchQuery.isEmpty) return _originalVideos;
    final query = searchQuery.toLowerCase();
    return _originalVideos
        .where((video) => video.name.toLowerCase().contains(query))
        .toList();
  }

  // --- Playlist Methods ---
  void createPlaylist(String name, {String? description}) {
    final playlist = Playlist.create(name: name, description: description);
    _playlists.add(playlist);
    notifyListeners();
    _scheduleSave();
  }

  void updatePlaylist(
    String playlistId, {
    String? name,
    String? description,
    List<PlaylistItem>? items,
  }) {
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
      final newItems = playlist.items
          .where((item) => item.id != itemId)
          .toList();
      _playlists[index] = playlist.copyWith(
        items: newItems,
        updatedAt: DateTime.now(),
      );
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

      final reorderedItems = items
          .map((item) => item.copyWith(order: items.indexOf(item)))
          .toList();

      _playlists[index] = playlist.copyWith(
        items: reorderedItems,
        updatedAt: DateTime.now(),
      );
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
          return clip != null
              ? PlaylistItemWithClip(item: item, clip: clip)
              : null;
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

  // --- 在线视频管理方法 ---

  /// 添加在线视频
  Future<void> addOnlineVideo(OnlineVideo video) async {
    if (_onlineVideos.any((v) => v.id == video.id)) {
      throw Exception('Online video with ID ${video.id} already exists');
    }

    _onlineVideos.add(video);
    notifyListeners();
    _scheduleSave();
  }

  /// 更新在线视频
  Future<void> updateOnlineVideo(OnlineVideo video) async {
    final index = _onlineVideos.indexWhere((v) => v.id == video.id);
    if (index != -1) {
      _onlineVideos[index] = video;
      notifyListeners();
      _scheduleSave();
    }
  }

  /// 删除在线视频
  Future<void> deleteOnlineVideo(String videoId) async {
    _onlineVideos.removeWhere((v) => v.id == videoId);
    // 同时删除相关的在线片段
    _onlineVideoClips.removeWhere((c) => c.onlineVideoId == videoId);
    notifyListeners();
    _scheduleSave();
  }

  /// 获取在线视频
  OnlineVideo? getOnlineVideo(String videoId) {
    return _onlineVideos.firstWhereOrNull((v) => v.id == videoId);
  }

  /// 添加在线视频片段
  Future<void> addOnlineVideoClip(OnlineVideoClip clip) async {
    if (_onlineVideoClips.any((c) => c.id == clip.id)) {
      throw Exception('Online video clip with ID ${clip.id} already exists');
    }

    _onlineVideoClips.add(clip);
    notifyListeners();
    _scheduleSave();
  }

  /// 更新在线视频片段
  Future<void> updateOnlineVideoClip(OnlineVideoClip clip) async {
    final index = _onlineVideoClips.indexWhere((c) => c.id == clip.id);
    if (index != -1) {
      _onlineVideoClips[index] = clip;
      notifyListeners();
      _scheduleSave();
    }
  }

  /// 删除在线视频片段
  Future<void> deleteOnlineVideoClip(String clipId) async {
    _onlineVideoClips.removeWhere((c) => c.id == clipId);
    notifyListeners();
    _scheduleSave();
  }

  /// 获取在线视频片段
  OnlineVideoClip? getOnlineVideoClip(String clipId) {
    return _onlineVideoClips.firstWhereOrNull((c) => c.id == clipId);
  }

  /// 获取指定在线视频的所有片段
  List<OnlineVideoClip> getOnlineVideoClips(String onlineVideoId) {
    return _onlineVideoClips
        .where((c) => c.onlineVideoId == onlineVideoId)
        .toList();
  }

  /// 获取所有标签（包括在线片段的标签）
  UnmodifiableListView<String> get allTags {
    final allTagsSet = <String>{};

    // 添加本地片段标签
    for (final clip in _clips) {
      allTagsSet.addAll(clip.tags);
    }

    // 添加在线片段标签
    for (final clip in _onlineVideoClips) {
      allTagsSet.addAll(clip.tags);
    }

    return UnmodifiableListView(allTagsSet.toList()..sort());
  }

  /// 获取混合片段列表（本地片段 + 在线片段）
  List<dynamic> getMixedClips() {
    final List<dynamic> mixedClips = [];

    // 添加本地片段
    for (final clip in _clips) {
      mixedClips.add({
        'type': 'local',
        'clip': clip,
        'video': _originalVideos.firstWhereOrNull(
          (v) => v.path == clip.videoPath,
        ),
      });
    }

    // 添加在线片段
    for (final clip in _onlineVideoClips) {
      mixedClips.add({
        'type': 'online',
        'clip': clip,
        'video': _onlineVideos.firstWhereOrNull(
          (v) => v.id == clip.onlineVideoId,
        ),
      });
    }

    return mixedClips;
  }

  /// 获取混合视频列表（本地视频 + 在线视频）
  List<dynamic> getMixedVideos({String? searchQuery}) {
    final List<dynamic> mixedVideos = [];

    // 添加本地视频
    for (final video in _originalVideos) {
      if (searchQuery == null ||
          searchQuery.isEmpty ||
          video.name.toLowerCase().contains(searchQuery.toLowerCase())) {
        mixedVideos.add({'type': 'local', 'video': video});
      }
    }

    // 添加在线视频
    for (final video in _onlineVideos) {
      if (searchQuery == null ||
          searchQuery.isEmpty ||
          video.title.toLowerCase().contains(searchQuery.toLowerCase()) ||
          (video.description?.toLowerCase().contains(
                searchQuery.toLowerCase(),
              ) ??
              false)) {
        mixedVideos.add({'type': 'online', 'video': video});
      }
    }

    return mixedVideos;
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
