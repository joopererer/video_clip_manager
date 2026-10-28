import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/playlist_time.dart';
import 'clip_media_preview.dart';
import 'common/timecode_chip.dart';
import 'playlist_card_parts.dart';
import 'playlist_timeline_view.dart';

String _date(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 16:9 cover built from the first playable clip. No player is created.
class _Cover extends StatelessWidget {
  const _Cover({required this.data});
  final PlaylistCardData data;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    if (data.entries.isEmpty) {
      return ColoredBox(
        color: c.background,
        child: Center(
          child: Icon(Icons.playlist_play, size: 40, color: c.textMuted),
        ),
      );
    }
    return ClipMediaPreview(clip: data.entries.first.clip);
  }
}

class _MissingChip extends StatelessWidget {
  const _MissingChip({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Tooltip(
      message: '$count 项引用的片段已不存在，播放时会被跳过',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.link_off, size: 13, color: c.warning),
          const SizedBox(width: 3),
          Text('$count 缺失', style: TextStyle(fontSize: 11, color: c.warning)),
        ],
      ),
    );
  }
}

/// Compact card for the grid view.
class PlaylistGridCard extends StatelessWidget {
  const PlaylistGridCard({
    super.key,
    required this.data,
    required this.selected,
    required this.onSelect,
    required this.onAction,
  });

  final PlaylistCardData data;
  final bool selected;
  final VoidCallback onSelect;
  final ValueChanged<PlaylistAction> onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final p = data.playlist;
    final s = data.summary;
    final canPlay = data.entries.isNotEmpty;
    return PlaylistCardFrame(
      selected: selected,
      onSelect: onSelect,
      onPlay: () {
        if (canPlay) onAction(PlaylistAction.play);
      },
      onAction: onAction,
      builder: (context, active) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _Cover(data: data),
                Positioned(
                  right: AppSpacing.xs,
                  bottom: AppSpacing.xs,
                  child: TimecodeChip(
                    duration: s.duration,
                    backgroundColor: Colors.black.withValues(alpha: 0.78),
                    borderColor: Colors.white24,
                    timeColor: Colors.white,
                  ),
                ),
                if (canPlay)
                  Center(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 120),
                      opacity: active ? 1 : 0,
                      child: Tooltip(
                        message: '播放',
                        child: Material(
                          color: c.primary,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: active
                                ? () => onAction(PlaylistAction.play)
                                : null,
                            child: const Padding(
                              padding: EdgeInsets.all(10),
                              child: Icon(
                                Icons.play_arrow,
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.xxs,
              0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                PlaylistMenuButton(onSelected: onAction),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Wrap(
              spacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${s.availableCount} 个片段',
                  style: TextStyle(color: c.textSecondary, fontSize: 12),
                ),
                Text(
                  _date(p.createdAt),
                  style: TextStyle(color: c.textMuted, fontSize: 12),
                ),
                if (s.missingCount > 0) _MissingChip(count: s.missingCount),
              ],
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              0,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: PlaylistTimelineView(
              items: data.entries,
              height: 10,
              showNames: false,
              showDuration: false,
              minSegmentWidth: 4,
              // Tapping a segment selects the card; the card handles it.
              onItemTap: (_) => onSelect(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wide row for the list view.
class PlaylistListRow extends StatelessWidget {
  const PlaylistListRow({
    super.key,
    required this.data,
    required this.selected,
    required this.onSelect,
    required this.onAction,
  });

  final PlaylistCardData data;
  final bool selected;
  final VoidCallback onSelect;
  final ValueChanged<PlaylistAction> onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final p = data.playlist;
    final s = data.summary;
    final canPlay = data.entries.isNotEmpty;
    final desc = p.description;
    return PlaylistCardFrame(
      selected: selected,
      onSelect: onSelect,
      onPlay: () {
        if (canPlay) onAction(PlaylistAction.play);
      },
      onAction: onAction,
      builder: (context, active) => Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            SizedBox(
              width: 144,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _Cover(data: data),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (desc != null && desc.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        desc,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.textSecondary, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _Stat(
                        Icons.video_library_outlined,
                        '${s.availableCount} 个片段',
                      ),
                      _Stat(
                        Icons.schedule,
                        formatPlaylistDuration(s.duration, millis: true),
                      ),
                      _Stat(Icons.calendar_today_outlined, _date(p.createdAt)),
                      if (s.missingCount > 0)
                        _MissingChip(count: s.missingCount),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  PlaylistTimelineView(
                    items: data.entries,
                    height: 18,
                    showNames: false,
                    showDuration: false,
                    minSegmentWidth: 4,
                    onItemTap: (_) => onSelect(),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Tooltip(
              message: canPlay ? '播放' : '播放列表为空',
              child: IconButton.filled(
                onPressed: canPlay ? () => onAction(PlaylistAction.play) : null,
                icon: const Icon(Icons.play_arrow),
              ),
            ),
            Tooltip(
              message: '管理片段与顺序',
              child: IconButton(
                onPressed: () => onAction(PlaylistAction.manage),
                icon: Icon(Icons.low_priority, color: c.textSecondary),
              ),
            ),
            PlaylistMenuButton(onSelected: onAction),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: c.textMuted),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: c.textSecondary, fontSize: 12)),
      ],
    );
  }
}
