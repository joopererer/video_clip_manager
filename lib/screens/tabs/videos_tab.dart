import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../utils/toast_utils.dart';
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
    final filteredVideos = appState.getFilteredVideos(
      searchQuery: widget.searchQuery,
    );

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
    AppState appState,
    List<OriginalVideo> filteredVideos,
  ) {
    final totalDuration = filteredVideos.fold<Duration>(
      Duration.zero,
      (sum, v) => sum + (v.duration ?? Duration.zero),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
      child: Row(
        children: [
          _buildInfoItem('Videos', '${filteredVideos.length}', Icons.movie),
          const SizedBox(width: 24),
          _buildInfoItem(
            'Total Duration',
            _formatDuration(totalDuration),
            Icons.access_time,
          ),
          const Spacer(),
          const Text('View:'),
          IconButton(
            tooltip: appState.videosIsGridView
                ? 'Switch to List View'
                : 'Switch to Grid View',
            icon: Icon(
              appState.videosIsGridView ? Icons.list : Icons.grid_view,
            ),
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
          const Icon(
            Icons.video_library_outlined,
            size: 64,
            color: Colors.grey,
          ),
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
    final clipCount = appState.clips
        .where((c) => c.videoPath == video.path)
        .length;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      clipBehavior: Clip.antiAlias, // 让 Card 内部的 InkWell 效果更好看
      child: InkWell(
        // 使用 InkWell 来替代 ListTile 的 onTap 和水波纹效果
        onTap: () => _navigateToClipEditor(context, video),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              // 预览图区域
              SizedBox(
                width: 100,
                height: 75,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4.0),
                  child: VideoThumbnail(video: video),
                ),
              ),
              const SizedBox(width: 16),
              // 中间文字区域 (自动填充剩余空间)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Duration: ${video.duration != null ? _formatDuration(video.duration!) : "..."}  |  Clips: $clipCount',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),

              // 右侧菜单按钮
              _buildVideoMenuButton(context, video),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoGridTile(BuildContext context, OriginalVideo video) {
    final appState = context.read<AppState>();
    final clipCount = appState.clips
        .where((c) => c.videoPath == video.path)
        .length;

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
                          horizontal: 4,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _formatDuration(video.duration!),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
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
                  Text(
                    'Clips: $clipCount',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  SizedBox(
                    height: 24,
                    width: 24,
                    child: _buildVideoMenuButton(
                      context,
                      video,
                      isCompact: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuButton<String> _buildVideoMenuButton(
    BuildContext context,
    OriginalVideo video, {
    bool isCompact = false,
  }) {
    return PopupMenuButton<String>(
      icon: isCompact
          ? const Icon(Icons.more_vert, size: 16)
          : const Icon(Icons.more_vert),
      onSelected: (value) => _handleVideoAction(context, value, video),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'create_clip',
          child: ListTile(
            leading: Icon(Icons.content_cut),
            title: Text('Create Clips'),
          ),
        ),
        const PopupMenuItem(
          value: 'clip_from_whole',
          child: ListTile(
            leading: Icon(Icons.movie_creation_outlined),
            title: Text('Clip From Whole Video'),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'delete_video',
          child: ListTile(
            leading: Icon(Icons.delete_forever, color: Colors.red),
            title: Text('Delete Video', style: TextStyle(color: Colors.red)),
          ),
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
      ToastUtils.showWarning(
        context,
        'Video "${p.basename(videoPath)}" already exists.',
      );
      return;
    }

    final video = OriginalVideo(
      id: 'vid_${videoPath.hashCode}',
      path: videoPath,
      name: p.basename(videoPath),
    );
    appState.addOriginalVideo(video); // AppState will handle metadata fetching
    ToastUtils.showSuccess(context, 'Added "${video.name}".');
  }

  void _navigateToClipEditor(BuildContext context, OriginalVideo video) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ClipEditorScreen(video: video)),
    );
  }

  void _handleVideoAction(
    BuildContext context,
    String action,
    OriginalVideo video,
  ) {
    final appState = context.read<AppState>();
    switch (action) {
      case 'create_clip':
        _navigateToClipEditor(context, video);
        break;
      case 'clip_from_whole':
        appState.createClipFromWholeVideo(video);
        ToastUtils.showSuccess(context, 'Created clip from "${video.name}"');
        break;
      case 'delete_video':
        _deleteVideo(context, video);
        break;
    }
  }

  void _deleteVideo(BuildContext context, OriginalVideo video) {
    final appState = context.read<AppState>();
    final clipCount = appState.clips
        .where((c) => c.videoPath == video.path)
        .length;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Confirm Video Deletion',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: 400, // 固定宽度
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to delete "${video.name}"?',
                style: const TextStyle(fontSize: 16),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              if (clipCount > 0) ...[
                Text(
                  'This video has $clipCount associated clips.',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Choose deletion option:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ] else ...[
                Text(
                  'This video has no associated clips.',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          if (clipCount > 0) ...[
            TextButton(
              onPressed: () {
                appState.deleteVideo(video.id, deleteClips: false);
                Navigator.of(ctx).pop();
                ToastUtils.showSuccess(
                  context,
                  'Deleted video "${video.name}" (clips preserved)',
                );
              },
              child: const Text('Delete Video Only'),
            ),
            TextButton(
              onPressed: () {
                appState.deleteVideo(video.id, deleteClips: true);
                Navigator.of(ctx).pop();
                ToastUtils.showSuccess(
                  context,
                  'Deleted video "${video.name}" and $clipCount clips',
                );
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete Video & Clips'),
            ),
          ] else ...[
            TextButton(
              onPressed: () {
                appState.deleteVideo(video.id, deleteClips: false);
                Navigator.of(ctx).pop();
                ToastUtils.showSuccess(
                  context,
                  'Deleted video "${video.name}"',
                );
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete Video'),
            ),
          ],
        ],
      ),
    );
  }
}
