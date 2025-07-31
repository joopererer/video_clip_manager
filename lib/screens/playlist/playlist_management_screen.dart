import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../widgets/clip_thumbnail.dart';

class PlaylistManagementScreen extends StatefulWidget {
  final Playlist playlist;

  const PlaylistManagementScreen({super.key, required this.playlist});

  @override
  State<PlaylistManagementScreen> createState() =>
      _PlaylistManagementScreenState();
}

class _PlaylistManagementScreenState extends State<PlaylistManagementScreen> {
  late List<PlaylistItemWithClip> _items;

  @override
  void initState() {
    super.initState();
    _refreshItems();
  }

  void _refreshItems() {
    final appState = context.read<AppState>();
    _items = appState.getPlaylistItemsWithClips(widget.playlist.id);
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('管理播放列表: ${widget.playlist.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_arrow),
            onPressed: () {
              // TODO: 实现播放列表播放功能
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('播放列表 "${widget.playlist.name}" 播放功能即将推出'),
                ),
              );
            },
            tooltip: '播放',
          ),
        ],
      ),
      body: Consumer<AppState>(
        builder: (context, appState, child) {
          _refreshItems();

          if (_items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.playlist_play,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '播放列表为空',
                    style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '添加一些片段来开始创建播放列表',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              _buildPlaylistInfo(),
              Expanded(child: _buildPlaylistItems()),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPlaylistInfo() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.purple.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.purple.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.playlist.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (widget.playlist.description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.playlist.description!,
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.video_library,
                      size: 16,
                      color: Colors.purple.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_items.length} 个片段',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      Icons.access_time,
                      size: 16,
                      color: Colors.purple.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '总时长: ${_formatDuration(widget.playlist.totalDuration)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
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

  Widget _buildPlaylistItems() {
    return ReorderableListView.builder(
      itemCount: _items.length,
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (oldIndex < newIndex) {
            newIndex -= 1;
          }
          final item = _items.removeAt(oldIndex);
          _items.insert(newIndex, item);
        });

        // 更新播放列表中的顺序
        final appState = context.read<AppState>();
        appState.reorderPlaylistItems(widget.playlist.id, oldIndex, newIndex);
      },
      itemBuilder: (context, index) {
        final itemWithClip = _items[index];
        return _buildPlaylistItem(itemWithClip, index);
      },
    );
  }

  Widget _buildPlaylistItem(PlaylistItemWithClip itemWithClip, int index) {
    final item = itemWithClip.item;
    final clip = itemWithClip.clip;

    return Card(
      key: ValueKey(item.id),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: () {
          // TODO: 播放这个片段
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('播放片段: ${clip.name}')));
        },
        child: Container(
          height: 80, // 固定高度
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              SizedBox(width: 60, height: 40, child: ClipThumbnail(clip: clip)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      clip.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '时长: ${_formatDuration(itemWithClip.effectiveDuration)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    if (item.customStartTime != null ||
                        item.customEndTime != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '自定义时间: ${item.customStartTime != null ? _formatDuration(item.customStartTime!) : "0:00"} - ${item.customEndTime != null ? _formatDuration(item.customEndTime!) : _formatDuration(clip.endTime - clip.startTime)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      onPressed: () => _editClipTiming(itemWithClip),
                      tooltip: '编辑时间',
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.remove_circle_outline,
                        size: 20,
                        color: Colors.red,
                      ),
                      onPressed: () => _removeClipFromPlaylist(itemWithClip),
                      tooltip: '从播放列表移除',
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
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

  void _editClipTiming(PlaylistItemWithClip itemWithClip) {
    // TODO: 实现编辑片段时间的功能
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('编辑片段时间功能即将推出')));
  }

  void _removeClipFromPlaylist(PlaylistItemWithClip itemWithClip) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认移除'),
        content: Text(
          '确定要从播放列表 "${widget.playlist.name}" 中移除片段 "${itemWithClip.clip.name}" 吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final appState = context.read<AppState>();
              appState.removeClipFromPlaylist(
                widget.playlist.id,
                itemWithClip.clip.id,
              );
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('移除'),
          ),
        ],
      ),
    );
  }
}
