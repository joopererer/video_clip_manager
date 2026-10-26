import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

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
  Uint8List? _hoverFrame;
  double? _hoverRatio;
  Duration? _hoverTime;

  @override
  void initState() {
    super.initState();
    final isOnline = widget.clip.videoPath.startsWith('http://') ||
        widget.clip.videoPath.startsWith('https://');

    if (isOnline) {
      _previewProgress = 1.0;
      _isProgressComplete = true;
    } else {
      _loadPreviewStatus();
      // 只在本地视频进度未完成时启动定时器，减少不必要的检测
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

  void _onHover(Offset localPosition, double width) {
    if (width <= 0) return;
    final ratio = (localPosition.dx / width).clamp(0.0, 1.0);
    final clipDuration = widget.clip.endTime - widget.clip.startTime;
    final targetTime = widget.clip.startTime +
        Duration(milliseconds: (clipDuration.inMilliseconds * ratio).round());

    final frame = PreviewService().getNearestKeyframe(
      widget.clip.videoPath,
      targetTime,
    );

    if (frame != null && frame != _hoverFrame) {
      setState(() {
        _hoverFrame = frame;
        _hoverRatio = ratio;
        _hoverTime = targetTime;
      });
    } else if (_hoverRatio != ratio) {
      setState(() {
        _hoverRatio = ratio;
        _hoverTime = targetTime;
      });
    }
  }

  void _onExit() {
    if (_hoverFrame != null || _hoverRatio != null) {
      setState(() {
        _hoverFrame = null;
        _hoverRatio = null;
        _hoverTime = null;
      });
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

    // 检查是否有语义检索命中帧
    Uint8List? hitFrame;
    double? hitRatio;
    if (widget.clip.hitTimestampMs != null) {
      final clipDuration = widget.clip.endTime - widget.clip.startTime;
      final hitOffsetMs =
          widget.clip.hitTimestampMs! - widget.clip.startTime.inMilliseconds;
      if (clipDuration.inMilliseconds > 0) {
        hitRatio = (hitOffsetMs / clipDuration.inMilliseconds).clamp(0.0, 1.0);
      }
      hitFrame = PreviewService().getNearestKeyframe(
        widget.clip.videoPath,
        Duration(milliseconds: widget.clip.hitTimestampMs!),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final actualWidth = widget.width ?? constraints.maxWidth;
        return MouseRegion(
          onHover: (e) => _onHover(e.localPosition, actualWidth),
          onExit: (_) => _onExit(),
          child: Container(
            width: widget.width,
            height: widget.height,
            color: Colors.grey.shade300,
            child: Stack(
              children: [
                // 主缩略图 / 悬停预览图 / 命中关键帧
                Positioned.fill(
                  child: _hoverFrame != null
                      ? Image.memory(
                          _hoverFrame!,
                          fit: widget.fit,
                          gaplessPlayback: true,
                        )
                      : (hitFrame != null
                          ? Image.memory(
                              hitFrame,
                              fit: widget.fit,
                              gaplessPlayback: true,
                            )
                          : (fullThumbPath == null
                              ? _buildPlaceholder()
                              : _buildImage(fullThumbPath))),
                ),

                // 悬停时间提示小浮层
                if (_hoverTime != null && _hoverRatio != null)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        _formatTime(_hoverTime!),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),

                // 语义命中角标 (在右上角显示高亮标识)
                if (widget.clip.hitTimestampMs != null)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade700.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 10,
                            color: Colors.white,
                          ),
                          SizedBox(width: 2),
                          Text(
                            'HIT',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // 底部悬停进度条 / 命中指示器
                if (_hoverRatio != null || hitRatio != null)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 3,
                      color: Colors.black.withValues(alpha: 0.4),
                      child: Stack(
                        children: [
                          // 命中点标记
                          if (hitRatio != null)
                            Positioned(
                              left: (actualWidth * hitRatio) - 2,
                              child: Container(
                                width: 4,
                                height: 3,
                                color: Colors.amber.shade400,
                              ),
                            ),
                          // 鼠标悬停游标
                          if (_hoverRatio != null)
                            Positioned(
                              left: 0,
                              width: actualWidth * _hoverRatio!,
                              child: Container(
                                height: 3,
                                color: Colors.blueAccent.shade400,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                // 预览生成进度覆盖层 - 只在未完成时显示
                if (_previewProgress < 1.0 && !_isProgressComplete)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: SizedBox(
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
          ),
        );
      },
    );
  }

  String _formatTime(Duration duration) {
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
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
