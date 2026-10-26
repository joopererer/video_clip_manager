import 'dart:async';
import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../services/preview_service.dart';
import '../services/screenshot_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/toast_utils.dart';
import '../widgets/ai_settings_dialog.dart';
import '../widgets/common/app_header.dart';
import '../widgets/common/app_sidebar.dart';
import 'settings/external_scrapers_settings_screen.dart';
import 'tabs/clips_tab.dart';
import 'tabs/playlists_tab.dart';
import 'tabs/videos_tab.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentTabIndex = 0;
  bool? _userCollapsedOverride;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isDraggingFile = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(
      () => setState(() => _searchQuery = _searchController.text),
    );
    _startGlobalPreGeneration();
  }

  /// 启动全局预览预生成
  Future<void> _startGlobalPreGeneration() async {
    if (kDebugMode) {
      print('MainScreen: _startGlobalPreGeneration called');
    }

    // 延迟启动，避免与界面初始化冲突
    await Future.delayed(const Duration(seconds: 3));

    if (!mounted) {
      if (kDebugMode) {
        print('MainScreen: Widget not mounted, aborting global pre-generation');
      }
      return;
    }

    final appState = context.read<AppState>();

    // 收集所有视频路径：OriginalVideo + VideoClip
    final Set<String> allVideoPaths = {};

    for (final video in appState.originalVideos) {
      allVideoPaths.add(video.path);
    }

    for (final clip in appState.clips) {
      allVideoPaths.add(clip.videoPath);
    }

    final videoPaths = allVideoPaths.toList();

    if (kDebugMode) {
      print(
        'MainScreen: Found ${videoPaths.length} unique videos (${appState.originalVideos.length} original + ${appState.clips.length} clips)',
      );
    }

    if (videoPaths.isNotEmpty) {
      if (kDebugMode) {
        print('MainScreen: Loading existing cache first...');
      }

      await PreviewService().loadExistingCache();

      if (kDebugMode) {
        print(
          'MainScreen: Starting global pre-generation for ${videoPaths.length} videos',
        );
      }

      PreviewService().startGlobalPreGeneration(videoPaths);
    } else {
      if (kDebugMode) {
        print('MainScreen: No videos found, skipping global pre-generation');
      }
    }
  }

  @override
  void dispose() {
    PreviewService().stopGlobalPreGeneration();
    _searchController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _executeSemanticSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    final appState = context.read<AppState>();
    final modelDir = await appState.aiService.resolveEmbeddingModelDir();
    if (modelDir == null) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.auto_awesome, color: AppColors.primary),
              SizedBox(width: 8),
              Text('语义检索模型未就绪'),
            ],
          ),
          content: const Text(
            '自然语言跨模态视频画面检索需要本地嵌入模型 (EmbeddingGemma 2，约 530MB)。\n\n检测到当前尚未下载该模型，是否前往 AI 设置一键下载？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('稍后再说'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('立即前往下载'),
              onPressed: () {
                Navigator.pop(ctx);
                showDialog(
                  context: context,
                  builder: (_) => const AiSettingsDialog(),
                );
              },
            ),
          ],
        ),
      );
      return;
    }

    await appState.performSemanticSearch(query: trimmed, modelDir: modelDir);

    if (!mounted) return;
    if (appState.lastSemanticError != null) {
      ToastUtils.showWarning(
        context,
        'AI 语义检索异常: ${appState.lastSemanticError}',
      );
    } else if (appState.semanticScores.isEmpty) {
      ToastUtils.showInfo(context, '未匹配到相似度高于阈值的视频帧');
    } else {
      ToastUtils.showSuccess(
        context,
        '✨ 语义检索成功！命中 ${appState.semanticScores.length} 个相关片段（已高亮最佳帧）',
      );
    }
  }

  void _handleVideoDrop(List<XFile> files) {
    final appState = context.read<AppState>();

    for (final file in files) {
      final p = file.path.toLowerCase();
      if (p.endsWith('.mp4') ||
          p.endsWith('.avi') ||
          p.endsWith('.mkv') ||
          p.endsWith('.mov') ||
          p.endsWith('.wmv') ||
          p.endsWith('.flv') ||
          p.endsWith('.webm')) {
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

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: AppColors.primary),
            SizedBox(width: 8),
            Text('关于 Video Clip Manager'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Video Clip Manager',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text('版本: 1.0.1 (Dark Media Workspace)'),
            SizedBox(height: 4),
            Text('作者: AI Assistant'),
            SizedBox(height: 4),
            Text('说明: 现代深色高性能本地与在线视频片段管理工作台'),
            SizedBox(height: 8),
            Text('核心能力:', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 4),
            Text('• 视频精准软剪切与无损片段标记'),
            Text('• 播放列表时间轴编排与事务编辑'),
            Text('• 多色系标签分类与星级评分系统'),
            Text('• 全局后台缩略图异步秒级预生成'),
            Text('• 本地 EmbeddingGemma 2 离线跨模态语义检索'),
            Text('• 在线流媒体解析与外部平台元数据嗅探'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  String _getTitleForTab(int index) {
    switch (index) {
      case 0:
        return '片段库';
      case 1:
        return '原始视频';
      case 2:
        return '播放列表';
      default:
        return 'Video Clip Manager';
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.background,
      body: Stack(
        children: [
          // 响应式主工作台 Shell (侧边栏 + 顶栏 + 内容区)
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 1050;
              final isSidebarCollapsed =
                  isNarrow || (_userCollapsedOverride ?? false);

              return Row(
                children: [
                  // 1. 左侧导航边栏 (208px / 64px 折叠)
                  AppSidebar(
                    currentIndex: _currentTabIndex,
                    onIndexChanged: (index) {
                      setState(() {
                        _currentTabIndex = index;
                      });
                    },
                    isCollapsed: isSidebarCollapsed,
                    onToggleCollapse: isNarrow
                        ? null
                        : () {
                            setState(() {
                              _userCollapsedOverride = !isSidebarCollapsed;
                            });
                          },
                    onOpenAiSettings: () {
                      showDialog(
                        context: context,
                        builder: (context) => const AiSettingsDialog(),
                      );
                    },
                    onOpenScraperSettings: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const ExternalScrapersSettingsScreen(),
                        ),
                      );
                    },
                    onOpenAbout: _showAboutDialog,
                    onSwitchDb: () async {
                      final result = await appState.switchDatabase();
                      _showSnackBar(result);
                    },
                    currentDbName: path.basename(appState.currentDbPath),
                  ),

                  // 2. 右侧主要工作区 (顶栏 + 内容区)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 顶部约 60px 工具栏
                        AppHeader(
                          title: _getTitleForTab(_currentTabIndex),
                          searchController: _searchController,
                          onSearchChanged: (val) {
                            setState(() {
                              _searchQuery = val;
                            });
                          },
                          onSearchSubmitted: (val) {
                            _executeSemanticSearch(val);
                          },
                          onClearSearch: () {
                            appState.clearSemanticSearch();
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                          isSemanticSearching: appState.isSemanticSearching,
                          hasSemanticScores: appState.semanticScores.isNotEmpty,
                          onTriggerSemanticSearch: () =>
                              _executeSemanticSearch(_searchQuery),
                          onRefreshThumbnails: () async {
                            await appState.forceRefreshThumbnails();
                            _showSnackBar(
                              "All thumbnails are being refreshed.",
                            );
                          },
                          onImportMerge: () async {
                            final result = await appState.importAndMergeClips();
                            _showSnackBar(result);
                          },
                          onSwitchDb: () async {
                            final result = await appState.switchDatabase();
                            _showSnackBar(result);
                          },
                          onOpenAiSettings: () {
                            showDialog(
                              context: context,
                              builder: (context) => const AiSettingsDialog(),
                            );
                          },
                          onOpenScraperSettings: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const ExternalScrapersSettingsScreen(),
                              ),
                            );
                          },
                          onOpenAbout: _showAboutDialog,
                          searchStatus: appState.searchStatus,
                          isNarrow: constraints.maxWidth < 1050,
                        ),

                        // 内容主展示区 (支持外部文件拖拽导入与 IndexedStack 保持各 Tab 状态)
                        Expanded(
                          child: DropTarget(
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
                                IndexedStack(
                                  index: _currentTabIndex,
                                  children: [
                                    ClipsTab(
                                      onClearSearch: () =>
                                          _searchController.clear(),
                                      onOpenVideos: () =>
                                          setState(() => _currentTabIndex = 1),
                                      searchQuery: _searchQuery,
                                      selectedTags: appState.selectedTags,
                                      selectedRating: appState.selectedRating,
                                      selectedFavorite:
                                          appState.selectedFavorite,
                                    ),
                                    VideosTab(
                                      searchQuery: _searchQuery,
                                      selectedTags: appState.selectedTags,
                                      selectedRating: appState.selectedRating,
                                      selectedFavorite:
                                          appState.selectedFavorite,
                                    ),
                                    PlaylistsTab(searchQuery: _searchQuery),
                                  ],
                                ),

                                // 拖拽悬停视觉提示
                                if (_isDraggingFile)
                                  Container(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.25,
                                    ),
                                    child: Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 32,
                                          vertical: 24,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colors.surfaceElevated,
                                          borderRadius: BorderRadius.circular(
                                            AppRadius.modal,
                                          ),
                                          border: Border.all(
                                            color: AppColors.primary,
                                            width: 1.5,
                                          ),
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.cloud_upload_outlined,
                                              size: 56,
                                              color: AppColors.primary,
                                            ),
                                            const SizedBox(
                                              height: AppSpacing.sm,
                                            ),
                                            Text(
                                              '释放文件以添加视频到媒体库',
                                              style: AppTypography.subtitle
                                                  .copyWith(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),

                                // 全局耗时任务加载遮罩
                                if (appState.isLoading ||
                                    appState.isSaving ||
                                    appState.isGeneratingThumbnails)
                                  Container(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    child: Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 32,
                                          vertical: 24,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colors.surfaceElevated,
                                          borderRadius: BorderRadius.circular(
                                            AppRadius.md,
                                          ),
                                          border: Border.all(
                                            color: colors.borderSubtle,
                                          ),
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const SizedBox(
                                              width: 32,
                                              height: 32,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 3,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                            const SizedBox(
                                              height: AppSpacing.md,
                                            ),
                                            Text(
                                              appState.isSaving
                                                  ? '正在保存项目数据…'
                                                  : (appState
                                                            .isGeneratingThumbnails
                                                        ? '正在后台生成缩略图…'
                                                        : '正在加载…'),
                                              style: AppTypography.body
                                                  .copyWith(
                                                    color: colors.textPrimary,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
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
              );
            },
          ),

          // 关键不可变机制：保持 ScreenshotService 运行所需的离屏 Video 宿主
          Positioned(
            left: -2,
            top: -2,
            width: 1,
            height: 1,
            child: Opacity(
              opacity: 0.0,
              child: Video(controller: ScreenshotService().videoController),
            ),
          ),
        ],
      ),
    );
  }
}
