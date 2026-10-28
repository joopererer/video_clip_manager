import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../utils/playlist_draft.dart';
import '../../utils/playlist_time.dart';
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
  // 事务草稿：所有编辑只发生在内存中，Save 时一次性提交完整列表。
  PlaylistDraft? _draft;

  int? _selectedItemIndex;

  // 草稿尚未加载前使用的空视图
  List<PlaylistItemWithClip> get _editingItems => _draft?.items ?? const [];

  // 是否有未保存的更改
  bool get _hasChanges => _draft?.isDirty ?? false;

  // 草稿的总时长（毫秒精度的有效时长之和）
  Duration get _currentEditingTotalDuration =>
      _draft?.totalDuration ?? Duration.zero;

  Playlist? _storedPlaylist(AppState appState) {
    for (final p in appState.playlists) {
      if (p.id == widget.playlist.id) return p;
    }
    return null;
  }

  PlaylistDraft _newDraftFromStore(AppState appState) {
    final stored = _storedPlaylist(appState) ?? widget.playlist;
    return PlaylistDraft.from(items: stored.items, clips: appState.clips);
  }

  @override
  void initState() {
    super.initState();
    _draft = _newDraftFromStore(context.read<AppState>());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 没有未保存编辑时，跟随 AppState 的外部变化；有编辑时保持草稿不被覆盖。
    final appState = context.watch<AppState>();
    final draft = _draft;
    if (draft == null || draft.isDirty) return;
    final stored = _storedPlaylist(appState);
    if (stored != null && draft.isStale(stored.items)) {
      _draft = _newDraftFromStore(appState);
    }
  }

  String _formatDuration(Duration duration) => formatPlaylistDuration(duration);

  void _onReorder(int oldIndex, int newIndex) {
    setState(() => _draft?.reorder(oldIndex, newIndex));
  }

  void _saveChanges() {
    final draft = _draft;
    if (draft == null) return;
    final appState = context.read<AppState>();
    final stored = _storedPlaylist(appState);
    if (stored == null) return;

    // 保存前确认外部没有改动列表，否则会覆盖其他入口添加/删除的片段。
    if (draft.isStale(stored.items)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('播放列表已在别处被修改，请重置后再编辑')));
      return;
    }

    // 一次性提交完整顺序。name / description / createdAt 不传，保持不变。
    appState.updatePlaylist(widget.playlist.id, items: draft.commit());

    // 以已保存的数据重新建立草稿基线（重置将回到刚保存的状态）
    setState(() => _draft = _newDraftFromStore(appState));

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('播放列表顺序已保存')));
  }

  void _resetChanges() {
    setState(() => _draft?.reset());

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已重置为原始状态')));
  }

  @override
  Widget build(BuildContext context) {
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
                      '总时长: ${_formatDuration(_currentEditingTotalDuration)}',
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
                '总时长: ${_formatDuration(_currentEditingTotalDuration)}',
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
        if (itemWithClip.item.id.isEmpty) {
          return const SizedBox.shrink();
        }

        return _buildPlaylistItem(itemWithClip, index);
      },
    );
  }

  Widget _buildPlaylistItem(PlaylistItemWithClip itemWithClip, int index) {
    // 严格的安全检查
    if (itemWithClip.item.id.isEmpty) {
      return const SizedBox.shrink();
    }

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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      clip.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 13, // 稍微减小字体
                      ),
                    ),
                    const SizedBox(height: 1), // 进一步减少间距
                    Text(
                      '时长: ${_formatDuration(itemWithClip.effectiveDuration)}',
                      style: TextStyle(
                        fontSize: 11, // 减小字体
                        color: Colors.grey.shade600,
                      ),
                    ),
                    if (item.customStartTime != null ||
                        item.customEndTime != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        '自定义: ${item.customStartTime != null ? _formatDuration(item.customStartTime!) : "0:00"}-${item.customEndTime != null ? _formatDuration(item.customEndTime!) : _formatDuration(clip.endTime - clip.startTime)}',
                        style: TextStyle(
                          fontSize: 10, // 进一步减小字体
                          color: Colors.orange.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.remove_circle_outline,
                  size: 18, // 稍微减小图标
                  color: Colors.red,
                ),
                onPressed: () => _removeClipFromPlaylist(itemWithClip, index),
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ), // 减小按钮约束
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _removeClipFromPlaylist(PlaylistItemWithClip itemWithClip, int index) {
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
              // 按行位置移除，避免旧数据中重复/空 id 误删多项
              setState(() => _draft?.removeAt(index));
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
