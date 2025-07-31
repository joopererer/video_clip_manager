import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../widgets/playlist_dialog.dart';
import '../../widgets/playlist_timeline_view.dart';
import '../../widgets/clip_thumbnail.dart';
import '../playlist/playlist_management_screen.dart';
import '../player/playlist_playback_screen.dart';

class PlaylistsTab extends StatefulWidget {
  final String searchQuery;
  const PlaylistsTab({super.key, required this.searchQuery});

  @override
  State<PlaylistsTab> createState() => _PlaylistsTabState();
}

class _PlaylistsTabState extends State<PlaylistsTab> {
  bool _isGridView = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<AppState>(
        builder: (context, appState, child) {
          final playlists = appState.playlists;
          final filteredPlaylists = _getFilteredPlaylists(playlists);

          return Column(
            children: [
              _buildHeader(context, appState, filteredPlaylists),
              _buildViewToggle(),
              Expanded(
                child: filteredPlaylists.isEmpty
                    ? _buildEmptyState()
                    : _isGridView
                    ? _buildPlaylistGrid(context, appState, filteredPlaylists)
                    : _buildPlaylistList(context, appState, filteredPlaylists),
              ),
            ],
          );
        },
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
          Expanded(
            child: Row(
              children: [
                _buildInfoItem(
                  '播放列表',
                  '${playlists.length}',
                  Icons.playlist_play,
                ),
                const SizedBox(width: 16),
                _buildInfoItem(
                  '总时长',
                  _formatDuration(totalDuration),
                  Icons.access_time,
                ),
                const SizedBox(width: 16),
                _buildInfoItem('总片段', '$totalClips', Icons.video_library),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.purple.shade600),
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

  Widget _buildViewToggle() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconButton(
            icon: Icon(_isGridView ? Icons.list : Icons.grid_view),
            onPressed: () {
              setState(() {
                _isGridView = !_isGridView;
              });
            },
            tooltip: _isGridView ? '列表视图' : '网格视图',
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.playlist_play, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            '暂无播放列表',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右下角按钮创建您的第一个播放列表',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
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
         crossAxisCount: 3,
         childAspectRatio: 1.1,
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
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      child: InkWell(
        onTap: () => _playPlaylist(context, appState, playlist),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.purple.shade100,
                radius: 20,
                child: Icon(
                  Icons.playlist_play,
                  color: Colors.purple.shade600,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 第一行：标题和菜单按钮
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
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, size: 20),
                          onSelected: (value) => _handlePlaylistAction(
                            context,
                            appState,
                            playlist,
                            value,
                          ),
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'play',
                              child: Row(
                                children: [
                                  Icon(Icons.play_arrow, size: 18),
                                  SizedBox(width: 8),
                                  Text('播放'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit, size: 18),
                                  SizedBox(width: 8),
                                  Text('编辑'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'manage',
                              child: Row(
                                children: [
                                  Icon(Icons.list, size: 18),
                                  SizedBox(width: 8),
                                  Text('管理片段'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    '删除',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // 第二行：描述（如果有）
                    if (playlist.description != null &&
                        playlist.description!.isNotEmpty) ...[
                      Text(
                        playlist.description!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                    ],
                    // 第三行：统计信息
                    Row(
                      children: [
                        Icon(
                          Icons.video_library,
                          size: 14,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${playlist.clipCount} 个片段',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDuration(playlist.totalDuration),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // 第四行：时间轴
                    _buildPlaylistTimeline(context, playlist),
                    const SizedBox(height: 4),
                    // 第五行：创建时间
                    Text(
                      '创建于 ${_formatDate(playlist.createdAt)}',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaylistGridCard(
    BuildContext context,
    AppState appState,
    Playlist playlist,
  ) {
    final itemsWithClips = appState.getPlaylistItemsWithClips(playlist.id);

    return Card(
      child: InkWell(
        onTap: () => _playPlaylist(context, appState, playlist),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
                         // 叠放的缩略图区域
             Expanded(
               flex: 4,
               child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                ),
                child: itemsWithClips.isEmpty
                    ? Center(
                        child: Icon(
                          Icons.playlist_play,
                          size: 32,
                          color: Colors.grey.shade400,
                        ),
                      )
                    : Stack(
                        children: [
                          // 背景缩略图（第一个clip）
                          if (itemsWithClips.isNotEmpty)
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(4),
                                  topRight: Radius.circular(4),
                                ),
                                child: ClipThumbnail(
                                  clip: itemsWithClips.first.clip,
                                ),
                              ),
                            ),
                          // 叠放的小缩略图
                          if (itemsWithClips.length > 1)
                            ...itemsWithClips
                                .skip(1)
                                .take(3)
                                .toList()
                                .asMap()
                                .entries
                                .map((entry) {
                                  final index = entry.key;
                                  final itemWithClip = entry.value;
                                  return Positioned(
                                    top: 8.0 + (index * 20.0),
                                    right: 8.0 + (index * 15.0),
                                    child: Container(
                                      width: 40,
                                      height: 25,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(2),
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 1,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                              0.2,
                                            ),
                                            blurRadius: 2,
                                            offset: const Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(2),
                                        child: ClipThumbnail(
                                          clip: itemWithClip.clip,
                                        ),
                                      ),
                                    ),
                                  );
                                })
                                .toList(),
                          // 播放列表信息覆盖层
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withOpacity(0.7),
                                  ],
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.playlist_play,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      playlist.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
                         // 信息区域
             Expanded(
               flex: 1,
               child: Padding(
                 padding: const EdgeInsets.all(6.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                                         Text(
                       playlist.name,
                       style: const TextStyle(
                         fontWeight: FontWeight.w600,
                         fontSize: 12,
                       ),
                       maxLines: 1,
                       overflow: TextOverflow.ellipsis,
                     ),
                     const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.video_library,
                          size: 12,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${playlist.clipCount}',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.access_time,
                          size: 12,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          _formatDuration(playlist.totalDuration),
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
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
    );
  }

  List<Playlist> _getFilteredPlaylists(List<Playlist> playlists) {
    if (widget.searchQuery.isEmpty) {
      return playlists;
    }

    final query = widget.searchQuery.toLowerCase();
    return playlists.where((playlist) {
      return playlist.name.toLowerCase().contains(query) ||
          (playlist.description?.toLowerCase().contains(query) ?? false);
    }).toList();
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

  Widget _buildPlaylistTimeline(BuildContext context, Playlist playlist) {
    if (playlist.items.isEmpty) {
      return Container(
        height: 30,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(4),
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

    return PlaylistTimelineView(
      items: itemsWithClips,
      height: 30,
      showDuration: false,
      showNames: true,
      enableReorder: false,
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
