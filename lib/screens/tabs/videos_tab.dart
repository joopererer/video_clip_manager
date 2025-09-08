import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../services/online_video_service.dart';
import '../../utils/toast_utils.dart';
import '../../widgets/video_thumbnail.dart';
import '../../widgets/online_video_add_dialog.dart';
import '../player/clip_editor_screen.dart';
import '../player/online_clip_editor_screen.dart';
import '../add_online_video_screen.dart';

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
    final mixedVideos = appState.getMixedVideos(
      searchQuery: widget.searchQuery,
    );

    return Scaffold(
      body: Column(
        children: [
          _buildVideoInfoBar(appState, mixedVideos),
          Expanded(
            child: mixedVideos.isEmpty
                ? _buildEmptyState(context)
                : appState.videosIsGridView
                ? _buildGridView(mixedVideos)
                : _buildListView(mixedVideos),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddVideoOptions(context),
        label: const Text('Add Videos'),
        icon: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildVideoInfoBar(
    AppState appState,
    List<dynamic> mixedVideos,
  ) {
    final localVideos = mixedVideos.where((v) => v['type'] == 'local').length;
    final onlineVideos = mixedVideos.where((v) => v['type'] == 'online').length;
    
    final totalDuration = mixedVideos.fold<Duration>(
      Duration.zero,
      (sum, v) {
        if (v['type'] == 'local') {
          final video = v['video'] as OriginalVideo;
          return sum + (video.duration ?? Duration.zero);
        } else {
          final video = v['video'] as OnlineVideo;
          return sum + (video.duration ?? Duration.zero);
        }
      },
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Row(
        children: [
          _buildInfoItem('Total', '${mixedVideos.length}', Icons.movie),
          const SizedBox(width: 16),
          _buildInfoItem('Local', '$localVideos', Icons.folder),
          const SizedBox(width: 16),
          _buildInfoItem('Online', '$onlineVideos', Icons.cloud),
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
            onPressed: () => _showAddVideoOptions(context),
            icon: const Icon(Icons.add),
            label: const Text('Add Your First Video'),
          ),
        ],
      ),
    );
  }

  Widget _buildListView(List<dynamic> videos) {
    return ListView.builder(
      itemCount: videos.length,
      itemBuilder: (context, index) {
        final videoData = videos[index];
        return _buildVideoListTile(context, videoData);
      },
    );
  }

  Widget _buildGridView(List<dynamic> videos) {
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
        final videoData = videos[index];
        return _buildVideoGridTile(context, videoData);
      },
    );
  }

  Widget _buildVideoListTile(BuildContext context, dynamic videoData) {
    final appState = context.read<AppState>();
    final video = videoData['video'];
    final videoType = videoData['type'];
    
    int clipCount;
    if (videoType == 'local') {
      clipCount = appState.clips
          .where((c) => c.videoPath == video.path)
          .length;
    } else {
      clipCount = appState.getOnlineVideoClips(video.id).length;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _navigateToClipEditor(context, video),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              // 预览图区域
              SizedBox(
                width: 100,
                height: 75,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4.0),
                      child: VideoThumbnail(video: video),
                    ),
                    // 视频类型标识
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: videoType == 'online' ? Colors.blue : Colors.green,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          videoType == 'online' ? Icons.cloud : Icons.folder,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // 中间文字区域
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            videoType == 'local' ? video.name : video.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (videoType == 'online')
                          Text(
                            OnlineVideoService.getPlatformIcon(video.platform),
                            style: const TextStyle(fontSize: 16),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Duration: ${video.duration != null ? _formatDuration(video.duration!) : "..."}  |  Clips: $clipCount',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (videoType == 'online')
                      Text(
                        OnlineVideoService.getPlatformName(video.platform),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.blue,
                        ),
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

  Widget _buildVideoGridTile(BuildContext context, dynamic videoData) {
    final appState = context.read<AppState>();
    final video = videoData['video'];
    final videoType = videoData['type'];
    
    int clipCount;
    if (videoType == 'local') {
      clipCount = appState.clips
          .where((c) => c.videoPath == video.path)
          .length;
    } else {
      clipCount = appState.getOnlineVideoClips(video.id).length;
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _navigateToClipEditor(context, video),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 预览图区域
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
                          color: Colors.black.withValues(alpha: 0.6),
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
                  // 视频类型标识
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: videoType == 'online' ? Colors.blue : Colors.green,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(
                        videoType == 'online' ? Icons.cloud : Icons.folder,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (videoType == 'online')
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Text(
                        OnlineVideoService.getPlatformIcon(video.platform),
                        style: const TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            // 文字信息区域
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    videoType == 'local' ? video.name : video.title,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (videoType == 'online')
                    Text(
                      OnlineVideoService.getPlatformName(video.platform),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.blue,
                      ),
                    ),
                ],
              ),
            ),
            // 操作按钮区域
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
    dynamic video, {
    bool isCompact = false,
  }) {
    return PopupMenuButton<String>(
      icon: isCompact ? null : const Icon(Icons.more_vert),
      onSelected: (value) => _handleVideoAction(context, value, video),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'create_clip',
          child: Row(
            children: [
              Icon(Icons.content_cut),
              SizedBox(width: 8),
              Text('Create Clip'),
            ],
          ),
        ),
        if (video is OriginalVideo)
          const PopupMenuItem(
            value: 'clip_from_whole',
            child: Row(
              children: [
                Icon(Icons.video_library),
                SizedBox(width: 8),
                Text('Clip from Whole Video'),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'delete_video',
          child: Row(
            children: [
              Icon(Icons.delete, color: Colors.red),
              SizedBox(width: 8),
              Text('Delete Video', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );
  }

  void _navigateToClipEditor(BuildContext context, dynamic video) {
    if (video is OriginalVideo) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => ClipEditorScreen(video: video)),
      );
    } else if (video is OnlineVideo) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => OnlineClipEditorScreen(video: video),
        ),
      );
    }
  }

  void _handleVideoAction(
    BuildContext context,
    String action,
    dynamic video,
  ) {
    final appState = context.read<AppState>();
    switch (action) {
      case 'create_clip':
        _navigateToClipEditor(context, video);
        break;
      case 'clip_from_whole':
        if (video is OriginalVideo) {
          appState.createClipFromWholeVideo(video);
          ToastUtils.showSuccess(context, 'Created clip from "${video.name}"');
        } else if (video is OnlineVideo) {
          ToastUtils.showWarning(context, 'Clipping from online videos is not yet supported.');
        }
        break;
      case 'delete_video':
        _deleteVideo(context, video);
        break;
    }
  }

  void _deleteVideo(BuildContext context, dynamic video) {
    final appState = context.read<AppState>();
    
    if (video is OriginalVideo) {
      final clipCount = appState.clips
          .where((c) => c.videoPath == video.path)
          .length;
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Video'),
          content: Text(
            'Are you sure you want to delete "${video.name}"? This will also delete all $clipCount associated clips.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                appState.deleteOriginalVideo(video.id);
                Navigator.of(context).pop();
                ToastUtils.showSuccess(context, 'Video deleted successfully');
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
    } else if (video is OnlineVideo) {
      final clipCount = appState.getOnlineVideoClips(video.id).length;
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Online Video'),
          content: Text(
            'Are you sure you want to delete "${video.title}"? This will also delete all $clipCount associated clips.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                appState.deleteOnlineVideo(video.id);
                Navigator.of(context).pop();
                ToastUtils.showSuccess(context, 'Online video deleted successfully');
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
    }
  }

  void _showAddVideoOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Add Video',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.folder),
              title: const Text('Add Local Video'),
              subtitle: const Text('Select video files from your device'),
              onTap: () {
                Navigator.pop(context);
                _pickAndAddVideos(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud),
              title: const Text('Add Online Video'),
              subtitle: const Text('Add video from YouTube, Bilibili, etc.'),
              onTap: () {
                Navigator.pop(context);
                _showAddOnlineVideoScreen(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAddOnlineVideoScreen(BuildContext context) async {
    // 在对话框显示之前获取 AppState 引用，避免异步操作后 context 失效
    final appState = context.read<AppState>();
    
    try {
      final result = await showDialog<OnlineVideo>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AddOnlineVideoScreen(),
      );
      
      if (result != null) {
        try {
          await appState.addOnlineVideo(result);
          if (mounted) {
            ToastUtils.showSuccess(context, 'Online video added successfully!');
          }
        } catch (e) {
          if (mounted) {
            ToastUtils.showError(context, 'Failed to add video: $e');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ToastUtils.showError(context, 'Failed to add online video: $e');
      }
    }
  }

  void _pickAndAddVideos(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final appState = context.read<AppState>();
        final paths = result.files.map((file) => file.path!).toList();
        
        for (final path in paths) {
          final video = OriginalVideo(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: p.basename(path),
            path: path,
          );
          appState.addOriginalVideo(video);
        }

        ToastUtils.showSuccess(
          context,
          'Added ${paths.length} video(s) successfully!',
        );
      }
    } catch (e) {
      ToastUtils.showError(context, 'Failed to add videos: $e');
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    
    if (hours > 0) {
      return '${hours}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes}:${seconds.toString().padLeft(2, '0')}';
    }
  }
}
