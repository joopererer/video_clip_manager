import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../player/player_screen.dart';

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
          final video = appState.getVideoById(clip.videoId);
          return clip.name.toLowerCase().contains(query) ||
              (clip.notes?.toLowerCase().contains(query) ?? false) ||
              clip.tags.any((t) => t.toLowerCase().contains(query)) ||
              (video?.name.toLowerCase().contains(query) ?? false);
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
                    onPressed: () {
                      setState(() {
                        _isGridView = !_isGridView;
                      });
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isGridView
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
        final video = appState.getVideoById(clip.videoId);
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: ListTile(
            leading: const Icon(Icons.movie_filter, size: 40),
            title: Text(clip.name),
            subtitle: Text(
              'From: ${video?.name ?? "Unknown Video"}\nTags: ${clip.tags.join(', ')}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (clip.isFavorite)
                  const Icon(Icons.favorite, color: Colors.pink),
                Text('${clip.rating}'),
                const Icon(Icons.star, color: Colors.amber),
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
        childAspectRatio: 3 / 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: clips.length,
      itemBuilder: (context, index) {
        final clip = clips[index];
        final video = appState.getVideoById(clip.videoId);
        return Card(
          clipBehavior: Clip.antiAlias,
          child: GridTile(
            footer: GridTileBar(
              backgroundColor: Colors.black45,
              title: Text(clip.name, style: const TextStyle(fontSize: 12)),
              subtitle: Text(
                video?.name ?? '',
                style: const TextStyle(fontSize: 10),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (clip.isFavorite)
                    const Icon(Icons.favorite, color: Colors.pink, size: 16),
                  Text('${clip.rating}', style: const TextStyle(fontSize: 12)),
                  const Icon(Icons.star, color: Colors.amber, size: 16),
                ],
              ),
            ),
            child: InkWell(
              onTap: () => _playClip(context, clip),
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
    final appState = Provider.of<AppState>(context, listen: false);
    final video = appState.getVideoById(clip.videoId);
    if (video != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PlayerScreen(video: video, initialClip: clip),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Original video not found!')),
      );
    }
  }
}
