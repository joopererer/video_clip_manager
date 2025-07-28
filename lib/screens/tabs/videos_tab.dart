import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../player/player_screen.dart';
import '../../widgets/clip_thumbnail.dart';

class VideosTab extends StatelessWidget {
  final String searchQuery;
  const VideosTab({super.key, required this.searchQuery});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final filteredVideos = appState.originalVideos.where((video) {
      return video.name.toLowerCase().contains(searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text('View Mode:'),
                IconButton(
                  icon: Icon(
                    appState.videosIsGridView ? Icons.list : Icons.grid_view,
                  ),
                  onPressed: () =>
                      appState.setVideosViewMode(!appState.videosIsGridView),
                ),
              ],
            ),
          ),
          Expanded(
            child: filteredVideos.isEmpty
                ? const Center(child: Text('No videos found.'))
                : appState.videosIsGridView
                ? buildGridView(context, filteredVideos, appState)
                : buildListView(context, filteredVideos, appState),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addNewClip(context, null),
        label: const Text('Add New Clip'),
        icon: const Icon(Icons.add),
      ),
    );
  }

  Widget buildListView(
    BuildContext context,
    List<OriginalVideo> videos,
    AppState appState,
  ) {
    return ListView.builder(
      itemCount: videos.length,
      itemBuilder: (context, index) {
        final video = videos[index];
        final clipsFromVideo = appState.clips
            .where((c) => c.videoPath == video.path)
            .toList();
        final representativeClip = clipsFromVideo.isNotEmpty
            ? clipsFromVideo[(clipsFromVideo.length / 2).floor()]
            : null;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: ListTile(
            leading: representativeClip != null
                ? ClipThumbnail(clip: representativeClip, size: 50)
                : const SizedBox(
                    width: 50,
                    child: Icon(Icons.movie_creation_outlined),
                  ),
            title: Text(video.name),
            subtitle: Text('Clips: ${clipsFromVideo.length}'),
            trailing: const Icon(Icons.add_box),
            onTap: () => _addNewClip(context, video),
          ),
        );
      },
    );
  }

  Widget buildGridView(
    BuildContext context,
    List<OriginalVideo> videos,
    AppState appState,
  ) {
    return GridView.builder(
      padding: const EdgeInsets.all(8.0),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        childAspectRatio: 1.0,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemBuilder: (context, index) {
        final video = videos[index];
        final clipsFromVideo = appState.clips
            .where((c) => c.videoPath == video.path)
            .toList();
        final representativeClip = clipsFromVideo.isNotEmpty
            ? clipsFromVideo[(clipsFromVideo.length / 2).floor()]
            : null;

        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _addNewClip(context, video),
            child: GridTile(
              footer: GridTileBar(
                backgroundColor: Colors.black45,
                title: Text(video.name, style: const TextStyle(fontSize: 12)),
                subtitle: Text(
                  'Clips: ${clipsFromVideo.length}',
                  style: const TextStyle(fontSize: 10),
                ),
              ),
              child: representativeClip != null
                  ? ClipThumbnail(clip: representativeClip)
                  : const Icon(Icons.movie_creation_outlined, size: 50),
            ),
          ),
        );
      },
    );
  }

  Future<void> _addNewClip(BuildContext context, OriginalVideo? video) async {
    OriginalVideo? targetVideo = video;
    if (targetVideo == null) {
      final result = await FilePicker.platform.pickFiles(type: FileType.video);
      if (result != null && result.files.single.path != null) {
        targetVideo = OriginalVideo(
          id: 'vid_new_${result.files.single.path.hashCode}',
          path: result.files.single.path!,
          name: result.files.single.name,
        );
      } else {
        return;
      }
    }
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerScreen(video: targetVideo!),
      ),
    );
  }
}
