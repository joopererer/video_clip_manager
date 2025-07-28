import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../player/player_screen.dart';

class VideosTab extends StatelessWidget {
  final String searchQuery;

  const VideosTab({super.key, required this.searchQuery});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final filteredVideos = appState.originalVideos.where((video) {
      return video.name.toLowerCase().contains(searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      body: filteredVideos.isEmpty
          ? const Center(
              child: Text(
                'No videos found. Load clips to see their source videos.',
              ),
            )
          : ListView.builder(
              itemCount: filteredVideos.length,
              itemBuilder: (context, index) {
                final video = filteredVideos[index];
                final clipsFromVideo = appState.clips
                    .where((c) => c.videoPath == video.path)
                    .length;
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 4.0,
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.movie_creation, size: 40),
                    title: Text(video.name),
                    subtitle: Text(
                      'Path: ${video.path}\nClips: $clipsFromVideo',
                      maxLines: 3,
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () => _addNewClip(context, video),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addNewClip(context, null),
        label: const Text('Add New Clip'),
        icon: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _addNewClip(BuildContext context, OriginalVideo? video) async {
    OriginalVideo? targetVideo = video;

    // If no video is provided, prompt the user to pick one.
    if (targetVideo == null) {
      final result = await FilePicker.platform.pickFiles(type: FileType.video);
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        targetVideo = OriginalVideo(
          id: 'vid_new_${file.path.hashCode}',
          path: file.path,
          name: result.files.single.name,
        );
      } else {
        return; // User cancelled file picking
      }
    }

    // Navigate to the editor screen to create a new clip for the target video
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerScreen(video: targetVideo!),
      ),
    );
  }
}
