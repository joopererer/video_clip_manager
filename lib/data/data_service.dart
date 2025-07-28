import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'models.dart';
import '../services/thumbnail_service.dart';

class LoadResult {
  final List<VideoClip>? clips;
  final String? path;
  LoadResult({this.clips, this.path});
}

class DataService {
  final ThumbnailService thumbnailService;

  DataService({required this.thumbnailService});

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
        debugPrint('File not found at $path, returning empty list.');
        return [];
      }
      final jsonString = await file.readAsString();
      if (jsonString.isEmpty) return [];

      final List<dynamic> jsonList = json.decode(jsonString);
      final clips = <VideoClip>[];
      for (var json in jsonList) {
        final clip = VideoClip.fromJson(json);
        clip.thumbnailPath = await thumbnailService.getThumbnail(
          clip.videoPath,
          clip.coverFrameTime,
          clip.id,
        );
        clips.add(clip);
      }
      return clips;
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

  Future<String> getDefaultDbPath() async {
    final docDir = await getApplicationDocumentsDirectory();
    return p.join(docDir.path, 'VideoClipManager', 'default_clips.json');
  }
}
