import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' hide Playlist;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:math';

import '../../data/models.dart';
import '../../data/app_state.dart';
// 添加颜色生成函数的导入
import '../../widgets/custom_progress_bar.dart';
import '../../widgets/custom_player_controls.dart';

// 播放模式枚举
enum PlaybackMode {
  sequential, // 顺序播放
  loop, // 循环播放
  random, // 随机播放
}

class PlaylistPlaybackScreen extends StatefulWidget {
  final Playlist playlist;

  const PlaylistPlaybackScreen({super.key, required this.playlist});

  @override
  State<PlaylistPlaybackScreen> createState() => _PlaylistPlaybackScreenState();
}

class _PlaylistPlaybackScreenState extends State<PlaylistPlaybackScreen> {
  late final Player player;
  late final VideoController controller;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<bool>? _playingSubscription;

  // 添加焦点节点
  late final FocusNode _focusNode;

  bool _isPlaying = false;
  bool _isPlayerReady = false; // 播放器就绪状态
  bool _disposed = false; // 组件销毁状态
  bool _isPlayerFullyInitialized = false; // 播放器完全初始化状态
  DateTime? _initializationStartTime; // 初始化开始时间
  bool _hasTriggeredNextForCurrentItem = false; // 重复触发保护
  String? _lastClipKey; // 记录上一个clip的key
  int _currentItemIndex = 0;
  List<PlaylistItemWithClip> _playlistItems = [];
  PlaylistItemWithClip? _currentItem;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  Duration _currentItemDuration = Duration.zero;

  bool _showPlaylistInfo = true;
  bool _showCustomProgressBar = true;
  bool _showHints = false; // 控制提示显示
  bool _showGlobalProgress = false; // 控制进度条模式：false=片段进度，true=全局进度

  // 播放模式相关
  PlaybackMode _playbackMode = PlaybackMode.sequential;
  Duration _totalPlayedTime = Duration.zero; // 总播放时间
  List<int> _playedItems = []; // 已播放的片段索引
  List<PlaylistItemWithClip> _generatedPlaylist = []; // 预生成的播放列表

  @override
  void initState() {
    super.initState();
    player = Player();
    controller = VideoController(player);
    _focusNode = FocusNode(); // 初始化焦点节点
    _initializePlaylist();

    // 延迟请求焦点，确保组件完全初始化
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
        print('Playlist: Focus requested'); // 调试信息
      }
    });
  }

  // 处理键盘快捷键
  void _handleKeyPress(RawKeyEvent event) {
    print('Playlist: Key pressed: ${event.logicalKey.keyLabel}'); // 调试信息

    if (event is RawKeyDownEvent) {
      switch (event.logicalKey.keyLabel) {
        case ' ':
          // 空格键：播放/暂停
          print('Playlist: Space key pressed, toggling play/pause'); // 调试信息
          _togglePlayPause();
          break;
        case 'R':
        case 'r':
          // R键：重播当前片段
          _replayCurrentItem();
          break;
        case 'Arrow Left':
        case 'A':
        case 'a':
          // 左箭头或A键：上一个片段
          _playPreviousItem();
          break;
        case 'Arrow Right':
        case 'D':
        case 'd':
          // 右箭头或D键：下一个片段
          _playNextItem();
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
        case 'M':
        case 'm':
          // M键：切换播放模式
          _switchPlaybackMode();
          break;
        case 'P':
        case 'p':
          // P键：切换进度条模式
          setState(() {
            _showGlobalProgress = !_showGlobalProgress;
          });
          break;
        case 'I':
        case 'i':
          // I键：切换播放列表信息显示
          setState(() {
            _showPlaylistInfo = !_showPlaylistInfo;
          });
          break;
        default:
          // 检查Ctrl + 数字键
          if (event.isControlPressed && event.logicalKey.keyLabel.length == 1) {
            final key = event.logicalKey.keyLabel;
            if (key.codeUnitAt(0) >= 49 && key.codeUnitAt(0) <= 57) {
              // 1-9
              final index = key.codeUnitAt(0) - 49; // 转换为0-8
              if (index < _generatedPlaylist.length) {
                print(
                  'Playlist: Ctrl+$key pressed, playing item at index $index',
                ); // 调试信息
                _playItemAtIndex(index);
              }
            } else if (key.codeUnitAt(0) == 48) {
              // 0键
              final index = 9; // 第10个片段
              if (index < _generatedPlaylist.length) {
                print(
                  'Playlist: Ctrl+0 pressed, playing item at index $index',
                ); // 调试信息
                _playItemAtIndex(index);
              }
            }
          }
          break;
      }
    }
  }

  // 切换播放模式
  void _switchPlaybackMode() {
    // 保存当前播放的片段
    final currentItem = _currentItem;

    // 切换播放模式
    switch (_playbackMode) {
      case PlaybackMode.sequential:
        _playbackMode = PlaybackMode.loop;
        break;
      case PlaybackMode.loop:
        _playbackMode = PlaybackMode.random;
        break;
      case PlaybackMode.random:
        _playbackMode = PlaybackMode.sequential;
        break;
    }

    // 重新生成播放列表，将当前片段放在第一个位置
    _generatePlaylistWithCurrentFirst(currentItem);

    // 更新当前索引为0（第一个位置）
    _currentItemIndex = 0;
    _currentItem = _generatedPlaylist[0];
    _currentItemDuration = _currentItem!.effectiveDuration;

    // 重新计算总时长
    _totalDuration = _calculateTotalDuration();

    // 重置进度状态
    _resetProgressState();

    // 显示播放模式切换提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('播放模式: ${_getPlaybackModeText()}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // 获取播放模式文本
  String _getPlaybackModeText() {
    switch (_playbackMode) {
      case PlaybackMode.sequential:
        return '顺序播放';
      case PlaybackMode.loop:
        return '循环播放';
      case PlaybackMode.random:
        return '随机播放';
    }
  }

  // 获取播放模式图标
  IconData _getPlaybackModeIcon() {
    switch (_playbackMode) {
      case PlaybackMode.sequential:
        return Icons.format_list_bulleted; // 顺序播放使用平行线列表图标
      case PlaybackMode.loop:
        return Icons.repeat_one; // 循环播放使用单曲循环图标
      case PlaybackMode.random:
        return Icons.shuffle; // 随机播放使用随机图标
    }
  }

  // 获取播放模式颜色
  Color _getPlaybackModeColor() {
    switch (_playbackMode) {
      case PlaybackMode.sequential:
        return Colors.blue;
      case PlaybackMode.loop:
        return Colors.purple;
      case PlaybackMode.random:
        return Colors.orange;
    }
  }

  void _initializePlaylist() {
    final appState = context.read<AppState>();

    _playlistItems = <PlaylistItemWithClip>[];

    for (final playlistItem in widget.playlist.items) {
      try {
        // 从 AppState 获取对应的 clip 数据
        final clip = appState.clips.firstWhere(
          (clip) => clip.id == playlistItem.clipId,
        );
        _playlistItems.add(
          PlaylistItemWithClip(item: playlistItem, clip: clip),
        );
      } catch (e) {
        // 如果找不到clip，跳过这个播放列表项
        print('Clip not found: ${playlistItem.clipId}, skipping...');
        continue;
      }
    }

    if (_playlistItems.isEmpty) {
      // 如果没有有效的播放列表项，显示错误信息
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('播放列表中没有有效的片段，可能某些片段已被删除'),
          backgroundColor: Colors.orange,
        ),
      );
      // 延迟返回上一页
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          Navigator.of(context).pop();
        }
      });
      return;
    }

    if (_playlistItems.isNotEmpty) {
      // 生成初始播放列表
      _generatePlaylist();

      _currentItem = _generatedPlaylist[0];
      _currentItemDuration = _currentItem!.effectiveDuration;
      _totalDuration = _calculateTotalDuration();
      _initializePlayer();
    }
  }

  Future<void> _initializePlayer() async {
    if (_currentItem == null) return;

    print(
      'Playlist: Initializing player for item at index $_currentItemIndex',
    ); // 调试信息

    final clip = _currentItem!.clip;
    final item = _currentItem!.item;

    // 确定播放的起始和结束时间
    final startTime = item.customStartTime ?? clip.startTime;
    final endTime = item.customEndTime ?? clip.endTime;

    print('Playlist: Opening media: ${clip.videoPath}'); // 调试信息
    print('Playlist: Start time: $startTime, End time: $endTime'); // 调试信息
    print('Playlist: Clip duration: ${clip.endTime - clip.startTime}'); // 调试信息
    print(
      'Playlist: Item custom time: ${item.customStartTime} - ${item.customEndTime}',
    ); // 调试信息

    // 重置播放器状态
    setState(() {
      _isPlayerReady = false;
      _isPlayerFullyInitialized = false;
      _hasTriggeredNextForCurrentItem = false; // 重置重复触发保护
    });
    _initializationStartTime = DateTime.now(); // 记录初始化开始时间
    _lastClipKey = null; // 重置clip key

    // 重置播放器就绪状态
    setState(() {
      _isPlayerReady = false;
    });

    // 打开媒体文件
    await player.open(Media(clip.videoPath), play: false);

    if (mounted) {
      // 等待媒体加载完成
      await Future.delayed(Duration(milliseconds: 200));

      // 跳转到开始时间
      await player.seek(startTime);

      // 再等待一下确保seek完成
      await Future.delayed(Duration(milliseconds: 50));

      // 开始播放
      await player.play();

      setState(() {
        _isPlaying = true;
      });
    }

    // 设置位置监听器（每次初始化时都重新设置）
    _positionSubscription?.cancel(); // 取消之前的监听器
    _positionSubscription = player.stream.position.listen((position) {
      if (mounted) {
        setState(() {
          _currentPosition = position;

          // 计算总播放时间（根据播放模式调整）
          _totalPlayedTime = Duration.zero;

          if (_playbackMode == PlaybackMode.sequential) {
            // 顺序播放：按播放顺序累积
            for (int i = 0; i < _playedItems.length; i++) {
              if (i < _generatedPlaylist.length) {
                _totalPlayedTime +=
                    _generatedPlaylist[_playedItems[i]].effectiveDuration;
              }
            }
          } else if (_playbackMode == PlaybackMode.loop) {
            // 循环播放：计算当前轮次 + 当前片段进度
            final completedRounds =
                _playedItems.length ~/ _generatedPlaylist.length;
            final currentRoundItems =
                _playedItems.length % _generatedPlaylist.length;

            // 完整轮次的总时长
            _totalPlayedTime = _totalDuration * completedRounds;

            // 当前轮次已播放的片段
            for (int i = 0; i < currentRoundItems; i++) {
              if (i < _generatedPlaylist.length) {
                _totalPlayedTime +=
                    _generatedPlaylist[_playedItems[i]].effectiveDuration;
              }
            }
          } else if (_playbackMode == PlaybackMode.random) {
            // 随机播放：按实际播放的片段累积
            for (int i = 0; i < _playedItems.length; i++) {
              if (i < _generatedPlaylist.length) {
                _totalPlayedTime +=
                    _generatedPlaylist[_playedItems[i]].effectiveDuration;
              }
            }
          }

          // 加上当前片段的播放时间（使用相对位置）
          if (_currentItem != null) {
            final currentItemStartTime =
                _currentItem!.item.customStartTime ??
                _currentItem!.clip.startTime;
            final currentItemEndTime =
                _currentItem!.item.customEndTime ?? _currentItem!.clip.endTime;
            final currentItemDuration =
                currentItemEndTime - currentItemStartTime;
            final relativePosition = position - currentItemStartTime;

            // 手动限制在有效范围内
            Duration currentItemPlayedTime;
            if (relativePosition < Duration.zero) {
              currentItemPlayedTime = Duration.zero;
            } else if (relativePosition > currentItemDuration) {
              currentItemPlayedTime = currentItemDuration;
            } else {
              currentItemPlayedTime = relativePosition;
            }

            _totalPlayedTime += currentItemPlayedTime;
          }
        });

        // 检查是否到达当前片段的结束时间
        final currentEndTime =
            _currentItem?.item.customEndTime ?? _currentItem?.clip.endTime;
        final currentStartTime =
            _currentItem?.item.customStartTime ?? _currentItem?.clip.startTime;

        if (currentEndTime != null && currentStartTime != null) {
          print(
            'Playlist: Position: $position, End time: $currentEndTime, Diff: ${currentEndTime - position}',
          ); // 调试信息

          // 检查clip是否变化
          String currentClipKey = _getCurrentClipKey();
          if (currentClipKey != _lastClipKey) {
            print(
              'Playlist: Clip changed from $_lastClipKey to $currentClipKey, resetting state',
            );
            _lastClipKey = currentClipKey;
            _hasTriggeredNextForCurrentItem = false; // 重置重复触发保护
          }

          // 简化的检测条件
          if (_isPlayerReady &&
              !_hasTriggeredNextForCurrentItem &&
              _isPlayerFullyInitialized) {
            // 主要检测：位置到达结束时间
            if (position >= currentEndTime) {
              print(
                'Playlist: Reached end time $currentEndTime at position $position, playing next item',
              );
              print(
                'Playlist: Current item: ${_currentItem?.clip.name}',
              ); // 调试信息
              print('Playlist: Current index: $_currentItemIndex'); // 调试信息
              _triggerNextItem("Reached end time");
            }
            // 备用检测：位置接近结束时间且播放器停止
            else if (position >= currentEndTime - Duration(milliseconds: 100) &&
                !player.state.playing) {
              print(
                'Playlist: Near end time and player stopped, playing next item',
              );
              print(
                'Playlist: Position: $position, End time: $currentEndTime, Player playing: ${player.state.playing}',
              ); // 调试信息
              print(
                'Playlist: Current item: ${_currentItem?.clip.name}',
              ); // 调试信息
              print('Playlist: Current index: $_currentItemIndex'); // 调试信息
              _triggerNextItem("Near end time and player stopped");
            }
          }
        } else {
          print('Playlist: No end time found for current item'); // 调试信息
        }
      }
    });

    // 监听播放状态（每次初始化时都重新设置）
    _playingSubscription?.cancel(); // 取消之前的监听器
    _playingSubscription = player.stream.playing.listen((playing) {
      print('Playlist: Playing state changed to: $playing'); // 调试信息
      print(
        'Playlist: Current player state - playing: ${player.state.playing}',
      ); // 调试信息
      if (mounted) {
        // 只在状态真正改变时才更新UI
        if (_isPlaying != playing) {
          setState(() {
            _isPlaying = playing;
          });
          print('Playlist: UI state updated, _isPlaying: $_isPlaying'); // 调试信息
        } else {
          print(
            'Playlist: UI state unchanged, _isPlaying: $_isPlaying',
          ); // 调试信息
        }

        // 备用检测：当播放器停止时，检查是否接近结束时间
        if (!playing) {
          final currentEndTime =
              _currentItem?.item.customEndTime ?? _currentItem?.clip.endTime;
          final currentStartTime =
              _currentItem?.item.customStartTime ??
              _currentItem?.clip.startTime;

          if (currentEndTime != null && currentStartTime != null) {
            final position = player.state.position;
            print(
              'Playlist: Player stopped - Position: $position, End time: $currentEndTime, Diff: ${currentEndTime - position}',
            ); // 调试信息

            // 检查clip是否变化
            String currentClipKey = _getCurrentClipKey();
            if (currentClipKey != _lastClipKey) {
              print(
                'Playlist: Clip changed from $_lastClipKey to $currentClipKey (playing state), resetting state',
              );
              _lastClipKey = currentClipKey;
              _hasTriggeredNextForCurrentItem = false; // 重置重复触发保护
            }

            // 简化的检测条件
            if (_isPlayerReady &&
                !_hasTriggeredNextForCurrentItem &&
                _isPlayerFullyInitialized) {
              // 检查是否接近结束时间（容错范围100毫秒）
              if (position >= currentEndTime - Duration(milliseconds: 100)) {
                print(
                  'Playlist: Player stopped near end time, playing next item',
                );
                print(
                  'Playlist: Current item: ${_currentItem?.clip.name}',
                ); // 调试信息
                print('Playlist: Current index: $_currentItemIndex'); // 调试信息
                _triggerNextItem("Player stopped near end time");
              }
            }
          }
        }
      }
    });

    // 设置播放器就绪状态
    setState(() {
      _isPlayerReady = true;
      _isPlayerFullyInitialized = true; // 设置播放器完全初始化
    });

    print('Playlist: Player initialized successfully'); // 调试信息
  }

  void _playNextItem() async {
    print(
      'Playlist: _playNextItem called, current index: $_currentItemIndex, mode: $_playbackMode',
    ); // 调试信息
    print(
      'Playlist: Total playlist items: ${_generatedPlaylist.length}',
    ); // 调试信息

    // 记录当前片段为已播放
    if (!_playedItems.contains(_currentItemIndex)) {
      _playedItems.add(_currentItemIndex);
    }

    // 根据播放模式决定下一个片段
    int nextIndex = -1;

    switch (_playbackMode) {
      case PlaybackMode.sequential:
        // 顺序播放：播放下一个
        print(
          'Playlist: Sequential mode - checking if $_currentItemIndex < ${_generatedPlaylist.length - 1}',
        ); // 调试信息
        if (_currentItemIndex < _generatedPlaylist.length - 1) {
          nextIndex = _currentItemIndex + 1;
          print(
            'Playlist: Sequential mode - next index will be $nextIndex',
          ); // 调试信息
        } else {
          print('Playlist: Sequential mode - reached end of playlist'); // 调试信息
        }
        break;

      case PlaybackMode.loop:
        // 循环播放：播放下一个，如果到末尾则回到开头
        nextIndex = (_currentItemIndex + 1) % _generatedPlaylist.length;
        print('Playlist: Loop mode - next index will be $nextIndex'); // 调试信息
        break;

      case PlaybackMode.random:
        // 随机播放：从未播放的片段中随机选择
        List<int> unplayedItems = [];
        for (int i = 0; i < _generatedPlaylist.length; i++) {
          if (!_playedItems.contains(i)) {
            unplayedItems.add(i);
          }
        }

        // 如果所有片段都播放过了，重新开始
        if (unplayedItems.isEmpty) {
          _playedItems.clear();
          // 重新生成随机播放列表
          _generatePlaylist();
          for (int i = 0; i < _generatedPlaylist.length; i++) {
            unplayedItems.add(i);
          }
        }

        if (unplayedItems.isNotEmpty) {
          nextIndex = unplayedItems[Random().nextInt(unplayedItems.length)];
        }
        print('Playlist: Random mode - next index will be $nextIndex'); // 调试信息
        break;
    }

    print('Playlist: Next index calculated: $nextIndex'); // 调试信息

    if (nextIndex >= 0 && nextIndex < _generatedPlaylist.length) {
      print('Playlist: Playing next item at index $nextIndex'); // 调试信息
      _currentItemIndex = nextIndex;
      _currentItem = _generatedPlaylist[_currentItemIndex];
      _currentItemDuration = _currentItem!.effectiveDuration;

      // 重新初始化播放器
      await _initializePlayer();
    } else {
      print('Playlist: No next item to play, playlist finished'); // 调试信息
      // 播放列表结束，暂停播放
      await _safePause();

      // 显示播放完成提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('播放列表播放完成 (${_getPlaybackModeText()})'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _playPreviousItem() async {
    if (_currentItemIndex > 0) {
      _currentItemIndex--;
      _currentItem = _generatedPlaylist[_currentItemIndex];
      _currentItemDuration = _currentItem!.effectiveDuration;

      // 重新初始化播放器
      await _initializePlayer();
    }
  }

  void _playItemAtIndex(int index) async {
    if (index >= 0 && index < _generatedPlaylist.length) {
      _currentItemIndex = index;
      _currentItem = _generatedPlaylist[index];
      _currentItemDuration = _currentItem!.effectiveDuration;

      // 重新初始化播放器
      await _initializePlayer();
    }
  }

  void _togglePlayPause() async {
    print(
      'Playlist: _togglePlayPause called, current _isPlaying: $_isPlaying',
    ); // 调试信息
    print('Playlist: Player state - playing: ${player.state.playing}'); // 调试信息

    if (!_isPlayerReady || _disposed) {
      print('Playlist: Cannot toggle - player not ready or disposed'); // 调试信息
      return;
    }

    try {
      if (player.state.playing) {
        print('Playlist: Player is playing, pausing...'); // 调试信息
        await player.pause();
        print('Playlist: Player paused successfully'); // 调试信息
      } else {
        print('Playlist: Player is paused, playing...'); // 调试信息
        await player.play();
        print('Playlist: Player played successfully'); // 调试信息
      }

      // 手动更新UI状态
      if (mounted && !_disposed) {
        setState(() {
          _isPlaying = player.state.playing;
        });
        print('Playlist: UI state updated to _isPlaying: $_isPlaying'); // 调试信息
      }
    } catch (e) {
      print('Playlist: Error during toggle: $e'); // 调试信息
    }
  }

  Future<void> _safePause() async {
    print(
      'Playlist: _safePause called, _isPlayerReady: $_isPlayerReady, _disposed: $_disposed',
    ); // 调试信息
    if (!_isPlayerReady || _disposed) {
      print('Playlist: Cannot pause - player not ready or disposed'); // 调试信息
      return;
    }

    try {
      print('Playlist: Calling player.pause()'); // 调试信息
      await player.pause();
      print('Playlist: player.pause() completed'); // 调试信息
      if (mounted && !_disposed) {
        setState(() {
          _isPlaying = false;
        });
        print('Playlist: UI state set to _isPlaying: false'); // 调试信息
      }
    } catch (e) {
      print('Playlist: Error during pause: $e'); // 调试信息
    }
  }

  Future<void> _safePlay() async {
    print(
      'Playlist: _safePlay called, _isPlayerReady: $_isPlayerReady, _disposed: $_disposed',
    ); // 调试信息
    if (!_isPlayerReady || _disposed) {
      print('Playlist: Cannot play - player not ready or disposed'); // 调试信息
      return;
    }

    try {
      print('Playlist: Calling player.play()'); // 调试信息
      await player.play();
      print('Playlist: player.play() completed'); // 调试信息
      if (mounted && !_disposed) {
        setState(() {
          _isPlaying = true;
        });
        print('Playlist: UI state set to _isPlaying: true'); // 调试信息
      }
    } catch (e) {
      print('Playlist: Error during play: $e'); // 调试信息
    }
  }

  void _replayCurrentItem() async {
    if (_currentItem != null) {
      await _initializePlayer();
    }
  }

  // 获取当前clip的唯一标识
  String _getCurrentClipKey() {
    return "${_currentItem?.clip.id}_$_currentItemIndex";
  }

  // 检查位置是否在合理范围内
  bool _isPositionReasonable(
    Duration position,
    Duration startTime,
    Duration endTime,
  ) {
    // 位置应该在开始时间和结束时间之间，允许1秒的容错
    return position >= startTime && position <= endTime + Duration(seconds: 1);
  }

  // 验证位置是否正确重置到开始时间
  bool _isPositionReset(Duration position, Duration startTime) {
    return (position - startTime).abs() < Duration(milliseconds: 200);
  }

  // 检查初始化延迟
  bool _isInitializationDelayPassed() {
    if (_initializationStartTime == null) return false;
    return DateTime.now().difference(_initializationStartTime!) >=
        Duration(milliseconds: 500);
  }

  // 触发播放下一个片段的保护方法
  void _triggerNextItem(String reason) {
    if (!_hasTriggeredNextForCurrentItem) {
      print('Playlist: $reason, playing next item');
      _hasTriggeredNextForCurrentItem = true; // 设置重复触发保护
      _playNextItem();
    } else {
      print('Playlist: $reason, but already triggered next item, skipping');
    }
  }

  // 生成初始播放列表
  void _generatePlaylist() {
    _generatedPlaylist.clear();

    switch (_playbackMode) {
      case PlaybackMode.sequential:
      case PlaybackMode.loop:
        // 顺序/循环模式：按原始顺序
        _generatedPlaylist = List.from(_playlistItems);
        break;

      case PlaybackMode.random:
        // 随机模式：随机排列（不重复）
        _generatedPlaylist = List.from(_playlistItems);
        _generatedPlaylist.shuffle(Random());
        break;
    }
  }

  // 生成包含当前片段的播放列表，并将其放在第一位
  void _generatePlaylistWithCurrentFirst(PlaylistItemWithClip? currentItem) {
    _generatedPlaylist.clear();

    if (currentItem == null) {
      // 如果没有当前片段，按正常逻辑生成
      _generatePlaylist();
      return;
    }

    switch (_playbackMode) {
      case PlaybackMode.sequential:
      case PlaybackMode.loop:
        // 顺序/循环模式：将当前片段放在第一个，其他按原始顺序
        _generatedPlaylist.add(currentItem);
        for (final item in _playlistItems) {
          if (item.clip.id != currentItem.clip.id) {
            _generatedPlaylist.add(item);
          }
        }
        break;

      case PlaybackMode.random:
        // 随机模式：将当前片段放在第一个，其他随机排列（不重复）
        _generatedPlaylist.add(currentItem);
        final remainingItems = _playlistItems
            .where((item) => item.clip.id != currentItem.clip.id)
            .toList();
        remainingItems.shuffle(Random());
        _generatedPlaylist.addAll(remainingItems);
        break;
    }
  }

  // 重置播放进度状态
  void _resetProgressState() {
    _playedItems.clear();
    _totalPlayedTime = Duration.zero;
    _lastClipKey = null;
    _hasTriggeredNextForCurrentItem = false;

    // 强制更新UI
    if (mounted) {
      setState(() {});
    }
  }

  // 计算总播放时长
  Duration _calculateTotalDuration() {
    Duration total = Duration.zero;
    for (final item in _generatedPlaylist) {
      total += item.effectiveDuration;
    }
    return total;
  }

  @override
  void dispose() {
    _disposed = true; // 设置销毁状态
    _positionSubscription?.cancel();
    _playingSubscription?.cancel();
    _focusNode.dispose(); // 释放焦点节点
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_playlistItems.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text('播放列表: ${widget.playlist.name}')),
        body: const Center(child: Text('播放列表为空，请先添加片段')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('播放列表: ${widget.playlist.name}'),
        actions: [
          // 播放模式切换按钮
          IconButton(
            onPressed: _switchPlaybackMode,
            icon: Icon(_getPlaybackModeIcon(), color: _getPlaybackModeColor()),
            tooltip: '播放模式: ${_getPlaybackModeText()} (M)',
          ),
          // 详细信息切换按钮

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
          // 进度条模式切换按钮
          IconButton(
            onPressed: () {
              setState(() {
                _showGlobalProgress = !_showGlobalProgress;
              });
            },
            icon: Icon(
              _showGlobalProgress ? Icons.timeline : Icons.crop_square,
              color: _showGlobalProgress ? Colors.blue : Colors.grey,
            ),
            tooltip: _showGlobalProgress ? '切换到片段进度' : '切换到全局进度',
          ),
          IconButton(
            icon: Icon(_showPlaylistInfo ? Icons.info : Icons.info_outline),
            onPressed: () {
              setState(() {
                _showPlaylistInfo = !_showPlaylistInfo;
              });
            },
            tooltip: '播放列表信息',
          ),
        ],
      ),
      body: RawKeyboardListener(
        focusNode: _focusNode, // 使用焦点节点
        onKey: _handleKeyPress,
        child: Column(
          children: [
            // 播放器区域
            Expanded(
              flex: 3,
              child: Card(
                elevation: 4.0,
                margin: const EdgeInsets.all(8.0),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    GestureDetector(
                      onTap: _togglePlayPause,
                      child: Video(controller: controller),
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
                              _buildShortcutHint('← / A', 'Previous'),
                              _buildShortcutHint('→ / D', 'Next'),
                              _buildShortcutHint('P', 'Toggle Progress Mode'),
                              _buildShortcutHint('M', 'Toggle Playback Mode'),
                              _buildShortcutHint('Ctrl+1-9', 'Play Item 1-9'),
                              _buildShortcutHint('Ctrl+0', 'Play Item 10'),
                              _buildShortcutHint('F1', 'Toggle Hints'),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // 播放列表信息区域
            if (_showPlaylistInfo) ...[
              Container(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 当前播放信息
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '当前播放: ${_currentItem?.clip.name ?? ""}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Row(
                                spacing: 8,
                                children: [
                                  Text(
                                    '${_currentItemIndex + 1} / ${_generatedPlaylist.length}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(width: 8, child: Text("|")),
                                  // 添加播放模式信息
                                  Text(
                                    '播放模式: ${_getPlaybackModeText()}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _getPlaybackModeColor(),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 8, child: Text("|")),
                                  // 添加全局播放进度
                                  Text(
                                    '全局进度: ${_formatDuration(_totalPlayedTime)} / ${_formatDuration(_totalDuration)} (${_getGlobalProgressPercentage()}%)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue.shade600,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // 播放控制按钮
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.skip_previous),
                              onPressed: _currentItemIndex > 0
                                  ? _playPreviousItem
                                  : null,
                              tooltip: '上一个片段 (← / A)',
                            ),
                            IconButton(
                              icon: Icon(
                                _isPlaying ? Icons.pause : Icons.play_arrow,
                              ),
                              onPressed: _togglePlayPause,
                              tooltip: _isPlaying ? '暂停 (Space)' : '播放 (Space)',
                            ),
                            IconButton(
                              icon: const Icon(Icons.skip_next),
                              onPressed:
                                  _currentItemIndex < _playlistItems.length - 1
                                  ? _playNextItem
                                  : null,
                              tooltip: '下一个片段 (→ / D)',
                            ),
                            IconButton(
                              icon: const Icon(Icons.replay),
                              onPressed: _replayCurrentItem,
                              tooltip: '重播当前片段 (R)',
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // 统一进度条（固定高度，避免跳动）
                    Container(
                      height: 40, // 固定高度
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      child: _showGlobalProgress
                          ? _buildGlobalProgressBar()
                          : _buildClipProgressBar(),
                    ),
                  ],
                ),
              ),
            ],

            // 播放列表轨道视图
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '播放列表轨道',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(child: _buildPlaylistTimeline()),
                  ],
                ),
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

  Widget _buildPlaylistTimeline() {
    if (_playlistItems.isEmpty) {
      return const Center(child: Text('暂无片段'));
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ListView.builder(
        itemCount: _playlistItems.length,
        itemBuilder: (context, index) {
          final itemWithClip = _playlistItems[index];
          final isCurrentItem = _currentItem?.clip.id == itemWithClip.clip.id;
          final isPlayed =
              _playedItems.isNotEmpty &&
              _playedItems.contains(_currentItemIndex);

          // 计算在预生成列表中的排序位置
          final generatedIndex = _generatedPlaylist.indexWhere(
            (item) => item.clip.id == itemWithClip.clip.id,
          );
          final sortOrder = generatedIndex >= 0 ? generatedIndex + 1 : null;

          return GestureDetector(
            onTap: () => _playItemAtIndex(index),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                color: isCurrentItem
                    ? _getClipColor(itemWithClip.clip).withValues(
                        alpha: 0.3,
                      ) // 当前播放项使用更深的颜色
                    : _getClipColor(
                        itemWithClip.clip,
                      ).withValues(alpha: 0.1), // 其他项使用浅色背景
                borderRadius: BorderRadius.circular(8),
                border: isCurrentItem
                    ? Border.all(
                        color: _getClipColor(itemWithClip.clip),
                        width: 2,
                      )
                    : null,
              ),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    // 播放状态指示器
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isCurrentItem
                            ? _getClipColor(itemWithClip.clip)
                            : isPlayed
                            ? Colors.green.shade400
                            : Colors.grey.shade400,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),

                    // 片段信息
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            itemWithClip.clip.name,
                            style: TextStyle(
                              fontWeight: isCurrentItem
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isCurrentItem
                                  ? Colors.blue.shade700
                                  : Colors.black87,
                              fontSize: isCurrentItem ? 14 : 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Row(
                            children: [
                              Text(
                                '时长: ${_formatDuration(itemWithClip.effectiveDuration)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              if (itemWithClip.item.customStartTime != null ||
                                  itemWithClip.item.customEndTime != null) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade100,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                  child: Text(
                                    '自定义',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.orange.shade700,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),

                    // 序号
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: isCurrentItem
                            ? Colors.blue.shade100
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isCurrentItem
                                ? Colors.blue.shade600
                                : Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ),

                    // 排序标记（始终显示，与数字标记区分）
                    if (sortOrder != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.shade100,
                          borderRadius: BorderRadius.circular(2), // 正方形边框
                          border: Border.all(
                            color: Colors.deepPurple.shade400,
                            width: 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '$sortOrder',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepPurple.shade700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDuration(Duration d) {
    final parts = d.toString().split('.').first.padLeft(8, '0').split(':');
    return '${parts[0]}:${parts[1]}:${parts[2]}';
  }

  String _getGlobalProgressPercentage() {
    if (_totalDuration.inSeconds == 0) {
      return '0';
    }

    // 计算百分比，但限制在100%以内
    final percentage =
        (_totalPlayedTime.inSeconds / _totalDuration.inSeconds) * 100;
    return percentage.clamp(0.0, 100.0).toStringAsFixed(0);
  }

  Duration _getCurrentItemRelativePosition() {
    if (_currentItem == null) {
      return Duration.zero;
    }
    final currentItemStartTime =
        _currentItem!.item.customStartTime ?? _currentItem!.clip.startTime;
    return _currentPosition - currentItemStartTime;
  }

  Widget _buildGlobalProgressBar() {
    if (_generatedPlaylist.isEmpty) {
      return const LinearProgressIndicator(
        value: 0.0,
        backgroundColor: Colors.grey,
        valueColor: AlwaysStoppedAnimation<Color>(Colors.transparent),
        minHeight: 6,
      );
    }

    return Row(
      // 时间显示
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 时间显示
        Text(
          _formatDuration(_totalPlayedTime),
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        const SizedBox(width: 8),
        // 彩色进度条
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Container(
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Stack(
                  children: [
                    // 绘制底色分段（按clip颜色）
                    _buildBackgroundSegments(constraints.maxWidth),
                    // 绘制当前播放进度（透明黑色覆盖层）
                    _buildProgressOverlay(constraints.maxWidth),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        // 时间显示
        Text(
          _formatDuration(_totalDuration),
          style: const TextStyle(fontFamily: 'monospace'),
        ),
      ],
    );
  }

  Widget _buildClipProgressBar() {
    if (_currentItem == null) {
      return const LinearProgressIndicator(
        value: 0.0,
        backgroundColor: Colors.grey,
        valueColor: AlwaysStoppedAnimation<Color>(Colors.transparent),
        minHeight: 6,
      );
    }

    return CustomProgressBar(
      player: player,
      startTime:
          _currentItem!.item.customStartTime ?? _currentItem!.clip.startTime,
      endTime: _currentItem!.item.customEndTime ?? _currentItem!.clip.endTime,
      onSetStart: (position) async {
        // 播放模式下不需要设置开始时间
      },
      onSetEnd: (position) async {
        // 播放模式下不需要设置结束时间
      },
      isPlaybackMode: true, // 启用播放模式
      showClipRelativeProgress: true, // 显示clip相对进度
      showThumbnailPreview: true, // 显示预览图
      videoPath: _currentItem!.clip.videoPath, // 视频路径
    );
  }

  Widget _buildBackgroundSegments(double containerWidth) {
    final List<Widget> segments = [];
    double accumulatedProgress = 0.0;

    // 绘制所有clip的底色分段
    for (int i = 0; i < _generatedPlaylist.length; i++) {
      final item = _generatedPlaylist[i];
      final itemDuration = item.effectiveDuration;
      final itemProgress =
          itemDuration.inMilliseconds / _totalDuration.inMilliseconds;

      segments.add(
        Positioned(
          left: accumulatedProgress * containerWidth,
          child: Container(
            width: itemProgress * containerWidth,
            height: 8,
            decoration: BoxDecoration(
              color: _getClipColor(item.clip).withValues(alpha: 0.35), // 半透明底色
              // borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      );

      accumulatedProgress += itemProgress;
    }

    return Stack(children: segments);
  }

  Widget _buildProgressOverlay(double containerWidth) {
    if (_totalDuration.inMilliseconds == 0) return const SizedBox.shrink();

    // 计算总播放进度
    double totalPlayedProgress = 0.0;

    // 已完成的片段
    for (
      int i = 0;
      i < _playedItems.length && i < _generatedPlaylist.length;
      i++
    ) {
      final item = _generatedPlaylist[_playedItems[i]];
      final itemDuration = item.effectiveDuration;
      totalPlayedProgress +=
          itemDuration.inMilliseconds / _totalDuration.inMilliseconds;
    }

    // 当前片段的进度
    if (_currentItem != null) {
      final currentItemPlayedTime = _getCurrentItemRelativePosition();
      final currentItemDuration = _currentItem!.effectiveDuration;
      if (currentItemDuration.inMilliseconds > 0) {
        final currentItemProgress =
            currentItemPlayedTime.inMilliseconds /
            currentItemDuration.inMilliseconds;

        // 计算当前片段在总进度中的位置
        double currentItemPosition = 0.0;
        for (
          int i = 0;
          i < _playedItems.length && i < _generatedPlaylist.length;
          i++
        ) {
          final item = _generatedPlaylist[_playedItems[i]];
          final itemDuration = item.effectiveDuration;
          currentItemPosition +=
              itemDuration.inMilliseconds / _totalDuration.inMilliseconds;
        }

        // 当前片段已播放的部分
        final currentItemProgressInTotal =
            (currentItemDuration.inMilliseconds /
                _totalDuration.inMilliseconds) *
            currentItemProgress;
        totalPlayedProgress += currentItemProgressInTotal;
      }
    }

    return Positioned(
      left: 0,
      child: Container(
        width: totalPlayedProgress * containerWidth,
        height: 8,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3), // 透明黑色覆盖层
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }

  Color _getClipColor(VideoClip clip) {
    // 使用与 playlist_timeline_view 相同的颜色计算逻辑
    final List<Color> _userDefinedTimelineColors = [
      Colors.blue.shade400,
      Colors.green.shade400,
      Colors.orange.shade400,
      Colors.purple.shade400,
      Colors.red.shade400,
      Colors.teal.shade400,
      Colors.indigo.shade400,
      Colors.pink.shade400,
      Colors.blue.shade600,
      Colors.green.shade600,
      Colors.orange.shade600,
      Colors.purple.shade600,
      Colors.red.shade600,
      Colors.teal.shade600,
      Colors.indigo.shade600,
      Colors.pink.shade600,
      Colors.blue.shade300,
      Colors.green.shade300,
      Colors.orange.shade300,
      Colors.purple.shade300,
      Colors.red.shade300,
      Colors.teal.shade300,
      Colors.indigo.shade300,
      Colors.pink.shade300,
    ];

    final hash = clip.id.hashCode.abs();
    final colorIndex =
        (hash * 7 + hash ~/ 7) % _userDefinedTimelineColors.length;
    return _userDefinedTimelineColors[colorIndex];
  }
}
