import 'dart:io';
import 'dart:async';

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
  double _previewProgress = 0.0;
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    _loadPreviewStatus();
    
    // 添加定时器，每2秒刷新一次进度
    _progressTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted && _previewProgress < 1.0) {
        _loadPreviewStatus();
      } else if (_previewProgress >= 1.0) {
        // 如果进度达到100%，停止定时器
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPreviewStatus() async {
    try {
      final progress = await PreviewService().getVideoProgress(widget.clip.videoPath);
      
      if (mounted) {
        setState(() {
          _previewProgress = progress;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _previewProgress = 0.0;
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
          // 主缩略图 - 确保填充整个容器
          Positioned.fill(
            child: fullThumbPath == null
                ? _buildPlaceholder()
                : _buildImage(fullThumbPath),
          ),
          
          // 预览生成进度覆盖层 - 只在未完成时显示
          if (_previewProgress < 1.0)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 2, // 2像素高度
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                ),
                child: LinearProgressIndicator(
                  value: _previewProgress,
                  backgroundColor: Colors.grey.withOpacity(0.3),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _previewProgress > 0.5 ? Colors.green : Colors.orange,
                  ),
                  minHeight: 2,
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
