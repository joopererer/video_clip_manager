import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../player/player_screen.dart';
import '../player/clip_playback_screen.dart';

class ClipsTab extends StatefulWidget {
  final String searchQuery;
  const ClipsTab({super.key, required this.searchQuery});

  @override
  State<ClipsTab> createState() => _ClipsTabState();
}

class _ClipsTabState extends State<ClipsTab> {
  bool _isGridView = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        final filteredClips = appState.clips.where((clip) {
          final query = widget.searchQuery.toLowerCase();
          return clip.name.toLowerCase().contains(query) ||
              (clip.notes?.toLowerCase().contains(query) ?? false) ||
              clip.tags.any((t) => t.toLowerCase().contains(query)) ||
              clip.videoPath.toLowerCase().contains(query);
        }).toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text('View Mode:'),
                  IconButton(
                    icon: Icon(_isGridView ? Icons.list : Icons.grid_view),
                    onPressed: () => setState(() => _isGridView = !_isGridView),
                  ),
                ],
              ),
            ),
            Expanded(
              child: filteredClips.isEmpty
                  ? const Center(
                      child: Text('No clips found. Try loading a JSON file.'),
                    )
                  : _isGridView
                  ? buildGridView(filteredClips, appState)
                  : buildListView(filteredClips, appState),
            ),
          ],
        );
      },
    );
  }

  Widget buildListView(List<VideoClip> clips, AppState appState) {
    return ListView.builder(
      itemCount: clips.length,
      itemBuilder: (context, index) {
        final clip = clips[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: ListTile(
            leading: const Icon(Icons.movie_filter, size: 40),
            title: Text(clip.name),
            subtitle: Text(
              'From: ${clip.videoPath}\nTags: ${clip.tags.join(', ')}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.grey),
                  tooltip: 'Edit Clip',
                  onPressed: () => _editClip(context, clip),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  tooltip: 'Delete Clip',
                  onPressed: () => _deleteClip(context, clip, appState),
                ),
              ],
            ),
            onTap: () => _playClip(context, clip),
          ),
        );
      },
    );
  }

  Widget buildGridView(List<VideoClip> clips, AppState appState) {
    return GridView.builder(
      padding: const EdgeInsets.all(8.0),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        childAspectRatio: 1.0, // Make it square
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: clips.length,
      itemBuilder: (context, index) {
        final clip = clips[index];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _playClip(context, clip),
            child: GridTile(
              header: Container(
                color: Colors.black54,
                padding: const EdgeInsets.all(4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(
                        Icons.edit,
                        color: Colors.white,
                        size: 18,
                      ),
                      tooltip: 'Edit Clip',
                      onPressed: () => _editClip(context, clip),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(
                        Icons.delete,
                        color: Colors.pink,
                        size: 18,
                      ),
                      tooltip: 'Delete Clip',
                      onPressed: () => _deleteClip(context, clip, appState),
                    ),
                  ],
                ),
              ),
              footer: GridTileBar(
                backgroundColor: Colors.black45,
                title: Text(clip.name, style: const TextStyle(fontSize: 12)),
                subtitle: Text(
                  clip.tags.join(', '),
                  style: const TextStyle(fontSize: 10),
                ),
              ),
              child: Container(
                color: Colors.blueGrey.shade100,
                child: const Center(
                  child: Icon(
                    Icons.play_circle_outline,
                    size: 40,
                    color: Colors.black54,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _playClip(BuildContext context, VideoClip clip) {
    showDialog(
      context: context,
      builder: (context) => Dialog(child: ClipPlaybackScreen(clip: clip)),
    );
  }

  void _editClip(BuildContext context, VideoClip clip) {
    final appState = Provider.of<AppState>(context, listen: false);
    final video = appState.originalVideos.firstWhere(
      (v) => v.path == clip.videoPath,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerScreen(video: video, initialClip: clip),
      ),
    );
  }

  void _deleteClip(BuildContext context, VideoClip clip, AppState appState) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: Text('Are you sure you want to delete "${clip.name}"?'),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          TextButton(
            onPressed: () {
              appState.deleteClip(clip.id);
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
