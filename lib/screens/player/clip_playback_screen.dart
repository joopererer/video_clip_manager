// New screen for PLAYBACK ONLY
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'dart:async';

import '../../data/models.dart';
import '../../main.dart';

class ClipPlaybackScreen extends StatefulWidget {
  final VideoClip clip;

  const ClipPlaybackScreen({super.key, required this.clip});

  @override
  State<ClipPlaybackScreen> createState() => _ClipPlaybackScreenState();
}

class _ClipPlaybackScreenState extends State<ClipPlaybackScreen> {
  late final Player player;
  late final VideoController controller;
  StreamSubscription<Duration>? _positionSubscription;

  @override
  void initState() {
    super.initState();
    player = Player();
    controller = VideoController(player);
    player.open(Media(widget.clip.videoPath), play: false).then((_) {
      player.seek(widget.clip.startTime);
      player.play();
    });

    // Enforce clip end time
    _positionSubscription = player.stream.position.listen((position) {
      if (position >= widget.clip.endTime) {
        player.pause();
        player.seek(widget.clip.startTime);
      }
    });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      width: 640, // Fixed width for dialog-like appearance
      height: 600,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.clip.name,
                  style: Theme.of(context).textTheme.headlineSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Video(controller: controller),
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoRow(
            Icons.timer,
            'Duration',
            '${formatDuration(widget.clip.startTime)} - ${formatDuration(widget.clip.endTime)}',
          ),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.label, 'Tags', widget.clip.tags.join(', ')),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.notes, 'Notes', widget.clip.notes ?? 'N/A'),
          const SizedBox(height: 8),
          _buildInfoRow(
            Icons.star,
            'Rating',
            List.generate(5, (i) => i < widget.clip.rating ? '★' : '☆').join(),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
        Expanded(child: Text(value)),
      ],
    );
  }
}
