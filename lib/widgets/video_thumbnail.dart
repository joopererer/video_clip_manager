import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/models.dart';
import '../data/app_state.dart';
import '../services/thumbnail_service.dart';
import '../services/path_service.dart';

class VideoThumbnail extends StatefulWidget {
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
  State<VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<VideoThumbnail> {
  bool? _fileExists;
  bool _isLoading = true;
  
  // 静态缓存，避免重复检查相同路径
  static final Map<String, bool> _fileExistsCache = {};

  @override
  void initState() {
    super.initState();
    _checkFileExists();
  }

  @override
  void didUpdateWidget(VideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 只有当thumbnailPath发生变化时才重新检查
    if (oldWidget.video.thumbnailPath != widget.video.thumbnailPath) {
      _checkFileExists();
    }
  }

  Future<void> _checkFileExists() async {
    if (widget.video.thumbnailPath == null) {
      setState(() {
        _fileExists = false;
        _isLoading = false;
      });
      return;
    }

    // 构建完整的缩略图路径
    String fullThumbPath;
    if (!widget.video.thumbnailPath!.contains('\\') && !widget.video.thumbnailPath!.contains('/')) {
      // 相对路径（只有文件名），构建完整路径
      final appState = context.read<AppState>();
      if (appState.currentDbFullPath != null) {
        fullThumbPath = appState.thumbnailService.buildThumbnailPath(appState.currentDbFullPath!, widget.video.thumbnailPath!);
      } else {
        // 没有数据库路径，无法构建完整路径
        setState(() {
          _fileExists = false;
          _isLoading = false;
        });
        return;
      }
    } else {
      // 完整路径，直接使用
      fullThumbPath = widget.video.thumbnailPath!;
    }

    // 检查缓存
    if (_fileExistsCache.containsKey(fullThumbPath)) {
      setState(() {
        _fileExists = _fileExistsCache[fullThumbPath];
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final exists = await File(fullThumbPath).exists();
      if (mounted) {
        // 更新缓存
        _fileExistsCache[fullThumbPath] = exists;
        setState(() {
          _fileExists = exists;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        // 缓存错误结果
        _fileExistsCache[fullThumbPath] = false;
        setState(() {
          _fileExists = false;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget child;

    final String? path = widget.video.thumbnailPath;
    Widget placeholder = Container(
      color: Colors.grey.shade300,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.movie_creation_outlined,
            size: widget.size * 0.3,
            color: Colors.grey.shade600,
          ),
          if (widget.video.duration != null) ...[
            const SizedBox(height: 4),
            Text(
              _formatDuration(widget.video.duration!),
              style: TextStyle(
                fontSize: widget.size * 0.08,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );

    if (path == null || _isLoading) {
      child = Center(child: CircularProgressIndicator(strokeWidth: 2.0));
    } else if (_fileExists == true) {
      // 构建完整的缩略图路径
      String? fullThumbPath;
      if (!path.contains('\\') && !path.contains('/')) {
        // 相对路径（只有文件名），构建完整路径
        final appState = context.read<AppState>();
        if (appState.currentDbFullPath != null) {
          fullThumbPath = appState.thumbnailService.buildThumbnailPath(appState.currentDbFullPath!, path);
        } else {
          // 没有数据库路径，无法构建完整路径
          child = Center(child: placeholder);
        }
      } else {
        // 完整路径，直接使用
        fullThumbPath = path;
      }
      
      // 只有在有完整路径时才创建图片
      if (fullThumbPath != null) {
        child = Image.file(
          File(fullThumbPath),
          fit: widget.fit,
          width: widget.size == double.infinity ? null : widget.size,
          height: widget.size == double.infinity ? null : widget.size,
          errorBuilder: (c, e, s) => Center(child: placeholder),
        );
      } else {
        child = Center(child: placeholder);
      }
    } else {
      child = Center(child: placeholder);
    }

    // If a size is provided (like in the ListView), wrap the child
    // in a SizedBox with fixed dimensions.
    if (widget.size != double.infinity) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
          color: Colors.grey.shade200,
        ),
        child: ClipRRect(
          borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
          child: child,
        ),
      );
    } else {
      return Container(
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
          color: Colors.grey.shade200,
        ),
        child: ClipRRect(
          borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
          child: child,
        ),
      );
    }
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