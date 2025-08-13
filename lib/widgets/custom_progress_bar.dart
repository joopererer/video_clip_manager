import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import '../services/preview_service.dart';

// Helper function
String formatDuration(Duration d) {
  final parts = d.toString().split('.').first.padLeft(8, '0').split(':');
  return '${parts[0]}:${parts[1]}:${parts[2]}';
}

class CustomProgressBar extends StatefulWidget {
  final Player player;
  final Duration startTime;
  final Duration endTime;
  final Function(Duration) onSetStart;
  final Function(Duration) onSetEnd;
  final bool showThumbnailPreview;
  final bool isPlaybackMode; // 新增：是否为播放模式
  final bool showClipRelativeProgress; // 新增：是否显示clip相对进度
  final String? videoPath; // 新增：视频文件路径，用于关键帧预览

  const CustomProgressBar({
    super.key,
    required this.player,
    required this.startTime,
    required this.endTime,
    required this.onSetStart,
    required this.onSetEnd,
    this.showThumbnailPreview = false,
    this.isPlaybackMode = false, // 默认为编辑模式
    this.showClipRelativeProgress = false, // 默认为显示完整视频进度
    this.videoPath, // 新增
  });

  @override
  State<CustomProgressBar> createState() => _CustomProgressBarState();
}

class _CustomProgressBarState extends State<CustomProgressBar> {
  // --- État pour la prévisualisation ---
  bool _isHovering = false;
  double? _hoverDx;
  Duration? _hoverTime;
  Uint8List? _thumbnailData;
  Future<void>? _pendingPreview;
  
  // 新增：预览生成进度状态
  double _previewProgress = 0.0;
  String _previewStatus = '未生成';
  bool _isLoadingPreview = false;

  // --- Fonctions utilitaires ---

  Duration _getTimeFromDx(double dx, double maxWidth, Duration totalDuration) {
    final double progress = (dx / maxWidth).clamp(0.0, 1.0);
    return totalDuration * progress;
  }

  Duration _clampDuration(Duration duration, Duration min, Duration max) {
    if (duration < min) return min;
    if (duration > max) return max;
    return duration;
  }

  void _updatePreview(Duration time) {
    _pendingPreview?.ignore();
    _pendingPreview = Future(() async {
      try {
        print('CustomProgressBar: Updating preview to time: $time using keyframe system');
        
        // 使用关键帧预览系统 - 直接获取最近的关键帧，不需要先检查缓存
        final data = PreviewService().getNearestKeyframe(
          widget.videoPath ?? '',
          time,
        );
        
        if (mounted && _isHovering && data != null) {
          setState(() {
            _thumbnailData = data;
          });
          print('CustomProgressBar: Keyframe preview updated successfully');
        } else if (data == null) {
          // 只有在没有找到任何关键帧时才显示 "No preview"
          final hasAnyKeyframes = PreviewService().hasKeyframes(widget.videoPath ?? '');
          if (!hasAnyKeyframes) {
            print('CustomProgressBar: No keyframes available for this video');
          } else {
            print('CustomProgressBar: No keyframe found near time $time');
          }
          setState(() {
            _thumbnailData = null;
          });
        }
      } catch (e) {
        print('CustomProgressBar: Preview update failed: $e');
        setState(() {
          _thumbnailData = null;
        });
      }
    });
  }

  // --- Gestion des événements souris ---

  void _handleHover(
    PointerHoverEvent event,
    BoxConstraints constraints,
    Duration totalDuration,
  ) {
    final dx = event.localPosition.dx;
    
    if (widget.showClipRelativeProgress && widget.isPlaybackMode) {
      // 相对进度模式：基于clip时长计算悬停时间
      final clipDuration = widget.endTime - widget.startTime;
      final progress = (dx / constraints.maxWidth).clamp(0.0, 1.0);
      final relativeTime = clipDuration * progress;
      final hoverTime = widget.startTime + relativeTime;
      
      setState(() {
        _hoverDx = dx;
        _hoverTime = hoverTime;
        if (widget.showThumbnailPreview) _thumbnailData = null;
      });
    } else {
      // 完整进度模式或编辑模式：基于完整视频时长计算
      final hoverTime = _getTimeFromDx(dx, constraints.maxWidth, totalDuration);
      
      setState(() {
        _hoverDx = dx;
        _hoverTime = hoverTime;
        if (widget.showThumbnailPreview) _thumbnailData = null;
      });
    }

    // 重新启用预览图生成，使用PreviewService
    if (widget.showThumbnailPreview) {
      _updatePreview(_hoverTime!);
    }
  }

  void _handleEnter(PointerEnterEvent event) {
    setState(() {
      _isHovering = true;
    });
  }

  void _handleExit(PointerExitEvent event) {
    setState(() {
      _isHovering = false;
      _hoverDx = null;
      _hoverTime = null;
      _thumbnailData = null;
    });
  }

  void _handlePrimaryTap(TapUpDetails details, double maxWidth, Duration totalDuration) {
    print('Tap detected at: ${details.localPosition.dx} / $maxWidth'); // 调试信息
    
    if (widget.isPlaybackMode) {
      // 播放模式：seek到点击位置
      if (widget.showClipRelativeProgress) {
        // 相对进度模式：基于clip时长计算点击位置
        final clipDuration = widget.endTime - widget.startTime;
        final dx = details.localPosition.dx;
        final progress = (dx / maxWidth).clamp(0.0, 1.0);
        final relativeTime = clipDuration * progress;
        final absoluteTime = widget.startTime + relativeTime;
        print('Relative mode: progress=$progress, relativeTime=$relativeTime, absoluteTime=$absoluteTime'); // 调试信息
        
        // 使用安全的seek方法
        _safeSeek(absoluteTime);
      } else {
        // 完整进度模式：基于完整视频时长计算点击位置
        final tapTime = _getTimeFromDx(details.localPosition.dx, maxWidth, totalDuration);
        print('Full mode: tapTime=$tapTime'); // 调试信息
        
        // 使用安全的seek方法
        _safeSeek(tapTime);
      }
    } else {
      // 编辑模式：设置开始时间
      final tapTime = _getTimeFromDx(details.localPosition.dx, maxWidth, totalDuration);
      print('Edit mode: tapTime=$tapTime'); // 调试信息
      widget.onSetStart(tapTime);
    }
  }

  // 新增：安全的seek方法
  Future<void> _safeSeek(Duration position) async {
    try {
      print('CustomProgressBar: Attempting to seek to $position'); // 调试信息
      print('CustomProgressBar: Player state - duration: ${widget.player.state.duration}, position: ${widget.player.state.position}, playing: ${widget.player.state.playing}'); // 调试信息
      
      // 直接执行seek操作，不做额外的状态检查
      print('CustomProgressBar: Executing seek to $position...'); // 调试信息
      await widget.player.seek(position);
      
      // 验证seek是否成功
      await Future.delayed(Duration(milliseconds: 100));
      final newPosition = widget.player.state.position;
      print('CustomProgressBar: Seek completed. New position: $newPosition, Target: $position'); // 调试信息
      
      if ((newPosition - position).abs() < Duration(seconds: 1)) {
        print('CustomProgressBar: Seek successful to: $position'); // 调试信息
      } else {
        print('CustomProgressBar: Seek may have failed. Expected: $position, Actual: $newPosition'); // 调试信息
      }
    } catch (e) {
      print('CustomProgressBar: Seek failed: $e'); // 调试信息
    }
  }

  void _handleSecondaryTap(TapUpDetails details, double maxWidth, Duration totalDuration) {
    if (!widget.isPlaybackMode) {
      // 只在编辑模式下处理右键
      final tapTime = _getTimeFromDx(details.localPosition.dx, maxWidth, totalDuration);
      widget.onSetEnd(tapTime);
    }
  }

  @override
  void initState() {
    super.initState();
    _updatePreviewProgress();
  }

  @override
  void didUpdateWidget(CustomProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoPath != widget.videoPath) {
      _updatePreviewProgress();
    }
  }

  /// 更新预览生成进度
  Future<void> _updatePreviewProgress() async {
    if (widget.videoPath == null) return;
    
    try {
      final progress = await PreviewService().getVideoProgress(widget.videoPath!);
      final status = await PreviewService().getVideoStatus(widget.videoPath!);
      
      if (mounted) {
        setState(() {
          _previewProgress = progress;
          _previewStatus = status;
        });
      }
    } catch (e) {
      print('CustomProgressBar: Error updating preview progress: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: widget.player.stream.duration,
      initialData: widget.player.state.duration,
      builder: (context, durationSnapshot) {
        final totalDuration = durationSnapshot.data ?? Duration.zero;
        if (totalDuration == Duration.zero) {
          return const SizedBox(height: 48);
        }

        // 计算clip相对进度
        final clipDuration = widget.endTime - widget.startTime;
        final clipProgress = clipDuration > Duration.zero
            ? clipDuration
            : Duration.zero;

        return Row(
          children: [
            StreamBuilder<Duration>(
              stream: widget.player.stream.position,
              initialData: widget.player.state.position,
              builder: (context, snapshot) {
                final currentPosition = snapshot.data ?? Duration.zero;
                final displayPosition = widget.showClipRelativeProgress
                    ? _clampDuration(
                        currentPosition - widget.startTime,
                        Duration.zero,
                        clipProgress,
                      )
                    : currentPosition;

                return Text(
                  formatDuration(displayPosition),
                  style: const TextStyle(fontFamily: 'monospace'),
                );
              },
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 主进度条
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return MouseRegion(
                        onEnter: _handleEnter,
                        onExit: _handleExit,
                        onHover: (event) =>
                            _handleHover(event, constraints, totalDuration),
                        child: GestureDetector(
                          onTapUp: (details) => _handlePrimaryTap(
                            details,
                            constraints.maxWidth,
                            totalDuration,
                          ),
                          onSecondaryTapUp: (details) => _handleSecondaryTap(
                            details,
                            constraints.maxWidth,
                            totalDuration,
                          ),
                          child: Tooltip(
                            message: widget.isPlaybackMode
                                ? 'Click to seek to position'
                                : 'Clic gauche: Définir Début / Clic droit: Définir Fin',
                            child: Stack(
                              clipBehavior: Clip.none,
                              alignment: Alignment.centerLeft,
                              children: [
                                // 背景条
                                Container(
                                  height: 8,
                                  width: constraints.maxWidth,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade300,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                // Clip范围高亮（只在非相对模式下显示）
                                if (!widget.showClipRelativeProgress)
                                  _buildPositionedBar(
                                    constraints.maxWidth,
                                    totalDuration,
                                    widget.startTime,
                                    widget.endTime,
                                    Theme.of(
                                      context,
                                    ).primaryColor.withValues(alpha: 0.4),
                                  ),
                                // 播放进度条
                                StreamBuilder<Duration>(
                                  stream: widget.player.stream.position,
                                  initialData: widget.player.state.position,
                                  builder: (context, positionSnapshot) {
                                    final position =
                                        positionSnapshot.data ?? Duration.zero;
                                    if (widget.showClipRelativeProgress) {
                                      // 显示clip相对进度
                                      final relativePosition = _clampDuration(
                                        position - widget.startTime,
                                        Duration.zero,
                                        clipProgress,
                                      );
                                      final progress = clipProgress > Duration.zero
                                          ? (relativePosition.inMilliseconds /
                                                    clipProgress.inMilliseconds)
                                                .clamp(0.0, 1.0)
                                          : 0.0;
                                      return Positioned(
                                        left: 0,
                                        child: Container(
                                          height: 8,
                                          width: (constraints.maxWidth * progress)
                                              .clamp(0, constraints.maxWidth),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context).primaryColor,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                        ),
                                      );
                                    } else {
                                      // 显示完整视频进度
                                      return _buildPositionedBar(
                                        constraints.maxWidth,
                                        totalDuration,
                                        Duration.zero,
                                        position,
                                        Theme.of(context).primaryColor,
                                      );
                                    }
                                  },
                                ),
                                // 标记（只在非相对模式下显示）
                                if (!widget.showClipRelativeProgress) ...[
                                  _buildMarker(
                                    constraints.maxWidth,
                                    totalDuration,
                                    widget.startTime,
                                    Colors.blue,
                                  ),
                                  _buildMarker(
                                    constraints.maxWidth,
                                    totalDuration,
                                    widget.endTime,
                                    Colors.red,
                                  ),
                                ],
                                // 悬停预览
                                if (_isHovering && _hoverDx != null)
                                  Positioned(
                                    left:
                                        _hoverDx! -
                                        (widget.showThumbnailPreview ? 50 : 28),
                                    bottom: 20,
                                    child: widget.showThumbnailPreview 
                                        ? _buildThumbnailPreview() 
                                        : _buildHoverTimePreview(),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  // 预览生成进度条（只在进度小于100%时显示）
                  if (_previewProgress < 1.0 && widget.videoPath != null) ...[
                    const SizedBox(height: 1),
                    Container(
                      height: 1,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(0.5),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: _previewProgress,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(0.5),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              widget.showClipRelativeProgress
                  ? formatDuration(clipProgress)
                  : formatDuration(totalDuration),
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ],
        );
      },
    );
  }

  // --- Widgets de construction (inchangés) ---

  Widget _buildPositionedBar(
    double maxWidth,
    Duration total,
    Duration start,
    Duration end,
    Color color,
  ) {
    final startDx = (start.inMilliseconds / total.inMilliseconds) * maxWidth;
    final endDx = (end.inMilliseconds / total.inMilliseconds) * maxWidth;
    return Positioned(
      left: startDx.clamp(0, maxWidth),
      child: Container(
        height: 8,
        width: (endDx - startDx).clamp(0, maxWidth),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  Widget _buildMarker(
    double maxWidth,
    Duration total,
    Duration time,
    Color color,
  ) {
    final dx = (time.inMilliseconds / total.inMilliseconds) * maxWidth;
    return Positioned(
      left: dx.clamp(0.0, maxWidth) - 8,
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
      ),
    );
  }

  Widget _buildThumbnailPreview() {
    // 在相对进度模式下显示相对时间，否则显示绝对时间
    Duration displayTime;
    if (widget.showClipRelativeProgress && widget.isPlaybackMode) {
      final clipDuration = widget.endTime - widget.startTime;
      final relativeTime = _hoverTime != null 
          ? _clampDuration(_hoverTime! - widget.startTime, Duration.zero, clipDuration)
          : Duration.zero;
      displayTime = relativeTime;
    } else {
      displayTime = _hoverTime ?? Duration.zero;
    }

    return Container(
      width: 100,
      padding: const EdgeInsets.all(4.0),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white54, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_thumbnailData != null)
            Image.memory(_thumbnailData!, width: 100, fit: BoxFit.contain)
          else
            const SizedBox(
              height: 56,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.image_not_supported, color: Colors.white54, size: 24),
                    SizedBox(height: 4),
                    Text(
                      'No Preview',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Hover to generate',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            formatDuration(displayTime),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHoverTimePreview() {
    // 在相对进度模式下显示相对时间，否则显示绝对时间
    Duration displayTime;
    if (widget.showClipRelativeProgress && widget.isPlaybackMode) {
      final clipDuration = widget.endTime - widget.startTime;
      final relativeTime = _hoverTime != null 
          ? _clampDuration(_hoverTime! - widget.startTime, Duration.zero, clipDuration)
          : Duration.zero;
      displayTime = relativeTime;
    } else {
      displayTime = _hoverTime ?? Duration.zero;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        formatDuration(displayTime),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
