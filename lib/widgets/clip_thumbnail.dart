import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/models.dart';
import '../data/app_state.dart';
import '../services/thumbnail_service.dart';
import '../services/path_service.dart';

class ClipThumbnail extends StatefulWidget {
  final VideoClip clip;
  final double? size;
  final double? width;
  final double? height;

  const ClipThumbnail({
    super.key, 
    required this.clip, 
    this.size,
    this.width,
    this.height,
  });

  @override
  State<ClipThumbnail> createState() => _ClipThumbnailState();
}

class _ClipThumbnailState extends State<ClipThumbnail> {
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
  void didUpdateWidget(ClipThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 只有当thumbnailPath发生变化时才重新检查
    if (oldWidget.clip.thumbnailPath != widget.clip.thumbnailPath) {
      _checkFileExists();
    }
    // 如果只是rating或isFavorite等属性变化，不需要重新检查文件
  }

  Future<void> _checkFileExists() async {
    if (widget.clip.thumbnailPath == null) {
      setState(() {
        _fileExists = false;
        _isLoading = false;
      });
      return;
    }

    // 构建完整的缩略图路径
    String fullThumbPath;
    if (!widget.clip.thumbnailPath!.contains('\\') && !widget.clip.thumbnailPath!.contains('/')) {
      // 相对路径（只有文件名），构建完整路径
      final appState = context.read<AppState>();
      if (appState.currentDbFullPath != null) {
        fullThumbPath = appState.thumbnailService.buildThumbnailPath(appState.currentDbFullPath!, widget.clip.thumbnailPath!);
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
      fullThumbPath = widget.clip.thumbnailPath!;
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

    final String? path = widget.clip.thumbnailPath;
    Widget placeholder = Icon(
      Icons.movie_filter,
      size: widget.size != null ? widget.size! * 0.8 : 40,
      color: Colors.grey.shade400,
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
        // 计算合适的缓存尺寸
        double displayWidth = widget.width ?? widget.size ?? 200;
        double displayHeight = widget.height ?? widget.size ?? 200;
        int cacheWidth = (displayWidth * 2).toInt(); // 2倍尺寸确保清晰度
        int cacheHeight = (displayHeight * 2).toInt();
        
        child = Image.file(
          File(fullThumbPath),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (c, e, s) => Center(child: placeholder),
          // 使用计算出的缓存参数
          cacheWidth: cacheWidth,
          cacheHeight: cacheHeight,
        );
      } else {
        child = Center(child: placeholder);
      }
    } else {
      child = Center(child: placeholder);
    }

    // If a size is provided (like in the ListView), wrap the child
    // in a SizedBox with fixed dimensions.
    if (widget.size != null) {
      return SizedBox(width: widget.size, height: widget.size, child: child);
    }
    
    // If width and height are provided, use them
    if (widget.width != null && widget.height != null) {
      return SizedBox(width: widget.width, height: widget.height, child: child);
    }

    // Otherwise (like in the GridView), return the child directly
    // to let it be sized by its parent (the GridTile).
    return child;
  }
}
