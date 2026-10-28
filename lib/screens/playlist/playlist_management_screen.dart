import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../utils/playlist_draft.dart';
import '../../utils/playlist_time.dart';
import '../../widgets/clip_thumbnail.dart';
import '../../widgets/playlist_timeline_view.dart';
import '../player/playlist_playback_screen.dart';

enum _LeaveChoice { keepEditing, discard, save }

class PlaylistManagementScreen extends StatefulWidget {
  final Playlist playlist;

  const PlaylistManagementScreen({super.key, required this.playlist});

  @override
  State<PlaylistManagementScreen> createState() =>
      _PlaylistManagementScreenState();
}

class _PlaylistManagementScreenState extends State<PlaylistManagementScreen> {
  static const double _rowExtent = 72;

  // 事务草稿：所有编辑只发生在内存中，Save 时一次性提交完整列表。
  PlaylistDraft? _draft;
  int? _selectedIndex;
  final ScrollController _scroll = ScrollController();

  AppColorExtension get _c => context.appColors;
  List<PlaylistItemWithClip> get _editingItems => _draft?.items ?? const [];
  bool get _hasChanges => _draft?.isDirty ?? false;
  Duration get _total => _draft?.totalDuration ?? Duration.zero;

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

  String _ms(Duration d) => formatPlaylistDuration(d, millis: true);

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
      _selectedIndex = null;
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      _draft?.reorder(oldIndex, newIndex);
      _selectedIndex = null;
    });
  }

  /// Commits the whole draft in one call. Returns false if nothing was saved.
  bool _saveChanges() {
    final draft = _draft;
    if (draft == null || !draft.isDirty) return false;
    final appState = context.read<AppState>();
    final stored = _storedPlaylist(appState);
    if (stored == null) return false;

    // 保存前确认外部没有改动列表，否则会覆盖其他入口添加/删除的片段。
    if (draft.isStale(stored.items)) {
      _toast('播放列表已在别处被修改，请重置后再编辑');
      return false;
    }

    // 一次性提交完整顺序。name / description / createdAt 不传，保持不变。
    appState.updatePlaylist(widget.playlist.id, items: draft.commit());
    setState(() {
      _draft = _newDraftFromStore(appState);
      _selectedIndex = null;
    });
    _toast('播放列表已保存');
    return true;
  }

  void _resetChanges() {
    setState(() {
      _draft?.reset();
      _selectedIndex = null;
    });
    _toast('已重置为原始状态');
  }

  Future<_LeaveChoice> _askLeave() async {
    final c = _c;
    final choice = await showDialog<_LeaveChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surfaceElevated,
        title: Text('有未保存的更改', style: TextStyle(color: c.textPrimary)),
        content: Text(
          '播放列表的顺序或片段已修改但尚未保存。离开前要保存吗？',
          style: TextStyle(color: c.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_LeaveChoice.keepEditing),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_LeaveChoice.discard),
            style: TextButton.styleFrom(foregroundColor: c.danger),
            child: const Text('放弃更改'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(_LeaveChoice.save),
            child: const Text('保存并离开'),
          ),
        ],
      ),
    );
    return choice ?? _LeaveChoice.keepEditing;
  }

  /// Back button, system back and the Cancel button all end up here.
  Future<void> _handleLeave() async {
    if (!_hasChanges) {
      Navigator.of(context).pop();
      return;
    }
    final choice = await _askLeave();
    if (!mounted) return;
    switch (choice) {
      case _LeaveChoice.keepEditing:
        return;
      case _LeaveChoice.discard:
        // 放弃：不写入 AppState。
        Navigator.of(context).pop();
      case _LeaveChoice.save:
        if (_saveChanges()) Navigator.of(context).pop();
    }
  }

  /// Plays the current draft order without saving it.
  void _playDraft() {
    final preview = widget.playlist.copyWith(
      items: _editingItems.map((e) => e.item).toList(),
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PlaylistPlaybackScreen(playlist: preview),
      ),
    );
  }

  void _selectAndReveal(int index) {
    setState(() => _selectedIndex = index);
    if (!_scroll.hasClients) return;
    final top = index * _rowExtent;
    final pos = _scroll.position;
    final viewTop = pos.pixels;
    final viewBottom = viewTop + pos.viewportDimension;
    if (top < viewTop) {
      _scroll.animateTo(
        top.clamp(0.0, pos.maxScrollExtent),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    } else if (top + _rowExtent > viewBottom) {
      _scroll.animateTo(
        (top + _rowExtent - pos.viewportDimension).clamp(
          0.0,
          pos.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _confirmRemove(int index) async {
    final c = _c;
    final entry = _editingItems[index];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surfaceElevated,
        title: Text('从播放列表移除', style: TextStyle(color: c.textPrimary)),
        content: Text(
          '把 "${entry.clip.name}" 从草稿中移除？片段本身不会被删除，保存后才会生效。',
          style: TextStyle(color: c.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: c.danger),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    // 按行位置移除，避免旧数据中重复/空 id 误删多项
    setState(() {
      _draft?.removeAt(index);
      _selectedIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final dirty = _hasChanges;
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleLeave();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
            if (_hasChanges) _saveChanges();
          },
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: c.background,
            body: Column(
              children: [
                _buildToolbar(c, dirty),
                Expanded(
                  child: _editingItems.isEmpty && !dirty
                      ? _buildEmpty(c)
                      : Column(
                          children: [
                            _buildSummary(c),
                            _buildTimeline(c),
                            Expanded(child: _buildQueue(c)),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(AppColorExtension c, bool dirty) {
    return Container(
      height: AppSpacing.topToolbarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: c.sidebar,
        border: Border(bottom: BorderSide(color: c.borderSubtle)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回',
            icon: const Icon(Icons.arrow_back),
            onPressed: _handleLeave,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.playlist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  dirty ? '有未保存的更改' : '管理播放列表',
                  style: TextStyle(
                    color: dirty ? c.warning : c.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Tooltip(
            message: '播放当前草稿顺序（无需保存）',
            child: OutlinedButton.icon(
              onPressed: _editingItems.isEmpty ? null : _playDraft,
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text('预览播放'),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Tooltip(
            message: '放弃所有未保存的更改',
            child: TextButton(
              onPressed: dirty ? _resetChanges : null,
              child: const Text('重置'),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          TextButton(onPressed: _handleLeave, child: const Text('取消')),
          const SizedBox(width: AppSpacing.xs),
          Tooltip(
            message: '保存 (Ctrl+S)',
            child: FilledButton.icon(
              onPressed: dirty ? _saveChanges : null,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('保存'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(AppColorExtension c) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.playlist_play, size: 56, color: c.textMuted),
          const SizedBox(height: AppSpacing.md),
          Text('播放列表为空', style: TextStyle(color: c.textPrimary, fontSize: 16)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '在片段库中把片段加入这个播放列表',
            style: TextStyle(color: c.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(AppColorExtension c) {
    final desc = widget.playlist.description;
    final hidden = _draft?.orphanCount ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: desc == null || desc.isEmpty
                ? const SizedBox.shrink()
                : Text(
                    desc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.textSecondary, fontSize: 13),
                  ),
          ),
          _chip(c, Icons.video_library_outlined, '${_editingItems.length} 个片段'),
          const SizedBox(width: AppSpacing.xs),
          Tooltip(
            message: '各片段有效时长之和：${_ms(_total)}',
            child: _chip(c, Icons.schedule, '总时长 ${_ms(_total)}'),
          ),
          if (hidden > 0) ...[
            const SizedBox(width: AppSpacing.xs),
            Tooltip(
              message: '$hidden 项引用的片段已不存在，不会显示，保存时会原样保留',
              child: _chip(c, Icons.link_off, '$hidden 项不可用', warn: true),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(
    AppColorExtension c,
    IconData icon,
    String text, {
    bool warn = false,
  }) {
    final color = warn ? c.warning : c.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.round),
        border: Border.all(color: c.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildTimeline(AppColorExtension c) {
    if (_editingItems.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: PlaylistTimelineView(
        items: _editingItems,
        height: 72,
        showDuration: true,
        showNames: true,
        showScale: true,
        selectedIndex: _selectedIndex,
        onItemTap: _selectAndReveal,
        enableReorder: true,
        onReorder: (from, finalIndex) => setState(() {
          _draft?.moveTo(from, finalIndex);
          _selectedIndex = null;
        }),
      ),
    );
  }

  Widget _buildQueue(AppColorExtension c) {
    if (_editingItems.isEmpty) {
      return Center(
        child: Text(
          '草稿中没有片段，可以点击“重置”恢复',
          style: TextStyle(color: c.textSecondary),
        ),
      );
    }
    return ReorderableListView.builder(
      scrollController: _scroll,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.md,
      ),
      buildDefaultDragHandles: false,
      itemExtent: _rowExtent,
      itemCount: _editingItems.length,
      onReorder: _onReorder,
      proxyDecorator: (child, index, animation) => Material(
        color: Colors.transparent,
        elevation: 4,
        shadowColor: Colors.black54,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: child,
      ),
      itemBuilder: (context, index) => _buildRow(c, index),
    );
  }

  Widget _buildRow(AppColorExtension c, int index) {
    final entry = _editingItems[index];
    final item = entry.item;
    final clip = entry.clip;
    final selected = _selectedIndex == index;
    final customized =
        item.customStartTime != null || item.customEndTime != null;
    // Identity key: ids may be empty or duplicated in legacy data, and each
    // draft entry is a distinct object that survives reordering.
    return Padding(
      key: ObjectKey(entry),
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: selected ? c.primaryContainer : c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          hoverColor: c.surfaceHighlight,
          onTap: () => setState(() => _selectedIndex = index),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: selected ? c.primary : c.borderSubtle),
            ),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Tooltip(
                      message: '拖动调整顺序',
                      child: Icon(
                        Icons.drag_indicator,
                        color: c.textMuted,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                SizedBox(
                  width: 28,
                  child: Text(
                    '${index + 1}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: SizedBox(
                    width: 72,
                    height: 40.5,
                    child: ColoredBox(
                      color: Colors.black,
                      child: ClipThumbnail(clip: clip, fit: BoxFit.contain),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        clip.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        customized
                            ? '播放列表范围 ${_ms(item.customStartTime ?? clip.startTime)} – ${_ms(item.customEndTime ?? clip.endTime)}'
                            : '片段范围 ${_ms(clip.startTime)} – ${_ms(clip.endTime)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: customized ? c.warning : c.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  _ms(entry.effectiveDuration),
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                IconButton(
                  tooltip: '从草稿移除',
                  icon: Icon(
                    Icons.remove_circle_outline,
                    size: 18,
                    color: c.danger,
                  ),
                  onPressed: () => _confirmRemove(index),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
