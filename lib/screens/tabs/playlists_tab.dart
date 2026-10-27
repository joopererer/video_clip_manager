import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../widgets/playlist_dialog.dart';
import '../../widgets/playlist_timeline_view.dart';
import '../../widgets/clip_thumbnail.dart';
import '../playlist/playlist_management_screen.dart';
import '../player/playlist_playback_screen.dart';
import '../../widgets/playlist_import_export_dialog.dart';
import '../../services/preview_service.dart';
import '../../services/screenshot_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

class _PlaylistCardBase extends StatelessWidget {
  final bool isSelected;
  final bool isHovered;
  final Widget child;
  final VoidCallback onTap;
  final ValueChanged<bool> onHover;

  const _PlaylistCardBase({
    required this.isSelected,
    required this.isHovered,
    required this.child,
    required this.onTap,
    required this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      color: isSelected
          ? c.primaryContainer.withValues(alpha: 0.35)
          : (isHovered ? c.surfaceElevated : c.surface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(
          color: isSelected
              ? c.primary
              : (isHovered ? c.primaryHover.withValues(alpha: 0.45) : c.border),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        onHover: onHover,
        hoverColor: Colors.transparent,
        child: child,
      ),
    );
  }
}

class PlaylistsTab extends StatefulWidget {
  final String searchQuery;
  const PlaylistsTab({super.key, required this.searchQuery});

  @override
  State<PlaylistsTab> createState() => _PlaylistsTabState();
}

class _PlaylistsTabState extends State<PlaylistsTab> {
  AppColorExtension get _c => context.appColors;

  void _setHover(int index, bool hovering) {
    final next = hovering
        ? index
        : (_hoveredIndex == index ? null : _hoveredIndex);
    if (next != _hoveredIndex) setState(() => _hoveredIndex = next);
  }

  // 以列表位置而非 id 作为选中/悬停键：历史数据中可能存在空 id 或重复 id
  int? _selectedIndex;
  int? _hoveredIndex;
  bool _isImporting = false;
  bool _isExporting = false;

  final Map<String, String> _sortOptions = {
    'name': '按名称',
    'date': '按创建时间',
    'duration': '按时长',
  };

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final filteredPlaylists = _getFilteredPlaylists(appState.playlists);

    return Scaffold(
      body: Column(
        children: [
          _buildHeader(context, appState, filteredPlaylists),
          Expanded(
            child: filteredPlaylists.isEmpty
                ? _buildEmptyState()
                : appState.playlistsIsGridView
                ? _buildPlaylistGrid(context, appState, filteredPlaylists)
                : _buildPlaylistList(context, appState, filteredPlaylists),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createPlaylist(context),
        label: const Text('创建播放列表'),
        icon: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    AppState appState,
    List<Playlist> playlists,
  ) {
    final totalDuration = playlists.fold<Duration>(
      Duration.zero,
      (total, playlist) => total + playlist.totalDuration,
    );
    final totalClips = playlists.fold<int>(
      0,
      (total, playlist) => total + playlist.clipCount,
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: _c.surface,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: _c.border, width: 0.5),
      ),
      child: Row(
        children: [
          // 播放列表统计信息
          Expanded(
            child: Wrap(
              // 使用 Wrap 可以在小屏幕上自动换行
              spacing: 16.0,
              runSpacing: 8.0,
              children: [
                _buildInfoItem(
                  '播放列表',
                  '${playlists.length}',
                  Icons.playlist_play,
                  _c.primary,
                ),
                const SizedBox(width: 16),
                _buildInfoItem(
                  '总时长',
                  _formatDuration(totalDuration),
                  Icons.access_time,
                  _c.info,
                ),
                const SizedBox(width: 16),
                _buildInfoItem(
                  '总片段',
                  '$totalClips',
                  Icons.video_library,
                  _c.success,
                ),
              ],
            ),
          ),

          // 导入按钮
          _buildHeaderAction(
            label: '导入:',
            tooltip: '导入播放列表',
            onTap: _isImporting
                ? null
                : () {
                    _importPlaylist(context, appState);
                  },
            icon: _isImporting
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(_c.primary),
                    ),
                  )
                : Icon(Icons.file_upload, size: 18, color: _c.textPrimary),
          ),

          const SizedBox(width: 24),

          // 排序选项
          _buildHeaderAction(
            label: '排序:',
            tooltip: '排序方式',
            icon: PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              icon: Icon(Icons.sort, size: 18, color: _c.textPrimary),
              onSelected: (value) => appState.setPlaylistsSortBy(value),
              // OPTIMIZED: 使用Map动态生成菜单项
              itemBuilder: (context) => _sortOptions.entries.map((entry) {
                return PopupMenuItem<String>(
                  value: entry.key,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(entry.value),
                      if (appState.playlistsSortBy == entry.key)
                        Icon(Icons.check, size: 16, color: _c.success),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(width: 8),

          // 视图模式切换
          _buildHeaderAction(
            label: '视图:',
            tooltip: '切换视图',
            onTap: () =>
                appState.setPlaylistsViewMode(!appState.playlistsIsGridView),
            icon: Icon(
              appState.playlistsIsGridView ? Icons.list : Icons.grid_view,
              size: 18,
              color: _c.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  /// A custom header action button with a label and an icon.
  /// The entire area is clickable and shows a tooltip on hover.
  Widget _buildHeaderAction({
    required String label,
    required Widget icon, // Renamed from 'child' for clarity
    required String tooltip, // Made tooltip required for good accessibility
    VoidCallback? onTap,
  }) {
    // The InkWell is now the parent of the Container.
    // This makes the entire area, including padding, responsive.
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(
          6,
        ), // Important for the ripple effect
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _c.surfaceElevated,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _c.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, color: _c.textSecondary),
              ),
              const SizedBox(width: 4),
              // The icon is placed in a SizedBox to ensure consistent layout
              SizedBox(
                width: 32,
                height: 32,
                child: Center(
                  child: icon,
                ), // Use Center to ensure the icon is centered
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          '$label: $value',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: _c.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: _c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _c.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _c.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.playlist_play, size: 48, color: _c.primary),
            ),
            const SizedBox(height: 24),
            Text(
              '暂无播放列表',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: _c.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '开始创建您的第一个播放列表',
              style: TextStyle(fontSize: 14, color: _c.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _createPlaylist(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('创建播放列表'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _c.primary,
                foregroundColor: _c.onPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistList(
    BuildContext context,
    AppState appState,
    List<Playlist> playlists,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        return _buildPlaylistCard(context, appState, playlist, index);
      },
    );
  }

  Widget _buildPlaylistGrid(
    BuildContext context,
    AppState appState,
    List<Playlist> playlists,
  ) {
    return GridView.builder(
      padding: const EdgeInsets.all(8.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        childAspectRatio: 0.85,
        crossAxisSpacing: 8.0,
        mainAxisSpacing: 8.0,
      ),
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        return _buildPlaylistGridCard(context, appState, playlist, index);
      },
    );
  }

  Widget _buildPlaylistCard(
    BuildContext context,
    AppState appState,
    Playlist playlist,
    int index,
  ) {
    return _PlaylistCardBase(
      isSelected: _selectedIndex == index,
      isHovered: _hoveredIndex == index,
      onTap: () {
        setState(() => _selectedIndex = index);
        _playPlaylist(context, appState, playlist);
      },
      onHover: (hovering) => _setHover(index, hovering),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          children: [
            SizedBox(
              width: 120,
              height: 90,
              child: _buildPlaylistThumbnail(appState, playlist),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          playlist.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: _c.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _buildActionButton(
                        icon: Icons.play_arrow,
                        tooltip: '播放',
                        onPressed: () => _handlePlaylistAction(
                          context,
                          appState,
                          playlist,
                          'play',
                        ),
                        color: _c.success,
                      ),
                      const SizedBox(width: 8),
                      _buildActionButton(
                        icon: Icons.edit,
                        tooltip: '编辑',
                        onPressed: () => _handlePlaylistAction(
                          context,
                          appState,
                          playlist,
                          'edit',
                        ),
                        color: _c.info,
                      ),
                      const SizedBox(width: 8),
                      _buildActionButton(
                        icon: Icons.list,
                        tooltip: '管理片段',
                        onPressed: () => _handlePlaylistAction(
                          context,
                          appState,
                          playlist,
                          'manage',
                        ),
                        color: _c.warning,
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        onSelected: (value) => _handlePlaylistAction(
                          context,
                          appState,
                          playlist,
                          value,
                        ),
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'export',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.file_download,
                                  color: _c.info,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text('导出', style: TextStyle(color: _c.info)),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, color: _c.danger, size: 18),
                                const SizedBox(width: 8),
                                Text('删除', style: TextStyle(color: _c.danger)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (playlist.description?.isNotEmpty ?? false) ...[
                    Text(
                      playlist.description!,
                      style: TextStyle(fontSize: 12, color: _c.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                  ],
                  Row(
                    children: [
                      _buildStatItem(
                        Icons.video_library,
                        '${playlist.clipCount} 个片段',
                        _c.info,
                      ),
                      const SizedBox(width: 16),
                      _buildStatItem(
                        Icons.access_time,
                        _formatDuration(playlist.totalDuration),
                        _c.success,
                      ),
                      const SizedBox(width: 16),
                      _buildStatItem(
                        Icons.calendar_today,
                        _formatDate(playlist.createdAt),
                        _c.warning,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildPlaylistTimeline(context, playlist),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistGridCard(
    BuildContext context,
    AppState appState,
    Playlist playlist,
    int index,
  ) {
    final isSelected = _selectedIndex == index;
    final itemsWithClips = appState.getPlaylistItemsWithClips(playlist.id);

    return _PlaylistCardBase(
      isSelected: isSelected,
      isHovered: _hoveredIndex == index,
      onTap: () {
        setState(() => _selectedIndex = index);
        _playPlaylist(context, appState, playlist);
      },
      onHover: (hovering) => _setHover(index, hovering),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // constraints 对象现在包含了父容器(Expanded)的可用宽高
                // constraints.maxWidth 和 constraints.maxHeight

                // 将这个尺寸传递给你的函数
                final parentSize = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );

                final play_icon_size = constraints.maxWidth / 4.5;

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // 如果没有片段，显示占位符
                    if (itemsWithClips.isEmpty)
                      Container(
                        decoration: BoxDecoration(
                          color: _c.surfaceElevated,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(8),
                            topRight: Radius.circular(8),
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.playlist_play,
                            color: _c.textMuted,
                            size: 48,
                          ),
                        ),
                      )
                    else
                      // OPTIMIZED: 调用新的方法来构建复杂缩略图
                      _buildMultiClipThumbnailStack(itemsWithClips, parentSize),

                    // 播放按钮覆盖
                    Center(
                      child: Container(
                        width: play_icon_size,
                        height: play_icon_size,
                        decoration: BoxDecoration(
                          color: _c.primary.withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: play_icon_size / 1.8,
                        ),
                      ),
                    ),
                    // 操作按钮
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: itemsWithClips.isNotEmpty
                          ? Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildActionButton(
                                    icon: Icons.edit,
                                    color: _c.info,
                                    tooltip: "编辑",
                                    onPressed: () => _handlePlaylistAction(
                                      context,
                                      appState,
                                      playlist,
                                      'edit',
                                    ),
                                    isMini: true,
                                  ),
                                  const SizedBox(width: 4),
                                  _buildActionButton(
                                    icon: Icons.list,
                                    color: _c.warning,
                                    tooltip: "管理片段",
                                    onPressed: () => _handlePlaylistAction(
                                      context,
                                      appState,
                                      playlist,
                                      'manage',
                                    ),
                                    isMini: true,
                                  ),
                                  const SizedBox(width: 4),
                                  _buildActionButton(
                                    icon: Icons.file_download,
                                    color: _c.info,
                                    tooltip: "导出",
                                    onPressed: () => _handlePlaylistAction(
                                      context,
                                      appState,
                                      playlist,
                                      'export',
                                    ),
                                    isMini: true,
                                    isLoading: _isExporting,
                                  ),
                                  const SizedBox(width: 4),
                                  _buildActionButton(
                                    icon: Icons.delete,
                                    color: _c.danger,
                                    tooltip: "删除",
                                    onPressed: () => _handlePlaylistAction(
                                      context,
                                      appState,
                                      playlist,
                                      'delete',
                                    ),
                                    isMini: true,
                                  ),
                                ],
                              ),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildActionButton(
                                  icon: Icons.edit,
                                  color: _c.info,
                                  tooltip: "编辑",
                                  onPressed: () => _handlePlaylistAction(
                                    context,
                                    appState,
                                    playlist,
                                    'edit',
                                  ),
                                  isMini: true,
                                ),
                                const SizedBox(width: 4),
                                _buildActionButton(
                                  icon: Icons.list,
                                  color: _c.warning,
                                  tooltip: "管理片段",
                                  onPressed: () => _handlePlaylistAction(
                                    context,
                                    appState,
                                    playlist,
                                    'manage',
                                  ),
                                  isMini: true,
                                ),
                                const SizedBox(width: 4),
                                _buildActionButton(
                                  icon: Icons.file_download,
                                  color: _c.info,
                                  tooltip: "导出",
                                  onPressed: () => _handlePlaylistAction(
                                    context,
                                    appState,
                                    playlist,
                                    'export',
                                  ),
                                  isMini: true,
                                  isLoading: _isExporting,
                                ),
                                const SizedBox(width: 4),
                                _buildActionButton(
                                  icon: Icons.delete,
                                  color: _c.danger,
                                  tooltip: "删除",
                                  onPressed: () => _handlePlaylistAction(
                                    context,
                                    appState,
                                    playlist,
                                    'delete',
                                  ),
                                  isMini: true,
                                ),
                              ],
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
          // 信息区域
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  playlist.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                    color: _c.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.video_library, size: 18, color: _c.info),
                    const SizedBox(width: 4),
                    Text(
                      '${playlist.clipCount}',
                      style: TextStyle(
                        fontSize: 14,
                        color: _c.info,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.access_time, size: 18, color: _c.success),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        _formatDuration(playlist.totalDuration),
                        style: TextStyle(
                          fontSize: 14,
                          color: _c.success,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // OPTIMIZED: 新增方法，用于构建单个堆叠的缩略图，避免代码重复
  Widget _buildStackedThumbnail({
    required VideoClip clip,
    required double width,
    required double height,
  }) {
    return Container(
      width: width,
      height: height,
      margin: const EdgeInsets.only(bottom: 8.0), // 用 margin 代替 SizedBox
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            // 修正：使用 withOpacity
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: ClipThumbnail(clip: clip),
      ),
    );
  }

  // OPTIMIZED: 新增方法，构建完整的多缩略图Stack视图
  Widget _buildMultiClipThumbnailStack(
    List<PlaylistItemWithClip> itemsWithClips,
    Size parentSize, // 接收父容器尺寸
  ) {
    final double baseWidth = parentSize.width;
    final double baseHeight = parentSize.height;

    // 定义堆叠缩略图的尺寸
    final stackedSizes = [
      Size(baseWidth * 0.38, baseHeight * 0.28),
      Size(baseWidth * 0.32, baseHeight * 0.24),
    ];

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. 背景缩略图 (第一个 Clip)
        if (itemsWithClips.isNotEmpty)
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(8),
            ),
            child: ClipThumbnail(clip: itemsWithClips.first.clip),
          ),

        // 2. 堆叠的缩略图 (从第二个 Clip 开始)
        if (itemsWithClips.length > 1)
          Positioned(
            top: 8,
            right: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // 使用 for 循环和 take(2) 最多只显示两个堆叠图，保持界面整洁
                for (var i = 0; i < itemsWithClips.skip(1).take(2).length; i++)
                  _buildStackedThumbnail(
                    clip: itemsWithClips[i + 1].clip,
                    width: stackedSizes[i].width,
                    height: stackedSizes[i].height,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  List<Playlist> _getFilteredPlaylists(List<Playlist> playlists) {
    // 创建可修改的列表副本
    List<Playlist> filtered = List.from(playlists);

    // 搜索过滤
    if (widget.searchQuery.isNotEmpty) {
      final query = widget.searchQuery.toLowerCase();
      filtered = filtered.where((playlist) {
        return playlist.name.toLowerCase().contains(query) ||
            (playlist.description?.toLowerCase().contains(query) ?? false);
      }).toList();
    }

    // 排序
    final appState = context.read<AppState>();
    switch (appState.playlistsSortBy) {
      case 'name':
        filtered.sort((a, b) => a.name.compareTo(b.name));
        break;
      case 'date':
        filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case 'duration':
        filtered.sort((a, b) => b.totalDuration.compareTo(a.totalDuration));
        break;
    }

    return filtered;
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Widget _buildPlaylistThumbnail(AppState appState, Playlist playlist) {
    final itemsWithClips = appState.getPlaylistItemsWithClips(playlist.id);
    Widget content;
    if (itemsWithClips.isEmpty) {
      content = Container(
        color: _c.surfaceElevated,
        child: Center(
          child: Icon(Icons.playlist_play, color: _c.textMuted, size: 24),
        ),
      );
    } else {
      content = ClipThumbnail(clip: itemsWithClips.first.clip);
    }
    return ClipRRect(borderRadius: BorderRadius.circular(8.0), child: content);
  }

  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    required Color color,
    bool isMini = false,
    bool isLoading = false,
  }) {
    final size = isMini ? 32.0 : 40.0;
    final iconSize = isMini ? 16.0 : 20.0;

    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        icon: isLoading
            ? SizedBox(
                width: iconSize,
                height: iconSize,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              )
            : Icon(icon, color: color, size: iconSize),
        onPressed: isLoading ? null : onPressed,
        style: IconButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(isMini ? 4 : 8),
            side: BorderSide(color: color.withValues(alpha: 0.3)),
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildPlaylistTimeline(BuildContext context, Playlist playlist) {
    if (playlist.items.isEmpty) {
      return Container(
        height: 28,
        decoration: BoxDecoration(
          color: _c.surfaceElevated,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _c.border),
        ),
        child: Center(
          child: Text(
            '暂无片段',
            style: TextStyle(fontSize: 10, color: _c.textSecondary),
          ),
        ),
      );
    }

    final appState = context.read<AppState>();
    final itemsWithClips = appState.getPlaylistItemsWithClips(playlist.id);

    return Container(
      decoration: BoxDecoration(
        color: _c.surfaceElevated,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _c.border),
      ),
      child: PlaylistTimelineView(
        items: itemsWithClips,
        height: 28,
        showDuration: false,
        showNames: true,
        enableReorder: false,
      ),
    );
  }

  Future<void> _createPlaylist(BuildContext context) async {
    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (context) => const PlaylistDialog(),
    );

    if (result != null) {
      final appState = context.read<AppState>();
      appState.createPlaylist(
        result['name']!,
        description: result['description'],
      );
    }
  }

  Future<void> _handlePlaylistAction(
    BuildContext context,
    AppState appState,
    Playlist playlist,
    String action,
  ) async {
    switch (action) {
      case 'play':
        _playPlaylist(context, appState, playlist);
        break;
      case 'edit':
        _editPlaylist(context, appState, playlist);
        break;
      case 'manage':
        _managePlaylist(context, appState, playlist);
        break;
      case 'export':
        _exportPlaylist(context, appState, playlist);
        break;
      case 'delete':
        _deletePlaylist(context, appState, playlist);
        break;
    }
  }

  Future<void> _playPlaylist(
    BuildContext context,
    AppState appState,
    Playlist playlist,
  ) async {
    PreviewService().pauseGlobalPreGeneration();
    await ScreenshotService().prepareForPlayback();
    if (!context.mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PlaylistPlaybackScreen(playlist: playlist),
      ),
    );
  }

  Future<void> _editPlaylist(
    BuildContext context,
    AppState appState,
    Playlist playlist,
  ) async {
    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (context) => PlaylistDialog(playlist: playlist),
    );

    if (result != null) {
      appState.updatePlaylist(
        playlist.id,
        name: result['name'],
        description: result['description'],
      );
    }
  }

  void _managePlaylist(
    BuildContext context,
    AppState appState,
    Playlist playlist,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PlaylistManagementScreen(playlist: playlist),
      ),
    );
  }

  Future<void> _importPlaylist(BuildContext context, AppState appState) async {
    setState(() {
      _isImporting = true;
    });

    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => const PlaylistImportExportDialog(),
      );

      // 导入流程现在在 PlaylistImportPreviewDialog 中处理
      // 这里不需要额外的处理，因为成功消息已经在预览对话框中显示了
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  Future<void> _exportPlaylist(
    BuildContext context,
    AppState appState,
    Playlist playlist,
  ) async {
    setState(() {
      _isExporting = true;
    });

    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => PlaylistImportExportDialog(playlist: playlist),
      );

      if (result == true) {
        // 导出成功，已经在对话框中显示了成功消息
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  Future<void> _deletePlaylist(
    BuildContext context,
    AppState appState,
    Playlist playlist,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除播放列表 "${playlist.name}" 吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _c.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      appState.deletePlaylist(playlist.id);
    }
  }
}
