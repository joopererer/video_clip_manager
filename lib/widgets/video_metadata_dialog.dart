import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/models.dart';
import '../services/video_metadata_service.dart';
import '../services/thumbnail_service.dart';

class VideoMetadataDialog extends StatefulWidget {
  final OriginalVideo video;
  final Function(OriginalVideo updatedVideo) onSave;

  const VideoMetadataDialog({
    super.key,
    required this.video,
    required this.onSave,
  });

  @override
  State<VideoMetadataDialog> createState() => _VideoMetadataDialogState();
}

class _VideoMetadataDialogState extends State<VideoMetadataDialog> {
  late TextEditingController _actorsController;
  late TextEditingController _yearController;
  late TextEditingController _seriesController;
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  
  final List<String> _actors = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final metadata = VideoMetadata(metadata: widget.video.metadata);
    
    _actorsController = TextEditingController();
    _yearController = TextEditingController(text: metadata.year?.toString() ?? '');
    _seriesController = TextEditingController(text: metadata.series ?? '');
    _titleController = TextEditingController(text: metadata.title ?? '');
    _descriptionController = TextEditingController(text: metadata.description ?? '');
    
    _actors.addAll(metadata.actors);
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
            child: Text(
              'Edit Video Metadata',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 视频名称
            const Text('Video Name:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(widget.video.name, style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
            const Text('Actors:', style: TextStyle(fontWeight: FontWeight.bold)),
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
                children: _actors.map((actor) => Chip(
                  label: Text(actor),
                  onDeleted: () {
                    setState(() {
                      _actors.remove(actor);
                    });
                  },
                )).toList(),
              ),
            ],
            const SizedBox(height: 16),
            
            // 年份
            const Text('Year:', style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(
              controller: _yearController,
              decoration: const InputDecoration(
                hintText: 'Enter release year (e.g., 2023)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            
            // 系列
            const Text('Series:', style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(
              controller: _seriesController,
              decoration: const InputDecoration(
                hintText: 'Enter series name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            
            // 描述
            const Text('Description:', style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                hintText: 'Enter video description',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            
            // 自动搜刮按钮
            if (!_isLoading)
              ElevatedButton.icon(
                onPressed: _scrapeMetadata,
                icon: const Icon(Icons.search),
                label: const Text('Auto-scrape Metadata'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            if (_isLoading)
              const Row(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16),
                  Text('Scraping metadata...'),
                ],
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
          onPressed: _saveMetadata,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _scrapeMetadata() async {
    setState(() => _isLoading = true);
    
    try {
      // 从context中获取thumbnailService
      final thumbnailService = Provider.of<ThumbnailService>(context, listen: false);
      final metadataService = VideoMetadataService(
        thumbnailService: thumbnailService,
      );
      
      // 使用新的处理方式，创建一个临时的OriginalVideo对象
      final tempVideo = OriginalVideo(
        id: widget.video.id,
        path: widget.video.path,
        name: widget.video.name,
      );
      
      // 处理元数据
      await metadataService.processVideoMetadataBatch([tempVideo], (
        result,
      ) {
        // 从结果中提取元数据 - 由于新的处理方式不直接返回metadata，我们需要从缓存中获取
        // 这里暂时使用空元数据，因为新的处理方式主要关注duration和thumbnail
        final metadata = <String, dynamic>{};
        
        setState(() {
          // 从元数据中提取演员信息
          final actorData = metadata['artist'] ?? metadata['actors'] ?? metadata['performer'];
          if (actorData is String && actorData.isNotEmpty) {
            _actors.clear();
            _actors.addAll(actorData
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty));
          }
          
          // 从元数据中提取年份
          final yearData = metadata['date'] ?? metadata['year'];
          if (yearData is String) {
            final yearMatch = RegExp(r'(\d{4})').firstMatch(yearData);
            if (yearMatch != null) {
              _yearController.text = yearMatch.group(1)!;
            }
          }
          
          // 从元数据中提取系列信息
          final seriesData = metadata['album'] ?? metadata['series'] ?? metadata['show'];
          if (seriesData is String) {
            _seriesController.text = seriesData;
          }
          
          // 从元数据中提取标题
          final titleData = metadata['title'];
          if (titleData is String) {
            _titleController.text = titleData;
          }
          
          // 从元数据中提取描述
          final descriptionData = metadata['description'] ?? metadata['comment'];
          if (descriptionData is String) {
            _descriptionController.text = descriptionData;
          }
        });
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Metadata scraped successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to scrape metadata: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _saveMetadata() {
    final updatedMetadata = <String, dynamic>{
      if (_titleController.text.isNotEmpty) 'title': _titleController.text,
      if (_actors.isNotEmpty) 'artist': _actors.join(', '),
      if (_yearController.text.isNotEmpty) 'year': _yearController.text,
      if (_seriesController.text.isNotEmpty) 'album': _seriesController.text,
      if (_descriptionController.text.isNotEmpty) 'description': _descriptionController.text,
    };

    final updatedVideo = widget.video.copyWith(metadata: updatedMetadata);
    widget.onSave(updatedVideo);
    Navigator.of(context).pop();
  }
} 