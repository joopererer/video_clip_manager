import 'package:flutter/material.dart';
import '../data/models.dart';

// --- PERFORMANCE OPTIMIZATION ---
// 1. Move the color list to a top-level constant to avoid rebuilding it on every item.
final List<Color> _userDefinedTimelineColors = [
  Colors.blue.shade400,
  Colors.green.shade400,
  Colors.orange.shade400,
  Colors.purple.shade400,
  Colors.red.shade400,
  Colors.teal.shade400,
  Colors.indigo.shade400,
  Colors.pink.shade400,
  Colors.blue.shade600,
  Colors.green.shade600,
  Colors.orange.shade600,
  Colors.purple.shade600,
  Colors.red.shade600,
  Colors.teal.shade600,
  Colors.indigo.shade600,
  Colors.pink.shade600,
  Colors.blue.shade300,
  Colors.green.shade300,
  Colors.orange.shade300,
  Colors.purple.shade300,
  Colors.red.shade300,
  Colors.teal.shade300,
  Colors.indigo.shade300,
  Colors.pink.shade300,
];

// 2. Move formatters to top-level functions for reusability and performance.
String _formatTimelineDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds % 60;
  if (minutes > 0) {
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  } else {
    return '${seconds}s';
  }
}

/// A widget that displays a timeline of playlist items, where each item's width
/// is proportional to its duration. Supports selection, dynamic text display,
/// and drag-and-drop reordering.
class PlaylistTimelineView extends StatelessWidget {
  final List<PlaylistItemWithClip> items;
  final double height;
  final bool showDuration;
  final bool showNames;
  final Function(int)? onItemTap;
  final int? selectedIndex;
  final Function(int, int)? onReorder;
  final bool enableReorder;

  const PlaylistTimelineView({
    super.key,
    required this.items,
    this.height = 60,
    this.showDuration = true,
    this.showNames = true,
    this.onItemTap,
    this.selectedIndex,
    this.onReorder,
    this.enableReorder = false,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _buildEmptyState();
    }

    final totalDurationMs = items.fold<int>(
      0,
      (total, item) => total + item.effectiveDuration.inMilliseconds,
    );

    // --- REORDERING IMPLEMENTATION ---
    // 3. Wrap the main Row in a DragTarget to handle drops.
    return DragTarget<int>(
      builder: (context, candidateData, rejectedData) {
        return Container(
          height: height,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: items.asMap().entries.map((entry) {
              final index = entry.key;
              final itemWithClip = entry.value;
              final durationRatio = totalDurationMs > 0
                  ? itemWithClip.effectiveDuration.inMilliseconds /
                        totalDurationMs
                  : 0.0;

              final itemWidget = _TimelineItem(
                itemWithClip: itemWithClip,
                durationRatio: durationRatio,
                isSelected: selectedIndex == index,
                showNames: showNames,
                showDuration: showDuration,
                onTap: () => onItemTap?.call(index),
              );

              // 4. Wrap each item in a LongPressDraggable if reordering is enabled.
              if (enableReorder) {
                return LongPressDraggable<int>(
                  data: index,
                  feedback: Opacity(
                    opacity: 0.7,
                    child: SizedBox(
                      height: height,
                      width: 100, // Fixed width for the feedback widget
                      child: Material(elevation: 4.0, child: itemWidget),
                    ),
                  ),
                  child: itemWidget,
                );
              } else {
                return itemWidget;
              }
            }).toList(),
          ),
        );
      },
      onAcceptWithDetails: (details) {
        final draggedIndex = details.data;
        // Determine drop position by checking relative x-offset
        final dropPosition = (context.findRenderObject() as RenderBox)
            .globalToLocal(details.offset);

        double currentWidth = 0;
        final totalWidth = (context.findRenderObject() as RenderBox).size.width;
        int droppedOnIndex = items.length - 1; // Default to last item

        for (int i = 0; i < items.length; i++) {
          final item = items[i];
          final ratio = totalDurationMs > 0
              ? item.effectiveDuration.inMilliseconds / totalDurationMs
              : 0;
          final itemWidth = ratio * totalWidth;
          if (dropPosition.dx >= currentWidth &&
              dropPosition.dx < currentWidth + itemWidth) {
            droppedOnIndex = i;
            break;
          }
          currentWidth += itemWidth;
        }

        onReorder?.call(draggedIndex, droppedOnIndex);
      },
    );
  }

  Widget _buildEmptyState() {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Center(
        child: Text(
          '暂无片段',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
        ),
      ),
    );
  }
}

// --- STRUCTURE & DYNAMIC LAYOUT ---
// 5. Extracted the timeline item into its own stateless widget for clarity and isolation.
class _TimelineItem extends StatelessWidget {
  final PlaylistItemWithClip itemWithClip;
  final double durationRatio;
  final bool isSelected;
  final bool showNames;
  final bool showDuration;
  final VoidCallback? onTap;

  const _TimelineItem({
    required this.itemWithClip,
    required this.durationRatio,
    required this.isSelected,
    required this.showNames,
    required this.showDuration,
    this.onTap,
  });

  // --- 核心修正：完全恢复您原来的颜色选择算法 ---
  Color _getColorForClip(VideoClip clip) {
    final hash = clip.id.hashCode.abs();
    final colorIndex =
        (hash * 7 + hash ~/ 7) % _userDefinedTimelineColors.length;
    return _userDefinedTimelineColors[colorIndex];
  }

  @override
  Widget build(BuildContext context) {
    final clip = itemWithClip.clip;
    final color = _getColorForClip(clip);
    const double minWidthForText = 40.0;

    return Expanded(
      flex: (durationRatio * 1000).round().clamp(1, 1000),
      child: GestureDetector(
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final canShowText = constraints.maxWidth > minWidthForText;

            return Container(
              margin: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(
                // 恢复您原来的透明度逻辑
                color: isSelected
                    ? color.withValues(alpha: 0.8)
                    : color.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isSelected ? color : color.withValues(alpha: 0.3),
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ]
                    : [],
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(painter: TimelineItemPainter(color: color)),
                  if (canShowText)
                    _buildItemContent(clip, itemWithClip.effectiveDuration),
                  if (isSelected)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: color, width: 1),
                        ),
                        child: Icon(Icons.check, size: 6, color: color),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildItemContent(VideoClip clip, Duration effectiveDuration) {
    // 这个方法保持不变
    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showNames)
            Text(
              clip.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                shadows: [
                  Shadow(
                    offset: Offset(0, 1),
                    blurRadius: 2,
                    color: Colors.black54,
                  ),
                ],
              ),
            ),
          if (showNames && showDuration) const SizedBox(height: 2),
          if (showDuration)
            Text(
              _formatTimelineDuration(effectiveDuration),
              style: const TextStyle(
                fontSize: 8,
                color: Colors.white70,
                fontWeight: FontWeight.w500,
                shadows: [
                  Shadow(
                    offset: Offset(0, 1),
                    blurRadius: 2,
                    color: Colors.black54,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class TimelineItemPainter extends CustomPainter {
  final Color color;
  TimelineItemPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [color.withValues(alpha: 0.05), color.withValues(alpha: 0.2)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant TimelineItemPainter oldDelegate) =>
      color != oldDelegate.color;
}
