import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class PathService {
  late final String _baseDir;

  Future<void> init() async {
    final docDir = await getApplicationDocumentsDirectory();
    _baseDir = p.join(docDir.path, 'VideoClipManager');
    await Directory(_baseDir).create(recursive: true);
  }

  String getBaseDir() => _baseDir;

  String getThumbnailDir() {
    final thumbDir = p.join(_baseDir, 'Thumbnails');
    Directory(thumbDir).createSync(recursive: true);
    return thumbDir;
  }

  String getDefaultDbPath() {
    return p.join(_baseDir, 'default_clips.json');
  }
}
