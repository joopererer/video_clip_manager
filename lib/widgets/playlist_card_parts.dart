import 'dart:async';

import 'package:flutter/material.dart';
import '../data/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/playlist_summary.dart';

enum PlaylistAction { play, edit, manage, export, delete }

/// Everything a playlist card needs, resolved once by the tab.
class PlaylistCardData {
  const PlaylistCardData({
    required this.playlist,
    required this.summary,
    required this.entries,
  });

  final Playlist playlist;
  final PlaylistSummary summary;

  /// Playable entries (clip still exists), in playlist order.
  final List<PlaylistItemWithClip> entries;
}

const _menuSpec = <PlaylistAction, (IconData, String)>{
  PlaylistAction.play: (Icons.play_arrow, '播放'),
  PlaylistAction.edit: (Icons.edit_outlined, '重命名 / 编辑信息'),
  PlaylistAction.manage: (Icons.low_priority, '管理片段与顺序'),
  PlaylistAction.export: (Icons.file_download_outlined, '导出'),
  PlaylistAction.delete: (Icons.delete_outline, '删除播放列表'),
};

List<PopupMenuEntry<PlaylistAction>> playlistMenuItems(AppColorExtension c) {
  PopupMenuItem<PlaylistAction> item(PlaylistAction a) {
    final (icon, label) = _menuSpec[a]!;
    final color = a == PlaylistAction.delete ? c.danger : c.textPrimary;
    return PopupMenuItem<PlaylistAction>(
      value: a,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(label, style: TextStyle(color: color)),
        ],
      ),
    );
  }

  return [
    item(PlaylistAction.play),
    item(PlaylistAction.edit),
    item(PlaylistAction.manage),
    item(PlaylistAction.export),
    const PopupMenuDivider(),
    item(PlaylistAction.delete),
  ];
}

Future<PlaylistAction?> showPlaylistContextMenu(
  BuildContext context,
  Offset globalPosition,
) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  return showMenu<PlaylistAction>(
    context: context,
    position: RelativeRect.fromRect(
      globalPosition & const Size(40, 40),
      Offset.zero & overlay.size,
    ),
    items: playlistMenuItems(context.appColors),
  );
}

/// The "more" button; offers the same entries as the context menu.
class PlaylistMenuButton extends StatelessWidget {
  const PlaylistMenuButton({super.key, required this.onSelected});

  final ValueChanged<PlaylistAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    // Fixed 32px box: the default button pads itself to a 48px tap target,
    // which does not fit in the grid card footer.
    return SizedBox(
      width: 32,
      height: 32,
      child: PopupMenuButton<PlaylistAction>(
        tooltip: '更多操作',
        padding: EdgeInsets.zero,
        icon: Icon(Icons.more_vert, size: 20, color: c.textSecondary),
        color: c.surfaceElevated,
        onSelected: onSelected,
        itemBuilder: (_) => playlistMenuItems(c),
      ),
    );
  }
}

/// Recognises a second tap on the same card within [window]. Selection stays
/// instant, unlike `onDoubleTap`, which delays the first tap.
class DoubleTapTracker {
  DoubleTapTracker({this.window = const Duration(milliseconds: 350)});

  final Duration window;
  Timer? _timer;

  /// Registers a tap; returns true when it completes a double tap.
  bool registerTap() {
    if (_timer?.isActive ?? false) {
      _timer!.cancel();
      _timer = null;
      return true;
    }
    _timer = Timer(window, () {});
    return false;
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

/// Shared look and interaction of playlist cards: hover, focus, selection,
/// single click selects, double click plays, right click opens the menu.
class PlaylistCardFrame extends StatefulWidget {
  const PlaylistCardFrame({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onPlay,
    required this.onAction,
    required this.builder,
  });

  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onPlay;
  final ValueChanged<PlaylistAction> onAction;
  final Widget Function(BuildContext context, bool active) builder;

  @override
  State<PlaylistCardFrame> createState() => _PlaylistCardFrameState();
}

class _PlaylistCardFrameState extends State<PlaylistCardFrame> {
  final _taps = DoubleTapTracker();
  bool _hovered = false;
  bool _focused = false;

  @override
  void dispose() {
    _taps.dispose();
    super.dispose();
  }

  Future<void> _openMenu(Offset position) async {
    widget.onSelect();
    final action = await showPlaylistContextMenu(context, position);
    if (action != null && mounted) widget.onAction(action);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final active = _hovered || _focused;
    return Focus(
      canRequestFocus: false,
      onFocusChange: (f) => setState(() => _focused = f),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          hoverColor: Colors.transparent,
          onTap: () {
            widget.onSelect();
            if (_taps.registerTap()) widget.onPlay();
          },
          onSecondaryTapDown: (d) => _openMenu(d.globalPosition),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: widget.selected ? c.surfaceElevated : c.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: widget.selected
                    ? c.primary
                    : (active
                          ? c.primaryHover.withValues(alpha: 0.6)
                          : c.border),
                width: widget.selected ? 1.6 : 1,
              ),
            ),
            child: widget.builder(context, active),
          ),
        ),
      ),
    );
  }
}
