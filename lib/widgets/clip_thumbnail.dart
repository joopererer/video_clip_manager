import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../services/thumbnail_service.dart';

class ClipThumbnail extends StatelessWidget {
  final VideoClip clip;
  final double? width;
  final double? height;
  final BoxFit fit;

  const ClipThumbnail({
    super.key,
    required this.clip,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final thumbnailService = context.read<ThumbnailService>();
    final dbPath = context.read<AppState>().currentDbFullPath;

    String? fullThumbPath;
    if (clip.thumbnailPath != null && dbPath != null) {
      fullThumbPath =
          thumbnailService.buildThumbnailPath(dbPath, clip.thumbnailPath!);
    }

    return Container(
      width: width,
      height: height,
      color: Colors.grey.shade300,
      child: fullThumbPath == null
          ? _buildPlaceholder()
          : _buildImage(fullThumbPath),
    );
  }

  Widget _buildImage(String path) {
    final imageFile = File(path);
    if (!imageFile.existsSync()) {
      return _buildPlaceholder();
    }

    return Image.file(
      imageFile,
      fit: fit,
      width: width,
      height: height,
      key: ValueKey(path),
      errorBuilder: (context, error, stackTrace) {
        return _buildPlaceholder();
      },
    );
  }

  Widget _buildPlaceholder() {
    return Icon(
      Icons.image_not_supported_outlined,
      color: Colors.grey.shade500,
    );
  }
}
