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

class _PlaylistCardBase extends StatelessWidget {
  final Playlist playlist;
  final bool isSelected;
  final Widget child;
  final VoidCallback onTap;
  final ValueChanged<bool> onHover;

  const _PlaylistCardBase({
    required this.playlist,
    required this.isSelected,
    required this.child,
    required this.onTap,
    required this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      color: isSelected ? Colors.purple.shade50 : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected ? Colors.purple.shade300 : Colors.grey.shade300,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: InkWell(onTap: onTap, onHover: onHover, child: child),
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
  String? _selectedPlaylistId;
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
        color: Colors.purple.shade50,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: Colors.purple.shade200, width: 0.5),
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
                  Colors.purple.shade600,
                ),
                const SizedBox(width: 16),
                _buildInfoItem(
                  '总时长',
                  _formatDuration(totalDuration),
                  Icons.access_time,
                  Colors.blue.shade600,
                ),
                const SizedBox(width: 16),
                _buildInfoItem(
                  '总片段',
                  '$totalClips',
                  Icons.video_library,
                  Colors.green.shade600,
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
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.purple.shade600,
                      ),
                    ),
                  )
                : Icon(Icons.file_upload, size: 18),
          ),

          const SizedBox(width: 24),

          // 排序选项
          _buildHeaderAction(
            label: '排序:',
            tooltip: '排序方式',
            icon: PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.sort, size: 18),
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
                        const Icon(Icons.check, size: 16, color: Colors.green),
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.purple.shade200, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(label, style: const TextStyle(fontSize: 12)),
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
            color: Colors.grey.shade700,
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
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.purple.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.playlist_play,
                size: 48,
                color: Colors.purple.shade600,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '暂无播放列表',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '开始创建您的第一个播放列表',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _createPlaylist(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('创建播放列表'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple.shade600,
                foregroundColor: Colors.white,
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
        return _buildPlaylistCard(context, appState, playlist);
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
        crossAxisCount: 5,
        childAspectRatio: 0.85,
        crossAxisSpacing: 8.0,
        mainAxisSpacing: 8.0,
      ),
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        return _buildPlaylistGridCard(context, appState, playlist);
      },
    );
  }

  Widget _buildPlaylistCard(
    BuildContext context,
    AppState appState,
    Playlist playlist,
  ) {
    return _PlaylistCardBase(
      playlist: playlist,
      isSelected: _selectedPlaylistId == playlist.id,
      onTap: () {
        setState(() => _selectedPlaylistId = playlist.id);
        _playPlaylist(context, appState, playlist);
      },
      onHover: (hovering) {
        if (hovering) setState(() => _selectedPlaylistId = playlist.id);
      },
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            SizedBox(
              width: 80,
              height: 60,
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
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
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
                        color: Colors.green.shade600,
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
                        color: Colors.blue.shade600,
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
                        color: Colors.orange.shade600,
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
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.file_download,
                                  color: Colors.blue,
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  '导出',
                                  style: TextStyle(color: Colors.blue),
                                ),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, color: Colors.red, size: 18),
                                SizedBox(width: 8),
                                Text('删除', style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (playlist.description?.isNotEmpty ?? false) ...[
                    Text(
                      playlist.description!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      _buildStatItem(
                        Icons.video_library,
                        '${playlist.clipCount} 个片段',
                        Colors.blue.shade600,
                      ),
                      const SizedBox(width: 16),
                      _buildStatItem(
                        Icons.access_time,
                        _formatDuration(playlist.totalDuration),
                        Colors.green.shade600,
                      ),
                      const SizedBox(width: 16),
                      _buildStatItem(
                        Icons.calendar_today,
                        _formatDate(playlist.createdAt),
                        Colors.orange.shade600,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
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
  ) {
    final isSelected = _selectedPlaylistId == playlist.id;
    final itemsWithClips = appState.getPlaylistItemsWithClips(playlist.id);

    return _PlaylistCardBase(
      playlist: playlist,
      isSelected: isSelected,
      onTap: () {
        setState(() => _selectedPlaylistId = playlist.id);
        _playPlaylist(context, appState, playlist);
      },
      onHover: (hovering) {
        if (hovering) setState(() => _selectedPlaylistId = playlist.id);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 如果没有片段，显示占位符
                if (itemsWithClips.isEmpty)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        topRight: Radius.circular(8),
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.playlist_play,
                        color: Colors.grey.shade400,
                        size: 48,
                      ),
                    ),
                  )
                else
                  // OPTIMIZED: 调用新的方法来构建复杂缩略图
                  _buildMultiClipThumbnailStack(itemsWithClips),

                // 播放按钮覆盖
                Center(
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.purple.shade600.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 32,
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
                                color: Colors.blue.shade600,
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
                                color: Colors.orange.shade600,
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
                                color: Colors.blue.shade600,
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
                                color: Colors.red.shade600,
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
                              color: Colors.blue.shade600,
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
                              color: Colors.orange.shade600,
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
                              color: Colors.blue.shade600,
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
                              color: Colors.red.shade600,
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
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.video_library,
                      size: 18,
                      color: Colors.blue.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${playlist.clipCount}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.blue.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.access_time,
                      size: 18,
                      color: Colors.green.shade600,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        _formatDuration(playlist.totalDuration),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.green.shade600,
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
  ) {
    // 定义堆叠缩略图的尺寸
    final stackedSizes = [const Size(100, 70), const Size(80, 64)];

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
    if (itemsWithClips.isEmpty) {
      return Container(
        color: Colors.grey.shade100,
        child: Center(
          child: Icon(
            Icons.playlist_play,
            color: Colors.grey.shade400,
            size: 24,
          ),
        ),
      );
    }
    return ClipThumbnail(clip: itemsWithClips.first.clip);
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
            fontSize: 12,
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
        height: 30,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Center(
          child: Text(
            '暂无片段',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
        ),
      );
    }

    final appState = context.read<AppState>();
    final itemsWithClips = appState.getPlaylistItemsWithClips(playlist.id);

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: PlaylistTimelineView(
        items: itemsWithClips,
        height: 30,
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

  void _playPlaylist(
    BuildContext context,
    AppState appState,
    Playlist playlist,
  ) {
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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
