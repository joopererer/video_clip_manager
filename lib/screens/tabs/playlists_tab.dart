import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../services/preview_service.dart';
import '../../services/screenshot_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../utils/playlist_summary.dart';
import '../../utils/playlist_time.dart';
import '../../widgets/playlist_card_parts.dart';
import '../../widgets/playlist_cards.dart';
import '../../widgets/playlist_dialog.dart';
import '../../widgets/playlist_import_export_dialog.dart';
import '../player/playlist_playback_screen.dart';
import '../playlist/playlist_management_screen.dart';

class PlaylistsTab extends StatefulWidget {
  final String searchQuery;
  const PlaylistsTab({super.key, required this.searchQuery});

  @override
  State<PlaylistsTab> createState() => _PlaylistsTabState();
}

class _PlaylistsTabState extends State<PlaylistsTab> {
  static const _sortOptions = {
    'name': '按名称',
    'date': '按创建时间',
    'duration': '按时长',
  };

  // 以列表位置而非 id 作为选中键：历史数据中可能存在空 id 或重复 id
  int? _selectedIndex;
  bool _isImporting = false;
  bool _isExporting = false;

  AppColorExtension get _c => context.appColors;

  List<PlaylistCardData> _buildCards(AppState appState) {
    final clipsById = <String, VideoClip>{};
    for (final clip in appState.clips) {
      clipsById.putIfAbsent(clip.id, () => clip);
    }

    var playlists = List<Playlist>.of(appState.playlists);
    final query = widget.searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      playlists = playlists
          .where(
            (p) =>
                p.name.toLowerCase().contains(query) ||
                (p.description?.toLowerCase().contains(query) ?? false),
          )
          .toList();
    }

    final cards = [
      for (final p in playlists)
        PlaylistCardData(
          playlist: p,
          summary: summarizePlaylist(p, clipsById),
          entries: [
            for (final item in p.items)
              if (clipsById[item.clipId] != null)
                PlaylistItemWithClip(item: item, clip: clipsById[item.clipId]!),
          ],
        ),
    ];
    return sortPlaylistEntries<PlaylistCardData>(
      cards,
      appState.playlistsSortBy,
      playlistOf: (c) => c.playlist,
      durationOf: (c) => c.summary.duration,
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final cards = _buildCards(appState);
    final selected = _selectedIndex != null && _selectedIndex! < cards.length
        ? _selectedIndex
        : null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          _buildHeader(appState, cards),
          Expanded(
            child: cards.isEmpty
                ? _buildEmptyState(filtered: widget.searchQuery.isNotEmpty)
                : appState.playlistsIsGridView
                ? _buildGrid(appState, cards, selected)
                : _buildList(appState, cards, selected),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- header

  Widget _buildHeader(AppState appState, List<PlaylistCardData> cards) {
    final c = _c;
    var totalMs = 0;
    var totalClips = 0;
    for (final d in cards) {
      totalMs += d.summary.duration.inMilliseconds;
      totalClips += d.summary.availableCount;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.borderSubtle),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.xs,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _stat(Icons.playlist_play, '播放列表', '${cards.length}', c.primary),
              _stat(
                Icons.schedule,
                '总时长',
                formatPlaylistDuration(Duration(milliseconds: totalMs)),
                c.info,
              ),
              _stat(
                Icons.video_library_outlined,
                '总片段',
                '$totalClips',
                c.success,
              ),
            ],
          ),
          Wrap(
            spacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: () => _createPlaylist(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('创建播放列表'),
              ),
              Tooltip(
                message: '导入播放列表',
                child: OutlinedButton.icon(
                  onPressed: _isImporting
                      ? null
                      : () => _importPlaylist(context, appState),
                  icon: _isImporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_upload_outlined, size: 18),
                  label: const Text('导入'),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '排序方式：${_sortOptions[appState.playlistsSortBy] ?? ''}',
                icon: Icon(Icons.sort, color: c.textSecondary),
                color: c.surfaceElevated,
                onSelected: appState.setPlaylistsSortBy,
                itemBuilder: (_) => [
                  for (final e in _sortOptions.entries)
                    PopupMenuItem<String>(
                      value: e.key,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 20,
                            child: appState.playlistsSortBy == e.key
                                ? Icon(Icons.check, size: 16, color: c.primary)
                                : null,
                          ),
                          Text(e.value),
                        ],
                      ),
                    ),
                ],
              ),
              Tooltip(
                message: appState.playlistsIsGridView ? '切换为列表视图' : '切换为网格视图',
                child: IconButton(
                  onPressed: () => appState.setPlaylistsViewMode(
                    !appState.playlistsIsGridView,
                  ),
                  icon: Icon(
                    appState.playlistsIsGridView
                        ? Icons.view_list_outlined
                        : Icons.grid_view,
                    color: c.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          '$label  $value',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: _c.textSecondary,
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- views

  Widget _buildEmptyState({required bool filtered}) {
    final c = _c;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            filtered ? Icons.search_off : Icons.playlist_play,
            size: 56,
            color: c.textMuted,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            filtered ? '没有匹配的播放列表' : '暂无播放列表',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            filtered ? '换个关键词试试' : '创建第一个播放列表，把喜欢的片段串起来',
            style: TextStyle(fontSize: 13, color: c.textSecondary),
          ),
          if (!filtered) ...[
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: () => _createPlaylist(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('创建播放列表'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGrid(
    AppState appState,
    List<PlaylistCardData> cards,
    int? selected,
  ) {
    const padding = AppSpacing.md;
    return LayoutBuilder(
      builder: (context, constraints) {
        final m = playlistGridMetrics(constraints.maxWidth - padding * 2);
        return GridView.builder(
          padding: const EdgeInsets.all(padding),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: m.columns,
            crossAxisSpacing: AppSpacing.md,
            mainAxisSpacing: AppSpacing.md,
            childAspectRatio: m.aspectRatio,
          ),
          itemCount: cards.length,
          itemBuilder: (context, i) => PlaylistGridCard(
            data: cards[i],
            selected: selected == i,
            onSelect: () => setState(() => _selectedIndex = i),
            onAction: (a) => _handleAction(appState, cards[i], a),
          ),
        );
      },
    );
  }

  Widget _buildList(
    AppState appState,
    List<PlaylistCardData> cards,
    int? selected,
  ) {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: cards.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
      itemBuilder: (context, i) => PlaylistListRow(
        data: cards[i],
        selected: selected == i,
        onSelect: () => setState(() => _selectedIndex = i),
        onAction: (a) => _handleAction(appState, cards[i], a),
      ),
    );
  }

  // --------------------------------------------------------------- actions

  void _handleAction(
    AppState appState,
    PlaylistCardData data,
    PlaylistAction action,
  ) {
    final playlist = data.playlist;
    switch (action) {
      case PlaylistAction.play:
        _playPlaylist(context, appState, data);
      case PlaylistAction.edit:
        _editPlaylist(context, appState, playlist);
      case PlaylistAction.manage:
        _managePlaylist(context, playlist);
      case PlaylistAction.export:
        _exportPlaylist(context, playlist);
      case PlaylistAction.delete:
        _deletePlaylist(context, appState, playlist);
    }
  }

  Future<void> _createPlaylist(BuildContext context) async {
    final appState = context.read<AppState>();
    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (context) => const PlaylistDialog(),
    );
    if (result != null) {
      appState.createPlaylist(
        result['name']!,
        description: result['description'],
      );
    }
  }

  Future<void> _playPlaylist(
    BuildContext context,
    AppState appState,
    PlaylistCardData data,
  ) async {
    if (data.entries.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('播放列表中没有可播放的片段')));
      return;
    }
    // 与原有流程一致：先暂停预生成并让截图服务空闲，再进入播放页。
    PreviewService().pauseGlobalPreGeneration();
    await ScreenshotService().prepareForPlayback();
    if (!context.mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PlaylistPlaybackScreen(playlist: data.playlist),
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

  void _managePlaylist(BuildContext context, Playlist playlist) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PlaylistManagementScreen(playlist: playlist),
      ),
    );
  }

  Future<void> _importPlaylist(BuildContext context, AppState appState) async {
    setState(() => _isImporting = true);
    try {
      // 导入结果在预览对话框内处理并提示。
      await showDialog<bool>(
        context: context,
        builder: (context) => const PlaylistImportExportDialog(),
      );
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _exportPlaylist(BuildContext context, Playlist playlist) async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      await showDialog<bool>(
        context: context,
        builder: (context) => PlaylistImportExportDialog(playlist: playlist),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _deletePlaylist(
    BuildContext context,
    AppState appState,
    Playlist playlist,
  ) async {
    final c = _c;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: c.surfaceElevated,
        title: Text('确认删除', style: TextStyle(color: c.textPrimary)),
        content: Text(
          '确定要删除播放列表 "${playlist.name}" 吗？其中的片段不会被删除，但播放列表本身无法恢复。',
          style: TextStyle(color: c.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: c.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      appState.deletePlaylist(playlist.id);
      if (mounted) setState(() => _selectedIndex = null);
    }
  }
}
