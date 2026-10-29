import 'dart:io';

import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../data/models.dart';
import '../../services/thumbnail_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../utils/tag_utils.dart';
import '../../utils/timecode.dart';

/// Clips already saved for the source video being edited.
///
/// The selected clip is the one currently loaded in the form. Selecting,
/// previewing and deleting are reported to the owner; deletion confirmation
/// stays in the editor screen.
class ClipListPanel extends StatelessWidget {
  const ClipListPanel({
    super.key,
    required this.clips,
    required this.dbPath,
    required this.thumbnailService,
    required this.selectedId,
    required this.listStamp,
    required this.scrollController,
    required this.onSelect,
    required this.onPlay,
    required this.onDelete,
  });

  final List<VideoClip> clips;
  final String? dbPath;
  final ThumbnailService thumbnailService;
  final String? selectedId;
  final int listStamp;
  final ItemScrollController scrollController;
  final ValueChanged<VideoClip> onSelect;
  final ValueChanged<VideoClip> onPlay;
  final ValueChanged<VideoClip> onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (clips.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.movie_filter_outlined,
                size: 36,
                color: colors.textMuted,
              ),
              const SizedBox(height: 12),
              Text('No clips yet', style: AppTypography.subtitle),
              const SizedBox(height: 4),
              Text(
                'Set IN and OUT on the timeline, then save to create one.',
                textAlign: TextAlign.center,
                style: AppTypography.bodySecondary,
              ),
            ],
          ),
        ),
      );
    }
    return ScrollablePositionedList.builder(
      padding: const EdgeInsets.all(12),
      itemCount: clips.length,
      itemScrollController: scrollController,
      itemBuilder: (context, index) {
        final clip = clips[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _ClipRow(
            clip: clip,
            selected: clip.id == selectedId,
            thumbnailPath: _thumbnailPath(clip),
            listStamp: listStamp,
            onSelect: () => onSelect(clip),
            onPlay: () => onPlay(clip),
            onDelete: () => onDelete(clip),
          ),
        );
      },
    );
  }

  String? _thumbnailPath(VideoClip clip) {
    final name = clip.thumbnailPath;
    if (name == null || dbPath == null) return null;
    return thumbnailService.buildThumbnailPath(dbPath!, name);
  }
}

class _ClipRow extends StatelessWidget {
  const _ClipRow({
    required this.clip,
    required this.selected,
    required this.thumbnailPath,
    required this.listStamp,
    required this.onSelect,
    required this.onPlay,
    required this.onDelete,
  });

  final VideoClip clip;
  final bool selected;
  final String? thumbnailPath;
  final int listStamp;
  final VoidCallback onSelect;
  final VoidCallback onPlay;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final length = clip.endTime > clip.startTime
        ? clip.endTime - clip.startTime
        : Duration.zero;
    return Semantics(
      selected: selected,
      button: true,
      label: 'Clip ${clip.name}, ${formatTimecode(length)}',
      child: Material(
        color: selected
            ? Color.alphaBlend(
                colors.primary.withValues(alpha: 0.18),
                colors.surface,
              )
            : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? colors.primary : colors.borderSubtle,
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onSelect,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Thumb(path: thumbnailPath, stamp: listStamp),
                const SizedBox(width: 10),
                Expanded(child: _info(context, colors, length)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _info(
    BuildContext context,
    AppColorExtension colors,
    Duration length,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                clip.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.subtitle.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
            if (clip.isFavorite)
              Icon(Icons.favorite, size: 14, color: colors.favoriteActive),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '${formatTimecode(clip.startTime)} – ${formatTimecode(clip.endTime)}',
          style: AppTypography.timecode(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: colors.textSecondary,
          ),
        ),
        Text(
          'Length ${formatTimecode(length)}',
          style: AppTypography.timecode(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: colors.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 4,
                runSpacing: 2,
                children: [
                  for (final tag in clip.tags.take(2)) _TagDot(tag: tag),
                  if (clip.tags.length > 2)
                    Text(
                      '+${clip.tags.length - 2}',
                      style: AppTypography.caption,
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.play_circle_outline, size: 20),
              tooltip: 'Preview this clip',
              visualDensity: VisualDensity.compact,
              color: colors.success,
              onPressed: onPlay,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: 'Delete this clip',
              visualDensity: VisualDensity.compact,
              color: colors.danger,
              onPressed: onDelete,
            ),
          ],
        ),
      ],
    );
  }
}

class _TagDot extends StatelessWidget {
  const _TagDot({required this.tag});

  final String tag;

  @override
  Widget build(BuildContext context) {
    final color = generateTagColor(tag);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(tag, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.path, required this.stamp});

  final String? path;
  final int stamp;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 112,
        height: 63,
        color: Colors.black,
        alignment: Alignment.center,
        child: path == null
            ? Icon(Icons.movie_creation_outlined, color: colors.textMuted)
            : Image.file(
                File(path!),
                key: ValueKey('${path}_$stamp'),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    Icon(Icons.broken_image_outlined, color: colors.danger),
              ),
      ),
    );
  }
}
