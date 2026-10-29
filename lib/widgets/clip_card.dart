import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../data/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/tag_utils.dart';
import 'clip_media_preview.dart';
import 'common/media_card_activation.dart';
import 'common/semantic_score_chip.dart';
import 'common/timecode_chip.dart';

class ClipCard extends StatefulWidget {
  final VideoClip clip;
  final bool isSelected;
  final VoidCallback onPlay;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onAddToPlaylist;
  final ValueChanged<int> onRatingChanged;
  final ValueChanged<bool> onFavoriteToggled;
  final VoidCallback? onSelect;

  /// Cosine similarity of the best matching frame for the current semantic
  /// search. Null for keyword-only results, so no score is ever invented.
  final double? semanticScore;

  const ClipCard({
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
    this.semanticScore,
  });

  @override
  State<ClipCard> createState() => _ClipCardState();
}

class _ClipCardState extends State<ClipCard> {
  bool _isHovered = false;
  bool _hasFocus = false;

  void _showContextMenu(Offset globalPosition) async {
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
        child: MediaCardInteractor(
          onSelect: widget.onSelect,
          onActivate: widget.onPlay,
          onSecondaryTapDown: (details) =>
              _showContextMenu(details.globalPosition),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: widget.isSelected
                    ? colors.primary
                    : ((_isHovered || _hasFocus)
                          ? colors.primaryHover.withValues(alpha: 0.6)
                          : colors.border),
                width: widget.isSelected ? 1.6 : 1.0,
              ),
              boxShadow: (_isHovered || _hasFocus)
                  ? [
                      BoxShadow(
                        color: colors.primary.withValues(alpha: 0.12),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. 16:9 响应式缩略图区域
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // 底层缩略图与关键帧预检
                      ClipMediaPreview(clip: clip),

                      // 右下角时间码浮层
                      Positioned(
                        right: AppSpacing.xs,
                        bottom: AppSpacing.xs,
                        child: TimecodeChip(
                          duration: duration,
                          backgroundColor: Colors.black.withValues(alpha: 0.78),
                          borderColor: Colors.white24,
                          timeColor: Colors.white,
                        ),
                      ),

                      // 左上角 AI 命中/语义标记
                      if (clip.hitTimestampMs != null ||
                          widget.semanticScore != null)
                        Positioned(
                          left: AppSpacing.xs,
                          top: AppSpacing.xs,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (clip.hitTimestampMs != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.warning.withValues(
                                      alpha: 0.92,
                                    ),
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
                                        AppTypography.formatTimecode(
                                          Duration(
                                            milliseconds: clip
                                                .hitTimestampMs!,
                                          ),
                                        ),
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (widget.semanticScore != null) ...[
                                const SizedBox(height: 3),
                                SemanticScoreChip(
                                  score: widget.semanticScore!,
                                  fontSize: 10,
                                ),
                              ],
                            ],
                          ),
                        ),

                      // 鼠标悬停时的半透明操作层
                      if (_isHovered || _hasFocus)
                        Align(
                          alignment: Alignment.topCenter,
                          child: Container(
                            height: 56,
                            color: Colors.black.withValues(alpha: 0.38),
                            child: Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // 播放主按钮
                                  Tooltip(
                                    message: '播放片段',
                                    child: InkWell(
                                      onTap: widget.onPlay,
                                      borderRadius: BorderRadius.circular(24),
                                      child: Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: colors.primary,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.play_arrow,
                                          color: Colors.white,
                                          size: 24,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  // 编辑按钮
                                  Tooltip(
                                    message: '编辑片段',
                                    child: InkWell(
                                      onTap: widget.onEdit,
                                      borderRadius: BorderRadius.circular(20),
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(
                                            alpha: 0.6,
                                          ),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white30,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.edit_outlined,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  IconButton(
                                    tooltip: '更多操作',
                                    icon: const Icon(
                                      Icons.more_vert,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    onPressed: () {
                                      // Opening the menu from the button also
                                      // selects the card (existing behavior).
                                      widget.onSelect?.call();
                                      final box =
                                          context.findRenderObject()
                                              as RenderBox;
                                      _showContextMenu(
                                        box.localToGlobal(const Offset(20, 40)),
                                      );
                                    },
                                  ),
                                  // 添加到播放列表
                                  Tooltip(
                                    message: '加入播放列表',
                                    child: InkWell(
                                      onTap: widget.onAddToPlaylist,
                                      borderRadius: BorderRadius.circular(20),
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(
                                            alpha: 0.6,
                                          ),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white30,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.playlist_add,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // 2. 文本与元数据展示区
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // 第 1 行：片段标题与收藏心标
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                clip.name.isNotEmpty ? clip.name : '未命名片段',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.subtitle.copyWith(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Tooltip(
                              message: clip.isFavorite ? '取消收藏' : '加入收藏',
                              child: InkWell(
                                onTap: () =>
                                    widget.onFavoriteToggled(!clip.isFavorite),
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.all(2.0),
                                  child: Icon(
                                    clip.isFavorite
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    size: 17,
                                    color: clip.isFavorite
                                        ? AppColors.favoriteActive
                                        : colors.textMuted,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        // 第 2 行：来源视频与 AI 简评
                        Text(
                          sourceName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption.copyWith(
                            color: colors.textSecondary,
                            fontSize: 11.5,
                          ),
                        ),
                        if (clip.aiSummary != null &&
                            clip.aiSummary!.isNotEmpty)
                          Text(
                            '✨ ${clip.aiSummary!}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.success,
                            ),
                          ),

                        // 第 3 行：交互式星级评分与标签
                        Row(
                          children: [
                            // 5 星交互评分
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
                                      padding: const EdgeInsets.only(
                                        right: 2.0,
                                      ),
                                      child: Icon(
                                        isActive
                                            ? Icons.star
                                            : Icons.star_border,
                                        size: 14,
                                        color: isActive
                                            ? AppColors.starActive
                                            : colors.textMuted,
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                            const Spacer(),
                            // 标签预览 (最多展示 2 个以避免拥挤)
                            if (clip.tags.isNotEmpty)
                              Flexible(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Tooltip(
                                        message: clip.tags.join(', '),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 1.5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: generateTagColor(
                                              clip.tags.first,
                                            ).withValues(alpha: 0.18),
                                            borderRadius: BorderRadius.circular(
                                              AppRadius.xs,
                                            ),
                                            border: Border.all(
                                              color: generateTagColor(
                                                clip.tags.first,
                                              ).withValues(alpha: 0.4),
                                              width: 0.6,
                                            ),
                                          ),
                                          constraints: const BoxConstraints(
                                            maxWidth: 80,
                                          ),
                                          child: Text(
                                            clip.tags.first,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w500,
                                              color: generateTagColor(
                                                clip.tags.first,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (clip.tags.length > 1) ...[
                                      const SizedBox(width: 3),
                                      Text(
                                        '+${clip.tags.length - 1}',
                                        style: AppTypography.caption.copyWith(
                                          fontSize: 9.5,
                                          color: colors.textMuted,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
