import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;

import '../../data/models.dart';
import '../../data/app_state.dart';
import '../tabs/clips_tab.dart';
import '../../utils/tag_utils.dart';
import '../../widgets/custom_progress_bar.dart'; // 添加自定义进度条导入
import '../../services/preview_service.dart'; // 添加预览服务导入

class ClipPlaybackScreen extends StatefulWidget {
  final VideoClip clip;
  final List<VideoClip>? allClips; // 用于导航功能
  final String searchQuery; // 当前搜索查询
  final List<String> selectedTags; // 当前选中的标签
  final int? selectedRating; // 当前选中的星级
  final bool? selectedFavorite; // 当前选中的收藏状态
  final SortOption currentSortOption;
  final Duration? initialSeekTime; // 当前排序选项

  const ClipPlaybackScreen({
    super.key,
    required this.clip,
    this.allClips,
    this.searchQuery = '',
    this.selectedTags = const [],
    this.selectedRating,
    this.selectedFavorite,
    this.currentSortOption = SortOption.dateAddedDesc,
      this.initialSeekTime,
  });

  @override
  State<ClipPlaybackScreen> createState() => _ClipPlaybackScreenState();
}

class _ClipPlaybackScreenState extends State<ClipPlaybackScreen> {
  // 播放器状态管理
  late Player mainPlayer;
  late VideoController mainController;

  // 播放器状态管理
  bool _isPlayerReady = false;
  bool _isInitializing = false;
  Timer? _recoveryTimer;
  bool _disposed = false;
  bool _isPlayerDisposed = false;
  bool _isSeeking = false; // 新增：seek锁定标志
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<bool>? _playingSubscription;
  bool _isPlaying = false;
  late VideoClip _currentClip; // 使用late关键字，在initState中初始化
  bool _showHints = false; // 控制提示显示
  bool _showCustomProgressBar = true; // 控制是否显示自定义进度条
  bool _showClipRelativeProgress = true; // 控制是否显示clip相对进度
  bool _isMuted = false; // 静音状态

  // 新增：全局焦点节点
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _currentClip = widget.clip; // 初始化当前clip
    mainPlayer = Player();
    mainController = VideoController(mainPlayer);
    _focusNode = FocusNode(); // 初始化焦点节点
    _initializePlayers();

    // 延迟请求焦点，确保组件完全初始化
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  Future<void> _initializePlayers() async {
    if (_isInitializing || _disposed) return;

    print('Initializing players for clip: ${_currentClip.name}'); // 调试信息

    setState(() {
      _isInitializing = true;
      _isPlayerReady = false;
    });

    try {
      // 确保播放器处于干净状态
      await _resetPlayers();

      // 初始化主播放器
      print('Opening main player with: ${_currentClip.videoPath}'); // 调试信息
      await mainPlayer.open(Media(_currentClip.videoPath), play: false);

      if (!mounted || _disposed) {
        print('Widget disposed during initialization, aborting'); // 调试信息
        return;
      }

      // 等待媒体加载完成（网络流/HLS 需要建立网络连接并解析分片，通常耗时 1~6 秒）
      Duration loadedDuration = mainPlayer.state.duration;
      if (loadedDuration == Duration.zero) {
        try {
          final isNetwork = _currentClip.videoPath.startsWith('http://') ||
              _currentClip.videoPath.startsWith('https://');
          final timeout = isNetwork
              ? const Duration(seconds: 12)
              : const Duration(seconds: 2);
          loadedDuration = await mainPlayer.stream.duration
              .firstWhere((d) => d > Duration.zero)
              .timeout(timeout);
        } catch (_) {
          loadedDuration = mainPlayer.state.duration;
        }
      }

      if (!mounted || _disposed) {
        print('Widget disposed during initialization, aborting'); // 调试信息
        return;
      }

      // 如果依然未能获取时长但已经有缓冲数据，也可以继续尝试
      if (loadedDuration == Duration.zero && mainPlayer.state.buffer == Duration.zero) {
        throw Exception('Main player failed to load media');
      }

      // 主播放器跳转到开始时间并开始播放
      print('Seeking main player to: ${_currentClip.startTime}'); // 调试信息
      final targetSeek = widget.initialSeekTime ?? _currentClip.startTime;
      if (targetSeek > Duration.zero) {
        await mainPlayer.seek(targetSeek);
        await Future.delayed(const Duration(milliseconds: 100));
      }

      print('Starting main player playback'); // 调试信息
      await mainPlayer.play();

      if (mounted && !_disposed) {
        setState(() {
          _isPlaying = true;
          _isPlayerReady = true;
          _isInitializing = false;
        });
        print('Players initialized successfully'); // 调试信息
      }

      // 预生成关键帧预览图
      // 智能预生成：检查全局缓存完成度，决定是否继续生成
      _smartPreGenerate();

      // 设置主播放器位置监听器
      _positionSubscription?.cancel();
      _positionSubscription = mainPlayer.stream.position.listen((position) {
        if (mounted &&
            !_disposed &&
            !_isSeeking &&
            _currentClip.endTime > Duration.zero &&
            position >= _currentClip.endTime) {
          print(
            'ClipPlaybackScreen: Position reached end time, pausing',
          ); // 调试信息
          _safePause();
        }
      });

      // 监听主播放器播放状态
      _playingSubscription?.cancel();
      _playingSubscription = mainPlayer.stream.playing.listen((playing) {
        if (mounted && !_disposed) {
          setState(() {
            _isPlaying = playing;
          });
        }
      });
    } catch (e) {
      print('Error during player initialization: $e'); // 调试信息
      if (mounted && !_disposed) {
        setState(() {
          _isInitializing = false;
          _isPlayerReady = false;
        });
        _scheduleRecovery();
      }
    }
  }

  // 新增：重置播放器状态
  Future<void> _resetPlayers() async {
    try {
      // 如果播放器已经打开，先暂停
      if (mainPlayer.state.playing) {
        await mainPlayer.pause();
      }

      // 等待一下确保暂停完成
      await Future.delayed(Duration(milliseconds: 100));
    } catch (e) {
      print('Error resetting players: $e'); // 调试信息
      // 继续执行，不要因为重置失败而阻止初始化
    }
  }

  void _scheduleRecovery() {
    _recoveryTimer?.cancel();
    _recoveryTimer = Timer(Duration(seconds: 3), () {
      if (mounted && !_disposed && !_isPlayerReady) {
        print('Attempting player recovery...'); // 调试信息
        _initializePlayers();
      }
    });
  }

  /// 智能预生成逻辑
  Future<void> _smartPreGenerate() async {
    if (widget.clip.videoPath == null) return;
    if (_currentClip.videoPath.startsWith('http://') ||
        _currentClip.videoPath.startsWith('https://')) {
      // 网络流/在线视频不执行本地关键帧提取，避免播放与抓帧在同一播放器上冲突
      return;
    }

    try {
      // 检查当前进度
      final progress = await PreviewService().getVideoProgress(
        widget.clip.videoPath!,
      );
      final remainingPercentage = 1.0 - progress;

      print(
        'ClipPlayback: Current progress: ${(progress * 100).toStringAsFixed(1)}%, remaining: ${(remainingPercentage * 100).toStringAsFixed(1)}%',
      );

      if (remainingPercentage > 0.05 && remainingPercentage <= 0.3) {
        // 剩余少于30%且未完成，继续生成并显示loading
        print(
          'ClipPlayback: Less than 30% remaining, continuing generation...',
        );
        await _continuePreGeneration();
      } else {
        print('ClipPlayback: Cache complete or more than 30% remaining, skipping generation');
      }
    } catch (e) {
      print('ClipPlayback: Error in smart pre-generation: $e');
    }
  }

  /// 继续预生成并显示loading
  Future<void> _continuePreGeneration() async {
    if (widget.clip.videoPath == null) return;

    try {
      // 暂停全局预生成
      PreviewService().pauseGlobalPreGeneration();

      // 显示loading状态
      _showLoadingPreview();

      // 获取视频时长
      final duration = mainPlayer.state.duration;
      if (duration == Duration.zero) {
        print('ClipPlayback: Cannot get video duration');
        return;
      }

      // 继续预生成
      await PreviewService().preGenerateKeyFrames(
        mainPlayer,
        widget.clip.videoPath!,
        duration,
      );

      print('ClipPlayback: Pre-generation completed');
    } catch (e) {
      print('ClipPlayback: Error continuing pre-generation: $e');
    } finally {
      // 在播放界面内不恢复全局预生成，避免后台抓帧争抢 Direct3D 纹理
    }
  }

  /// 显示loading预览状态
  void _showLoadingPreview() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('正在生成预览图...'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _safePause() async {
    if (!_isPlayerReady || _disposed) return;

    try {
      await mainPlayer.pause();
      if (mounted && !_disposed) {
        setState(() {
          _isPlaying = false;
        });
      }
    } catch (e) {
      print('Error during pause: $e'); // 调试信息
      _scheduleRecovery();
    }
  }

  Future<void> _safePlay() async {
    if (!_isPlayerReady || _disposed) return;

    try {
      await mainPlayer.play();
      if (mounted && !_disposed) {
        setState(() {
          _isPlaying = true;
        });
      }
    } catch (e) {
      print('Error during play: $e'); // 调试信息
      _scheduleRecovery();
    }
  }

  Future<void> _safeSeek(Duration position) async {
    if (!_isPlayerReady || _disposed) {
      print(
        'ClipPlaybackScreen: Cannot seek - player not ready or disposed',
      ); // 调试信息
      return;
    }

    if (_isSeeking) {
      print('ClipPlaybackScreen: Seek already in progress, ignoring'); // 调试信息
      return;
    }

    try {
      _isSeeking = true; // 设置seek锁定
      print(
        'ClipPlaybackScreen: Attempting to seek main player to $position',
      ); // 调试信息
      print(
        'ClipPlaybackScreen: Main player state - duration: ${mainPlayer.state.duration}, position: ${mainPlayer.state.position}, playing: ${mainPlayer.state.playing}',
      ); // 调试信息

      // 确保播放器处于可用状态
      if (mainPlayer.state.duration == Duration.zero) {
        print(
          'ClipPlaybackScreen: Main player duration is zero, attempting to recover...',
        ); // 调试信息
        await _initializePlayers();
        return;
      }

      // 执行seek操作
      await mainPlayer.seek(position);

      // 验证seek是否成功
      await Future.delayed(Duration(milliseconds: 200)); // 增加延迟确保seek完成
      final newPosition = mainPlayer.state.position;
      print(
        'ClipPlaybackScreen: Seek completed. New position: $newPosition, Target: $position',
      ); // 调试信息

      if ((newPosition - position).abs() < Duration(seconds: 1)) {
        print('ClipPlaybackScreen: Seek successful to: $position'); // 调试信息
      } else {
        print(
          'ClipPlaybackScreen: Seek may have failed. Expected: $position, Actual: $newPosition',
        ); // 调试信息
      }
    } catch (e) {
      print('ClipPlaybackScreen: Error during seek: $e'); // 调试信息
      _scheduleRecovery();
    } finally {
      // 延迟释放seek锁定，确保其他逻辑不会立即覆盖
      Future.delayed(Duration(milliseconds: 500), () {
        if (mounted && !_disposed) {
          _isSeeking = false;
          print('ClipPlaybackScreen: Seek lock released'); // 调试信息
        }
      });
    }
  }

  @override
  void dispose() {
    print('ClipPlaybackScreen disposing...'); // 调试信息
    _disposed = true;

    // 取消所有定时器和订阅
    _recoveryTimer?.cancel();
    _positionSubscription?.cancel();
    _playingSubscription?.cancel();

    // 释放焦点节点
    _focusNode.dispose();

    // 安全地停止和释放播放器
    _disposePlayers();

    super.dispose();
  }

  // 新增：安全的播放器释放方法
  Future<void> _disposePlayers() async {
    if (_isPlayerDisposed) return;
    _isPlayerDisposed = true;
    try {
      if (mainPlayer.state.playing) {
        await mainPlayer.pause();
      }
      await mainPlayer.dispose();
      print('Players disposed successfully'); // 调试信息
    } catch (e) {
      print('Error during player disposal: $e'); // 调试信息
    }
  }

  void _replay() async {
    if (!_isPlayerReady) return;
    await _safeSeek(_currentClip.startTime);
    await _safePlay();
  }

  void _togglePlayPause() async {
    if (!_isPlayerReady) return;
    if (_isPlaying) {
      await _safePause();
    } else {
      await _safePlay();
    }
  }

  // 修改导航逻辑，在同一窗口中切换clip
  void _navigateToClip(VideoClip? targetClip) async {
    if (targetClip != null && !_disposed) {
      // 取消之前的订阅
      await _positionSubscription?.cancel();
      await _playingSubscription?.cancel();

      // 暂停当前播放
      await _safePause();

      // 更新当前clip
      setState(() {
        _currentClip = targetClip;
        _isPlaying = false;
        _isPlayerReady = false;
      });

      // 重新初始化播放器
      await _initializePlayers();
    }
  }

  // 排序逻辑（与ClipsTab保持一致）
  List<VideoClip> _sortClips(List<VideoClip> clips) {
    final sortedClips = List<VideoClip>.from(clips);

    switch (widget.currentSortOption) {
      case SortOption.nameAsc:
        sortedClips.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        break;
      case SortOption.nameDesc:
        sortedClips.sort(
          (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()),
        );
        break;
      case SortOption.dateAddedAsc:
        sortedClips.sort((a, b) => a.id.compareTo(b.id)); // 假设ID按时间顺序
        break;
      case SortOption.dateAddedDesc:
        sortedClips.sort((a, b) => b.id.compareTo(a.id));
        break;
      case SortOption.ratingAsc:
        sortedClips.sort((a, b) => a.rating.compareTo(b.rating));
        break;
      case SortOption.ratingDesc:
        sortedClips.sort((a, b) => b.rating.compareTo(a.rating));
        break;
      case SortOption.durationAsc:
        sortedClips.sort((a, b) {
          final durationA = a.endTime - a.startTime;
          final durationB = b.endTime - b.startTime;
          return durationA.compareTo(durationB);
        });
        break;
      case SortOption.durationDesc:
        sortedClips.sort((a, b) {
          final durationA = a.endTime - a.startTime;
          final durationB = b.endTime - b.startTime;
          return durationB.compareTo(durationA);
        });
        break;
    }

    return sortedClips;
  }

  VideoClip? _getPreviousClip() {
    // 获取当前过滤后的clip列表并应用排序
    final appState = context.read<AppState>();
    final filteredClips = appState.getFilteredClips(
      searchQuery: widget.searchQuery,
      selectedTags: widget.selectedTags,
      selectedRating: widget.selectedRating,
      selectedFavorite: widget.selectedFavorite,
    );

    // 应用与ClipsTab相同的排序
    final sortedClips = _sortClips(filteredClips);

    final currentIndex = sortedClips.indexWhere((c) => c.id == _currentClip.id);
    if (currentIndex > 0) {
      return sortedClips[currentIndex - 1];
    }
    return null;
  }

  VideoClip? _getNextClip() {
    // 获取当前过滤后的clip列表并应用排序
    final appState = context.read<AppState>();
    final filteredClips = appState.getFilteredClips(
      searchQuery: widget.searchQuery,
      selectedTags: widget.selectedTags,
      selectedRating: widget.selectedRating,
      selectedFavorite: widget.selectedFavorite,
    );

    // 应用与ClipsTab相同的排序
    final sortedClips = _sortClips(filteredClips);

    final currentIndex = sortedClips.indexWhere((c) => c.id == _currentClip.id);
    if (currentIndex >= 0 && currentIndex < sortedClips.length - 1) {
      return sortedClips[currentIndex + 1];
    }
    return null;
  }

  Future<void> _editClip() async {
    if (_disposed) return;
    _disposed = true;

    // 取消所有定时器和订阅
    _recoveryTimer?.cancel();
    _positionSubscription?.cancel();
    _playingSubscription?.cancel();

    await _disposePlayers();

    if (mounted) {
      // 关闭播放弹窗，并将当前 clip 作为结果回传给 ClipsTab 调用方
      Navigator.of(context).pop(_currentClip);
    }
  }

  void _filterByTag(String tag) {
    // 获取AppState并设置标签过滤
    final appState = context.read<AppState>();
    appState.setSelectedTags([tag]); // 设置为只过滤这个标签

    // 关闭播放器并返回到clips_tab
    Navigator.of(context).pop();

    // 显示过滤成功的提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Filtering clips by tag: $tag'),
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: 'Clear',
          onPressed: () => appState.clearSelectedTags(),
        ),
      ),
    );
  }

  void _openVideoFile() async {
    try {
      final file = File(_currentClip.videoPath);
      if (await file.exists()) {
        // 在Windows上直接打开文件所在文件夹并选中文件
        final result = await Process.run('explorer', [
          '/select,',
          _currentClip.videoPath,
        ]);

        if (result.exitCode == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Opened file location: ${p.basename(_currentClip.videoPath)}',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        } else {
          // 如果选择文件失败，只显示错误信息，不再尝试打开文件夹
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to open file location'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'File not found: ${p.basename(_currentClip.videoPath)}',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error opening file: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // 切换静音状态
  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });

    if (_isMuted) {
      mainPlayer.setVolume(0);
      print('ClipPlayback: Audio muted');
    } else {
      mainPlayer.setVolume(100);
      print('ClipPlayback: Audio unmuted');
    }
  }

  // 处理键盘快捷键
  void _handleKeyPress(RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
      switch (event.logicalKey.keyLabel) {
        case ' ':
          // 空格键：播放/暂停
          _togglePlayPause();
          break;
        case 'R':
        case 'r':
          // R键：重播
          _replay();
          break;
        case 'Arrow Left':
        case 'A':
        case 'a':
          // 左箭头或A键：上一个
          final prevClip = _getPreviousClip();
          if (prevClip != null) {
            _navigateToClip(prevClip);
          }
          break;
        case 'Arrow Right':
        case 'D':
        case 'd':
          // 右箭头或D键：下一个
          final nextClip = _getNextClip();
          if (nextClip != null) {
            _navigateToClip(nextClip);
          }
          break;
        case 'E':
        case 'e':
          // E键：编辑
          _editClip();
          break;
        case 'F1':
          // F1键：显示/隐藏快捷键提示
          setState(() {
            _showHints = !_showHints;
          });
          break;
        case 'P':
        case 'p':
          // P键：切换自定义进度条显示
          setState(() {
            _showCustomProgressBar = !_showCustomProgressBar;
          });
          break;
        case 'T':
        case 't':
          // T键：切换clip相对进度显示
          setState(() {
            _showClipRelativeProgress = !_showClipRelativeProgress;
          });
          break;
        case 'S':
        case 's':
          // S键：切换静音
          _toggleMute();
          break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    // 获取最新的clip数据，确保状态同步
    final currentClip = appState.clips.firstWhere(
      (clip) => clip.id == _currentClip.id,
      orElse: () => _currentClip,
    );
    final previousClip = _getPreviousClip();
    final nextClip = _getNextClip();

    return RawKeyboardListener(
      focusNode: _focusNode, // 使用全局焦点节点
      onKey: _handleKeyPress,
      child: Container(
        padding: const EdgeInsets.all(16.0),
        width: 720,
        height: 680,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    currentClip.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Row(
                  children: [
                    // 快捷键提示按钮
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _showHints = !_showHints;
                        });
                      },
                      icon: Icon(
                        _showHints ? Icons.keyboard : Icons.keyboard_outlined,
                        color: _showHints ? Colors.blue : Colors.grey,
                      ),
                      tooltip: 'Keyboard Shortcuts (F1)',
                    ),
                    // 自定义进度条切换按钮
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _showCustomProgressBar = !_showCustomProgressBar;
                        });
                      },
                      icon: Icon(
                        _showCustomProgressBar
                            ? Icons.timeline
                            : Icons.timeline_outlined,
                        color: _showCustomProgressBar
                            ? Colors.green
                            : Colors.grey,
                      ),
                      tooltip: 'Toggle Custom Progress Bar (P)',
                    ),
                    // Clip相对进度切换按钮
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _showClipRelativeProgress =
                              !_showClipRelativeProgress;
                        });
                      },
                      icon: Icon(
                        _showClipRelativeProgress
                            ? Icons.crop_square
                            : Icons.crop_square_outlined,
                        color: _showClipRelativeProgress
                            ? Colors.purple
                            : Colors.grey,
                      ),
                      tooltip: 'Toggle Clip Relative Progress (T)',
                    ),
                    // 编辑按钮移到右上角
                    IconButton(
                      onPressed: _editClip,
                      icon: const Icon(Icons.edit, color: Colors.orange),
                      tooltip: 'Edit Clip (E)',
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 视频播放区域
            Expanded(
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Video(controller: mainController),
                    // 重播按钮
                    Positioned(
                      bottom: 8, // 恢复原来的位置
                      right: 60, // 恢复原来的位置，避免与全屏按钮重叠
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            // 添加点击反馈
                            HapticFeedback.lightImpact();
                            _replay();
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(
                              Icons.replay,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // 快捷键提示悬浮窗
                    if (_showHints)
                      Positioned(
                        top: 16,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Keyboard Shortcuts',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _buildShortcutHint('Space', 'Play/Pause'),
                              _buildShortcutHint('R', 'Replay'),
                              _buildShortcutHint('S', 'Mute/Unmute'),
                              _buildShortcutHint('← / A', 'Previous'),
                              _buildShortcutHint('→ / D', 'Next'),
                              _buildShortcutHint('E', 'Edit'),
                              _buildShortcutHint('P', 'Toggle Progress Bar'),
                              _buildShortcutHint('T', 'Toggle Clip Progress'),
                              _buildShortcutHint('F1', 'Toggle Hints'),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // 自定义进度条 - 显示起始和终止标记
            if (_showCustomProgressBar)
              Column(
                children: [
                  // 简化的Clip信息
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.timer, size: 16, color: Colors.blue),
                        const SizedBox(width: 4),
                        Text(
                          _showClipRelativeProgress
                              ? 'Clip: ${formatDuration(currentClip.endTime - currentClip.startTime)}'
                              : 'Video: ${formatDuration(currentClip.startTime)} - ${formatDuration(currentClip.endTime)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  // 进度条
                  StreamBuilder<Duration>(
                    stream: mainPlayer.stream.duration,
                    initialData: mainPlayer.state.duration,
                    builder: (context, snapshot) {
                      final totalDuration = snapshot.data ?? Duration.zero;
                      if (totalDuration == Duration.zero) {
                        return const SizedBox(height: 48);
                      }

                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        child: CustomProgressBar(
                          player: mainPlayer,
                          startTime: currentClip.startTime,
                          endTime: currentClip.endTime,
                          onSetStart: (time) {},
                          onSetEnd: (time) {},
                          showThumbnailPreview: true,
                          isPlaybackMode: true,
                          showClipRelativeProgress: _showClipRelativeProgress,
                          videoPath: currentClip.videoPath, // 新增
                        ),
                      );
                    },
                  ),
                ],
              ),
            const SizedBox(height: 8),

            // 导航按钮行 - 前一个和下一个按钮放在一起
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 上一个按钮
                IconButton(
                  onPressed: previousClip != null
                      ? () => _navigateToClip(previousClip)
                      : null,
                  icon: Icon(
                    Icons.skip_previous,
                    color: previousClip != null ? Colors.blue : Colors.grey,
                  ),
                  tooltip: 'Previous Clip (← / A)',
                ),

                const SizedBox(width: 20),

                // 下一个按钮
                IconButton(
                  onPressed: nextClip != null
                      ? () => _navigateToClip(nextClip)
                      : null,
                  icon: Icon(
                    Icons.skip_next,
                    color: nextClip != null ? Colors.blue : Colors.grey,
                  ),
                  tooltip: 'Next Clip (→ / D)',
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 信息显示区域 - 按原始顺序排列
            // 1. 时间标记信息
            _buildInfoRow(
              Icons.timer,
              'Time Range',
              '${formatDuration(currentClip.startTime)} - ${formatDuration(currentClip.endTime)} (${formatDuration(currentClip.endTime - currentClip.startTime)})',
            ),
            const SizedBox(height: 8),

            // 2. 文件路径信息
            _buildClickableInfoRow(
              Icons.video_file,
              'Video',
              currentClip.videoPath.split('/').last,
              onTap: _openVideoFile,
            ),
            const SizedBox(height: 8),

            // 3. 标签信息 - 可点击过滤
            _buildTagInfoRow(currentClip.tags),
            const SizedBox(height: 8),

            // 4. 备注信息
            _buildInfoRow(
              Icons.notes,
              'Notes',
              currentClip.notes != null && currentClip.notes!.isNotEmpty
                  ? currentClip.notes!
                  : 'No notes',
            ),
            const SizedBox(height: 8),

            // 5. 星级评分 - 可点击修改
            Container(
              // 固定高度，确保布局一致性
              height: 32,
              child: Row(
                children: [
                  const Icon(Icons.star, size: 18, color: Colors.amber),
                  const SizedBox(width: 8),
                  const Text(
                    'Rating: ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  ...List.generate(5, (starIndex) {
                    return GestureDetector(
                      onTap: () {
                        final newRating = currentClip.rating == starIndex + 1
                            ? 0
                            : starIndex + 1;
                        final updatedClip = currentClip.copyWith(
                          rating: newRating,
                        );
                        appState.updateClipSilently(updatedClip);
                      },
                      child: Icon(
                        starIndex < currentClip.rating
                            ? Icons.star
                            : Icons.star_border,
                        color: starIndex < currentClip.rating
                            ? Colors.amber
                            : Colors.grey,
                        size: 20,
                      ),
                    );
                  }),
                  const Spacer(),
                  // 收藏按钮 - 可点击修改
                  GestureDetector(
                    onTap: () {
                      final updatedClip = currentClip.copyWith(
                        isFavorite: !currentClip.isFavorite,
                      );
                      appState.updateClipSilently(updatedClip);
                    },
                    child: Icon(
                      currentClip.isFavorite
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: currentClip.isFavorite
                          ? Colors.redAccent
                          : Colors.grey,
                      size: 24,
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

  Widget _buildShortcutHint(String key, String action) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              key,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(action, style: TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
        Expanded(
          child: Container(
            // 固定高度，确保布局一致性
            height: 20,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildClickableInfoRow(
    IconData icon,
    String label,
    String value, {
    VoidCallback? onTap,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
        Expanded(
          child: Container(
            // 固定高度，确保布局一致性
            height: 20,
            child: Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: onTap,
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    color: onTap != null ? Colors.blue : null,
                    decoration: onTap != null ? TextDecoration.underline : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTagInfoRow(List<String> tags) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.label, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Text('Tags: ', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            // 固定高度，确保布局一致性
            height: 32, // 始终保持32px高度
            child: tags.isEmpty
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'No tags',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade500,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                : Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.start,
                    children: tags.map((tag) => _buildTagChip(tag)).toList(),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildTagChip(String tag) {
    return buildTagChipWithTap(tag, () => _filterByTag(tag));
  }
}

String formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);

  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  } else {
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
