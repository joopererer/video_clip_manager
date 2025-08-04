import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' hide Playlist;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import '../../data/models.dart';
import '../../data/app_state.dart';
import '../../widgets/custom_progress_bar.dart';
import '../../widgets/custom_player_controls.dart';

class PlaylistPlaybackScreen extends StatefulWidget {
  final Playlist playlist;

  const PlaylistPlaybackScreen({
    super.key,
    required this.playlist,
  });

  @override
  State<PlaylistPlaybackScreen> createState() => _PlaylistPlaybackScreenState();
}

class _PlaylistPlaybackScreenState extends State<PlaylistPlaybackScreen> {
  late final Player player;
  late final VideoController controller;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<bool>? _playingSubscription;
  
  bool _isPlaying = false;
  int _currentItemIndex = 0;
  List<PlaylistItemWithClip> _playlistItems = [];
  PlaylistItemWithClip? _currentItem;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  Duration _currentItemDuration = Duration.zero;
  
  bool _showPlaylistInfo = true;
  bool _showCustomProgressBar = true;

  @override
  void initState() {
    super.initState();
    player = Player();
    controller = VideoController(player);
    _initializePlaylist();
  }

  void _initializePlaylist() {
    final appState = context.read<AppState>();
    
    // 使用传入的播放列表数据，而不是从 AppState 重新获取
    // 这样可以确保播放的是当前管理界面的状态
    _playlistItems = widget.playlist.items.map((playlistItem) {
      // 从 AppState 获取对应的 clip 数据
      final clip = appState.clips.firstWhere(
        (clip) => clip.id == playlistItem.clipId,
        orElse: () => throw Exception('Clip not found: ${playlistItem.clipId}'),
      );
      return PlaylistItemWithClip(item: playlistItem, clip: clip);
    }).toList();
    
    if (_playlistItems.isNotEmpty) {
      _currentItem = _playlistItems[0];
      _currentItemDuration = _currentItem!.effectiveDuration;
      _totalDuration = widget.playlist.totalDuration;
      _initializePlayer();
    }
  }

  Future<void> _initializePlayer() async {
    if (_currentItem == null) return;

    final clip = _currentItem!.clip;
    final item = _currentItem!.item;
    
    // 确定播放的起始和结束时间
    final startTime = item.customStartTime ?? clip.startTime;
    final endTime = item.customEndTime ?? clip.endTime;
    
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

    // 设置位置监听器
    _positionSubscription = player.stream.position.listen((position) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
        
        // 检查是否到达当前片段的结束时间
        // 使用当前片段的实际结束时间，而不是闭包中的变量
        final currentEndTime = _currentItem?.item.customEndTime ?? _currentItem?.clip.endTime;
        if (currentEndTime != null && position >= currentEndTime) {
          _playNextItem();
        }
      }
    });

    // 监听播放状态
    _playingSubscription = player.stream.playing.listen((playing) {
      if (mounted) {
        setState(() {
          _isPlaying = playing;
        });
      }
    });
  }

  void _playNextItem() async {
    if (_currentItemIndex < _playlistItems.length - 1) {
      _currentItemIndex++;
      _currentItem = _playlistItems[_currentItemIndex];
      _currentItemDuration = _currentItem!.effectiveDuration;
      
      // 重新初始化播放器
      await _initializePlayer();
    } else {
      // 播放列表结束，暂停播放
      await player.pause();
      setState(() {
        _isPlaying = false;
      });
    }
  }

  void _playPreviousItem() async {
    if (_currentItemIndex > 0) {
      _currentItemIndex--;
      _currentItem = _playlistItems[_currentItemIndex];
      _currentItemDuration = _currentItem!.effectiveDuration;
      
      // 重新初始化播放器
      await _initializePlayer();
    }
  }

  void _playItemAtIndex(int index) async {
    if (index >= 0 && index < _playlistItems.length) {
      _currentItemIndex = index;
      _currentItem = _playlistItems[index];
      _currentItemDuration = _currentItem!.effectiveDuration;
      
      // 重新初始化播放器
      await _initializePlayer();
    }
  }

  void _togglePlayPause() async {
    if (_isPlaying) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  void _replayCurrentItem() async {
    if (_currentItem != null) {
      await _initializePlayer();
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _playingSubscription?.cancel();
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_playlistItems.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text('播放列表: ${widget.playlist.name}'),
        ),
        body: const Center(
          child: Text('播放列表为空，请先添加片段'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('播放列表: ${widget.playlist.name}'),
        actions: [
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
      body: Column(
        children: [
          // 播放器区域
          Expanded(
            flex: 3,
            child: Card(
              elevation: 4.0,
              margin: const EdgeInsets.all(8.0),
              clipBehavior: Clip.antiAlias,
              child: GestureDetector(
                onTap: _togglePlayPause,
                child: Video(
                  controller: controller,
                  controls: (state) {
                    if (!state.mounted) return const SizedBox.shrink();
                    return CustomPlayerControls(
                      player: player,
                      isFullscreen: state.isFullscreen(),
                      onToggleFullscreen: state.toggleFullscreen,
                    );
                  },
                ),
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
                            Text(
                              '${_currentItemIndex + 1} / ${_playlistItems.length}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 播放控制按钮
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.skip_previous),
                            onPressed: _currentItemIndex > 0 ? _playPreviousItem : null,
                            tooltip: '上一个片段',
                          ),
                          IconButton(
                            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                            onPressed: _togglePlayPause,
                            tooltip: _isPlaying ? '暂停' : '播放',
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_next),
                            onPressed: _currentItemIndex < _playlistItems.length - 1 ? _playNextItem : null,
                            tooltip: '下一个片段',
                          ),
                          IconButton(
                            icon: const Icon(Icons.replay),
                            onPressed: _replayCurrentItem,
                            tooltip: '重播当前片段',
                          ),
                        ],
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 8),
                  
                                     // 进度条
                   if (_showCustomProgressBar && _currentItem != null) ...[
                     CustomProgressBar(
                       player: player,
                       startTime: _currentItem!.item.customStartTime ?? _currentItem!.clip.startTime,
                       endTime: _currentItem!.item.customEndTime ?? _currentItem!.clip.endTime,
                       onSetStart: (position) async {
                         // 播放模式下不需要设置开始时间
                       },
                       onSetEnd: (position) async {
                         // 播放模式下不需要设置结束时间
                       },
                       // isPlaybackMode: true, // 移除这个参数，因为 CustomProgressBar 不支持
                       // showClipRelativeProgress: true, // 移除这个参数，因为 CustomProgressBar 不支持
                     ),
                   ],
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
                  Expanded(
                    child: _buildPlaylistTimeline(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistTimeline() {
    if (_playlistItems.isEmpty) {
      return const Center(
        child: Text('暂无片段'),
      );
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
          final isCurrentItem = index == _currentItemIndex;
          final isPlayed = index < _currentItemIndex;
          
          return GestureDetector(
            onTap: () => _playItemAtIndex(index),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isCurrentItem 
                    ? Colors.blue.shade100 
                    : isPlayed 
                        ? Colors.green.shade50 
                        : Colors.white,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isCurrentItem 
                      ? Colors.blue.shade300 
                      : Colors.grey.shade300,
                  width: isCurrentItem ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  // 播放状态图标
                  Icon(
                    isCurrentItem 
                        ? (_isPlaying ? Icons.play_arrow : Icons.pause)
                        : isPlayed 
                            ? Icons.check_circle 
                            : Icons.radio_button_unchecked,
                    color: isCurrentItem 
                        ? Colors.blue.shade600 
                        : isPlayed 
                            ? Colors.green.shade600 
                            : Colors.grey.shade400,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  
                  // 片段信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          itemWithClip.clip.name,
                          style: TextStyle(
                            fontWeight: isCurrentItem ? FontWeight.bold : FontWeight.normal,
                            color: isCurrentItem ? Colors.blue.shade700 : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '时长: ${_formatDuration(itemWithClip.effectiveDuration)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // 序号
                  Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isCurrentItem ? Colors.blue.shade600 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
} 