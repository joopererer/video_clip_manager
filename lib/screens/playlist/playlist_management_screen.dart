import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../widgets/clip_thumbnail.dart';
import '../../widgets/playlist_timeline_view.dart';
import '../player/playlist_playback_screen.dart';

class PlaylistManagementScreen extends StatefulWidget {
  final Playlist playlist;

  const PlaylistManagementScreen({super.key, required this.playlist});

  @override
  State<PlaylistManagementScreen> createState() =>
      _PlaylistManagementScreenState();
}

class _PlaylistManagementScreenState extends State<PlaylistManagementScreen> {
  // 原始状态（从 AppState 获取的真实数据）
  List<PlaylistItemWithClip> _originalItems = [];

  // 编辑状态（用户正在编辑的副本）
  List<PlaylistItemWithClip> _editingItems = [];

  // 是否处于编辑模式
  final bool _isEditing = false;

  // 是否有未保存的更改
  bool _hasChanges = false;

  int? _selectedItemIndex;

  @override
  void initState() {
    super.initState();
    // 延迟初始化，确保 context 可用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshItems();
    });
  }

  void _refreshItems() {
    if (!mounted) return;
    final appState = context.read<AppState>();
    _originalItems = appState.getPlaylistItemsWithClips(widget.playlist.id);

    // 如果不在编辑模式，同步编辑状态
    if (!_isEditing) {
      _editingItems = List.from(_originalItems);
      _hasChanges = false;
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _refreshFromExternalChanges() {
    if (!mounted) return;
    final appState = context.read<AppState>();
    final newItems = appState.getPlaylistItemsWithClips(widget.playlist.id);

    // 检查是否有外部变化
    if (_originalItems.length != newItems.length ||
        !_originalItems.every(
          (item) => newItems.any((newItem) => newItem.item.id == item.item.id),
        )) {
      setState(() {
        _originalItems = newItems;
        // 如果不在编辑模式，同步编辑状态
        if (!_isEditing) {
          _editingItems = List.from(_originalItems);
          _hasChanges = false;
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 只在依赖项变化时检查外部变化，避免拖拽时被干扰
    if (_originalItems.isNotEmpty && !_hasChanges && mounted) {
      _refreshFromExternalChanges();
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final item = _editingItems.removeAt(oldIndex);
      _editingItems.insert(newIndex, item);
      _hasChanges = true;
    });
  }

  void _saveChanges() {
    final appState = context.read<AppState>();

    // 计算新的顺序并应用到 AppState
    for (int i = 0; i < _editingItems.length; i++) {
      final currentIndex = _originalItems.indexWhere(
        (item) => item.item.id == _editingItems[i].item.id,
      );
      if (currentIndex != i) {
        appState.reorderPlaylistItems(widget.playlist.id, currentIndex, i);
        break; // 一次只处理一个移动
      }
    }

    // 更新本地状态
    setState(() {
      _originalItems = List.from(_editingItems);
      _hasChanges = false;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('播放列表顺序已保存')));
  }

  void _resetChanges() {
    setState(() {
      _editingItems = List.from(_originalItems);
      _hasChanges = false;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已重置为原始状态')));
  }

  @override
  Widget build(BuildContext context) {
    // 监听 AppState 变化
    context.watch<AppState>();

    // 检查外部变化
    _refreshFromExternalChanges();

    return Scaffold(
      appBar: AppBar(
        title: Text('管理播放列表: ${widget.playlist.name}'),
        actions: [
          if (_hasChanges) ...[
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _resetChanges,
              tooltip: '重置',
            ),
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveChanges,
              tooltip: '保存',
            ),
          ],
          IconButton(
            icon: const Icon(Icons.play_arrow),
            onPressed: () {
              // 使用当前编辑状态创建播放列表副本
              final currentPlaylist = widget.playlist.copyWith(
                items: _editingItems
                    .map((itemWithClip) => itemWithClip.item)
                    .toList(),
              );

              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) =>
                      PlaylistPlaybackScreen(playlist: currentPlaylist),
                ),
              );
            },
            tooltip: '播放',
          ),
        ],
      ),
      body: _editingItems.isEmpty
          ? Center(
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
            )
          : Column(
              children: [
                _buildPlaylistInfo(),
                _buildTimelineView(),
                const SizedBox(height: 16),
                Expanded(child: _buildPlaylistItems()),
              ],
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
                      '${_editingItems.length} 个片段',
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

  Widget _buildTimelineView() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timeline, size: 16, color: Colors.blue.shade600),
              const SizedBox(width: 8),
              Text(
                '轨道视图',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue.shade600,
                ),
              ),
              const Spacer(),
              Text(
                '总时长: ${_formatDuration(widget.playlist.totalDuration)}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          PlaylistTimelineView(
            items: _editingItems,
            height: 80,
            showDuration: true,
            showNames: true,
            selectedIndex: _selectedItemIndex,
            onItemTap: (index) {
              setState(() {
                _selectedItemIndex = index;
              });
              // 滚动到对应的列表项
              _scrollToItem(index);
            },
          ),
        ],
      ),
    );
  }

  void _scrollToItem(int index) {
    // TODO: 实现滚动到指定列表项的功能
    // 这需要给 ReorderableListView 添加一个 GlobalKey
  }

  Widget _buildPlaylistItems() {
    if (_editingItems.isEmpty) {
      return const Center(child: Text('播放列表为空'));
    }

    return ReorderableListView.builder(
      itemCount: _editingItems.length,
      onReorder: _onReorder,
      itemBuilder: (context, index) {
        // 严格的安全检查
        if (index < 0 || index >= _editingItems.length) {
          return const SizedBox.shrink();
        }
        
        final itemWithClip = _editingItems[index];
        if (itemWithClip == null || 
            itemWithClip.item == null || 
            itemWithClip.clip == null ||
            itemWithClip.item.id.isEmpty) {
          return const SizedBox.shrink();
        }
        
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
              // 序号
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.blue.shade300),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
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
              // 从编辑状态中移除
              setState(() {
                _editingItems.removeWhere(
                  (item) => item.item.id == itemWithClip.item.id,
                );
                _hasChanges = true;
              });
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
