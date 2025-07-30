import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/models.dart';
import '../data/app_state.dart';
import '../services/thumbnail_service.dart';
import '../services/path_service.dart';

class VideoThumbnail extends StatelessWidget {
  final OriginalVideo video;
  final double size;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final String? dbPath; // 数据库路径，用于构建相对路径

  const VideoThumbnail({
    super.key,
    required this.video,
    this.size = 100,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.dbPath,
  });

  @override
  Widget build(BuildContext context) {
    if (size == double.infinity) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: borderRadius ?? BorderRadius.circular(8),
          color: Colors.grey.shade200,
        ),
        child: ClipRRect(
          borderRadius: borderRadius ?? BorderRadius.circular(8),
          child: _buildThumbnail(),
        ),
      );
    } else {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: borderRadius ?? BorderRadius.circular(8),
          color: Colors.grey.shade200,
        ),
        child: ClipRRect(
          borderRadius: borderRadius ?? BorderRadius.circular(8),
          child: _buildThumbnail(),
        ),
      );
    }
  }

  Widget _buildThumbnail() {
    if (video.thumbnailPath != null) {
      // 构建完整的缩略图路径
      String fullThumbPath;
      if (!video.thumbnailPath!.contains('\\') && !video.thumbnailPath!.contains('/')) {
        // 相对路径（只有文件名），需要数据库路径来构建完整路径
        if (dbPath != null) {
          final thumbnailService = ThumbnailService(pathService: PathService());
          fullThumbPath = thumbnailService.buildThumbnailPath(dbPath!, video.thumbnailPath!);
        } else {
          // 没有数据库路径，无法构建完整路径
          return _buildFallback();
        }
      } else {
        // 完整路径，直接使用
        fullThumbPath = video.thumbnailPath!;
      }
      
      final file = File(fullThumbPath);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: fit,
          width: size == double.infinity ? null : size,
          height: size == double.infinity ? null : size,
          errorBuilder: (context, error, stackTrace) {
            debugPrint('Error loading thumbnail for ${video.name}: $error');
            return _buildFallback();
          },
        );
      }
    }
    return _buildFallback();
  }

  Widget _buildFallback() {
    return Container(
      color: Colors.grey.shade300,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.movie_creation_outlined,
            size: size * 0.3,
            color: Colors.grey.shade600,
          ),
          if (video.duration != null) ...[
            const SizedBox(height: 4),
            Text(
              _formatDuration(video.duration!),
              style: TextStyle(
                fontSize: size * 0.08,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    
    if (hours > 0) {
      return '${hours}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes}:${seconds.toString().padLeft(2, '0')}';
    }
  }
} 