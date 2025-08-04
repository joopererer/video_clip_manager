import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../widgets/video_thumbnail.dart';
import '../player/clip_editor_screen.dart';

class VideosTab extends StatefulWidget {
  final String searchQuery;
  final List<String> selectedTags;
  final int? selectedRating;
  final bool? selectedFavorite;

  const VideosTab({
    super.key,
    required this.searchQuery,
    required this.selectedTags,
    this.selectedRating,
    this.selectedFavorite,
  });

  @override
  State<VideosTab> createState() => _VideosTabState();
}

class _VideosTabState extends State<VideosTab> {
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final filteredVideos =
        appState.getFilteredVideos(searchQuery: widget.searchQuery);

    return Scaffold(
      body: Column(
        children: [
          _buildVideoInfoBar(appState, filteredVideos),
          Expanded(
            child: filteredVideos.isEmpty
                ? _buildEmptyState(context)
                : appState.videosIsGridView
                    ? _buildGridView(filteredVideos)
                    : _buildListView(filteredVideos),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _pickAndAddVideos(context),
        label: const Text('Add Videos'),
        icon: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildVideoInfoBar(
      AppState appState, List<OriginalVideo> filteredVideos) {
    final totalDuration = filteredVideos.fold<Duration>(
        Duration.zero, (sum, v) => sum + (v.duration ?? Duration.zero));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
      child: Row(
        children: [
          _buildInfoItem('Videos', '${filteredVideos.length}', Icons.movie),
          const SizedBox(width: 24),
          _buildInfoItem(
              'Total Duration', _formatDuration(totalDuration), Icons.access_time),
          const Spacer(),
          const Text('View:'),
          IconButton(
            tooltip: appState.videosIsGridView
                ? 'Switch to List View'
                : 'Switch to Grid View',
            icon: Icon(appState.videosIsGridView ? Icons.list : Icons.grid_view),
            onPressed: () =>
                appState.setVideosViewMode(!appState.videosIsGridView),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.secondary),
        const SizedBox(width: 8),
        Text('$label: $value', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.video_library_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('No videos found.', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () => _pickAndAddVideos(context),
            icon: const Icon(Icons.add),
            label: const Text('Add Your First Video'),
          ),
        ],
      ),
    );
  }

  Widget _buildListView(List<OriginalVideo> videos) {
    return ListView.builder(
      itemCount: videos.length,
      itemBuilder: (context, index) {
        final video = videos[index];
        return _buildVideoListTile(context, video);
      },
    );
  }

  Widget _buildGridView(List<OriginalVideo> videos) {
    return GridView.builder(
      padding: const EdgeInsets.all(8.0),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        childAspectRatio: 0.9,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: videos.length,
      itemBuilder: (context, index) {
        final video = videos[index];
        return _buildVideoGridTile(context, video);
      },
    );
  }

  Widget _buildVideoListTile(BuildContext context, OriginalVideo video) {
    final appState = context.read<AppState>();
    final clipCount =
        appState.clips.where((c) => c.videoPath == video.path).length;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: ListTile(
        leading: SizedBox(
          width: 80,
          child: VideoThumbnail(video: video),
        ),
        title: Text(video.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
            'Duration: ${video.duration != null ? _formatDuration(video.duration!) : "..."}  |  Clips: $clipCount'),
        trailing: _buildVideoMenuButton(context, video),
        onTap: () => _navigateToClipEditor(context, video),
      ),
    );
  }

  Widget _buildVideoGridTile(BuildContext context, OriginalVideo video) {
    final appState = context.read<AppState>();
    final clipCount =
        appState.clips.where((c) => c.videoPath == video.path).length;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _navigateToClipEditor(context, video),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  VideoThumbnail(video: video),
                  if (video.duration != null)
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _formatDuration(video.duration!),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                video.name,
                style: const TextStyle(fontWeight: FontWeight.w500),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8.0, 0, 8.0, 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Clips: $clipCount',
                      style: Theme.of(context).textTheme.bodySmall),
                  SizedBox(
                    height: 24,
                    width: 24,
                    child: _buildVideoMenuButton(context, video, isCompact: true),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuButton<String> _buildVideoMenuButton(
      BuildContext context, OriginalVideo video,
      {bool isCompact = false}) {
    return PopupMenuButton<String>(
      icon: isCompact
          ? const Icon(Icons.more_vert, size: 16)
          : const Icon(Icons.more_vert),
      onSelected: (value) => _handleVideoAction(context, value, video),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'create_clip',
          child:
              ListTile(leading: Icon(Icons.content_cut), title: Text('Create Clips')),
        ),
        const PopupMenuItem(
          value: 'clip_from_whole',
          child: ListTile(
              leading: Icon(Icons.movie_creation_outlined),
              title: Text('Clip From Whole Video')),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'delete_video',
          child: ListTile(
              leading: Icon(Icons.delete_forever, color: Colors.red),
              title: Text('Delete Video', style: TextStyle(color: Colors.red))),
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final parts = d.toString().split('.').first.padLeft(8, '0').split(':');
    return '${parts[0]}:${parts[1]}:${parts[2]}';
  }

  Future<void> _pickAndAddVideos(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true,
    );
    if (result != null) {
      final appState = context.read<AppState>();
      for (final file in result.files) {
        if (file.path != null) {
          _addVideo(appState, file.path!);
        }
      }
    }
  }

  void _addVideo(AppState appState, String videoPath) {
    if (appState.originalVideos.any((v) => v.path == videoPath)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Video "${p.basename(videoPath)}" already exists.')),
      );
      return;
    }

    final video = OriginalVideo(
      id: 'vid_${videoPath.hashCode}',
      path: videoPath,
      name: p.basename(videoPath),
    );
    appState.addOriginalVideo(video); // AppState will handle metadata fetching
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('Added "${video.name}".'),
          backgroundColor: Colors.green),
    );
  }

  void _navigateToClipEditor(BuildContext context, OriginalVideo video) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ClipEditorScreen(video: video)),
    );
  }

  void _handleVideoAction(
      BuildContext context, String action, OriginalVideo video) {
    final appState = context.read<AppState>();
    switch (action) {
      case 'create_clip':
        _navigateToClipEditor(context, video);
        break;
      case 'clip_from_whole':
        appState.createClipFromWholeVideo(video);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Created clip from "${video.name}"'),
            backgroundColor: Colors.green));
        break;
      case 'delete_video':
        // TODO: Implement video deletion with confirmation
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Video deletion not yet implemented.')));
        break;
    }
  }
}
