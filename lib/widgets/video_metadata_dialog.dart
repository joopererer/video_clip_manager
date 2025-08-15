import 'package:flutter/material.dart';
import '../data/models.dart';

class VideoMetadataDialog extends StatefulWidget {
  final OriginalVideo video;
  final Function(OriginalVideo) onSave;

  const VideoMetadataDialog({
    super.key,
    required this.video,
    required this.onSave,
  });

  @override
  State<VideoMetadataDialog> createState() => _VideoMetadataDialogState();
}

class _VideoMetadataDialogState extends State<VideoMetadataDialog> {
  final List<String> _actors = [];
  final _actorsController = TextEditingController();
  final _yearController = TextEditingController();
  final _seriesController = TextEditingController();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // 暂时注释掉，因为 VideoMetadata 类和 metadata 属性不存在
    // final metadata = VideoMetadata(metadata: widget.video.metadata);

    // _actors.addAll(metadata.actors); // 暂时注释掉
  }

  @override
  void dispose() {
    _actorsController.dispose();
    _yearController.dispose();
    _seriesController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.edit),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Edit Video Metadata', overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 视频名称
            const Text(
              'Video Name:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              widget.video.name,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),

            // 标题
            const Text('Title:', style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                hintText: 'Enter video title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // 演员
            const Text(
              'Actors:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _actorsController,
                    decoration: const InputDecoration(
                      hintText: 'Enter actor name',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (value) {
                      if (value.isNotEmpty && !_actors.contains(value)) {
                        setState(() {
                          _actors.add(value);
                          _actorsController.clear();
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    final value = _actorsController.text.trim();
                    if (value.isNotEmpty && !_actors.contains(value)) {
                      setState(() {
                        _actors.add(value);
                        _actorsController.clear();
                      });
                    }
                  },
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            if (_actors.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                children: _actors
                    .map(
                      (actor) => Chip(
                        label: Text(actor),
                        onDeleted: () {
                          setState(() {
                            _actors.remove(actor);
                          });
                        },
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 16),

            // 年份
            const Text('Year:', style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(
              controller: _yearController,
              decoration: const InputDecoration(
                hintText: 'Enter year (e.g., 2024)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),

            // 系列
            const Text(
              'Series:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            TextField(
              controller: _seriesController,
              decoration: const InputDecoration(
                hintText: 'Enter series name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // 描述
            const Text(
              'Description:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Enter description',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _scrapeMetadata,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Scrape Metadata'),
        ),
        ElevatedButton(onPressed: _saveMetadata, child: const Text('Save')),
      ],
    );
  }

  Future<void> _scrapeMetadata() async {
    setState(() => _isLoading = true);

    try {
      // Temporarily disabled metadata scraping functionality
      // The new VideoMetadataService focuses on duration extraction only
      // Metadata scraping will be re-implemented in a future update

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Metadata scraping is currently disabled.'),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to scrape metadata: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _saveMetadata() {
    // Temporarily disabled metadata saving
    // OriginalVideo no longer has a metadata property
    // This will be re-implemented in a future update
    final updatedVideo = widget.video; // Temporarily not updating metadata
    widget.onSave(updatedVideo);
    Navigator.of(context).pop();
  }
}
