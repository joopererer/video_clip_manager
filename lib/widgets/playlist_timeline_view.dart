import 'package:flutter/material.dart';
import '../data/models.dart';

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
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    final totalDuration = items.fold<Duration>(
      Duration.zero,
      (total, item) => total + item.effectiveDuration,
    );

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
                     // 轨道标签
           Container(
             width: 80,
             padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
             decoration: BoxDecoration(
               color: Colors.blue.shade50,
               borderRadius: const BorderRadius.only(
                 topLeft: Radius.circular(8),
                 bottomLeft: Radius.circular(8),
               ),
               border: Border(
                 right: BorderSide(color: Colors.grey.shade300),
               ),
             ),
             child: Row(
               mainAxisAlignment: MainAxisAlignment.center,
               children: [
                 Icon(
                   Icons.timeline,
                   size: 12,
                   color: Colors.blue.shade600,
                 ),
                 const SizedBox(width: 4),
                 Text(
                   '轨道',
                   style: TextStyle(
                     fontSize: 10,
                     color: Colors.blue.shade600,
                     fontWeight: FontWeight.w500,
                   ),
                 ),
               ],
             ),
           ),
          // 轨道内容
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
              ),
                             child: Row(
                 children: items.asMap().entries.map((entry) {
                   final index = entry.key;
                   final itemWithClip = entry.value;
                   final item = itemWithClip.item;
                   final clip = itemWithClip.clip;
                   
                   // 计算宽度比例
                   final durationRatio = itemWithClip.effectiveDuration.inMilliseconds / 
                                       totalDuration.inMilliseconds;
                   
                   return _buildTimelineItem(
                     context,
                     index,
                     itemWithClip,
                     durationRatio,
                   );
                 }).toList(),
               ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(
    BuildContext context,
    int index,
    PlaylistItemWithClip itemWithClip,
    double durationRatio,
  ) {
    final item = itemWithClip.item;
    final clip = itemWithClip.clip;
    final isSelected = selectedIndex == index;
    
    // 根据时长生成颜色
    final colors = [
      Colors.blue.shade400,
      Colors.green.shade400,
      Colors.orange.shade400,
      Colors.purple.shade400,
      Colors.red.shade400,
      Colors.teal.shade400,
      Colors.indigo.shade400,
      Colors.pink.shade400,
    ];
    final color = colors[index % colors.length];

    return Expanded(
      flex: (durationRatio * 1000).round(),
      child: GestureDetector(
        onTap: () => onItemTap?.call(index),
        child: Container(
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.8) : color.withOpacity(0.6),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? color : color.withOpacity(0.3),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Stack(
            children: [
              // 背景纹理
              Positioned.fill(
                child: CustomPaint(
                  painter: TimelineItemPainter(color: color),
                ),
              ),
              // 内容
              Padding(
                padding: const EdgeInsets.all(4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (showNames) ...[
                      Text(
                        clip.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              offset: const Offset(0, 1),
                              blurRadius: 2,
                              color: Colors.black.withOpacity(0.5),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    if (showDuration) ...[
                      Text(
                        _formatDuration(itemWithClip.effectiveDuration),
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          shadows: [
                            Shadow(
                              offset: const Offset(0, 1),
                              blurRadius: 2,
                              color: Colors.black.withOpacity(0.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // 选中指示器
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
                    child: Icon(
                      Icons.check,
                      size: 6,
                      color: color,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    if (minutes > 0) {
      return '${minutes}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${seconds}s';
    }
  }
}

class TimelineItemPainter extends CustomPainter {
  final Color color;

  TimelineItemPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.1)
      ..style = PaintingStyle.fill;

    // 绘制斜线纹理
    final path = Path();
    for (int i = 0; i < size.width + size.height; i += 8) {
      path.moveTo(i.toDouble(), 0);
      path.lineTo(i.toDouble() - size.height, size.height);
    }
    
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

 