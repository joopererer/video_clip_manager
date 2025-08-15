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
  bool _isProgressComplete = false;

  @override
  void initState() {
    super.initState();
    _loadPreviewStatus();

    // 只在进度未完成时启动定时器，减少不必要的检测
    if (!_isProgressComplete) {
      _progressTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
        if (mounted && !_isProgressComplete && _previewProgress < 1.0) {
          _loadPreviewStatus();
        } else if (_previewProgress >= 1.0 || _isProgressComplete) {
          // 如果进度达到100%，停止定时器
          timer.cancel();
          _isProgressComplete = true;
        }
      });
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPreviewStatus() async {
    try {
      final progress = await PreviewService().getVideoProgress(
        widget.clip.videoPath,
      );

      if (mounted) {
        setState(() {
          _previewProgress = progress;
          if (progress >= 1.0) {
            _isProgressComplete = true;
            _progressTimer?.cancel();
          }
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
      fullThumbPath = thumbnailService.buildThumbnailPath(
        dbPath,
        widget.clip.thumbnailPath!,
      );
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
          if (_previewProgress < 1.0 && !_isProgressComplete)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 2,
                child: LinearProgressIndicator(
                  value: _previewProgress,
                  backgroundColor: Colors.grey.shade400,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.blue.shade600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey.shade200,
      child: const Center(
        child: Icon(Icons.video_library, color: Colors.grey, size: 32),
      ),
    );
  }

  Widget _buildImage(String fullPath) {
    final file = File(fullPath);
    if (!file.existsSync()) {
      return _buildPlaceholder();
    }

    return Image.file(
      file,
      fit: widget.fit,
      errorBuilder: (context, error, stackTrace) {
        return _buildPlaceholder();
      },
    );
  }
}
