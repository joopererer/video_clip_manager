import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../widgets/playlist_dialog.dart';
import '../../widgets/playlist_timeline_view.dart';
import '../playlist/playlist_management_screen.dart';
import '../player/playlist_playback_screen.dart';

class PlaylistsTab extends StatelessWidget {
  final String searchQuery;
  const PlaylistsTab({super.key, required this.searchQuery});

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
              Expanded(
                child: filteredPlaylists.isEmpty
                    ? _buildEmptyState()
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
                    if (playlist.description != null && playlist.description!.isNotEmpty) ...[
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

  List<Playlist> _getFilteredPlaylists(List<Playlist> playlists) {
    if (searchQuery.isEmpty) {
      return playlists;
    }

    final query = searchQuery.toLowerCase();
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
