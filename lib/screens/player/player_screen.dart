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

  // State for the clip being edited
  late VideoClip _currentClip;
  bool _isNewClip = true;

  @override
  void initState() {
    super.initState();
    player = Player();
    controller = VideoController(player);

    // Determine if we are editing an existing clip or creating a new one
    if (widget.initialClip != null) {
      _currentClip = widget.initialClip!;
      _isNewClip = false;
    } else {
      _isNewClip = true;
      _currentClip = VideoClip(
        id: 'clip_${DateTime.now().millisecondsSinceEpoch}',
        videoId: widget.video.id,
        name: 'New Clip',
        startTime: Duration.zero,
        endTime: Duration.zero,
      );
    }

    // Open media and seek to start time if available
    player.open(Media(widget.video.path), play: false).then((_) {
      if (widget.initialClip != null) {
        player.seek(widget.initialClip!.startTime);
      }
      // This is needed to get the duration for the progress bar
      setState(() {});
    });
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  void _setStartTime(Duration time) {
    setState(() {
      // Ensure start time is not after end time
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
      // Ensure end time is not before start time
      if (time < _currentClip.startTime) {
        _currentClip.endTime = _currentClip.startTime;
      } else {
        _currentClip.endTime = time;
      }
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

  void _deleteClip() {
    final appState = Provider.of<AppState>(context, listen: false);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: Text(
          'Are you sure you want to delete "${_currentClip.name}"?',
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          TextButton(
            onPressed: () {
              appState.deleteClip(_currentClip.id);
              Navigator.of(ctx).pop(); // close dialog
              Navigator.of(context).pop(); // close player screen
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.video.name)),
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
              isNewClip: _isNewClip,
              onSave: _saveClip,
              onDelete: _deleteClip,
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
