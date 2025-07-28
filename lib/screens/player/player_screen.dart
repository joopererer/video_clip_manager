// This screen now functions as the CLIP EDITOR
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/app_state.dart';
import '../../widgets/custom_progress_bar.dart';
import 'clip_editor_panel.dart';

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

  @override
  void initState() {
    super.initState();
    player = Player();
    controller = VideoController(player);

    if (widget.initialClip != null) {
      // Editing an existing clip
      _currentClip = widget.initialClip!;
      _isNewClip = false;
    } else {
      // Creating a new clip
      _isNewClip = true;
      _currentClip = VideoClip(
        id: 'clip_${DateTime.now().millisecondsSinceEpoch}',
        videoPath: widget.video.path,
        name: 'New Clip for ${widget.video.name}',
        startTime: Duration.zero,
        endTime: Duration.zero,
      );
    }

    player.open(Media(widget.video.path), play: false).then((_) {
      if (!_isNewClip) {
        player.seek(_currentClip.startTime);
      }
      setState(() {}); // Update to show duration
    });
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  void _setStartTime(Duration time) {
    setState(() {
      if (_currentClip.endTime != Duration.zero &&
          time > _currentClip.endTime) {
        _currentClip.startTime = _currentClip.endTime;
      } else {
        _currentClip.startTime = time;
      }
    });
    player.seek(time);
  }

  void _setEndTime(Duration time) {
    setState(() {
      if (time < _currentClip.startTime) {
        _currentClip.endTime = _currentClip.startTime;
      } else {
        _currentClip.endTime = time;
      }
      setState(() {});
    });
  }

  void _saveClip() {
    final appState = Provider.of<AppState>(context, listen: false);
    if (_isNewClip) {
      appState.addClip(_currentClip);
    } else {
      appState.updateClip(_currentClip);
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Clip "${_currentClip.name}" saved!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNewClip ? 'Create Clip' : 'Edit Clip'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Save Clip',
            onPressed: _saveClip,
          ),
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
              child: Video(controller: controller),
            ),
          ),
          CustomProgressBar(
            player: player,
            startTime: _currentClip.startTime,
            endTime: _currentClip.endTime,
            onSetStart: _setStartTime,
            onSetEnd: _setEndTime,
          ),
          Expanded(
            flex: 2,
            child: ClipEditorPanel(
              clip: _currentClip,
              onUpdate: (updatedClip) {
                setState(() {
                  _currentClip = updatedClip;
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}
