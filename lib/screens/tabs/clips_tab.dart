import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../player/clip_editor_screen.dart';
import '../player/clip_playback_screen.dart';
import '../../widgets/clip_thumbnail.dart';

class ClipsTab extends StatelessWidget {
  final String searchQuery;
  final List<String> selectedTags;
  const ClipsTab({
    super.key,
    required this.searchQuery,
    required this.selectedTags,
  });

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    final filteredClips = appState.clips.where((clip) {
      final query = searchQuery.toLowerCase();
      final textMatch =
          query.isEmpty ||
              clip.name.toLowerCase().contains(query) ||
              (clip.notes?.toLowerCase().contains(query) ?? false) ||
              clip.videoPath.toLowerCase().contains(query);

      final tagMatch =
          selectedTags.isEmpty ||
              selectedTags.every((tag) => clip.tags.contains(tag));

      return textMatch && tagMatch;
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
                icon: Icon(
                  appState.clipsIsGridView ? Icons.list : Icons.grid_view,
                ),
                onPressed: () =>
                    appState.setClipsViewMode(!appState.clipsIsGridView),
              ),
            ],
          ),
        ),
        Expanded(
          child: filteredClips.isEmpty
              ? const Center(
            child: Text('No clips found. Try loading a JSON file.'),
          )
              : appState.clipsIsGridView
              ? buildGridView(context, filteredClips)
              : buildListView(context, filteredClips),
        ),
      ],
    );
  }

  Widget buildListView(BuildContext context, List<VideoClip> clips) {
    final appState = context.read<AppState>();
    return ListView.builder(
      itemCount: clips.length,
      itemBuilder: (context, index) {
        final clip = clips[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: ListTile(
            leading: ClipThumbnail(clip: clip, size: 50),
            title: Text(clip.name),
            subtitle: Text(
              'Tags: ${clip.tags.join(', ')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.grey),
                  onPressed: () => _editClip(context, clip),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
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

  Widget buildGridView(BuildContext context, List<VideoClip> clips) {
    final appState = context.read<AppState>();
    return GridView.builder(
      padding: const EdgeInsets.all(8.0),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        childAspectRatio: 1.0,
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.edit,
                        color: Colors.white,
                        size: 18,
                      ),
                      onPressed: () => _editClip(context, clip),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete,
                        color: Colors.pink,
                        size: 18,
                      ),
                      onPressed: () => _deleteClip(context, clip, appState),
                    ),
                  ],
                ),
              ),
              footer: GridTileBar(
                backgroundColor: Colors.black45,
                title: Text(clip.name, style: const TextStyle(fontSize: 12)),
              ),
              child: ClipThumbnail(clip: clip),
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
    final appState = context.read<AppState>();
    final video = appState.originalVideos.firstWhere(
          (v) => v.path == clip.videoPath,
      // Au cas où la vidéo originale aurait été supprimée, on en crée une temporaire.
      orElse: () => OriginalVideo(
        id: 'temp_${clip.videoPath.hashCode}',
        path: clip.videoPath,
        name: clip.videoPath.split(Platform.pathSeparator).last,
      ),
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        // **LA CORRECTION EST ICI**
        // On passe uniquement la vidéo. ClipEditorScreen se chargera d'afficher tous les clips associés.
        builder: (context) => ClipEditorScreen(
          video: video,
          clipToEdit: clip,
        ),
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