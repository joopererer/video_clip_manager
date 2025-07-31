import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:video_clip_manager/main.dart';

class CustomProgressBar extends StatefulWidget {
  final Player player;
  final Duration startTime;
  final Duration endTime;
  final Function(Duration) onSetStart;
  final Function(Duration) onSetEnd;
  final bool showThumbnailPreview;
  final bool isPlaybackMode; // 新增：是否为播放模式
  final bool showClipRelativeProgress; // 新增：是否显示clip相对进度

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

  // ✨ --- État pour gérer la restauration de la position ---
  /// Mémorise la position de la tête de lecture au début du survol.
  Duration? _positionBeforeHover;
  /// Un drapeau pour savoir si un clic a eu lieu pendant le survol.
  bool _clickPerformed = false;

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
      await widget.player.seek(time);
      await Future.delayed(const Duration(milliseconds: 50));
      if (!_isHovering || !mounted) return;
      final data = await widget.player.screenshot();
      if (mounted && _isHovering) {
        setState(() {
          _thumbnailData = data;
        });
      }
    });
  }

  // --- Gestion des événements souris ---

  void _handleHover(PointerHoverEvent event, BoxConstraints constraints, Duration totalDuration) {
    final dx = event.localPosition.dx;
    final hoverTime = _getTimeFromDx(dx, constraints.maxWidth, totalDuration);

    setState(() {
      _hoverDx = dx;
      _hoverTime = hoverTime;
      if(widget.showThumbnailPreview) _thumbnailData = null;
    });

    // 只在编辑模式下才进行预览seek，播放模式下只显示悬停位置
    if (widget.showThumbnailPreview && !widget.isPlaybackMode) {
      _updatePreview(hoverTime);
    } else if (!widget.isPlaybackMode) {
      // 只在非播放模式下才进行seek预览
      widget.player.seek(hoverTime);
    }
  }

  void _handleEnter(PointerEnterEvent event) {
    setState(() {
      _isHovering = true;
      // ✨ On mémorise la position actuelle et on réinitialise le drapeau de clic.
      _positionBeforeHover = widget.player.state.position;
      _clickPerformed = false;
    });
  }

  void _handleExit(PointerExitEvent event) {
    setState(() {
      _isHovering = false;
    });
    // ✨ Si aucun clic n'a été fait, on restaure la position.
    if (!_clickPerformed && _positionBeforeHover != null) {
      widget.player.seek(_positionBeforeHover!);
    }
  }

  void _handlePrimaryTap(TapUpDetails details, double maxWidth, Duration totalDuration) {
    final tappedTime = _getTimeFromDx(details.localPosition.dx, maxWidth, totalDuration);
    
    if (widget.isPlaybackMode) {
      // 播放模式：只跳转到点击位置，不修改clip
      widget.player.seek(tappedTime);
      _clickPerformed = true;
    } else {
      // 编辑模式：设置开始时间
      widget.onSetStart(tappedTime);
      widget.player.seek(tappedTime);
      _clickPerformed = true;
    }
  }

  void _handleSecondaryTap(TapUpDetails details, double maxWidth, Duration totalDuration) {
    final tappedTime = _getTimeFromDx(details.localPosition.dx, maxWidth, totalDuration);
    
    if (widget.isPlaybackMode) {
      // 播放模式：只跳转到点击位置，不修改clip
      widget.player.seek(tappedTime);
      _clickPerformed = true;
    } else {
      // 编辑模式：设置结束时间
      widget.onSetEnd(tappedTime);
      widget.player.seek(tappedTime);
      _clickPerformed = true;
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
        final clipProgress = clipDuration > Duration.zero ? clipDuration : Duration.zero;

        return Row(
          children: [
            StreamBuilder<Duration>(
              stream: widget.player.stream.position,
              initialData: widget.player.state.position,
              builder: (context, snapshot) {
                final currentPosition = snapshot.data ?? Duration.zero;
                final displayPosition = widget.showClipRelativeProgress 
                    ? _clampDuration(currentPosition - widget.startTime, Duration.zero, clipProgress)
                    : currentPosition;
                
                return Text(
                  formatDuration(displayPosition), 
                  style: const TextStyle(fontFamily: 'monospace')
                );
              },
            ),
            const SizedBox(width: 8),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return MouseRegion(
                    onEnter: _handleEnter,
                    onExit: _handleExit,
                    onHover: (event) => _handleHover(event, constraints, totalDuration),
                    child: GestureDetector(
                      onTapUp: (details) => _handlePrimaryTap(details, constraints.maxWidth, totalDuration),
                      onSecondaryTapUp: (details) => _handleSecondaryTap(details, constraints.maxWidth, totalDuration),
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
                                borderRadius: BorderRadius.circular(4)
                              )
                            ),
                            // Clip范围高亮（只在非相对模式下显示）
                            if (!widget.showClipRelativeProgress)
                              _buildPositionedBar(
                                constraints.maxWidth, 
                                totalDuration, 
                                widget.startTime, 
                                widget.endTime, 
                                Theme.of(context).primaryColor.withValues(alpha: 0.4)
                              ),
                            // 播放进度条
                            StreamBuilder<Duration>(
                              stream: widget.player.stream.position,
                              initialData: widget.player.state.position,
                              builder: (context, positionSnapshot) {
                                final position = positionSnapshot.data ?? Duration.zero;
                                if (widget.showClipRelativeProgress) {
                                  // 显示clip相对进度
                                  final relativePosition = _clampDuration(position - widget.startTime, Duration.zero, clipProgress);
                                  final progress = clipProgress > Duration.zero 
                                      ? (relativePosition.inMilliseconds / clipProgress.inMilliseconds).clamp(0.0, 1.0)
                                      : 0.0;
                                  return Positioned(
                                    left: 0,
                                    child: Container(
                                      height: 8,
                                      width: (constraints.maxWidth * progress).clamp(0, constraints.maxWidth),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).primaryColor,
                                        borderRadius: BorderRadius.circular(4)
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
                                    Theme.of(context).primaryColor
                                  );
                                }
                              },
                            ),
                            // 标记（只在非相对模式下显示）
                            if (!widget.showClipRelativeProgress) ...[
                              _buildMarker(constraints.maxWidth, totalDuration, widget.startTime, Colors.blue),
                              _buildMarker(constraints.maxWidth, totalDuration, widget.endTime, Colors.red),
                            ],
                            // 悬停预览
                            if (_isHovering && _hoverDx != null)
                              Positioned(
                                left: _hoverDx! - (widget.showThumbnailPreview ? 50 : 28),
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
            ),
            const SizedBox(width: 8),
            Text(
              widget.showClipRelativeProgress 
                  ? formatDuration(clipProgress)
                  : formatDuration(totalDuration), 
              style: const TextStyle(fontFamily: 'monospace')
            ),
          ],
        );
      },
    );
  }

  // --- Widgets de construction (inchangés) ---

  Widget _buildPositionedBar(double maxWidth, Duration total, Duration start, Duration end, Color color) {
    final startDx = (start.inMilliseconds / total.inMilliseconds) * maxWidth;
    final endDx = (end.inMilliseconds / total.inMilliseconds) * maxWidth;
    return Positioned(left: startDx.clamp(0, maxWidth), child: Container(height: 8, width: (endDx - startDx).clamp(0, maxWidth), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))));
  }

  Widget _buildMarker(double maxWidth, Duration total, Duration time, Color color) {
    final dx = (time.inMilliseconds / total.inMilliseconds) * maxWidth;
    return Positioned(left: dx.clamp(0.0, maxWidth) - 8, child: Container(width: 16, height: 16, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2))));
  }

  Widget _buildThumbnailPreview() {
    return Container(
      width: 100,
      padding: const EdgeInsets.all(4.0),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white54, width: 1)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_thumbnailData != null) Image.memory(_thumbnailData!, width: 100, fit: BoxFit.contain) else const SizedBox(height: 56, child: Center(child: CircularProgressIndicator())),
          const SizedBox(height: 4),
          Text(formatDuration(_hoverTime ?? Duration.zero), style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _buildHoverTimePreview() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        formatDuration(_hoverTime ?? Duration.zero),
        style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
      ),
    );
  }
}