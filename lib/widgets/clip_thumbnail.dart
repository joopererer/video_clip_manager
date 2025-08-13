import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../services/thumbnail_service.dart';
import '../services/preview_service.dart';

class ClipThumbnail extends StatefulWidget {
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
  State<ClipThumbnail> createState() => _ClipThumbnailState();
}

class _ClipThumbnailState extends State<ClipThumbnail> {
  String _previewStatus = '';
  double _previewProgress = 0.0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPreviewStatus();
  }

  Future<void> _loadPreviewStatus() async {
    try {
      final status = await PreviewService().getVideoStatus(widget.clip.videoPath);
      final progress = await PreviewService().getVideoProgress(widget.clip.videoPath);
      
      if (mounted) {
        setState(() {
          _previewStatus = status;
          _previewProgress = progress;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _previewStatus = '错误';
          _previewProgress = 0.0;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final thumbnailService = context.read<ThumbnailService>();
    final dbPath = context.read<AppState>().currentDbFullPath;

    String? fullThumbPath;
    if (widget.clip.thumbnailPath != null && dbPath != null) {
      fullThumbPath =
          thumbnailService.buildThumbnailPath(dbPath, widget.clip.thumbnailPath!);
    }

    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.grey.shade300,
      child: Stack(
        children: [
          // 主缩略图
          fullThumbPath == null
              ? _buildPlaceholder()
              : _buildImage(fullThumbPath),
          
          // 预览生成进度覆盖层
          if (_previewProgress < 1.0) // 只在未完成时显示
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 2, // 减小到2像素高度
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                ),
                child: LinearProgressIndicator(
                  value: _previewProgress,
                  backgroundColor: Colors.grey.withOpacity(0.3),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _previewProgress > 0.5 ? Colors.green : Colors.orange,
                  ),
                  minHeight: 2, // 确保最小高度为2像素
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImage(String path) {
    final imageFile = File(path);
    if (!imageFile.existsSync()) {
      return _buildPlaceholder();
    }

    return Image.file(
      imageFile,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
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
