import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../data/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/tag_utils.dart';
import 'clip_media_preview.dart';
import 'common/timecode_chip.dart';

class ClipListRow extends StatefulWidget {
  final VideoClip clip;
  final bool isSelected;
  final VoidCallback onPlay;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onAddToPlaylist;
  final ValueChanged<int> onRatingChanged;
  final ValueChanged<bool> onFavoriteToggled;
  final VoidCallback? onSelect;

  const ClipListRow({
    super.key,
    required this.clip,
    this.isSelected = false,
    required this.onPlay,
    required this.onEdit,
    required this.onDelete,
    required this.onAddToPlaylist,
    required this.onRatingChanged,
    required this.onFavoriteToggled,
    this.onSelect,
  });

  @override
  State<ClipListRow> createState() => _ClipListRowState();
}

class _ClipListRowState extends State<ClipListRow> {
  bool _isHovered = false;
  bool _hasFocus = false;

  void _showContextMenu(Offset globalPosition) async {
    widget.onSelect?.call();
    final RenderBox? overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final value = await showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem<int>(
          value: 0,
          child: Row(
            children: [
              Icon(Icons.play_arrow, size: 18),
              SizedBox(width: 8),
              Text('播放片段'),
            ],
          ),
        ),
        const PopupMenuItem<int>(
          value: 1,
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 18),
              SizedBox(width: 8),
              Text('编辑时间范围与元数据'),
            ],
          ),
        ),
        const PopupMenuItem<int>(
          value: 2,
          child: Row(
            children: [
              Icon(Icons.playlist_add, size: 18),
              SizedBox(width: 8),
              Text('添加到播放列表'),
            ],
          ),
        ),
        const PopupMenuItem<int>(
          value: 3,
          child: Row(
            children: [
              Icon(Icons.copy_outlined, size: 18),
              SizedBox(width: 8),
              Text('复制源视频完整路径'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<int>(
          value: 4,
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
              SizedBox(width: 8),
              Text('删除片段', style: TextStyle(color: AppColors.danger)),
            ],
          ),
        ),
      ],
    );

    if (!mounted || value == null) return;
    switch (value) {
      case 0:
        widget.onPlay();
        break;
      case 1:
        widget.onEdit();
        break;
      case 2:
        widget.onAddToPlaylist();
        break;
      case 3:
        Clipboard.setData(ClipboardData(text: widget.clip.videoPath));
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已复制视频完整路径到剪贴板')));
        break;
      case 4:
        widget.onDelete();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final clip = widget.clip;
    final duration = clip.endTime - clip.startTime;
    final sourceName = p.basename(clip.videoPath);

    return Focus(
      canRequestFocus: false,
      onFocusChange: (focused) => setState(() => _hasFocus = focused),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: InkWell(
          onSecondaryTapDown: (details) =>
              _showContextMenu(details.globalPosition),
          onTap: () {
            widget.onSelect?.call();
            widget.onPlay();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.5),
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? AppColors.primaryContainer.withValues(alpha: 0.28)
                  : ((_isHovered || _hasFocus)
                        ? colors.surfaceHighlight.withValues(alpha: 0.5)
                        : colors.surface),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: widget.isSelected
                    ? AppColors.primary
                    : ((_isHovered || _hasFocus)
                          ? AppColors.primaryHover.withValues(alpha: 0.45)
                          : colors.border),
                width: widget.isSelected ? 1.4 : 0.8,
              ),
            ),
            child: Row(
              children: [
                // 1. 缩略图区域 (16:9, 固定宽度 120px)
                SizedBox(
                  width: 120,
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                          child: ClipMediaPreview(clip: clip),
                        ),
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: TimecodeChip(
                            duration: duration,
                            fontSize: 10,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            backgroundColor: Colors.black.withValues(
                              alpha: 0.8,
                            ),
                            borderColor: Colors.white24,
                            timeColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: AppSpacing.sm),

                // 2. 信息列
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 标题与来源
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              clip.name.isNotEmpty ? clip.name : '未命名片段',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.subtitle.copyWith(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (clip.hitTimestampMs != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.xs,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.auto_awesome,
                                    size: 11,
                                    color: Colors.black87,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    '命中: ${AppTypography.formatTimecode(Duration(milliseconds: clip.hitTimestampMs!))}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),

                      const SizedBox(height: 3),

                      // 来源文件名与剪辑区间
                      Text(
                        '$sourceName · ${AppTypography.formatTimecode(clip.startTime)} — ${AppTypography.formatTimecode(clip.endTime)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(
                          color: colors.textSecondary,
                          fontSize: 11.5,
                        ),
                      ),

                      if (clip.aiSummary != null && clip.aiSummary!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2.0),
                          child: Text(
                            '✨ ${clip.aiSummary!}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.success,
                            ),
                          ),
                        ),

                      // 标签行
                      if (clip.tags.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          children: clip.tags.take(3).map((tag) {
                            final tagColor = generateTagColor(tag);
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: tagColor.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.xs,
                                ),
                                border: Border.all(
                                  color: tagColor.withValues(alpha: 0.35),
                                  width: 0.6,
                                ),
                              ),
                              child: Text(
                                tag,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: tagColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(width: AppSpacing.sm),

                // 3. 评分交互 (5星)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(5, (starIdx) {
                    final score = starIdx + 1;
                    final isActive = score <= clip.rating;
                    return Tooltip(
                      message: '评为 $score 星',
                      child: InkWell(
                        onTap: () => widget.onRatingChanged(
                          clip.rating == score ? 0 : score,
                        ),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1.5),
                          child: Icon(
                            isActive ? Icons.star : Icons.star_border,
                            size: 15,
                            color: isActive
                                ? AppColors.starActive
                                : colors.textMuted,
                          ),
                        ),
                      ),
                    );
                  }),
                ),

                const SizedBox(width: AppSpacing.sm),

                // 4. 收藏按钮
                Tooltip(
                  message: clip.isFavorite ? '取消收藏' : '加入收藏',
                  child: IconButton(
                    icon: Icon(
                      clip.isFavorite ? Icons.favorite : Icons.favorite_border,
                      size: 18,
                      color: clip.isFavorite
                          ? AppColors.favoriteActive
                          : colors.textMuted,
                    ),
                    onPressed: () => widget.onFavoriteToggled(!clip.isFavorite),
                    visualDensity: VisualDensity.compact,
                  ),
                ),

                // 5. 快速操作按钮 (播放、编辑、加入播放列表、删除)
                IconButton(
                  icon: const Icon(Icons.play_circle_outline, size: 20),
                  tooltip: '播放',
                  onPressed: widget.onPlay,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: '编辑',
                  onPressed: widget.onEdit,
                  visualDensity: VisualDensity.compact,
                ),
                PopupMenuButton<int>(
                  icon: const Icon(Icons.more_vert, size: 18),
                  tooltip: '更多选项',
                  padding: EdgeInsets.zero,
                  onSelected: (val) {
                    switch (val) {
                      case 0:
                        widget.onAddToPlaylist();
                        break;
                      case 1:
                        Clipboard.setData(
                          ClipboardData(text: widget.clip.videoPath),
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已复制视频完整路径到剪贴板')),
                          );
                        }
                        break;
                      case 2:
                        widget.onDelete();
                        break;
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 0,
                      child: Row(
                        children: [
                          Icon(Icons.playlist_add, size: 18),
                          SizedBox(width: 8),
                          Text('添加到播放列表'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 1,
                      child: Row(
                        children: [
                          Icon(Icons.copy_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('复制源视频路径'),
                        ],
                      ),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      value: 2,
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: AppColors.danger,
                          ),
                          SizedBox(width: 8),
                          Text(
                            '删除片段',
                            style: TextStyle(color: AppColors.danger),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
