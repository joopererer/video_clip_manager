import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:desktop_drop/desktop_drop.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../player/clip_editor_screen.dart';
import '../../widgets/video_thumbnail.dart';
import '../../services/video_metadata_service.dart';
import '../../widgets/draggable_video_source.dart';

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
  bool _isProcessingMetadata = false;
  bool _isDraggingFile = false;

  @override
  void initState() {
    super.initState();
    // 只在需要时处理视频元数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _processVideoMetadataIfNeeded();
    });
  }

  Future<void> _processVideoMetadataIfNeeded() async {
    final appState = context.read<AppState>();

    // 检查是否有视频需要处理元数据
    final videosNeedingMetadata = appState.originalVideos
        .where((v) => v.duration == null || v.thumbnailPath == null)
        .toList();

    if (videosNeedingMetadata.isNotEmpty) {
      if (!mounted) return;
      setState(() => _isProcessingMetadata = true);

      try {
        await appState.processVideoMetadata();
      } finally {
        if (mounted) {
          setState(() => _isProcessingMetadata = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    final filteredVideos = appState.getFilteredVideos(
      searchQuery: widget.searchQuery,
    );

    return Scaffold(
      body: DropTarget(
        // <-- 1. 使用 desktop_drop 的 DropTarget 包裹
        onDragDone: (details) {
          // 当外部文件被放下时触发
          for (final file in details.files) {
            // 只处理视频文件
            final path = file.path.toLowerCase();
            if (path.endsWith('.mp4') ||
                path.endsWith('.mkv') ||
                path.endsWith('.mov')) {
              _addVideoFromPath(file.path);
            }
          }
          setState(() {
            _isDraggingFile = false;
          });
        },
        onDragEntered: (details) {
          setState(() {
            _isDraggingFile = true;
          });
        },
        onDragExited: (details) {
          setState(() {
            _isDraggingFile = false;
          });
        },
        child: Column(
          // <-- 你原来的 Column
          children: [
            _buildVideoInfoBar(appState, filteredVideos),
            Expanded(
              child: Stack(
                // <-- 2. 使用 Stack 来显示覆盖层
                children: [
                  _buildDragTarget(
                    // 这是你原有的 DragTarget，处理应用内拖拽
                    child: filteredVideos.isEmpty
                        ? _buildEmptyState()
                        : _buildVideoList(filteredVideos, appState),
                  ),
                  if (_isDraggingFile) // <-- 3. 当有外部文件拖入时显示覆盖层
                    Container(
                      color: Colors.blue.withValues(alpha: 0.3),
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.cloud_upload,
                              size: 64,
                              color: Colors.blue,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Drop video here to add',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.blue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addNewVideo(context),
        label: const Text('Add Video'),
        icon: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildVideoInfoBar(
    AppState appState,
    List<OriginalVideo> filteredVideos,
  ) {
    final totalDuration = filteredVideos
        .where((v) => v.duration != null)
        .fold<Duration>(Duration.zero, (sum, v) => sum + v.duration!);

    final totalSize = filteredVideos.length;
    final totalClips = appState.clips.length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: Colors.blue.shade200, width: 0.5),
      ),
      child: Row(
        children: [
          // 视频统计信息
          Expanded(
            child: Row(
              children: [
                _buildInfoItem('Videos', '$totalSize', Icons.movie),
                const SizedBox(width: 16),
                _buildInfoItem(
                  'Duration',
                  _formatDuration(totalDuration),
                  Icons.access_time,
                ),
                const SizedBox(width: 16),
                _buildInfoItem('Clips', '$totalClips', Icons.cut),
              ],
            ),
          ),

          // 视图模式切换
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.blue.shade200, width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('View:', style: TextStyle(fontSize: 12)),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  icon: Icon(
                    appState.videosIsGridView ? Icons.list : Icons.grid_view,
                    size: 18,
                  ),
                  onPressed: () =>
                      appState.setVideosViewMode(!appState.videosIsGridView),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.blue.shade600),
        const SizedBox(width: 4),
        Text(
          '$label: $value',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }

  Widget _buildDragTarget({required Widget child}) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (data) {
        // 现在只用检查是否为应用内拖拽的视频即可
        final isAccepted = data.data.startsWith('video:');
        debugPrint('Internal DragTarget onWillAccept: $isAccepted');
        return isAccepted;
      },
      onAcceptWithDetails: (data) {
        // 应用内拖拽的视频被放下时触发
        debugPrint('DragTarget onAcceptWithDetails: ${data.data}');
        final videoPath = data.data.substring(6); // 移除 "video:" 前缀
        debugPrint('Adding video from internal drag: $videoPath');

        // 注意：这里的逻辑是重新添加视频，你的代码会显示 "video already exists"。
        // 这可能不是你最终想要的行为，但我们暂时保持你原有的实现。
        _addVideoFromPath(videoPath);
      },
      builder: (context, candidateData, rejectedData) {
        // 这个 builder 现在只为应用内拖拽显示覆盖层
        // 外部文件拖拽的覆盖层由 _isDraggingFile 控制
        return Stack(
          children: [
            child,
            if (candidateData.isNotEmpty) // 当内部视频拖到上方时显示
              Container(
                color: Colors.blue.withValues(alpha: 0.3), // 和外部拖拽保持一致
                child: const Center(
                  child: Icon(
                    Icons.add_circle_outline,
                    size: 64,
                    color: Colors.blue,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.movie_creation_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'No videos found',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            'Add videos by clicking the + button or drag files here',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoList(List<OriginalVideo> videos, AppState appState) {
    if (_isProcessingMetadata) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Processing video metadata...'),
          ],
        ),
      );
    }

    return appState.videosIsGridView
        ? _buildGridView(videos, appState)
        : _buildListView(videos, appState);
  }

  Widget _buildListView(List<OriginalVideo> videos, AppState appState) {
    return ListView.builder(
      itemCount: videos.length,
      itemBuilder: (context, index) {
        final video = videos[index];
        final clipsFromVideo = appState.clips
            .where((c) => c.videoPath == video.path)
            .toList();

        return _buildVideoListTile(video, clipsFromVideo, appState);
      },
    );
  }

  Widget _buildGridView(List<OriginalVideo> videos, AppState appState) {
    return GridView.builder(
      padding: const EdgeInsets.all(8.0),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        childAspectRatio: 0.85,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: videos.length,
      itemBuilder: (context, index) {
        final video = videos[index];
        final clipsFromVideo = appState.clips
            .where((c) => c.videoPath == video.path)
            .toList();

        return _buildVideoGridTile(video, clipsFromVideo, appState);
      },
    );
  }

  Widget _buildVideoListTile(
    OriginalVideo video,
    List<VideoClip> clipsFromVideo,
    AppState appState,
  ) {
    return DraggableVideoSource(
      videoPath: video.path,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: ListTile(
          leading: SizedBox(
            width: 60,
            height: 60,
            child: VideoThumbnail(
              video: video,
              size: 60,
              dbPath: appState.currentDbFullPath,
            ),
          ),
          title: Text(
            video.name,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (video.duration != null)
                Text('Duration: ${_formatDuration(video.duration!)}'),
              Text('Clips: ${clipsFromVideo.length}'),
            ],
          ),
          trailing: IconButton(
            icon: const Icon(Icons.add_box),
            onPressed: () => _addNewClip(context, video),
            tooltip: 'Add new clip',
          ),
          onTap: () => _addNewClip(context, video),
        ),
      ),
    );
  }

  Widget _buildVideoGridTile(
    OriginalVideo video,
    List<VideoClip> clipsFromVideo,
    AppState appState,
  ) {
    return DraggableVideoSource(
      videoPath: video.path,
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.all(4.0),
        child: InkWell(
          onTap: () => _addNewClip(context, video),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8),
                    ),
                    color: Colors.grey.shade200,
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(8),
                        ),
                        child: _buildThumbnail(video),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${clipsFromVideo.length} clips',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      if (video.duration != null)
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _formatDuration(video.duration!),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      video.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (video.metadata.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _buildMetadataChips(video, isGrid: true),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(OriginalVideo video) {
    if (video.thumbnailPath != null) {
      // 获取 AppState 来访问当前数据库路径和 ThumbnailService
      final appState = context.read<AppState>();

      // 构建完整的缩略图路径
      String fullThumbPath;
      if (!video.thumbnailPath!.contains('\\') &&
          !video.thumbnailPath!.contains('/')) {
        // 相对路径（只有文件名），构建完整路径
        if (appState.currentDbFullPath != null) {
          fullThumbPath = appState.thumbnailService.buildThumbnailPath(
            appState.currentDbFullPath!,
            video.thumbnailPath!,
          );
        } else {
          // 没有数据库路径，无法构建完整路径
          return _buildFallback(video);
        }
      } else {
        // 完整路径，直接使用
        fullThumbPath = video.thumbnailPath!;
      }

      final file = File(fullThumbPath);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (context, error, stackTrace) {
            debugPrint('Error loading thumbnail: $error');
            return _buildFallback(video);
          },
        );
      }
    }
    return _buildFallback(video);
  }

  Widget _buildFallback(OriginalVideo video) {
    return Container(
      color: Colors.grey.shade300,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.movie_creation_outlined,
            size: 40,
            color: Colors.grey.shade600,
          ),
          if (video.duration != null) ...[
            const SizedBox(height: 4),
            Text(
              _formatDuration(video.duration!),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetadataChips(OriginalVideo video, {bool isGrid = false}) {
    final metadata = VideoMetadata(metadata: video.metadata);
    final chips = <Widget>[];

    if (metadata.actors.isNotEmpty) {
      chips.add(
        isGrid
            ? _buildCompactChip(metadata.actors.first, Colors.blue.shade100)
            : Chip(
                label: Text(metadata.actors.first),
                backgroundColor: Colors.blue.shade100,
                labelStyle: const TextStyle(fontSize: 10),
              ),
      );
    }

    if (metadata.year != null) {
      chips.add(
        isGrid
            ? _buildCompactChip(metadata.year.toString(), Colors.green.shade100)
            : Chip(
                label: Text(metadata.year.toString()),
                backgroundColor: Colors.green.shade100,
                labelStyle: const TextStyle(fontSize: 10),
              ),
      );
    }

    if (metadata.series != null) {
      chips.add(
        isGrid
            ? _buildCompactChip(metadata.series!, Colors.orange.shade100)
            : Chip(
                label: Text(metadata.series!),
                backgroundColor: Colors.orange.shade100,
                labelStyle: const TextStyle(fontSize: 10),
              ),
      );
    }

    return Wrap(spacing: 4, runSpacing: 4, children: chips);
  }

  Widget _buildCompactChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _addNewVideo(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true,
    );

    if (result != null && result.files.isNotEmpty) {
      for (final file in result.files) {
        if (file.path != null) {
          await _addVideoFromPath(file.path!);
        }
      }
    }
  }

  Future<void> _addVideoFromPath(String videoPath) async {
    debugPrint('_addVideoFromPath called with: $videoPath');
    final appState = context.read<AppState>();
    final videoName = p.basename(videoPath);
    final videoId = 'vid_${videoPath.hashCode}';
    debugPrint('Video name: $videoName, ID: $videoId');

    // 检查视频是否已存在
    if (appState.originalVideos.any((v) => v.path == videoPath)) {
      debugPrint('Video already exists: $videoPath');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Video "$videoName" already exists')),
      );
      return;
    }

    final video = OriginalVideo(id: videoId, path: videoPath, name: videoName);

    // 添加到视频列表
    appState.addOriginalVideo(video);

    // 处理元数据
    await appState.updateVideoMetadata(videoId);
  }

  Future<void> _addNewClip(BuildContext context, OriginalVideo video) async {
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ClipEditorScreen(video: video)),
    );
  }
}
