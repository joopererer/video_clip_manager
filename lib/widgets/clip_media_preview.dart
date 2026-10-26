import 'dart:io';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../theme/app_colors.dart';
import 'clip_thumbnail.dart';

/// Reuses the existing thumbnail/cache preview; never creates a player.
class ClipMediaPreview extends StatefulWidget {
  final VideoClip clip;

  const ClipMediaPreview({super.key, required this.clip});

  @override
  State<ClipMediaPreview> createState() => _ClipMediaPreviewState();
}

class _ClipMediaPreviewState extends State<ClipMediaPreview> {
  late Future<bool> _exists;

  void _checkFile() {
    final path = widget.clip.videoPath;
    _exists = path.startsWith('https://') || path.startsWith('http://')
        ? Future.value(true)
        : File(path).exists().catchError((_) => false);
  }

  @override
  void initState() {
    super.initState();
    _checkFile();
  }

  @override
  void didUpdateWidget(ClipMediaPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clip.videoPath != widget.clip.videoPath) _checkFile();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.appColors.background,
    child: FutureBuilder<bool>(
      future: _exists,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.expand();
        if (snapshot.data == false) {
          return const Tooltip(
            message: '源视频文件不存在，请检查磁盘或文件路径',
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.video_file_outlined, color: AppColors.warning),
                  Text('源文件缺失', style: TextStyle(fontSize: 11)),
                ],
              ),
            ),
          );
        }
        return ClipThumbnail(
          clip: widget.clip,
          fit: BoxFit.contain,
          backgroundColor: context.appColors.background,
        );
      },
    ),
  );
}
