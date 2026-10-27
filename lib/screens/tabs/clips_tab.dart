import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../services/preview_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../utils/tag_utils.dart';
import '../../widgets/add_to_playlist_dialog.dart';
import '../../widgets/clip_card.dart';
import '../../widgets/clip_list_row.dart';
import '../player/clip_editor_screen.dart';
import '../player/clip_playback_screen.dart';

// 排序选项枚举
enum SortOption {
  nameAsc('名称 (A-Z)', Icons.sort_by_alpha),
  nameDesc('名称 (Z-A)', Icons.sort_by_alpha),
  dateAddedAsc('最早添加', Icons.access_time),
  dateAddedDesc('最新添加', Icons.access_time),
  ratingAsc('评分 (从低到高)', Icons.star),
  ratingDesc('评分 (从高到低)', Icons.star),
  durationAsc('时长 (从短到长)', Icons.timer),
  durationDesc('时长 (从长到短)', Icons.timer);

  const SortOption(this.label, this.icon);
  final String label;
  final IconData icon;
}

class ClipsTab extends StatefulWidget {
  final String searchQuery;
  final List<String> selectedTags;
  final int? selectedRating;
  final bool? selectedFavorite;
  final VoidCallback? onClearSearch;
  final VoidCallback? onOpenVideos;

  const ClipsTab({
    super.key,
    required this.searchQuery,
    required this.selectedTags,
    this.selectedRating,
    this.selectedFavorite,
    this.onClearSearch,
    this.onOpenVideos,
  });

  @override
  State<ClipsTab> createState() => _ClipsTabState();
}

class _ClipsTabState extends State<ClipsTab> {
  SortOption _currentSortOption = SortOption.dateAddedDesc;
  String? _selectedClipId;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final viewMode = appState.clipsIsGridView;
    final allClips = appState.clips;

    // 使用 AppState 的过滤逻辑获取匹配列表
    final filteredClips = appState.getFilteredClips(
      searchQuery: widget.searchQuery,
      selectedTags: widget.selectedTags,
      selectedRating: widget.selectedRating ?? appState.selectedRating,
      selectedFavorite: widget.selectedFavorite ?? appState.selectedFavorite,
    );

    // 应用排序规则
    final sortedClips = _sortClips(filteredClips);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 顶部控制与筛选工具条
        _buildToolbar(context, appState, sortedClips.length, allClips.length),

        // 主展示内容区 (响应式网格 / 列表 / 空状态)
        Expanded(
          child: sortedClips.isEmpty
              ? _buildEmptyState(context, appState, allClips.length)
              : viewMode
              ? _buildGridView(context, appState, sortedClips)
              : _buildListView(context, appState, sortedClips),
        ),
      ],
    );
  }

  Widget _buildToolbar(
    BuildContext context,
    AppState appState,
    int filteredCount,
    int totalCount,
  ) {
    final colors = context.appColors;
    final viewMode = appState.clipsIsGridView;

    final hasActiveFilter =
        appState.selectedTags.isNotEmpty ||
        appState.selectedRating != null ||
        appState.selectedFavorite != null ||
        widget.searchQuery.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(
          bottom: BorderSide(color: colors.borderSubtle, width: 1.0),
        ),
      ),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          // 左侧：排序菜单与筛选触发器
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 排序下拉
              _buildSortDropdown(context, colors),

              const SizedBox(width: AppSpacing.sm),

              // 快捷筛选弹出菜单
              _buildFilterMenuButton(context, appState, colors),
              const SizedBox(width: AppSpacing.xs),
              FilterChip(
                avatar: const Icon(Icons.favorite_border, size: 16),
                label: const Text('收藏'),
                selected: appState.selectedFavorite == true,
                onSelected: (selected) =>
                    appState.setSelectedFavorite(selected ? true : null),
              ),

              if (hasActiveFilter) ...[
                const SizedBox(width: AppSpacing.xs),
                // 一键清除筛选
                TextButton.icon(
                  onPressed: () {
                    appState.clearAllFilters();
                    widget.onClearSearch?.call();
                    if (appState.semanticScores.isNotEmpty) {
                      appState.clearSemanticSearch();
                    }
                  },
                  icon: const Icon(Icons.clear_all, size: 16),
                  label: const Text('重置筛选', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.textSecondary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                ),
              ],
            ],
          ),

          // 右侧：结果数量统计与网格/列表切换
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 统计徽章
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceElevated,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: colors.borderSubtle),
                ),
                child: Text(
                  '展示 $filteredCount / 共 $totalCount 个片段',
                  style: AppTypography.caption.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

              const SizedBox(width: AppSpacing.sm),

              // 视图切换按钮组
              Container(
                decoration: BoxDecoration(
                  color: colors.surfaceElevated,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: colors.borderSubtle),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: '网格视图',
                      child: InkWell(
                        onTap: () => appState.setClipsViewMode(true),
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(AppRadius.sm),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: viewMode
                                ? colors.primaryContainer
                                : Colors.transparent,
                            borderRadius: const BorderRadius.horizontal(
                              left: Radius.circular(AppRadius.sm),
                            ),
                          ),
                          child: Icon(
                            Icons.grid_view,
                            size: 17,
                            color: viewMode ? colors.primary : colors.textMuted,
                          ),
                        ),
                      ),
                    ),
                    Tooltip(
                      message: '列表视图',
                      child: InkWell(
                        onTap: () => appState.setClipsViewMode(false),
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(AppRadius.sm),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: !viewMode
                                ? colors.primaryContainer
                                : Colors.transparent,
                            borderRadius: const BorderRadius.horizontal(
                              right: Radius.circular(AppRadius.sm),
                            ),
                          ),
                          child: Icon(
                            Icons.view_list,
                            size: 18,
                            color: !viewMode
                                ? colors.primary
                                : colors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSortDropdown(BuildContext context, AppColorExtension colors) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<SortOption>(
          value: _currentSortOption,
          icon: Icon(
            Icons.arrow_drop_down,
            color: colors.textSecondary,
            size: 20,
          ),
          dropdownColor: colors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppRadius.md),
          style: TextStyle(color: colors.textPrimary, fontSize: 12.5),
          items: SortOption.values.map((option) {
            return DropdownMenuItem<SortOption>(
              value: option,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(option.icon, size: 14, color: colors.primary),
                  const SizedBox(width: 6),
                  Text(option.label),
                ],
              ),
            );
          }).toList(),
          onChanged: (newVal) {
            if (newVal != null) {
              setState(() => _currentSortOption = newVal);
            }
          },
        ),
      ),
    );
  }

  Widget _buildFilterMenuButton(
    BuildContext context,
    AppState appState,
    AppColorExtension colors,
  ) {
    return PopupMenuButton<String>(
      tooltip: '多维条件筛选',
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: colors.border),
      ),
      color: colors.surfaceElevated,
      onSelected: (action) {
        switch (action) {
          case 'tags':
            _showTagFilterDialog(context, appState);
            break;
          case 'rating':
            _showRatingFilterDialog(context, appState);
            break;
          case 'favorite':
            _showFavoriteFilterDialog(context, appState);
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'tags',
          child: Row(
            children: [
              const Icon(Icons.label_outline, size: 18),
              const SizedBox(width: 8),
              Text(
                appState.selectedTags.isEmpty
                    ? '按标签筛选…'
                    : '标签已选 (${appState.selectedTags.length})',
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'rating',
          child: Row(
            children: [
              const Icon(Icons.star_outline, size: 18),
              const SizedBox(width: 8),
              Text(
                appState.selectedRating == null
                    ? '按星级筛选…'
                    : '星级已选 (${appState.selectedRating == 0 ? "无星" : "${appState.selectedRating}星"})',
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'favorite',
          child: Row(
            children: [
              const Icon(Icons.favorite_outline, size: 18),
              const SizedBox(width: 8),
              Text(
                appState.selectedFavorite == null
                    ? '按收藏筛选…'
                    : (appState.selectedFavorite! ? '仅看收藏' : '仅看未收藏'),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color:
              (appState.selectedTags.isNotEmpty ||
                  appState.selectedRating != null ||
                  appState.selectedFavorite != null)
              ? colors.primaryContainer.withValues(alpha: 0.6)
              : colors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color:
                (appState.selectedTags.isNotEmpty ||
                    appState.selectedRating != null ||
                    appState.selectedFavorite != null)
                ? colors.primary
                : colors.borderSubtle,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_list,
              size: 16,
              color:
                  (appState.selectedTags.isNotEmpty ||
                      appState.selectedRating != null ||
                      appState.selectedFavorite != null)
                  ? colors.primaryHover
                  : colors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              '筛选',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color:
                    (appState.selectedTags.isNotEmpty ||
                        appState.selectedRating != null ||
                        appState.selectedFavorite != null)
                    ? colors.primaryHover
                    : colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridView(
    BuildContext context,
    AppState appState,
    List<VideoClip> clips,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 根据可用宽度动态计算网格列数 (220px - 280px 卡片宽度适中)
        final crossAxisCount = (constraints.maxWidth / 240).floor().clamp(1, 6);

        return GridView.builder(
          padding: const EdgeInsets.all(AppSpacing.md),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: AppSpacing.md,
            mainAxisSpacing: AppSpacing.md,
            mainAxisExtent:
                ((constraints.maxWidth - 32 - (crossAxisCount - 1) * 16) /
                        crossAxisCount) *
                    9 /
                    16 +
                112,
          ),
          itemCount: clips.length,
          itemBuilder: (context, index) {
            final clip = clips[index];
            return ClipCard(
              key: ValueKey(clip.id),
              clip: clip,
              isSelected: _selectedClipId == clip.id,
              onSelect: () => setState(() => _selectedClipId = clip.id),
              onPlay: () => _playClip(context, clip),
              onEdit: () => _editClip(context, clip),
              onDelete: () => _deleteClip(context, clip, appState),
              onAddToPlaylist: () => _showAddToPlaylistDialog(context, clip),
              onRatingChanged: (newRating) {
                appState.updateClip(clip.copyWith(rating: newRating));
              },
              onFavoriteToggled: (newFav) {
                appState.updateClip(clip.copyWith(isFavorite: newFav));
              },
            );
          },
        );
      },
    );
  }

  Widget _buildListView(
    BuildContext context,
    AppState appState,
    List<VideoClip> clips,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      itemCount: clips.length,
      itemBuilder: (context, index) {
        final clip = clips[index];
        return ClipListRow(
          key: ValueKey(clip.id),
          clip: clip,
          isSelected: _selectedClipId == clip.id,
          onSelect: () => setState(() => _selectedClipId = clip.id),
          onPlay: () => _playClip(context, clip),
          onEdit: () => _editClip(context, clip),
          onDelete: () => _deleteClip(context, clip, appState),
          onAddToPlaylist: () => _showAddToPlaylistDialog(context, clip),
          onRatingChanged: (newRating) {
            appState.updateClip(clip.copyWith(rating: newRating));
          },
          onFavoriteToggled: (newFav) {
            appState.updateClip(clip.copyWith(isFavorite: newFav));
          },
        );
      },
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    AppState appState,
    int totalClipsCount,
  ) {
    final colors = context.appColors;
    final isFiltered = totalClipsCount > 0;

    return Center(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: colors.surfaceElevated,
                shape: BoxShape.circle,
                border: Border.all(color: colors.borderSubtle),
              ),
              child: Icon(
                isFiltered ? Icons.search_off : Icons.video_library_outlined,
                size: 48,
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              isFiltered ? '未找到符合条件的片段' : '片段库暂无视频片段',
              style: AppTypography.sectionTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              isFiltered
                  ? '尝试修改搜索关键词或重置当前标签/星级过滤条件。'
                  : '请先导入本地或在线视频，进入片段编辑器标记 IN/OUT 剪辑点保存片段。',
              style: AppTypography.bodySecondary,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (isFiltered)
              FilledButton.icon(
                onPressed: () {
                  appState.clearAllFilters();
                  widget.onClearSearch?.call();
                  if (appState.semanticScores.isNotEmpty) {
                    appState.clearSemanticSearch();
                  }
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重置所有筛选'),
              )
            else
              FilledButton.icon(
                onPressed: () {
                  widget.onOpenVideos?.call();
                },
                icon: const Icon(Icons.movie_outlined, size: 16),
                label: const Text('前往原始视频库导入'),
              ),
          ],
        ),
      ),
    );
  }

  // 排序算法实现
  List<VideoClip> _sortClips(List<VideoClip> clips) {
    final sorted = List<VideoClip>.from(clips);

    switch (_currentSortOption) {
      case SortOption.nameAsc:
        sorted.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        break;
      case SortOption.nameDesc:
        sorted.sort(
          (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()),
        );
        break;
      case SortOption.dateAddedAsc:
        sorted.sort((a, b) => a.id.compareTo(b.id));
        break;
      case SortOption.dateAddedDesc:
        sorted.sort((a, b) => b.id.compareTo(a.id));
        break;
      case SortOption.ratingAsc:
        sorted.sort((a, b) => a.rating.compareTo(b.rating));
        break;
      case SortOption.ratingDesc:
        sorted.sort((a, b) => b.rating.compareTo(a.rating));
        break;
      case SortOption.durationAsc:
        sorted.sort((a, b) {
          final durA = a.endTime - a.startTime;
          final durB = b.endTime - b.startTime;
          return durA.compareTo(durB);
        });
        break;
      case SortOption.durationDesc:
        sorted.sort((a, b) {
          final durA = a.endTime - a.startTime;
          final durB = b.endTime - b.startTime;
          return durB.compareTo(durA);
        });
        break;
    }

    return sorted;
  }

  // 播放与编辑弹窗逻辑
  void _playClip(BuildContext context, VideoClip clip) async {
    final appState = context.read<AppState>();
    final clipToEdit = await showDialog<VideoClip?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 1200,
            maxHeight: 800,
            minWidth: 800,
            minHeight: 600,
          ),
          child: ClipPlaybackScreen(
            clip: clip,
            allClips: appState.clips.toList(),
            searchQuery: widget.searchQuery,
            selectedTags: widget.selectedTags,
            selectedRating: widget.selectedRating,
            selectedFavorite: widget.selectedFavorite,
            currentSortOption: _currentSortOption,
            initialSeekTime: clip.hitTimestampMs != null
                ? Duration(milliseconds: clip.hitTimestampMs!)
                : null,
          ),
        ),
      ),
    );

    if (clipToEdit != null && context.mounted) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (context.mounted) {
        _editClip(context, clipToEdit);
      }
    } else {
      PreviewService().resumeGlobalPreGeneration();
    }
  }

  void _editClip(BuildContext context, VideoClip clip) {
    final appState = context.read<AppState>();
    final video = appState.originalVideos.firstWhere(
      (v) => v.path == clip.videoPath,
      orElse: () => OriginalVideo(
        id: 'temp_${clip.videoPath.hashCode}',
        path: clip.videoPath,
        name: clip.videoPath.split(Platform.pathSeparator).last,
      ),
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ClipEditorScreen(video: video, clipToEdit: clip),
      ),
    );
  }

  void _showAddToPlaylistDialog(BuildContext context, VideoClip clip) {
    showDialog(
      context: context,
      builder: (context) => AddToPlaylistDialog(clip: clip),
    );
  }

  void _deleteClip(BuildContext context, VideoClip clip, AppState appState) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除片段确认'),
        content: Text('确定要删除片段 "${clip.name}" 吗？此操作仅移除元数据记录，不会删除源视频文件。'),
        actions: [
          TextButton(
            child: const Text('取消'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          FilledButton(
            onPressed: () {
              appState.deleteClip(clip.id);
              Navigator.of(ctx).pop();
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
  }

  // 筛选对话框
  void _showTagFilterDialog(BuildContext context, AppState appState) {
    final allTags = appState.allTags;
    List<String> tempSelectedTags = List.from(appState.selectedTags);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('按标签筛选'),
          content: SizedBox(
            width: 360,
            child: allTags.isEmpty
                ? const Text('库中暂无可用的标签。')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: allTags.length,
                    itemBuilder: (context, index) {
                      final tag = allTags[index];
                      final isSelected = tempSelectedTags.contains(tag);
                      return CheckboxListTile(
                        title: buildTagText(tag),
                        value: isSelected,
                        onChanged: (val) {
                          setDialogState(() {
                            if (val == true) {
                              tempSelectedTags.add(tag);
                            } else {
                              tempSelectedTags.remove(tag);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                appState.setSelectedTags(tempSelectedTags);
                Navigator.pop(ctx);
              },
              child: const Text('应用'),
            ),
          ],
        ),
      ),
    );
  }

  void _showRatingFilterDialog(BuildContext context, AppState appState) {
    int? tempRating = appState.selectedRating;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('按星级筛选'),
          content: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('全部星级'),
                selected: tempRating == null,
                onSelected: (selected) {
                  setDialogState(
                    () => tempRating = selected ? null : tempRating,
                  );
                },
              ),
              ChoiceChip(
                label: const Text('无评分 (0星)'),
                selected: tempRating == 0,
                onSelected: (selected) {
                  setDialogState(() => tempRating = selected ? 0 : null);
                },
              ),
              ...List.generate(5, (index) {
                final rating = index + 1;
                return ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.star,
                        size: 14,
                        color: AppColors.starActive,
                      ),
                      const SizedBox(width: 4),
                      Text('$rating 星'),
                    ],
                  ),
                  selected: tempRating == rating,
                  onSelected: (selected) {
                    setDialogState(() => tempRating = selected ? rating : null);
                  },
                );
              }),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                appState.setSelectedRating(tempRating);
                Navigator.pop(ctx);
              },
              child: const Text('应用'),
            ),
          ],
        ),
      ),
    );
  }

  void _showFavoriteFilterDialog(BuildContext context, AppState appState) {
    bool? tempFav = appState.selectedFavorite;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('按收藏状态筛选'),
          content: Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('全部片段'),
                selected: tempFav == null,
                onSelected: (selected) {
                  setDialogState(() => tempFav = selected ? null : tempFav);
                },
              ),
              ChoiceChip(
                label: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.favorite,
                      size: 14,
                      color: AppColors.favoriteActive,
                    ),
                    SizedBox(width: 4),
                    Text('仅看收藏'),
                  ],
                ),
                selected: tempFav == true,
                onSelected: (selected) {
                  setDialogState(() => tempFav = selected ? true : null);
                },
              ),
              ChoiceChip(
                label: const Text('仅看未收藏'),
                selected: tempFav == false,
                onSelected: (selected) {
                  setDialogState(() => tempFav = selected ? false : null);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                appState.setSelectedFavorite(tempFav);
                Navigator.pop(ctx);
              },
              child: const Text('应用'),
            ),
          ],
        ),
      ),
    );
  }
}
