import 'package:flutter/material.dart';
import '../data/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/playlist_time.dart';
import '../utils/timeline_layout.dart';

/// Muted hues that read well on the dark surfaces. A clip always gets the same
/// colour (see [_colorForClip]).
const List<Color> _segmentColors = [
  Color(0xFF6C8CD5),
  Color(0xFF5FB49C),
  Color(0xFFD9A15B),
  Color(0xFFB07CC6),
  Color(0xFFD2706F),
  Color(0xFF58A6B8),
  Color(0xFF8C97D9),
  Color(0xFFC2749A),
];

Color _colorForClip(String clipId) {
  // FNV-1a so the colour does not depend on String.hashCode.
  var h = 0x811c9dc5;
  for (final unit in clipId.codeUnits) {
    h = ((h ^ unit) * 0x01000193) & 0xFFFFFFFF;
  }
  return _segmentColors[h % _segmentColors.length];
}

String _compactDuration(Duration d) {
  if (d.inMinutes > 0) return formatPlaylistDuration(d);
  final s = d.inMilliseconds / 1000;
  return s >= 10 ? '${s.round()}s' : '${s.toStringAsFixed(1)}s';
}

/// A timeline of playlist items. Each segment's width is proportional to its
/// effective duration, with a small visual floor so very short clips stay
/// visible and clickable. Labels and tooltips always show the real times.
///
/// [onReorder] receives `(from, finalIndex)`: the position the dragged entry
/// ends up at once moved, ready for `PlaylistDraft.moveTo`.
class PlaylistTimelineView extends StatefulWidget {
  final List<PlaylistItemWithClip> items;
  final double height;
  final bool showDuration;
  final bool showNames;
  final bool showScale;
  final double minSegmentWidth;
  final ValueChanged<int>? onItemTap;
  final int? selectedIndex;
  final void Function(int from, int finalIndex)? onReorder;
  final bool enableReorder;

  const PlaylistTimelineView({
    super.key,
    required this.items,
    this.height = 60,
    this.showDuration = true,
    this.showNames = true,
    this.showScale = false,
    this.minSegmentWidth = 8,
    this.onItemTap,
    this.selectedIndex,
    this.onReorder,
    this.enableReorder = false,
  });

  @override
  State<PlaylistTimelineView> createState() => _PlaylistTimelineViewState();
}

class _PlaylistTimelineViewState extends State<PlaylistTimelineView> {
  /// Insertion slot (0..length) currently hovered while dragging.
  int? _dropSlot;
  int? _dragging;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    if (widget.items.isEmpty) return _empty(c);

    final bar = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final layout = computeTimelineLayout(
          [
            for (final e in widget.items)
              playlistItemDuration(e).inMilliseconds,
          ],
          width,
          minSegment: widget.minSegmentWidth,
        );
        final bounds = layout.boundaries;

        return DragTarget<int>(
          onWillAcceptWithDetails: (_) => widget.enableReorder,
          onMove: (details) {
            final box = context.findRenderObject() as RenderBox;
            final local = box.globalToLocal(details.offset);
            final slot = layout.nearestSlot(local.dx);
            if (slot != _dropSlot) setState(() => _dropSlot = slot);
          },
          onLeave: (_) => setState(() => _dropSlot = null),
          onAcceptWithDetails: (details) {
            final slot = _dropSlot;
            setState(() => _dropSlot = null);
            if (slot == null) return;
            final target = finalIndexForSlot(details.data, slot);
            if (target != null) widget.onReorder?.call(details.data, target);
          },
          builder: (context, candidates, rejected) {
            return Container(
              height: widget.height,
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: c.borderSubtle),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  for (var i = 0; i < widget.items.length; i++)
                    Positioned(
                      left: bounds[i],
                      width: layout.widths[i],
                      top: 0,
                      bottom: 0,
                      child: _segment(
                        c,
                        i,
                        layout.widths[i],
                        layout.expanded[i],
                      ),
                    ),
                  if (_dropSlot != null && _dragging != null)
                    Positioned(
                      left: (bounds[_dropSlot!] - 1.5).clamp(0.0, width - 3),
                      width: 3,
                      top: 0,
                      bottom: 0,
                      child: IgnorePointer(child: ColoredBox(color: c.primary)),
                    ),
                ],
              ),
            );
          },
        );
      },
    );

    if (!widget.showScale) return bar;
    final total = playlistTotalDuration(widget.items);
    final style = TextStyle(color: c.textMuted, fontSize: 11);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        bar,
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('0:00', style: style),
            Text(formatPlaylistDuration(total, millis: true), style: style),
          ],
        ),
      ],
    );
  }

  Widget _segment(AppColorExtension c, int index, double width, bool expanded) {
    final entry = widget.items[index];
    final selected = widget.selectedIndex == index;
    final color = _colorForClip(entry.clip.id);
    final dragged = _dragging == index;

    Widget body = _SegmentBody(
      entry: entry,
      color: color,
      width: width,
      selected: selected,
      expanded: expanded,
      dimmed: dragged,
      showNames: widget.showNames,
      showDuration: widget.showDuration,
      selectedBorder: c.textPrimary,
    );

    body = Tooltip(
      richMessage: _tooltip(index),
      waitDuration: const Duration(milliseconds: 350),
      child: MouseRegion(
        cursor: widget.onItemTap != null
            ? SystemMouseCursors.click
            : MouseCursor.defer,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onItemTap == null
              ? null
              : () => widget.onItemTap!(index),
          child: body,
        ),
      ),
    );

    if (!widget.enableReorder) return body;
    return Draggable<int>(
      data: index,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () => setState(() => _dragging = index),
      onDragEnd: (_) => setState(() {
        _dragging = null;
        _dropSlot = null;
      }),
      feedback: _DragChip(label: entry.clip.name, color: color),
      child: body,
    );
  }

  InlineSpan _tooltip(int index) {
    final entry = widget.items[index];
    final item = entry.item;
    final clip = entry.clip;
    final start = item.customStartTime ?? clip.startTime;
    final end = item.customEndTime ?? clip.endTime;
    final offset = playlistOffsetOf(widget.items, index);
    final length = playlistItemDuration(entry);
    String t(Duration d) => formatPlaylistDuration(d, millis: true);
    return TextSpan(
      children: [
        TextSpan(
          text: '${index + 1}. ${clip.name}\n',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        TextSpan(text: '素材时间 ${t(start)} – ${t(end)}\n'),
        TextSpan(text: '时长 ${t(length)}\n'),
        TextSpan(text: '列表位置 ${t(offset)} – ${t(offset + length)}'),
      ],
    );
  }

  Widget _empty(AppColorExtension c) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: c.borderSubtle),
      ),
      alignment: Alignment.center,
      child: Text('暂无片段', style: TextStyle(color: c.textMuted, fontSize: 13)),
    );
  }
}

class _SegmentBody extends StatelessWidget {
  final PlaylistItemWithClip entry;
  final Color color;
  final double width;
  final bool selected;
  final bool expanded;
  final bool dimmed;
  final bool showNames;
  final bool showDuration;
  final Color selectedBorder;

  const _SegmentBody({
    required this.entry,
    required this.color,
    required this.width,
    required this.selected,
    required this.expanded,
    required this.dimmed,
    required this.showNames,
    required this.showDuration,
    required this.selectedBorder,
  });

  @override
  Widget build(BuildContext context) {
    const gap = 1.0;
    final inner = width - gap * 2;
    final canShowText = inner > 44;
    return Opacity(
      opacity: dimmed ? 0.35 : 1,
      child: Container(
        margin: const EdgeInsets.all(gap),
        decoration: BoxDecoration(
          color: color.withValues(alpha: selected ? 0.95 : 0.72),
          borderRadius: BorderRadius.circular(inner < 12 ? 2 : 6),
          border: Border.all(
            color: selected ? selectedBorder : color.withValues(alpha: 0.4),
            width: selected ? 2 : 1,
          ),
        ),
        // A hatch under the segment marks widths drawn larger than real scale.
        foregroundDecoration: expanded
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(inner < 12 ? 2 : 6),
                border: Border(
                  bottom: BorderSide(color: Colors.white70, width: 2),
                ),
              )
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: canShowText
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showNames)
                    Text(
                      entry.clip.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  if (showDuration)
                    Text(
                      _compactDuration(playlistItemDuration(entry)),
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white70,
                      ),
                    ),
                ],
              )
            : null,
      ),
    );
  }
}

class _DragChip extends StatelessWidget {
  final String label;
  final Color color;
  const _DragChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6)],
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    );
  }
}
