import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'models.dart';
import '../services/path_service.dart';

class LoadResult {
  final List<VideoClip>? clips;
  final List<OriginalVideo>? videos;
  final List<Playlist>? playlists;
  final List<OnlineVideo>? onlineVideos;
  final List<OnlineVideoClip>? onlineVideoClips;
  final String? path;
  LoadResult({
    this.clips, 
    this.videos, 
    this.playlists, 
    this.onlineVideos,
    this.onlineVideoClips,
    this.path
  });
}

class DataService {
  final PathService pathService;

  DataService({required this.pathService});

  Future<void> ensureDirectoryExists(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  Future<LoadResult> pickAndLoadClips() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final clips = await loadClipsFromPath(path);
      return LoadResult(clips: clips, path: path);
    }
    return LoadResult();
  }

  Future<List<VideoClip>> loadClipsFromPath(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        await ensureDirectoryExists(p.dirname(path));
        await file.create();
        return [];
      }
      final jsonString = await file.readAsString();
      if (jsonString.isEmpty) return [];

      final List<dynamic> jsonList = json.decode(jsonString);
      return jsonList.map((json) => VideoClip.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error loading clips from $path: $e');
      rethrow;
    }
  }

  Future<String> saveClipsToPath(List<VideoClip> clips, String path) async {
    try {
      await ensureDirectoryExists(p.dirname(path));
      final file = File(path);
      final jsonList = clips.map((clip) => clip.toJson()).toList();
      final jsonString = const JsonEncoder.withIndent('  ').convert(jsonList);
      await file.writeAsString(jsonString);
      return 'Successfully saved to $path';
    } catch (e) {
      debugPrint('Error saving clips to $path: $e');
      rethrow;
    }
  }

  Future<String> saveDataToPath(
    List<VideoClip> clips,
    List<OriginalVideo> videos,
    List<Playlist> playlists,
    List<OnlineVideo> onlineVideos,
    List<OnlineVideoClip> onlineVideoClips,
    String path,
  ) async {
    try {
      await ensureDirectoryExists(p.dirname(path));
      final file = File(path);

      final data = {
        'clips': clips.map((clip) => clip.toJson()).toList(),
        'videos': videos.map((video) => video.toJson()).toList(),
        'playlists': playlists.map((playlist) => playlist.toJson()).toList(),
        'onlineVideos': onlineVideos.map((video) => video.toJson()).toList(),
        'onlineVideoClips': onlineVideoClips.map((clip) => clip.toJson()).toList(),
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(data);
      await file.writeAsString(jsonString);
      return 'Successfully saved to $path';
    } catch (e) {
      debugPrint('Error saving data to $path: $e');
      rethrow;
    }
  }

  Future<LoadResult> loadDataFromPath(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        await ensureDirectoryExists(p.dirname(path));
        await file.create();
        return LoadResult(clips: [], path: path);
      }

      final jsonString = await file.readAsString();
      if (jsonString.isEmpty) return LoadResult(clips: [], path: path);

      // 尝试解析为新格式（包含所有数据类型的对象）
      try {
        final Map<String, dynamic> data = json.decode(jsonString);
        if (data.containsKey('clips') && data.containsKey('videos')) {
          final clips = (data['clips'] as List)
              .map((json) => VideoClip.fromJson(json))
              .toList();
          final videos = (data['videos'] as List)
              .map((json) => OriginalVideo.fromJson(json))
              .toList();
          final playlists = data.containsKey('playlists')
              ? (data['playlists'] as List)
                    .map((json) => Playlist.fromJson(json))
                    .toList()
              : <Playlist>[];
          final onlineVideos = data.containsKey('onlineVideos')
              ? (data['onlineVideos'] as List)
                    .map((json) => OnlineVideo.fromJson(json))
                    .toList()
              : <OnlineVideo>[];
          final onlineVideoClips = data.containsKey('onlineVideoClips')
              ? (data['onlineVideoClips'] as List)
                    .map((json) => OnlineVideoClip.fromJson(json))
                    .toList()
              : <OnlineVideoClip>[];
          
          return LoadResult(
            clips: clips,
            videos: videos,
            playlists: playlists,
            onlineVideos: onlineVideos,
            onlineVideoClips: onlineVideoClips,
            path: path,
          );
        }
      } catch (e) {
        // 如果解析为新格式失败，尝试旧格式
        debugPrint('Failed to parse as new format, trying old format: $e');
      }

      // 旧格式，只有clips数组
      final List<dynamic> jsonList = json.decode(jsonString);
      final clips = jsonList.map((json) => VideoClip.fromJson(json)).toList();
      return LoadResult(clips: clips, path: path);
    } catch (e) {
      debugPrint('Error loading data from $path: $e');
      rethrow;
    }
  }

  String getDefaultDbPath() {
    return pathService.getDefaultDbPath();
  }
}
