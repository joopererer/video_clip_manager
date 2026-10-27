import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../utils/timecode.dart';

/// Right-hand properties panel of the clip editor: name, tags, notes (with AI
/// captioning), rating / favorite and cover.
///
/// Stateless on purpose: the editor screen owns the form state and the text
/// controllers, so the panel can be moved between the side column and the
/// narrow-window drawer without losing edits.
class ClipPropertiesPanel extends StatelessWidget {
  const ClipPropertiesPanel({
    super.key,
    required this.clip,
    required this.allTags,
    required this.nameController,
    required this.notesController,
    required this.tagController,
    required this.tagFocusNode,
    required this.onChanged,
    required this.isGeneratingAi,
    required this.onGenerateAi,
    required this.onOpenAiSettings,
    required this.coverPreviewPath,
    required this.coverPreviewStamp,
    required this.isSettingCover,
    required this.onSetCover,
    required this.onResetCover,
  });

  final VideoClip clip;
  final List<String> allTags;
  final TextEditingController nameController;
  final TextEditingController notesController;
  final TextEditingController tagController;
  final FocusNode tagFocusNode;
  final ValueChanged<VideoClip> onChanged;
  final bool isGeneratingAi;
  final VoidCallback onGenerateAi;
  final VoidCallback onOpenAiSettings;
  final String? coverPreviewPath;
  final int coverPreviewStamp;
  final bool isSettingCover;
  final VoidCallback onSetCover;
  final VoidCallback onResetCover;

  void _addTag(String raw) {
    final tag = raw.trim();
    if (tag.isEmpty || clip.tags.contains(tag)) return;
    onChanged(clip.copyWith(tags: [...clip.tags, tag]));
  }

  void _removeTag(String tag) {
    onChanged(clip.copyWith(tags: clip.tags.where((t) => t != tag).toList()));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Section(
          title: 'Details',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Clip name',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              _buildTags(context),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Section(
          title: 'Notes',
          trailing: _buildAiActions(context),
          child: TextField(
            controller: notesController,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: 'Notes, scene description…',
              isDense: true,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _Section(title: 'Rating', child: _buildRating(context)),
        const SizedBox(height: 12),
        _Section(title: 'Cover', child: _buildCover(context)),
      ],
    );
  }

  Widget _buildTags(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (clip.tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in clip.tags)
                  InputChip(
                    label: Text(tag),
                    visualDensity: VisualDensity.compact,
                    onDeleted: () => _removeTag(tag),
                    deleteButtonTooltipMessage: 'Remove tag "$tag"',
                  ),
              ],
            ),
          ),
        RawAutocomplete<String>(
          textEditingController: tagController,
          focusNode: tagFocusNode,
          optionsBuilder: (value) {
            final query = value.text.toLowerCase();
            return allTags.where(
              (tag) =>
                  !clip.tags.contains(tag) &&
                  (query.isEmpty || tag.toLowerCase().contains(query)),
            );
          },
          onSelected: (selection) {
            _addTag(selection);
            tagController.clear();
            tagFocusNode.requestFocus();
          },
          fieldViewBuilder: (context, controller, focusNode, _) => TextField(
            controller: controller,
            focusNode: focusNode,
            decoration: const InputDecoration(
              labelText: 'Add a tag',
              hintText: 'Type and press Enter',
              isDense: true,
            ),
            onSubmitted: (value) {
              _addTag(value);
              controller.clear();
              focusNode.requestFocus();
            },
          ),
          optionsViewBuilder: (context, onSelected, options) => Align(
            alignment: Alignment.topLeft,
            child: Material(
              color: colors.surfaceElevated,
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 200,
                  maxWidth: 300,
                ),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final option = options.elementAt(index);
                    return ListTile(
                      dense: true,
                      title: Text(option),
                      onTap: () => onSelected(option),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAiActions(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.tune, size: 18),
          tooltip: 'Configure the VLM engine',
          visualDensity: VisualDensity.compact,
          onPressed: onOpenAiSettings,
        ),
        if (isGeneratingAi)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          TextButton.icon(
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: const Text('AI describe'),
            onPressed: onGenerateAi,
          ),
      ],
    );
  }

  Widget _buildRating(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: [
        for (var i = 0; i < 5; i++)
          IconButton(
            icon: Icon(
              i < clip.rating ? Icons.star_rounded : Icons.star_border_rounded,
              color: i < clip.rating ? colors.starActive : colors.textMuted,
            ),
            tooltip: '${i + 1} star${i == 0 ? '' : 's'}',
            visualDensity: VisualDensity.compact,
            onPressed: () => onChanged(
              clip.copyWith(rating: clip.rating == i + 1 ? 0 : i + 1),
            ),
          ),
        const Spacer(),
        IconButton(
          icon: Icon(
            clip.isFavorite ? Icons.favorite : Icons.favorite_border,
            color: clip.isFavorite ? colors.favoriteActive : colors.textMuted,
          ),
          tooltip: clip.isFavorite
              ? 'Remove from favorites'
              : 'Add to favorites',
          onPressed: () =>
              onChanged(clip.copyWith(isFavorite: !clip.isFavorite)),
        ),
      ],
    );
  }

  Widget _buildCover(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('At ', style: AppTypography.caption),
            Text(
              formatTimecode(clip.coverFrameTime),
              style: AppTypography.timecode(fontSize: 12.5, color: colors.info),
            ),
            const Spacer(),
            FilledButton.tonalIcon(
              icon: isSettingCover
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.photo_camera_outlined, size: 16),
              label: const Text('Set cover (C)'),
              onPressed: isSettingCover ? null : onSetCover,
            ),
            IconButton(
              icon: const Icon(Icons.settings_backup_restore, size: 18),
              tooltip: 'Reset cover to IN point',
              onPressed: isSettingCover ? null : onResetCover,
            ),
          ],
        ),
        if (coverPreviewPath != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                color: Colors.black,
                constraints: const BoxConstraints(maxHeight: 140),
                alignment: Alignment.center,
                child: Image.file(
                  File(coverPreviewPath!),
                  key: ValueKey('${coverPreviewPath}_$coverPreviewStamp'),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: colors.danger,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.subtitle.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
