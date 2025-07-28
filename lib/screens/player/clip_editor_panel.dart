import 'package:flutter/material.dart';
import '../../data/models.dart';
import '../../main.dart'; // for formatDuration

class ClipEditorPanel extends StatefulWidget {
  final VideoClip clip;
  final bool isNewClip;
  final VoidCallback onSave;
  final VoidCallback onDelete;
  final ValueChanged<VideoClip> onUpdate;

  const ClipEditorPanel({
    super.key,
    required this.clip,
    required this.isNewClip,
    required this.onSave,
    required this.onDelete,
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
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tagsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _updateClipState() {
    widget.clip.name = _nameController.text;
    widget.clip.tags = _tagsController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    widget.clip.notes = _notesController.text;
    widget.onUpdate(widget.clip);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.isNewClip ? 'Create New Clip' : 'Edit Clip',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Clip Name',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _updateClipState(),
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
            onChanged: (_) => _updateClipState(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(
              labelText: 'Notes',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            onChanged: (_) => _updateClipState(),
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
                      setState(() {
                        widget.clip.rating = index + 1;
                        _updateClipState();
                      });
                    },
                  );
                }),
              ),
              IconButton(
                icon: Icon(
                  widget.clip.isFavorite
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: widget.clip.isFavorite ? Colors.pink : Colors.grey,
                ),
                onPressed: () {
                  setState(() {
                    widget.clip.isFavorite = !widget.clip.isFavorite;
                    _updateClipState();
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!widget.isNewClip)
                TextButton.icon(
                  icon: const Icon(Icons.delete),
                  label: const Text('Delete'),
                  onPressed: widget.onDelete,
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              const Spacer(),
              ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('Save Clip'),
                onPressed: widget.onSave,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
