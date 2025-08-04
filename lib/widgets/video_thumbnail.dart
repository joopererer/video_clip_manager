import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../services/thumbnail_service.dart';

class VideoThumbnail extends StatelessWidget {
  final OriginalVideo video;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const VideoThumbnail({
    super.key,
    required this.video,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final thumbnailService = context.read<ThumbnailService>();
    final dbPath = context.read<AppState>().currentDbFullPath;

    String? fullThumbPath;
    if (video.thumbnailPath != null && dbPath != null) {
      fullThumbPath =
          thumbnailService.buildThumbnailPath(dbPath, video.thumbnailPath!);
    }
    
    // The main container that defines the shape and background
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: borderRadius ?? BorderRadius.circular(8),
        color: Colors.grey.shade300, // Placeholder background color
      ),
      clipBehavior: Clip.antiAlias, // Ensures the child respects the border radius
      child: fullThumbPath == null
          ? _buildPlaceholder()
          : _buildImage(fullThumbPath),
    );
  }

  Widget _buildImage(String path) {
    final imageFile = File(path);
    
    // Use a simple check for existence, can be improved with FutureBuilder
    // for very large lists, but this is often sufficient and simpler.
    if (!imageFile.existsSync()) {
      return _buildPlaceholder();
    }

    return Image.file(
      imageFile,
      fit: fit,
      // Add a key to ensure the widget updates when the path changes
      key: ValueKey(path), 
      errorBuilder: (context, error, stackTrace) {
        // This catches errors like file corruption or read permissions
        debugPrint('Error loading thumbnail for $path: $error');
        return _buildPlaceholder();
      },
    );
  }

  Widget _buildPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.movie_creation_outlined,
          size: 32,
          color: Colors.grey.shade600,
        ),
        if (video.duration != null && video.duration! > Duration.zero) ...[
          const SizedBox(height: 4),
          Text(
            _formatDuration(video.duration!),
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  String _formatDuration(Duration d) {
    final parts = d.toString().split('.').first.padLeft(8, '0').split(':');
    return '${parts[0]}:${parts[1]}:${parts[2]}';
  }
}
