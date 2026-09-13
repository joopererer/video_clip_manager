import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' hide Playlist;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../../data/models.dart';
import '../../data/app_state.dart';
// 添加颜色生成函数的导入
import '../../widgets/custom_progress_bar.dart';
import '../../services/preview_service.dart';
import '../../services/screenshot_service.dart';

// 播放模式枚举
enum PlaybackMode {
  sequential, // 顺序播放
  loop, // 循环播放
  random, // 随机播放
}

// Clip 映射数据结构
class ClipMapping {
  final int clipIndex;
  final Duration globalStartTime;
  final Duration globalEndTime;
  final Duration clipStartTime;
  final Duration clipEndTime;
  final String videoPath;

  ClipMapping({
    required this.clipIndex,
    required this.globalStartTime,
    required this.globalEndTime,
    required this.clipStartTime,
    required this.clipEndTime,
    required this.videoPath,
  });
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
  bool _showHints = false; // 控制提示显示
  bool _showGlobalProgress = false; // 控制进度条模式：false=片段进度，true=全局进度
  bool _isMuted = false; // 静音状态
  
  // 新增：全局进度条交互状态
  bool _isHoveringGlobalProgress = false;
  double? _hoverDx;
  Duration? _hoverTime;
  Uint8List? _thumbnailData;
  Future<void>? _pendingPreview;

  // 新增：跨 clip 点击定位后的延迟 seek（等待新视频加载完成）
  Duration? _pendingGlobalSeekTime;
  int? _pendingGlobalSeekClipIndex;

  // 播放模式相关
  PlaybackMode _playbackMode = PlaybackMode.sequential;
  Duration _totalPlayedTime = Duration.zero; // 总播放时间
  final List<int> _playedItems = []; // 已播放的片段索引
  List<PlaylistItemWithClip> _generatedPlaylist = []; // 预生成的播放列表

  @override
  void initState() {
    super.initState();
    player = Player();
    controller = VideoController(player);
    _focusNode = FocusNode(); // 初始化焦点节点
    // Disable screenshot host while playlist playback is active to reduce texture races
    ScreenshotService().disableHost();
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
    if (kDebugMode) {
      print('Playlist: Key pressed: ${event.logicalKey.keyLabel}');
    } // 调试信息

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
        case 'S':
        case 's':
          // S键：切换静音
          _toggleMute();
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

  // 切换静音状态
  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });

    if (_isMuted) {
      player.setVolume(0);
      print('Playlist: Audio muted');
    } else {
      player.setVolume(100);
      print('Playlist: Audio unmuted');
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

    // 根据播放模式重新生成播放列表
    if (_playbackMode == PlaybackMode.random) {
      // 随机模式：生成随机播放列表，将当前片段放在第一个位置
      _generatePlaylistWithCurrentFirst(currentItem);
    } else {
      // 顺序和循环模式：使用默认列表次序，不重新排列
      _useDefaultPlaylistOrder();
    }

    // 根据播放模式设置当前索引
    if (_playbackMode == PlaybackMode.random) {
      // 随机模式：当前片段放在第一个位置
      _currentItemIndex = 0;
      _currentItem = _generatedPlaylist[0];
    } else {
      // 顺序和循环模式：找到当前片段在默认列表中的位置
      if (currentItem != null) {
        int currentItemIndexInDefault = -1;
        for (int i = 0; i < _generatedPlaylist.length; i++) {
          if (_generatedPlaylist[i].clip.id == currentItem.clip.id) {
            currentItemIndexInDefault = i;
            break;
          }
        }

        if (currentItemIndexInDefault >= 0) {
          _currentItemIndex = currentItemIndexInDefault;
          _currentItem = _generatedPlaylist[currentItemIndexInDefault];
        } else {
          _currentItemIndex = 0;
          _currentItem = _generatedPlaylist[0];
        }
      } else {
        _currentItemIndex = 0;
        _currentItem = _generatedPlaylist[0];
      }
    }

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
      // 打印默认播放列表信息
      print(
        'Playlist: Default playlist initialized with ${_playlistItems.length} items:',
      );
      for (int i = 0; i < _playlistItems.length; i++) {
        print(
          'Playlist: Default item $i: ${_playlistItems[i].clip.name} (ID: ${_playlistItems[i].clip.id})',
        );
      }

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

      // 跳转到开始时间或挂起的全局定位时间
      final seekTarget = (_pendingGlobalSeekClipIndex == _currentItemIndex &&
              _pendingGlobalSeekTime != null)
          ? _pendingGlobalSeekTime!
          : startTime;
      await player.seek(seekTarget);

      // 再等待一下确保seek完成
      await Future.delayed(Duration(milliseconds: 50));

      // 开始播放
      await player.play();

      setState(() {
        _isPlaying = true;
      });

      // 清除挂起的全局定位
      _pendingGlobalSeekTime = null;
      _pendingGlobalSeekClipIndex = null;
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
            // 循环播放：基于播放历史计算进度
            // 计算当前轮次：已播放片段数 / 总长度
            final completedRounds =
                _playedItems.length ~/ _generatedPlaylist.length;
            final currentPositionInRound = _currentItemIndex;

            // 完整轮次的总时长
            _totalPlayedTime = _totalDuration * completedRounds;

            // 当前轮次已播放的片段
            for (int i = 0; i < currentPositionInRound; i++) {
              _totalPlayedTime += _generatedPlaylist[i].effectiveDuration;
            }

            // 添加调试信息
            print(
              'Playlist: Loop mode progress - completedRounds: $completedRounds, currentPositionInRound: $currentPositionInRound',
            );
            print(
              'Playlist: Loop mode progress - totalPlayedTime: $_totalPlayedTime, totalDuration: $_totalDuration',
            );
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

    // 记录当前片段为已播放（在切换到下一个片段之前）
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

        print(
          'Playlist: Random mode - playedItems: $_playedItems, unplayedItems: $unplayedItems',
        ); // 调试信息

        // 如果所有片段都播放过了，重新开始
        if (unplayedItems.isEmpty) {
          print('Playlist: All items played, resetting for new round'); // 调试信息
          _playedItems.clear();

          // 保存当前播放的片段（刚播放完的片段）
          final lastPlayedClip = _currentItem;

          // 重新生成随机播放列表，确保第一个片段与刚播放完的不同
          _generateRandomPlaylistExcluding(lastPlayedClip);

          // 新列表的第一个片段开始播放
          nextIndex = 0;
          print(
            'Playlist: New random playlist generated, starting with index 0',
          ); // 调试信息

          // 强制更新UI以确保底色分段同步（在重新生成播放列表后）
          if (mounted) {
            setState(() {});
            print(
              'Playlist: UI updated after playlist regeneration in _playNextItem',
            );
          }

          // 重要：重新生成播放列表后，需要重新计算未播放的片段
          unplayedItems = [];
          for (int i = 0; i < _generatedPlaylist.length; i++) {
            if (!_playedItems.contains(i)) {
              unplayedItems.add(i);
            }
          }
          print(
            'Playlist: After regeneration - playedItems: $_playedItems, unplayedItems: $unplayedItems',
          ); // 调试信息
        } else {
          nextIndex = unplayedItems[Random().nextInt(unplayedItems.length)];
        }
        print('Playlist: Random mode - next index will be $nextIndex'); // 调试信息
        break;
    }

    print('Playlist: Next index calculated: $nextIndex'); // 调试信息

    if (nextIndex >= 0 && nextIndex < _generatedPlaylist.length) {
      print('Playlist: Playing next item at index $nextIndex'); // 调试信息
      print(
        'Playlist: Current item will be: ${_generatedPlaylist[nextIndex].clip.name}',
      ); // 调试信息
      _currentItemIndex = nextIndex;
      _currentItem = _generatedPlaylist[_currentItemIndex];
      _currentItemDuration = _currentItem!.effectiveDuration;

      // 强制更新UI以确保底色分段同步
      if (mounted) {
        setState(() {});
      }

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
    if (_generatedPlaylist.isEmpty) return;

    int previousIndex = -1;

    switch (_playbackMode) {
      case PlaybackMode.sequential:
        // 顺序模式：只有当前不是第一个时才可播放上一个
        if (_currentItemIndex > 0) {
          previousIndex = _currentItemIndex - 1;
        }
        break;
      case PlaybackMode.loop:
        // 循环模式：可以循环到最后一个
        previousIndex =
            (_currentItemIndex - 1 + _generatedPlaylist.length) %
            _generatedPlaylist.length;
        break;
      case PlaybackMode.random:
        // 随机模式：如果当前是第一个，重新生成列表
        if (_currentItemIndex == 0) {
          print(
            'Playlist: At first item in random mode, regenerating playlist',
          );

          // 保存当前播放的片段
          final currentClip = _currentItem;

          // 重新生成随机播放列表，确保第一个不是当前播放的
          _generateRandomPlaylistExcluding(currentClip);

          // 新列表的第一个位置开始播放
          previousIndex = 0;
          print(
            'Playlist: New random playlist generated, starting from first position: $previousIndex',
          );

          // 强制更新UI以确保底色分段同步（在重新生成播放列表后）
          if (mounted) {
            setState(() {});
            print(
              'Playlist: UI updated after playlist regeneration in _playPreviousItem',
            );
          }
        } else {
          // 如果不在第一个，跳到当前列表的前一个位置
          previousIndex = _currentItemIndex - 1;
          print(
            'Playlist: Random mode - going to previous item at index $previousIndex',
          );
        }
        break;
    }

    if (previousIndex >= 0 && previousIndex < _generatedPlaylist.length) {
      print('Playlist: Playing previous item at index $previousIndex'); // 调试信息
      print(
        'Playlist: Previous item will be: ${_generatedPlaylist[previousIndex].clip.name}',
      ); // 调试信息
      _currentItemIndex = previousIndex;
      _currentItem = _generatedPlaylist[previousIndex];
      _currentItemDuration = _currentItem!.effectiveDuration;

      // 强制更新UI以确保底色分段同步
      if (mounted) {
        setState(() {});
      }

      // 重新初始化播放器
      await _initializePlayer();
    } else {
      print('Playlist: No previous item to play'); // 调试信息
    }
  }

  void _playItemAtIndex(int index) async {
    // 找到在 _generatedPlaylist 中对应的索引
    if (index >= 0 && index < _playlistItems.length) {
      final targetClipId = _playlistItems[index].clip.id;
      final generatedIndex = _generatedPlaylist.indexWhere(
        (item) => item.clip.id == targetClipId,
      );
      
      if (generatedIndex >= 0) {
        _currentItemIndex = generatedIndex;
        _currentItem = _generatedPlaylist[generatedIndex];
        _currentItemDuration = _currentItem!.effectiveDuration;

        // 重新初始化播放器
        await _initializePlayer();
      }
    }
  }

  // 新增：根据 _generatedPlaylist 索引播放（用于全局进度条点击）
  void _playItemAtGeneratedIndex(int generatedIndex) async {
    if (generatedIndex >= 0 && generatedIndex < _generatedPlaylist.length) {
      _currentItemIndex = generatedIndex;
      _currentItem = _generatedPlaylist[generatedIndex];
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

  void _replayCurrentItem() async {
    if (_currentItem != null) {
      await _initializePlayer();
    }
  }

  // 获取当前clip的唯一标识
  String _getCurrentClipKey() {
    return "${_currentItem?.clip.id}_$_currentItemIndex";
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

    // 重新计算总时长
    _totalDuration = _calculateTotalDuration();

    // 强制更新UI以确保底色分段同步
    if (mounted) {
      setState(() {});
    }

    print(
      'Playlist: Generated playlist with ${_generatedPlaylist.length} items for ${_playbackMode} mode',
    );
    print('Playlist: Total duration updated to: $_totalDuration');
  }

  // 生成随机播放列表，确保指定片段不在第一个位置（用于随机模式重新生成）
  void _generateRandomPlaylistExcluding(PlaylistItemWithClip? excludeItem) {
    _generatedPlaylist.clear();

    if (excludeItem == null) {
      // 如果没有要排除的片段，正常生成
      _generatePlaylist();
      return;
    }

    print('Playlist: Original playlist has ${_playlistItems.length} items');
    print(
      'Playlist: Ensuring ${excludeItem.clip.name} is not at first position',
    );

    // 打印所有原始片段的ID，检查是否有重复
    print('Playlist: All original items:');
    for (int i = 0; i < _playlistItems.length; i++) {
      print(
        'Playlist: Item $i: ${_playlistItems[i].clip.name} (ID: ${_playlistItems[i].clip.id})',
      );
    }

    // 检查是否有重复的ID
    final Set<String> allIds = {};
    final List<String> duplicateIds = [];
    for (final item in _playlistItems) {
      if (allIds.contains(item.clip.id)) {
        duplicateIds.add(item.clip.id);
      } else {
        allIds.add(item.clip.id);
      }
    }

    if (duplicateIds.isNotEmpty) {
      print('Playlist: WARNING - Found duplicate IDs: $duplicateIds');
    } else {
      print('Playlist: All IDs are unique');
    }

    // 生成随机播放列表，确保指定片段不在第一个位置
    _generatedPlaylist = List.from(_playlistItems);
    _generatedPlaylist.shuffle(Random());

    // 如果指定片段在第一个位置，将其移动到其他随机位置
    if (_generatedPlaylist[0].clip.id == excludeItem.clip.id) {
      print(
        'Playlist: Excluded item was at first position, moving to random position',
      );

      // 随机选择一个非第一个位置
      final randomPosition =
          Random().nextInt(_generatedPlaylist.length - 1) + 1;

      // 交换第一个位置和随机位置
      final temp = _generatedPlaylist[0];
      _generatedPlaylist[0] = _generatedPlaylist[randomPosition];
      _generatedPlaylist[randomPosition] = temp;

      print(
        'Playlist: Moved ${excludeItem.clip.name} from position 0 to position $randomPosition',
      );
    } else {
      print(
        'Playlist: Excluded item is not at first position, no need to move',
      );
    }

    // 重新计算总时长
    _totalDuration = _calculateTotalDuration();

    // 强制更新UI以确保底色分段同步
    if (mounted) {
      setState(() {});
      print('Playlist: UI updated via setState()');
    } else {
      print('Playlist: WARNING - Widget not mounted, cannot update UI');
    }

    print(
      'Playlist: Generated random playlist ensuring ${excludeItem.clip.name} not at first',
    );
    print('Playlist: New playlist has ${_generatedPlaylist.length} items');
    print('Playlist: Total duration updated to: $_totalDuration');

    // 打印最终播放列表
    print('Playlist: Final playlist order:');
    for (int i = 0; i < _generatedPlaylist.length; i++) {
      print('Playlist: Position $i: ${_generatedPlaylist[i].clip.name}');
    }

    // 验证播放列表是否正确更新
    print('Playlist: Verification - _generatedPlaylist content:');
    for (int i = 0; i < _generatedPlaylist.length; i++) {
      print('Playlist: Generated[$i]: ${_generatedPlaylist[i].clip.name}');
    }
  }

  // 生成随机播放列表，确保指定片段不在最后一个位置（用于随机模式上一首）
  void _generateRandomPlaylistExcludingLast(PlaylistItemWithClip? excludeItem) {
    _generatedPlaylist.clear();

    if (excludeItem == null) {
      // 如果没有要排除的片段，正常生成
      _generatePlaylist();
      return;
    }

    print('Playlist: Original playlist has ${_playlistItems.length} items');
    print(
      'Playlist: Ensuring ${excludeItem.clip.name} is not at last position',
    );

    // 打印所有原始片段的ID，检查是否有重复
    print('Playlist: All original items:');
    for (int i = 0; i < _playlistItems.length; i++) {
      print(
        'Playlist: Item $i: ${_playlistItems[i].clip.name} (ID: ${_playlistItems[i].clip.id})',
      );
    }

    // 检查是否有重复的ID
    final Set<String> allIds = {};
    final List<String> duplicateIds = [];
    for (final item in _playlistItems) {
      if (allIds.contains(item.clip.id)) {
        duplicateIds.add(item.clip.id);
      } else {
        allIds.add(item.clip.id);
      }
    }

    if (duplicateIds.isNotEmpty) {
      print('Playlist: WARNING - Found duplicate IDs: $duplicateIds');
    } else {
      print('Playlist: All IDs are unique');
    }

    // 生成随机播放列表，确保指定片段不在最后一个位置
    _generatedPlaylist = List.from(_playlistItems);
    _generatedPlaylist.shuffle(Random());

    // 如果指定片段在最后一个位置，将其移动到其他随机位置
    if (_generatedPlaylist[_generatedPlaylist.length - 1].clip.id ==
        excludeItem.clip.id) {
      print(
        'Playlist: Excluded item was at last position, moving to random position',
      );

      // 随机选择一个非最后一个位置
      final randomPosition = Random().nextInt(_generatedPlaylist.length - 1);

      // 交换最后一个位置和随机位置
      final temp = _generatedPlaylist[_generatedPlaylist.length - 1];
      _generatedPlaylist[_generatedPlaylist.length - 1] =
          _generatedPlaylist[randomPosition];
      _generatedPlaylist[randomPosition] = temp;

      print(
        'Playlist: Moved ${excludeItem.clip.name} from last position to position $randomPosition',
      );
    } else {
      print('Playlist: Excluded item is not at last position, no need to move');
    }

    // 重新计算总时长
    _totalDuration = _calculateTotalDuration();

    // 强制更新UI以确保底色分段同步
    if (mounted) {
      setState(() {});
    }

    print(
      'Playlist: Generated random playlist ensuring ${excludeItem.clip.name} not at last',
    );
    print('Playlist: New playlist has ${_generatedPlaylist.length} items');
    print('Playlist: Total duration updated to: $_totalDuration');

    // 打印最终播放列表
    print('Playlist: Final playlist order:');
    for (int i = 0; i < _generatedPlaylist.length; i++) {
      print('Playlist: Position $i: ${_generatedPlaylist[i].clip.name}');
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
        // 顺序/循环模式：使用默认列表次序，重新定位到当前片段
        // 找到当前片段在默认列表中的位置
        int currentItemIndexInDefault = -1;
        for (int i = 0; i < _playlistItems.length; i++) {
          if (_playlistItems[i].clip.id == currentItem.clip.id) {
            currentItemIndexInDefault = i;
            break;
          }
        }

        if (currentItemIndexInDefault >= 0) {
          // 从当前片段开始，按默认列表次序重新排列
          for (
            int i = currentItemIndexInDefault;
            i < _playlistItems.length;
            i++
          ) {
            _generatedPlaylist.add(_playlistItems[i]);
          }
          // 添加当前片段之前的片段（循环）
          for (int i = 0; i < currentItemIndexInDefault; i++) {
            _generatedPlaylist.add(_playlistItems[i]);
          }
        } else {
          // 如果找不到当前片段，使用默认列表
          _generatedPlaylist = List.from(_playlistItems);
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

    // 强制更新UI以确保底色分段同步
    if (mounted) {
      setState(() {});
    }

    print(
      'Playlist: Generated playlist with current first, ${_generatedPlaylist.length} items for ${_playbackMode} mode',
    );
  }

  // 恢复默认播放列表并定位到当前片段
  void _restoreDefaultPlaylistWithCurrentItem(
    PlaylistItemWithClip? currentItem,
  ) {
    _generatedPlaylist.clear();

    if (currentItem == null) {
      // 如果没有当前片段，使用默认列表
      _generatedPlaylist = List.from(_playlistItems);
    } else {
      // 找到当前片段在默认列表中的位置
      int currentItemIndexInDefault = -1;
      for (int i = 0; i < _playlistItems.length; i++) {
        if (_playlistItems[i].clip.id == currentItem.clip.id) {
          currentItemIndexInDefault = i;
          break;
        }
      }

      if (currentItemIndexInDefault >= 0) {
        // 从当前片段开始，按默认列表次序重新排列
        for (
          int i = currentItemIndexInDefault;
          i < _playlistItems.length;
          i++
        ) {
          _generatedPlaylist.add(_playlistItems[i]);
        }
        // 添加当前片段之前的片段（循环）
        for (int i = 0; i < currentItemIndexInDefault; i++) {
          _generatedPlaylist.add(_playlistItems[i]);
        }
      } else {
        // 如果找不到当前片段，使用默认列表
        _generatedPlaylist = List.from(_playlistItems);
      }
    }

    // 强制更新UI以确保底色分段同步
    if (mounted) {
      setState(() {});
    }

    print(
      'Playlist: Restored default playlist with current item, ${_generatedPlaylist.length} items for ${_playbackMode} mode',
    );
  }

  // 使用默认播放列表次序（不重新排列）
  void _useDefaultPlaylistOrder() {
    _generatedPlaylist = List.from(_playlistItems);

    // 强制更新UI以确保底色分段同步
    if (mounted) {
      setState(() {});
    }

    print(
      'Playlist: Using default playlist order, ${_generatedPlaylist.length} items for ${_playbackMode} mode',
    );
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

    // Delay player disposal until screenshot queue is idle to avoid native texture races
    ScreenshotService().whenIdle().then((_) async {
      try {
        await player.dispose();
        print('Playlist player disposed (delayed)');
      } catch (e) {
        print('Error disposing playlist player after idle: $e');
        try {
          player.dispose();
        } catch (e2) {
          print('Force dispose failed: $e2');
        }
      } finally {
        // Re-enable screenshot host after player disposed
        try {
          ScreenshotService().markReady();
          print('ScreenshotService: markReady() called after playlist dispose');
        } catch (e) {
          print('Error marking ScreenshotService ready: $e');
        }
      }
    });

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
                              _buildShortcutHint('S', 'Toggle Mute'),
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
                              onPressed: _canPlayPrevious()
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
                              onPressed: _canPlayNext() ? _playNextItem : null,
                              tooltip: '下一个片段 (→ / D)',
                            ),
                            IconButton(
                              icon: const Icon(Icons.replay),
                              onPressed: _replayCurrentItem,
                              tooltip: '重播当前片段 (R)',
                            ),
                            IconButton(
                              icon: Icon(
                                _isMuted ? Icons.volume_off : Icons.volume_up,
                              ),
                              onPressed: _toggleMute,
                              tooltip: _isMuted ? '取消静音 (S)' : '静音 (S)',
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

  Duration _getDisplayTime() {
    if (_playbackMode == PlaybackMode.loop) {
      // 循环模式：显示当前轮次内的播放时间
      final completedRounds = _playedItems.length ~/ _generatedPlaylist.length;
      final currentPositionInRound = _currentItemIndex;

      // 计算当前轮次内的播放时间
      Duration currentRoundPlayedTime = Duration.zero;

      // 当前轮次已播放的片段
      for (int i = 0; i < currentPositionInRound; i++) {
        currentRoundPlayedTime += _generatedPlaylist[i].effectiveDuration;
      }

      // 添加调试信息
      print(
        'Playlist: Display time - completedRounds: $completedRounds, currentPositionInRound: $currentPositionInRound',
      );
      print(
        'Playlist: Display time - currentRoundPlayedTime: $currentRoundPlayedTime',
      );

      // 加上当前片段的播放时间
      if (_currentItem != null) {
        final currentItemStartTime =
            _currentItem!.item.customStartTime ?? _currentItem!.clip.startTime;
        final currentItemEndTime =
            _currentItem!.item.customEndTime ?? _currentItem!.clip.endTime;
        final currentItemDuration = currentItemEndTime - currentItemStartTime;
        final relativePosition = _currentPosition - currentItemStartTime;

        Duration currentItemPlayedTime;
        if (relativePosition < Duration.zero) {
          currentItemPlayedTime = Duration.zero;
        } else if (relativePosition > currentItemDuration) {
          currentItemPlayedTime = currentItemDuration;
        } else {
          currentItemPlayedTime = relativePosition;
        }

        currentRoundPlayedTime += currentItemPlayedTime;
      }

      return currentRoundPlayedTime;
    } else {
      // 顺序和随机模式：显示总播放时间
      return _totalPlayedTime;
    }
  }

  String _getGlobalProgressPercentage() {
    if (_totalDuration.inSeconds == 0) {
      return '0';
    }

    // 根据播放模式计算百分比
    if (_playbackMode == PlaybackMode.loop) {
      // 循环模式：计算当前轮次内的进度
      final completedRounds = _playedItems.length ~/ _generatedPlaylist.length;
      final currentPositionInRound = _currentItemIndex;

      // 计算当前轮次内的播放时间
      Duration currentRoundPlayedTime = Duration.zero;

      // 当前轮次已播放的片段
      for (int i = 0; i < currentPositionInRound; i++) {
        currentRoundPlayedTime += _generatedPlaylist[i].effectiveDuration;
      }

      // 加上当前片段的播放时间
      if (_currentItem != null) {
        final currentItemStartTime =
            _currentItem!.item.customStartTime ?? _currentItem!.clip.startTime;
        final currentItemEndTime =
            _currentItem!.item.customEndTime ?? _currentItem!.clip.endTime;
        final currentItemDuration = currentItemEndTime - currentItemStartTime;
        final relativePosition = _currentPosition - currentItemStartTime;

        Duration currentItemPlayedTime;
        if (relativePosition < Duration.zero) {
          currentItemPlayedTime = Duration.zero;
        } else if (relativePosition > currentItemDuration) {
          currentItemPlayedTime = currentItemDuration;
        } else {
          currentItemPlayedTime = relativePosition;
        }

        currentRoundPlayedTime += currentItemPlayedTime;
      }

      // 计算当前轮次内的百分比
      final percentage =
          (currentRoundPlayedTime.inSeconds / _totalDuration.inSeconds) * 100;
      return percentage.clamp(0.0, 100.0).toStringAsFixed(0);
    } else {
      // 顺序和随机模式：使用原有的计算方式
      final percentage =
          (_totalPlayedTime.inSeconds / _totalDuration.inSeconds) * 100;
      return percentage.clamp(0.0, 100.0).toStringAsFixed(0);
    }
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
          _formatDuration(_getDisplayTime()),
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        const SizedBox(width: 8),
        // 彩色进度条
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // 进度条容器
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // 绘制底色分段（按clip颜色）
                        _buildBackgroundSegments(constraints.maxWidth),
                        // 绘制当前播放进度（透明黑色覆盖层）
                        _buildProgressOverlay(constraints.maxWidth),
                        // 添加交互层（移除预览窗口部分）
                        _buildInteractiveLayer(constraints.maxWidth),
                      ],
                    ),
                  ),
                  // 预览窗口 - 移到这里，不会被Container高度限制
                  if (_isHoveringGlobalProgress && _hoverDx != null) ...[
                    Positioned(
                      left: _hoverDx! - 50,
                      bottom: 20,
                      child: _buildThumbnailPreview(),
                    ),
                    // 调试指示器
                    Positioned(
                      left: _hoverDx! - 2,
                      top: -10,
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ],
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

  // 新增：构建交互层
  Widget _buildInteractiveLayer(double containerWidth) {
    return MouseRegion(
      onEnter: (event) {
        print('Playlist: Mouse entered global progress bar');
        setState(() {
          _isHoveringGlobalProgress = true;
        });
      },
      onExit: (event) {
        print('Playlist: Mouse exited global progress bar');
        setState(() {
          _isHoveringGlobalProgress = false;
          _hoverDx = null;
          _hoverTime = null;
          _thumbnailData = null;
        });
      },
             onHover: (event) {
         final dx = event.localPosition.dx;
         final hoverTime = _getTimeFromDx(dx, containerWidth, _totalDuration);
         
         print('Playlist: Mouse hover at dx: $dx, time: $hoverTime');
         
         setState(() {
           _hoverDx = dx;
           _hoverTime = hoverTime;
           // 始终更新预览图，确保跨clip移动时能正确更新
           _updatePreview(hoverTime);
         });
       },
      child: GestureDetector(
        onTapUp: (details) {
          final tapTime = _getTimeFromDx(
            details.localPosition.dx,
            containerWidth,
            _totalDuration,
          );
          _handleGlobalProgressSeek(tapTime);
        },
        child: Container(
          width: containerWidth,
          height: 8,
          color: Colors.transparent,
        ),
      ),
    );
  }

  // 新增：根据 x 坐标计算时间
  Duration _getTimeFromDx(double dx, double maxWidth, Duration totalDuration) {
    final double progress = (dx / maxWidth).clamp(0.0, 1.0);
    return totalDuration * progress;
  }

  // 新增：处理全局进度条跳转
  void _handleGlobalProgressSeek(Duration globalTime) {
    // 找到对应的 clip
    final clipMapping = _findClipByGlobalTime(globalTime);
    
    if (clipMapping != null) {
      // 跳转到指定的 clip
      final targetTime = clipMapping.clipStartTime +
          (globalTime - clipMapping.globalStartTime);

      if (clipMapping.clipIndex == _currentItemIndex) {
        // 当前 clip：直接 seek
        _safeSeek(targetTime);
      } else {
        // 其他 clip：记录待处理的 seek，待新视频加载后执行
        _pendingGlobalSeekTime = targetTime;
        _pendingGlobalSeekClipIndex = clipMapping.clipIndex;
        _jumpToClip(clipMapping.clipIndex);
      }
    }
  }

  // 新增：根据全局时间找到对应的 clip
  ClipMapping? _findClipByGlobalTime(Duration globalTime) {
    Duration currentTime = Duration.zero;
    
    for (int i = 0; i < _generatedPlaylist.length; i++) {
      final item = _generatedPlaylist[i];
      final clipDuration = item.effectiveDuration;
      
      if (globalTime >= currentTime && globalTime <= currentTime + clipDuration) {
        return ClipMapping(
          clipIndex: i,
          globalStartTime: currentTime,
          globalEndTime: currentTime + clipDuration,
          clipStartTime: item.item.customStartTime ?? item.clip.startTime,
          clipEndTime: item.item.customEndTime ?? item.clip.endTime,
          videoPath: item.clip.videoPath,
        );
      }
      
      currentTime += clipDuration;
    }
    return null;
  }

  // 新增：跳转到指定的 clip
  void _jumpToClip(int clipIndex) {
    if (clipIndex >= 0 && clipIndex < _generatedPlaylist.length) {
      setState(() {
        _currentItemIndex = clipIndex;
        _currentItem = _generatedPlaylist[clipIndex];
        _hasTriggeredNextForCurrentItem = false;
      });
      
      // 使用现有的初始化逻辑加载新的视频
      _playItemAtGeneratedIndex(clipIndex);
    }
  }

  // 新增：安全的 seek 方法
  Future<void> _safeSeek(Duration position) async {
    try {
      await player.seek(position);
    } catch (e) {
      print('Playlist: Seek failed: $e');
    }
  }

  // 新增：更新预览图
  void _updatePreview(Duration time) {
    _pendingPreview?.ignore();
    _pendingPreview = Future(() async {
      try {
        // 找到对应的 clip 和视频路径
        final clipMapping = _findClipByGlobalTime(time);
        if (clipMapping != null) {
          final videoPath = clipMapping.videoPath;
          final previewTime = time - clipMapping.globalStartTime + clipMapping.clipStartTime;
          
          // 使用关键帧预览系统 - 这是同步方法，直接调用
          final data = PreviewService().getNearestKeyframe(videoPath, previewTime);
          
          if (mounted && _isHoveringGlobalProgress) {
            setState(() {
              _thumbnailData = data;
            });
          }
        }
      } catch (e) {
        print('Playlist: Preview update failed: $e');
      }
    });
  }

  // 新增：构建预览图
  Widget _buildThumbnailPreview() {
    print('Playlist: Building thumbnail preview, hoverDx: $_hoverDx, hoverTime: $_hoverTime, thumbnailData: ${_thumbnailData != null ? 'has data' : 'null'}');
    return Container(
      width: 100, // 改为与 CustomProgressBar 一致
      padding: const EdgeInsets.all(4.0), // 改为与 CustomProgressBar 一致
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8), // 改为与 CustomProgressBar 一致
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white54, width: 1), // 改为与 CustomProgressBar 一致
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_thumbnailData != null)
            Image.memory(_thumbnailData!, width: 100, fit: BoxFit.contain) // 改为与 CustomProgressBar 一致
          else
            const SizedBox(
              height: 56, // 改为与 CustomProgressBar 一致
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.image_not_supported,
                      color: Colors.white54,
                      size: 24,
                    ),
                    SizedBox(height: 4),
                    Text(
                      'No Preview',
                      style: TextStyle(color: Colors.white54, fontSize: 10),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Hover to generate',
                      style: TextStyle(color: Colors.white38, fontSize: 8),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            _formatDuration(_hoverTime ?? Duration.zero),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontFamily: 'monospace',
            ), // 移除 fontWeight: FontWeight.bold
          ),
        ],
      ),
    );
  }



     Widget _buildBackgroundSegments(double containerWidth) {
     final List<Widget> segments = [];

     // 强制刷新：确保使用最新的播放列表

    // 绘制所有clip的底色分段（按照播放列表顺序显示）
    double accumulatedProgress = 0.0;

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
            child: Center(
              child: Text(
                '${i + 1}',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
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

    // 计算当前播放位置在全局进度条中的位置
    double totalPlayedProgress = 0.0;

    // 计算当前片段之前的所有片段时长
    for (int i = 0; i < _currentItemIndex; i++) {
      final item = _generatedPlaylist[i];
      final itemDuration = item.effectiveDuration;
      totalPlayedProgress +=
          itemDuration.inMilliseconds / _totalDuration.inMilliseconds;
    }

    // 加上当前片段的进度
    if (_currentItem != null) {
      final currentItemPlayedTime = _getCurrentItemRelativePosition();
      final currentItemDuration = _currentItem!.effectiveDuration;
      if (currentItemDuration.inMilliseconds > 0) {
        final currentItemProgress =
            currentItemPlayedTime.inMilliseconds /
            currentItemDuration.inMilliseconds;

        // 当前片段已播放的部分
        final currentItemProgressInTotal =
            (currentItemDuration.inMilliseconds /
                _totalDuration.inMilliseconds) *
            currentItemProgress;
        totalPlayedProgress += currentItemProgressInTotal;
      }
    }

    // 限制进度不超过100%
    totalPlayedProgress = totalPlayedProgress.clamp(0.0, 1.0);

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

  bool _canPlayPrevious() {
    if (_generatedPlaylist.isEmpty) return false;

    switch (_playbackMode) {
      case PlaybackMode.sequential:
        // 顺序模式：只有在不是第一个时才可点击
        return _currentItemIndex > 0;
      case PlaybackMode.loop:
        // 循环模式：始终可以点击（会循环到最后一个）
        return true;
      case PlaybackMode.random:
        // 随机模式：始终可以点击（会随机选择）
        return true;
    }
  }

  int _getNextRandomIndex({bool excludeCurrent = false}) {
    List<int> availableIndices = [];
    for (int i = 0; i < _generatedPlaylist.length; i++) {
      if (!excludeCurrent || i != _currentItemIndex) {
        availableIndices.add(i);
      }
    }
    if (availableIndices.isEmpty) {
      return -1; // 没有可用索引
    }

    int selectedIndex =
        availableIndices[Random().nextInt(availableIndices.length)];
    print(
      'Playlist: Random index selected: $selectedIndex (excludeCurrent: $excludeCurrent, currentIndex: $_currentItemIndex)',
    );
    return selectedIndex;
  }

  bool _canPlayNext() {
    if (_generatedPlaylist.isEmpty) return false;

    switch (_playbackMode) {
      case PlaybackMode.sequential:
        // 顺序模式：只有在不是最后一个时才可点击
        return _currentItemIndex < _generatedPlaylist.length - 1;
      case PlaybackMode.loop:
        // 循环模式：始终可以点击（会循环到第一个）
        return true;
      case PlaybackMode.random:
        // 随机模式：始终可以点击（会随机选择）
        return true;
    }
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
