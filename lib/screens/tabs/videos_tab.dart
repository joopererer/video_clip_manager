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
      body: ListView.builder(
        itemCount: filteredVideos.length,
        itemBuilder: (context, index) {
          final video = filteredVideos[index];
          final clipsFromVideo = appState.clips
              .where((c) => c.videoId == video.id)
              .length;
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: ListTile(
              leading: const Icon(Icons.movie_creation, size: 40),
              title: Text(video.name),
              subtitle: Text('Path: ${video.path}\nClips: $clipsFromVideo'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_forever),
                onPressed: () => _confirmDelete(context, video, appState),
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PlayerScreen(video: video),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addVideo(context, appState),
        tooltip: 'Add Video',
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _addVideo(BuildContext context, AppState appState) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final video = OriginalVideo(
        id: 'vid_${DateTime.now().millisecondsSinceEpoch}',
        path: file.path,
        name: result.files.single.name,
      );
      appState.addVideo(video);
    }
  }

  void _confirmDelete(
    BuildContext context,
    OriginalVideo video,
    AppState appState,
  ) {
    final clipsFromVideo = appState.clips
        .where((c) => c.videoId == video.id)
        .length;
    if (clipsFromVideo > 0) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cannot Delete Video'),
          content: Text(
            'This video has $clipsFromVideo associated clip(s). You must delete them first.',
          ),
          actions: [
            TextButton(
              child: const Text('OK'),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirm Deletion'),
          content: Text('Are you sure you want to delete "${video.name}"?'),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
            TextButton(
              onPressed: () {
                appState.deleteVideo(video.id);
                Navigator.of(ctx).pop();
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
    }
  }
}
