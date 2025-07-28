import 'package:flutter/material.dart';
import '../../data/models.dart';
import '../../main.dart'; // for formatDuration

class ClipEditorPanel extends StatefulWidget {
  final VideoClip clip;
  final ValueChanged<VideoClip> onUpdate;

  const ClipEditorPanel({
    super.key,
    required this.clip,
    required this.onUpdate,
  });

  @override
  State<ClipEditorPanel> createState() => _ClipEditorPanelState();
}

class _ClipEditorPanelState extends State<ClipEditorPanel> {
  late TextEditingController _nameController;
  late TextEditingController _tagsController;
  late TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.clip.name);
    _tagsController = TextEditingController(text: widget.clip.tags.join(', '));
    _notesController = TextEditingController(text: widget.clip.notes);

    _nameController.addListener(_updateClipState);
    _tagsController.addListener(_updateClipState);
    _notesController.addListener(_updateClipState);
  }

  @override
  void dispose() {
    _nameController.removeListener(_updateClipState);
    _tagsController.removeListener(_updateClipState);
    _notesController.removeListener(_updateClipState);
    _nameController.dispose();
    _tagsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _updateClipState() {
    final clip = widget.clip;
    clip.name = _nameController.text;
    clip.tags = _tagsController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    clip.notes = _notesController.text;
    widget.onUpdate(clip);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Clip Details', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Clip Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text('Start: ${formatDuration(widget.clip.startTime)}'),
              ),
              Expanded(
                child: Text('End: ${formatDuration(widget.clip.endTime)}'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tagsController,
            decoration: const InputDecoration(
              labelText: 'Tags (comma-separated)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(
              labelText: 'Notes',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Rating:'),
              Row(
                children: List.generate(5, (index) {
                  return IconButton(
                    icon: Icon(
                      index < widget.clip.rating
                          ? Icons.star
                          : Icons.star_border,
                      color: Colors.amber,
                    ),
                    onPressed: () {
                      widget.clip.rating = index + 1;
                      _updateClipState();
                      setState(() {});
                    },
                  );
                }),
              ),
              IconButton(
                tooltip: 'Toggle Favorite',
                icon: Icon(
                  widget.clip.isFavorite
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: widget.clip.isFavorite ? Colors.pink : Colors.grey,
                ),
                onPressed: () {
                  widget.clip.isFavorite = !widget.clip.isFavorite;
                  _updateClipState();
                  setState(() {});
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
