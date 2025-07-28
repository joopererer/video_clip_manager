import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';

import '../../data/models.dart';
import '../../data/app_state.dart';
import '../../widgets/custom_progress_bar.dart';
import '../../services/thumbnail_service.dart';
import '../../main.dart'; // for formatDuration

class PlayerScreen extends StatefulWidget {
  final OriginalVideo video;
  final VideoClip? initialClip;

  const PlayerScreen({super.key, required this.video, this.initialClip});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player player;
  late final VideoController controller;
  late VideoClip _currentClip;
  bool _isNewClip = true;
  String? _coverPreviewPath;

  final _nameController = TextEditingController();
  final _tagsController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    player = Player();
    controller = VideoController(player);

    if (widget.initialClip != null) {
      _currentClip = widget.initialClip!;
      _isNewClip = false;
    } else {
      _isNewClip = true;
      _currentClip = VideoClip(
        id: 'clip_${DateTime.now().millisecondsSinceEpoch}',
        videoPath: widget.video.path,
        name: 'New Clip for ${widget.video.name}',
        startTime: Duration.zero,
        endTime: Duration.zero,
        coverFrameTime: Duration.zero,
      );
    }

    _nameController.text = _currentClip.name;
    _tagsController.text = _currentClip.tags.join(', ');
    _notesController.text = _currentClip.notes ?? '';
    _coverPreviewPath = _currentClip.thumbnailPath;

    player.open(Media(widget.video.path), play: false).then((_) {
      player.seek(_currentClip.startTime);
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    player.dispose();
    _nameController.dispose();
    _tagsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _setStartTimeFromPlayer() {
    final time = player.state.position;
    setState(() {
      if (_currentClip.endTime != Duration.zero &&
          time > _currentClip.endTime) {
        _currentClip.startTime = _currentClip.endTime;
      } else {
        _currentClip.startTime = time;
      }
    });
  }

  void _setEndTimeFromPlayer() {
    final time = player.state.position;
    setState(() {
      if (time < _currentClip.startTime) {
        _currentClip.endTime = _currentClip.startTime;
      } else {
        _currentClip.endTime = time;
      }
    });
  }

  Future<void> _previewClip() async {
    if (_currentClip.startTime >= _currentClip.endTime) return;
    await player.seek(_currentClip.startTime);
    await player.play();

    Future.delayed(_currentClip.endTime - _currentClip.startTime, () {
      if (mounted && player.state.playing) {
        player.pause();
      }
    });
  }

  Future<void> _setCover() async {
    final thumbnailService = context.read<ThumbnailService>();
    // Use the main player instance for screenshotting as it's visible
    final newThumbPath = await thumbnailService.generateThumbnail(
      widget.video.path,
      player.state.position,
      _currentClip.id,
    );

    if (mounted && newThumbPath != null) {
      setState(() {
        _currentClip.coverFrameTime = player.state.position;
        _currentClip.thumbnailPath = newThumbPath;
        _coverPreviewPath = newThumbPath;
      });
    }
  }

  Future<void> _saveClip() async {
    final appState = context.read<AppState>();

    _currentClip.name = _nameController.text;
    _currentClip.notes = _notesController.text;
    _currentClip.tags = _tagsController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (_currentClip.thumbnailPath == null ||
        !await File(_currentClip.thumbnailPath!).exists()) {
      if (_currentClip.coverFrameTime == Duration.zero) {
        _currentClip.coverFrameTime = _currentClip.startTime;
      }
      final thumbnailService = context.read<ThumbnailService>();
      // Use the main player instance for screenshotting
      _currentClip.thumbnailPath = await thumbnailService.generateThumbnail(
        widget.video.path,
        _currentClip.coverFrameTime,
        _currentClip.id,
      );
    }

    if (_isNewClip) {
      await appState.addClip(_currentClip);
    } else {
      await appState.updateClip(_currentClip);
    }
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Clip "${_currentClip.name}" saved!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNewClip ? 'Create Clip' : 'Edit Clip'),
        actions: [
          IconButton(icon: const Icon(Icons.save), onPressed: _saveClip),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Card(
              elevation: 4.0,
              margin: const EdgeInsets.all(8.0),
              clipBehavior: Clip.antiAlias,
              // 告诉 Video 组件不要构建任何默认控件
              child: ExcludeSemantics(
                child: Video(
                  controller: controller,
                  controls: (state) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
          CustomProgressBar(
            player: player,
            startTime: _currentClip.startTime,
            endTime: _currentClip.endTime,
            onSetStart: (time) => setState(() => _currentClip.startTime = time),
            onSetEnd: (time) => setState(() => _currentClip.endTime = time),
          ),
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Clip Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TypeAheadField<String>(
                    controller: _tagsController,
                    builder: (context, controller, focusNode) => TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        labelText: 'Tags (comma-separated)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    suggestionsCallback: (pattern) {
                      final lastTagPattern = pattern.split(',').last.trim();
                      if (lastTagPattern.isEmpty) return <String>[];
                      return appState.allTags
                          .where(
                            (tag) => tag.toLowerCase().contains(
                              lastTagPattern.toLowerCase(),
                            ),
                          )
                          .toList();
                    },
                    itemBuilder: (context, suggestion) =>
                        ListTile(title: Text(suggestion)),
                    onSelected: (suggestion) {
                      final currentTags = _tagsController.text
                          .split(',')
                          .map((t) => t.trim())
                          .where((t) => t.isNotEmpty)
                          .toList();
                      if (currentTags.isNotEmpty) currentTags.removeLast();
                      if (!currentTags.contains(suggestion)) {
                        currentTags.add(suggestion);
                      }
                      _tagsController.text = '${currentTags.join(', ')}, ';
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: _setStartTimeFromPlayer,
                        child: const Text("Set Start"),
                      ),
                      ElevatedButton(
                        onPressed: _setEndTimeFromPlayer,
                        child: const Text("Set End"),
                      ),
                      ElevatedButton(
                        onPressed: _previewClip,
                        child: const Text("Preview Clip"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_coverPreviewPath != null)
                    Column(
                      children: [
                        const Text(
                          "Cover Preview:",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Image.file(
                          File(_coverPreviewPath!),
                          key: ValueKey(_coverPreviewPath!),
                          height: 100,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(Icons.error),
                        ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Cover Time: ${formatDuration(_currentClip.coverFrameTime)}',
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: _setCover,
                        child: const Text('Set Cover From Current Frame'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
