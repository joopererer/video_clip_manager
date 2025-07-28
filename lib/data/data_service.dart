import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'models.dart';

class DataService {
  Future<List<VideoClip>?> loadClipsFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final jsonString = await file.readAsString();
        final List<dynamic> jsonList = json.decode(jsonString);

        return jsonList.map((json) => VideoClip.fromJson(json)).toList();
      }
    } catch (e) {
      debugPrint('Error loading clips: $e');
      rethrow;
    }
    return null;
  }

  Future<String> saveClipsToFile(List<VideoClip> clips) async {
    try {
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Please select an output file:',
        fileName: 'video_clips.json',
        allowedExtensions: ['json'],
      );

      if (outputFile != null) {
        final file = File(outputFile);
        final jsonList = clips.map((clip) => clip.toJson()).toList();
        final jsonString = const JsonEncoder.withIndent('  ').convert(jsonList);
        await file.writeAsString(jsonString);
        return 'Successfully saved to $outputFile';
      }
      return 'Save operation cancelled.';
    } catch (e) {
      debugPrint('Error saving clips: $e');
      rethrow;
    }
  }
}
