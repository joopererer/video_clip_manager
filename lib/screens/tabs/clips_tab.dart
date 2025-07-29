import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../player/clip_editor_screen.dart';
import '../player/clip_playback_screen.dart';
import '../../widgets/clip_thumbnail.dart';

// 排序选项枚举
enum SortOption {
  nameAsc('Name (A-Z)', Icons.sort_by_alpha),
  nameDesc('Name (Z-A)', Icons.sort_by_alpha),
  dateAddedAsc('Date Added (Oldest)', Icons.access_time),
  dateAddedDesc('Date Added (Newest)', Icons.access_time),
  ratingAsc('Rating (Low to High)', Icons.star),
  ratingDesc('Rating (High to Low)', Icons.star),
  durationAsc('Duration (Short to Long)', Icons.timer),
  durationDesc('Duration (Long to Short)', Icons.timer);

  const SortOption(this.label, this.icon);
  final String label;
  final IconData icon;
}

class ClipsTab extends StatefulWidget {
  final String searchQuery;
  final List<String> selectedTags;
  final int? selectedRating;
  final bool? selectedFavorite;
  
  const ClipsTab({
    super.key,
    required this.searchQuery,
    required this.selectedTags,
    this.selectedRating,
    this.selectedFavorite,
  });

  @override
  State<ClipsTab> createState() => _ClipsTabState();
}

class _ClipsTabState extends State<ClipsTab> {
  SortOption _currentSortOption = SortOption.dateAddedDesc; // 默认按添加时间倒序

  @override
  Widget build(BuildContext context) {
    // 只监听视图模式变化，不监听clips数据变化
    final viewMode = context.select<AppState, bool>((appState) => appState.clipsIsGridView);
    
    // 直接获取clips数据，不通过watch
    final appState = context.read<AppState>();
    final clips = appState.clips;

    // 使用AppState的getFilteredClips方法，包含所有过滤条件
    final filteredClips = appState.getFilteredClips(
      searchQuery: widget.searchQuery,
      selectedTags: widget.selectedTags,
      selectedRating: widget.selectedRating ?? appState.selectedRating,
      selectedFavorite: widget.selectedFavorite ?? appState.selectedFavorite,
    );

    // 应用排序
    final sortedClips = _sortClips(filteredClips);

    return Column(
      children: [
        // 顶部控制栏：排序、视图模式、统计信息
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(16.0),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.shade200,
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // 排序下拉菜单
              Expanded(
                flex: 2,
                child: _buildSortDropdown(),
              ),
              const SizedBox(width: 16),
              // 统计信息
              _buildStatistics(sortedClips.length, clips.length),
              const SizedBox(width: 16),
              // 视图模式切换按钮
              GestureDetector(
                onTap: () => appState.setClipsViewMode(!viewMode),
                child: Container(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade600,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.shade200,
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    viewMode ? Icons.list : Icons.grid_view,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
        // 内容区域
        Expanded(
          child: sortedClips.isEmpty
              ? const Center(
            child: Text('No clips found. Try loading a JSON file.'),
          )
              : viewMode
              ? buildGridView(context, sortedClips)
              : buildListView(context, sortedClips),
        ),
      ],
    );
  }

  // 构建排序下拉菜单
  Widget _buildSortDropdown() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<SortOption>(
          value: _currentSortOption,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade600),
          iconSize: 20,
          elevation: 8,
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(12),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          items: SortOption.values.map((SortOption option) {
            return DropdownMenuItem<SortOption>(
              value: option,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _currentSortOption == option 
                          ? Colors.blue.shade50 
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      option.icon, 
                      size: 16,
                      color: _currentSortOption == option 
                          ? Colors.blue.shade700 
                          : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      option.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: _currentSortOption == option 
                            ? FontWeight.w600 
                            : FontWeight.normal,
                        color: _currentSortOption == option 
                            ? Colors.blue.shade700 
                            : Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (SortOption? newValue) {
            if (newValue != null) {
              setState(() {
                _currentSortOption = newValue;
              });
            }
          },
        ),
      ),
    );
  }

  // 构建统计信息显示
  Widget _buildStatistics(int filteredCount, int totalCount) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade50, Colors.blue.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20.0),
        border: Border.all(color: Colors.blue.shade200, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade100.withValues(alpha: 0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.blue.shade600,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.video_library, 
              size: 14, 
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$filteredCount / $totalCount',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.blue.shade800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // 排序逻辑
  List<VideoClip> _sortClips(List<VideoClip> clips) {
    final sortedClips = List<VideoClip>.from(clips);
    
    switch (_currentSortOption) {
      case SortOption.nameAsc:
        sortedClips.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case SortOption.nameDesc:
        sortedClips.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case SortOption.dateAddedAsc:
        sortedClips.sort((a, b) => a.id.compareTo(b.id)); // 假设ID按时间顺序
        break;
      case SortOption.dateAddedDesc:
        sortedClips.sort((a, b) => b.id.compareTo(a.id));
        break;
      case SortOption.ratingAsc:
        sortedClips.sort((a, b) => a.rating.compareTo(b.rating));
        break;
      case SortOption.ratingDesc:
        sortedClips.sort((a, b) => b.rating.compareTo(a.rating));
        break;
      case SortOption.durationAsc:
        sortedClips.sort((a, b) {
          final durationA = a.endTime - a.startTime;
          final durationB = b.endTime - b.startTime;
          return durationA.compareTo(durationB);
        });
        break;
      case SortOption.durationDesc:
        sortedClips.sort((a, b) {
          final durationA = a.endTime - a.startTime;
          final durationB = b.endTime - b.startTime;
          return durationB.compareTo(durationA);
        });
        break;
    }
    
    return sortedClips;
  }

  Widget buildListView(BuildContext context, List<VideoClip> clips) {
    final appState = context.read<AppState>();
    return ListView.builder(
      itemCount: clips.length,
      itemBuilder: (context, index) {
        final clip = clips[index];
        
        return ClipListItem(
          clip: clip,
          onPlay: () => _playClip(context, clip),
          onEdit: () => _editClip(context, clip),
          onDelete: () => _deleteClip(context, clip, appState),
        );
      },
    );
  }

  Widget buildGridView(BuildContext context, List<VideoClip> clips) {
    final appState = context.read<AppState>();
    return GridView.builder(
      padding: const EdgeInsets.all(8.0),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        childAspectRatio: 0.8,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: clips.length,
      itemBuilder: (context, index) {
        final clip = clips[index];
        final duration = clip.endTime - clip.startTime;
        
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _playClip(context, clip),
            child: Column(
              children: [
                // Header with action buttons only (no favorite icon)
                Container(
                  color: Colors.black54,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end, // 靠右对齐
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.edit,
                          color: Colors.white,
                          size: 18,
                        ),
                        onPressed: () => _editClip(context, clip),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete,
                          color: Colors.pink,
                          size: 18,
                        ),
                        onPressed: () => _deleteClip(context, clip, appState),
                      ),
                    ],
                  ),
                ),
                // Thumbnail
                Expanded(
                  child: ClipThumbnail(clip: clip),
                ),
                // Footer with info and controls
                Container(
                  color: Colors.black45,
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        clip.name,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // Duration
                      Text(
                        formatDuration(duration),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white70,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Rating stars and favorite button in one row
                      Row(
                        children: [
                          // Rating stars
                          ...List.generate(5, (starIndex) {
                            return GestureDetector(
                              onTap: () {
                                final newRating = clip.rating == starIndex + 1 ? 0 : starIndex + 1;
                                final updatedClip = clip.copyWith(rating: newRating);
                                appState.updateClip(updatedClip);
                              },
                              child: Icon(
                                starIndex < clip.rating ? Icons.star : Icons.star_border,
                                color: starIndex < clip.rating ? Colors.amber : Colors.white54,
                                size: 14,
                              ),
                            );
                          }),
                          const Spacer(),
                          // Favorite button
                          GestureDetector(
                            onTap: () {
                              final updatedClip = clip.copyWith(isFavorite: !clip.isFavorite);
                              appState.updateClip(updatedClip);
                            },
                            child: Icon(
                              clip.isFavorite ? Icons.favorite : Icons.favorite_border,
                              color: clip.isFavorite ? Colors.redAccent : Colors.white54,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Play button
                          GestureDetector(
                            onTap: () => _playClip(context, clip),
                            child: const Icon(
                              Icons.play_circle_outline,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _playClip(BuildContext context, VideoClip clip) {
    final appState = context.read<AppState>();
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: ClipPlaybackScreen(
          clip: clip,
          allClips: appState.clips.toList(),
          searchQuery: widget.searchQuery,
          selectedTags: widget.selectedTags,
          selectedRating: widget.selectedRating,
          selectedFavorite: widget.selectedFavorite,
          currentSortOption: _currentSortOption,
        ),
      ),
    );
  }

  void _editClip(BuildContext context, VideoClip clip) {
    final appState = context.read<AppState>();
    final video = appState.originalVideos.firstWhere(
          (v) => v.path == clip.videoPath,
      // Au cas où la vidéo originale aurait été supprimée, on en crée une temporaire.
      orElse: () => OriginalVideo(
        id: 'temp_${clip.videoPath.hashCode}',
        path: clip.videoPath,
        name: clip.videoPath.split(Platform.pathSeparator).last,
      ),
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        // **LA CORRECTION EST ICI**
        // On passe uniquement la vidéo. ClipEditorScreen se chargera d'afficher tous les clips associés.
        builder: (context) => ClipEditorScreen(
          video: video,
          clipToEdit: clip,
        ),
      ),
    );
  }

  void _deleteClip(BuildContext context, VideoClip clip, AppState appState) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: Text('Are you sure you want to delete "${clip.name}"?'),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          TextButton(
            onPressed: () {
              appState.deleteClip(clip.id);
              Navigator.of(ctx).pop();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

String formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  } else {
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

// 独立的列表项widget，只监听自己的clip数据变化
class ClipListItem extends StatefulWidget {
  final VideoClip clip;
  final VoidCallback onPlay;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const ClipListItem({
    super.key,
    required this.clip,
    required this.onPlay,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<ClipListItem> createState() => _ClipListItemState();
}

class _ClipListItemState extends State<ClipListItem> {
  late ValueNotifier<int> _ratingNotifier;
  late ValueNotifier<bool> _favoriteNotifier;

  @override
  void initState() {
    super.initState();
    _ratingNotifier = ValueNotifier(widget.clip.rating);
    _favoriteNotifier = ValueNotifier(widget.clip.isFavorite);
  }

  @override
  void didUpdateWidget(ClipListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clip.rating != widget.clip.rating) {
      _ratingNotifier.value = widget.clip.rating;
    }
    if (oldWidget.clip.isFavorite != widget.clip.isFavorite) {
      _favoriteNotifier.value = widget.clip.isFavorite;
    }
  }

  @override
  void dispose() {
    _ratingNotifier.dispose();
    _favoriteNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.clip.endTime - widget.clip.startTime;
    
    return RepaintBoundary(
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: InkWell(
          onTap: widget.onPlay,
          child: Container(
            height: 80, // 调整高度
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                // 1. 略缩图 - 使用RepaintBoundary隔离
                RepaintBoundary(
                  child: Container(
                    width: 80, // 调整略缩图宽度
                    height: 56, // 保持16:9比例
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      color: Colors.grey.shade200,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: ClipThumbnail(clip: widget.clip, width: 80, height: 56),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 2. 信息区域
                Expanded(
                  child: RepaintBoundary(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 标题
                        Text(
                          widget.clip.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        // 时间信息
                        Text(
                          '${formatDuration(widget.clip.startTime)} - ${formatDuration(widget.clip.endTime)} (${formatDuration(duration)})',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                        if (widget.clip.tags.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Tags: ${widget.clip.tags.join(', ')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 3. 星级评分 - 使用ValueListenableBuilder精确更新
                ValueListenableBuilder<int>(
                  valueListenable: _ratingNotifier,
                  builder: (context, rating, child) {
                    return Wrap(
                      spacing: 1.0,
                      children: List.generate(5, (starIndex) {
                        return GestureDetector(
                          onTap: () {
                            final appState = context.read<AppState>();
                            final newRating = rating == starIndex + 1 ? 0 : starIndex + 1;
                            final updatedClip = widget.clip.copyWith(rating: newRating);
                            appState.updateClip(updatedClip);
                          },
                          child: Icon(
                            starIndex < rating ? Icons.star : Icons.star_border,
                            color: starIndex < rating ? Colors.amber : Colors.grey,
                            size: 16,
                          ),
                        );
                      }),
                    );
                  },
                ),
                const SizedBox(width: 8),
                // 4. 爱心收藏 - 使用ValueListenableBuilder精确更新
                ValueListenableBuilder<bool>(
                  valueListenable: _favoriteNotifier,
                  builder: (context, isFavorite, child) {
                    return GestureDetector(
                      onTap: () {
                        final appState = context.read<AppState>();
                        final updatedClip = widget.clip.copyWith(isFavorite: !isFavorite);
                        appState.updateClip(updatedClip);
                      },
                      child: Icon(
                        isFavorite ? Icons.favorite : Icons.favorite_border,
                        color: isFavorite ? Colors.redAccent : Colors.grey,
                        size: 18,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 16), // 5. <空白> 区域
                // 6. 编辑按钮
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                  onPressed: widget.onEdit,
                  tooltip: 'Edit Clip',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 4),
                // 7. 删除按钮
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
                  onPressed: widget.onDelete,
                  tooltip: 'Delete Clip',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}