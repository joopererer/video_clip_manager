import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:path/path.dart' as path;
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../utils/tag_utils.dart';
import '../services/preview_service.dart'; // 添加预览服务导入
import '../services/thumbnail_service.dart'; // 添加缩略图服务导入
import 'tabs/videos_tab.dart';
import 'tabs/clips_tab.dart';
import 'tabs/playlists_tab.dart';
import 'player/clip_playback_screen.dart';
import 'player/clip_editor_screen.dart';
import 'player/playlist_playback_screen.dart';
import '../widgets/video_import_dialog.dart';
import '../widgets/playlist_import_export_dialog.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isDraggingFile = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() {}); // 当tab切换时触发UI更新
    });
    _searchController.addListener(
      () => setState(() => _searchQuery = _searchController.text),
    );
    _startGlobalPreGeneration();
  }
  
  /// 启动全局预览预生成
  Future<void> _startGlobalPreGeneration() async {
    print('MainScreen: _startGlobalPreGeneration called');
    
    // 延迟启动，避免与界面初始化冲突
    await Future.delayed(Duration(seconds: 3));
    
    if (!mounted) {
      print('MainScreen: Widget not mounted, aborting global pre-generation');
      return;
    }
    
    final appState = context.read<AppState>();
    
    // 收集所有视频路径：OriginalVideo + VideoClip
    final Set<String> allVideoPaths = {};
    
    // 添加 OriginalVideo 路径
    for (final video in appState.originalVideos) {
      allVideoPaths.add(video.path);
    }
    
         // 添加 VideoClip 中的视频路径
     for (final clip in appState.clips) {
       allVideoPaths.add(clip.videoPath);
     }
     
     final videoPaths = allVideoPaths.toList();
     
     print('MainScreen: Found ${videoPaths.length} unique videos (${appState.originalVideos.length} original + ${appState.clips.length} clips)');
    print('MainScreen: Video paths: ${videoPaths.map((p) => p.split('/').last).join(', ')}');
    
    if (videoPaths.isNotEmpty) {
      print('MainScreen: Loading existing cache first...');
      
      // 首先加载已有的缓存文件到内存
      await PreviewService().loadExistingCache();
      
      print('MainScreen: Starting global pre-generation for ${videoPaths.length} videos');
      
      // 在后台启动全局预生成
      PreviewService().startGlobalPreGeneration(videoPaths);
    } else {
      print('MainScreen: No videos found, skipping global pre-generation');
    }
  }
  
  @override
  void dispose() {
    // 停止全局预生成
    PreviewService().stopGlobalPreGeneration();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _handleVideoDrop(List<XFile> files) {
    final appState = context.read<AppState>();

    for (final file in files) {
      final path = file.path.toLowerCase();
      if (path.endsWith('.mp4') ||
          path.endsWith('.avi') ||
          path.endsWith('.mkv') ||
          path.endsWith('.mov') ||
          path.endsWith('.wmv') ||
          path.endsWith('.flv') ||
          path.endsWith('.webm')) {
        _addVideoFromPath(file.path, appState);
      }
    }
  }

  Future<void> _addVideoFromPath(String videoPath, AppState appState) async {
    final videoName = path.basename(videoPath);
    final videoId = 'vid_${videoPath.hashCode}';

    if (appState.originalVideos.any((v) => v.path == videoPath)) {
      _showSnackBar('Video "$videoName" already exists');
      return;
    }

    final video = OriginalVideo(id: videoId, path: videoPath, name: videoName);

    appState.addOriginalVideo(video);
    await appState.updateVideoMetadata(videoId);

    _showSnackBar('Added video: $videoName');
  }

  void _showTagFilterDialog() {
    final appState = context.read<AppState>();
    showDialog(
      context: context,
      builder: (context) {
        final allTags = appState.allTags;
        List<String> tempSelectedTags = List.from(appState.selectedTags);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Filter by Tags'),
              content: SizedBox(
                width: double.maxFinite,
                child: allTags.isEmpty
                    ? const Text('No tags available.')
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: allTags.length,
                        itemBuilder: (context, index) {
                          final tag = allTags[index];
                          return CheckboxListTile(
                            title: buildTagText(tag),
                            value: tempSelectedTags.contains(tag),
                            onChanged: (isSelected) {
                              setDialogState(() {
                                if (isSelected == true) {
                                  tempSelectedTags.add(tag);
                                } else {
                                  tempSelectedTags.remove(tag);
                                }
                              });
                            },
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    appState.setSelectedTags(tempSelectedTags);
                    Navigator.of(context).pop();
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showRatingFilterDialog() {
    final appState = context.read<AppState>();
    int? tempSelectedRating = appState.selectedRating;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Filter by Rating'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Select rating to filter by:'),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('All Ratings'),
                        selected: tempSelectedRating == null,
                        onSelected: (selected) {
                          setDialogState(() {
                            tempSelectedRating = selected
                                ? null
                                : tempSelectedRating;
                          });
                        },
                      ),
                      ChoiceChip(
                        label: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.star_border,
                              size: 16,
                              color: Colors.grey,
                            ),
                            Text(' No Rating'),
                          ],
                        ),
                        selected: tempSelectedRating == 0,
                        onSelected: (selected) {
                          setDialogState(() {
                            tempSelectedRating = selected ? 0 : null;
                          });
                        },
                      ),
                      ...List.generate(5, (index) {
                        final rating = index + 1;
                        return ChoiceChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ...List.generate(
                                rating,
                                (starIndex) => const Icon(
                                  Icons.star,
                                  size: 16,
                                  color: Colors.amber,
                                ),
                              ),
                              Text(' $rating'),
                            ],
                          ),
                          selected: tempSelectedRating == rating,
                          onSelected: (selected) {
                            setDialogState(() {
                              tempSelectedRating = selected ? rating : null;
                            });
                          },
                        );
                      }),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    appState.setSelectedRating(tempSelectedRating);
                    Navigator.of(context).pop();
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showFavoriteFilterDialog() {
    final appState = context.read<AppState>();
    bool? tempSelectedFavorite = appState.selectedFavorite;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Filter by Favorite'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Select favorite status to filter by:'),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('All Clips'),
                        selected: tempSelectedFavorite == null,
                        onSelected: (selected) {
                          setDialogState(() {
                            tempSelectedFavorite = selected
                                ? null
                                : tempSelectedFavorite;
                          });
                        },
                      ),
                      ChoiceChip(
                        label: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.favorite, color: Colors.red),
                            SizedBox(width: 4),
                            Text('Favorites Only'),
                          ],
                        ),
                        selected: tempSelectedFavorite == true,
                        onSelected: (selected) {
                          setDialogState(() {
                            tempSelectedFavorite = selected ? true : null;
                          });
                        },
                      ),
                      ChoiceChip(
                        label: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.favorite_border, color: Colors.grey),
                            SizedBox(width: 4),
                            Text('Not Favorites'),
                          ],
                        ),
                        selected: tempSelectedFavorite == false,
                        onSelected: (selected) {
                          setDialogState(() {
                            tempSelectedFavorite = selected ? false : null;
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    appState.setSelectedFavorite(tempSelectedFavorite);
                    Navigator.of(context).pop();
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue),
            SizedBox(width: 8),
            Text('About Video Clip Manager'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Video Clip Manager',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text('Version: 1.0.0'),
            SizedBox(height: 4),
            Text('Author: AI Assistant'),
            SizedBox(height: 4),
            Text('Description: A powerful video clip management tool'),
            SizedBox(height: 8),
            Text(
              'Features:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 4),
            Text('• Video clip creation and editing'),
            Text('• Playlist management'),
            Text('• Tag-based organization'),
            Text('• Rating and favorite system'),
            Text('• Thumbnail generation'),
            Text('• Cross-platform support'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final thumbnailService = context.read<ThumbnailService>();

    return Scaffold(
      body: Stack(
        children: [
          // The main UI
          Scaffold(
            appBar: AppBar(
              title: Text(
                'Video Clip Manager (${appState.currentDbPath ?? "No DB"})',
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh All Thumbnails',
                  onPressed: () async {
                    await appState.forceRefreshThumbnails();
                    _showSnackBar("All thumbnails are being refreshed.");
                  },
                ),
                const SizedBox(width: 8),
                PopupMenuButton<int>(
                  onSelected: (item) async {
                    if (item == 0) {
                      final result = await appState.importAndMergeClips();
                      _showSnackBar(result);
                    } else if (item == 1) {
                      final result = await appState.switchDatabase();
                      _showSnackBar(result);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem<int>(
                      value: 0,
                      child: Text('Import & Merge JSON'),
                    ),
                    const PopupMenuItem<int>(
                      value: 1,
                      child: Text('Switch Database'),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  tooltip: 'About',
                  onPressed: _showAboutDialog,
                ),
              ],
              bottom: TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(icon: Icon(Icons.cut), text: 'Clips'),
                  Tab(icon: Icon(Icons.movie), text: 'Original Videos'),
                  Tab(icon: Icon(Icons.playlist_play), text: 'Playlists'),
                ],
              ),
            ),
            body: DropTarget(
              onDragDone: (details) {
                _handleVideoDrop(details.files);
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
              child: Stack(
                children: [
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            labelText: 'Search...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_tabController.index == 0 &&
                                      appState.selectedTags.isNotEmpty)
                                    Chip(
                                      label: Text(
                                        '${appState.selectedTags.length}',
                                      ),
                                      onDeleted: () =>
                                          appState.clearSelectedTags(),
                                    ),
                                  if (_tabController.index == 0 &&
                                      appState.selectedRating != null)
                                    Chip(
                                      label: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          appState.selectedRating == 0
                                              ? const Icon(
                                                  Icons.star_border,
                                                  size: 16,
                                                  color: Colors.grey,
                                                )
                                              : const Icon(
                                                  Icons.star,
                                                  size: 16,
                                                  color: Colors.amber,
                                                ),
                                          Text(
                                            appState.selectedRating == 0
                                                ? 'No Rating'
                                                : '${appState.selectedRating}',
                                          ),
                                        ],
                                      ),
                                      onDeleted: () =>
                                          appState.clearSelectedRating(),
                                    ),
                                  if (_tabController.index == 0 &&
                                      appState.selectedFavorite != null)
                                    Chip(
                                      label: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            appState.selectedFavorite!
                                                ? Icons.favorite
                                                : Icons.favorite_border,
                                            size: 16,
                                            color: appState.selectedFavorite!
                                                ? Colors.red
                                                : Colors.grey,
                                          ),
                                          Text(
                                            appState.selectedFavorite!
                                                ? 'Fav'
                                                : 'Not Fav',
                                          ),
                                        ],
                                      ),
                                      onDeleted: () =>
                                          appState.clearSelectedFavorite(),
                                    ),
                                if (_tabController.index == 0)
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.filter_list),
                                    onSelected: (value) {
                                      switch (value) {
                                        case 'tags':
                                          _showTagFilterDialog();
                                          break;
                                        case 'rating':
                                          _showRatingFilterDialog();
                                          break;
                                        case 'favorite':
                                          _showFavoriteFilterDialog();
                                          break;
                                        case 'clear_all':
                                          appState.clearAllFilters();
                                          break;
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem<String>(
                                        value: 'tags',
                                        child: Row(
                                          children: [
                                            Icon(Icons.label),
                                            SizedBox(width: 8),
                                            Text('Filter by Tags'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem<String>(
                                        value: 'rating',
                                        child: Row(
                                          children: [
                                            Icon(Icons.star),
                                            SizedBox(width: 8),
                                            Text('Filter by Rating'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem<String>(
                                        value: 'favorite',
                                        child: Row(
                                          children: [
                                            Icon(Icons.favorite),
                                            SizedBox(width: 8),
                                            Text('Filter by Favorite'),
                                          ],
                                        ),
                                      ),
                                      if (appState.selectedTags.isNotEmpty ||
                                          appState.selectedRating != null ||
                                          appState.selectedFavorite != null)
                                        const PopupMenuDivider(),
                                      if (appState.selectedTags.isNotEmpty ||
                                          appState.selectedRating != null ||
                                          appState.selectedFavorite != null)
                                        const PopupMenuItem<String>(
                                          value: 'clear_all',
                                          child: Row(
                                            children: [
                                              Icon(Icons.clear_all),
                                              SizedBox(width: 8),
                                              Text('Clear All Filters'),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                                                  if (_searchQuery.isNotEmpty)
                                    IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () => _searchController.clear(),
                                    ),
                                ],
                              ),
                            ),
                            border: const OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(8.0)),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            ClipsTab(
                              searchQuery: _searchQuery,
                              selectedTags: appState.selectedTags,
                              selectedRating: appState.selectedRating,
                              selectedFavorite: appState.selectedFavorite,
                            ),
                            VideosTab(
                              searchQuery: _searchQuery,
                              selectedTags: appState.selectedTags,
                              selectedRating: appState.selectedRating,
                              selectedFavorite: appState.selectedFavorite,
                            ),
                            PlaylistsTab(searchQuery: _searchQuery),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_isDraggingFile)
                    Container(
                      color: Colors.blue.withOpacity(0.3),
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
                              'Drop video files here to add',
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
                  if (appState.isLoading ||
                      appState.isSaving ||
                      appState.isGeneratingThumbnails)
                    Container(
                      color: Colors.black.withOpacity(0.5),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(
                              appState.isSaving
                                  ? 'Saving...'
                                  : (appState.isGeneratingThumbnails
                                        ? 'Generating Thumbnails...'
                                        : 'Loading...'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // This is the global, 1x1 pixel "drawing board" for screenshots
          Positioned(
            left: -1, // Use -1 instead of 0 to ensure it's fully off-screen
            top: -1,
            width: 1,
            height: 1,
            child: Opacity(
              opacity: 0.0, // Fully transparent
              child: Video(controller: thumbnailService.videoController),
            ),
          ),
          // This is the global, 1x1 pixel "drawing board" for preview screenshots
          Positioned(
            left: -2, // Use -2 to ensure it's fully off-screen and separate from thumbnail widget
            top: -2,
            width: 1,
            height: 1,
            child: Opacity(
              opacity: 0.0, // Fully transparent
              child: Video(controller: PreviewService().videoController),
            ),
          ),
        ],
      ),
    );
  }
}
