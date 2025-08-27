import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../services/thumbnail_service.dart';

class VideoThumbnail extends StatelessWidget {
  final dynamic video; // OriginalVideo 或 OnlineVideo
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
    if (video is OriginalVideo) {
      return _buildLocalVideoThumbnail(context, video as OriginalVideo);
    } else if (video is OnlineVideo) {
      return _buildOnlineVideoThumbnail(context, video as OnlineVideo);
    } else {
      return _buildPlaceholder();
    }
  }

  Widget _buildLocalVideoThumbnail(BuildContext context, OriginalVideo video) {
    final thumbnailService = context.read<ThumbnailService>();
    final dbPath = context.read<AppState>().currentDbFullPath;

    String? fullThumbPath;
    if (video.thumbnailPath != null && dbPath != null) {
      fullThumbPath = thumbnailService.buildThumbnailPath(
        dbPath,
        video.thumbnailPath!,
      );
    }

    // The main container that defines the shape and background
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: borderRadius ?? BorderRadius.circular(8),
        color: Colors.grey.shade300, // Placeholder background color
      ),
      clipBehavior:
          Clip.antiAlias, // Ensures the child respects the border radius
      child: fullThumbPath == null
          ? _buildPlaceholder()
          : _buildImage(fullThumbPath),
    );
  }

  Widget _buildOnlineVideoThumbnail(BuildContext context, OnlineVideo video) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: borderRadius ?? BorderRadius.circular(8),
        color: Colors.grey.shade300,
      ),
      clipBehavior: Clip.antiAlias,
      child: video.thumbnailUrl != null
          ? _buildNetworkImage(video.thumbnailUrl!)
          : _buildPlaceholder(),
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

  Widget _buildNetworkImage(String url) {
    return Image.network(
      url,
      fit: fit,
      key: ValueKey(url),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'image/webp,image/apng,image/*,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
        'Cache-Control': 'no-cache',
      },
      errorBuilder: (context, error, stackTrace) {
        debugPrint('Error loading online thumbnail for $url: $error');
        return _buildPlaceholder();
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return _buildPlaceholder();
      },
      // 添加重试机制
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          child: child,
        );
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
