import 'dart:async';
import 'dart:io';


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:multi_split_view/multi_split_view.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:http/http.dart' as http;

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../services/thumbnail_service.dart';
import '../../services/video_sniffer_service.dart';

import '../../widgets/custom_progress_bar.dart';

String formatDuration(Duration d) {
  final parts = d.toString().split('.').first.padLeft(8, '0').split(':');
  return '${parts[0]}:${parts[1]}:${parts[2]}';
}

class SaveIntent extends Intent {
  const SaveIntent();
}

class TogglePlayPauseIntent extends Intent {
  const TogglePlayPauseIntent();
}

class OnlineClipEditorScreen extends StatefulWidget {
  final OnlineVideo video;
  final OnlineVideoClip? clipToEdit;

  const OnlineClipEditorScreen({
    super.key, 
    required this.video, 
    this.clipToEdit,
  });

  @override
  State<OnlineClipEditorScreen> createState() => _OnlineClipEditorScreenState();
}

class _OnlineClipEditorScreenState extends State<OnlineClipEditorScreen> {
  late final Player player;
  late final VideoController controller;
  final MultiSplitViewController _splitViewController =
      MultiSplitViewController(
        areas: [
          Area(flex: 13, data: 'editor'),
          Area(flex: 7, data: 'list'),
        ],
      );

  late OnlineVideoClip _formClip;
  OnlineVideoClip? _originalEditingClip;

  bool _isSaving = false;
  String? _coverPreviewFullPath;
  bool _isSettingCover = false;
  int _coverPreviewTimestamp = 0;
  int _clipsListTimestamp = 0;
  String? _tempThumbnailPath;

  final _nameController = TextEditingController();
  final _notesController = TextEditingController();
  final _newTagController = TextEditingController();
  final _tagFocusNode = FocusNode();
  final _videoFocusNode = FocusNode();
  final ItemScrollController _itemScrollController = ItemScrollController();
  bool _isMuted = false;

  bool _showHints = false;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    player = Player();
    controller = VideoController(player);
    _focusNode = FocusNode();

    if (widget.clipToEdit != null) {
      _startEditing(widget.clipToEdit!, fromInit: true);
    } else {
      _resetFormToBlank();
    }

    // 对于在线视频，使用URL而不是本地路径
    _initializeVideo();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  Future<void> _initializeVideo() async {
    try {
      // 优先使用本地下载的视频
      String videoPath = widget.video.url;
      
      if (widget.video.isDownloaded && widget.video.localPath != null) {
        final localFile = File(widget.video.localPath!);
        if (await localFile.exists()) {
          videoPath = widget.video.localPath!;
          await player.open(Media(videoPath), play: false);
          return;
        }
      }
      
      // 如果是网页URL，尝试嗅探视频链接
      if (videoPath == widget.video.url && !widget.video.isDownloaded) {
        await _sniffAndPlayVideo();
        return;
      }
      
      // 尝试直接播放
      await player.open(Media(videoPath), play: false);
      
      // 监听播放器状态变化
      player.stream.error.listen((error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Video loading error: $error'),
              backgroundColor: Colors.red[700],
            ),
          );
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load video: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    }
  }

  /// 嗅探并播放在线视频
  Future<void> _sniffAndPlayVideo() async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('正在嗅探视频链接...'),
            backgroundColor: Colors.blue[700],
            duration: const Duration(seconds: 3),
          ),
        );
      }

      // 嗅探视频链接
      final videos = await VideoSnifferService.sniffVideoUrls(widget.video.url);
      
      if (videos.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('未找到可播放的视频链接，请尝试下载视频'),
              backgroundColor: Colors.orange[700],
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      // 选择最佳视频链接
      final bestVideo = _selectBestVideo(videos);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('找到视频链接: ${bestVideo.title}'),
            backgroundColor: Colors.green[700],
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // 播放视频
      await player.open(Media(bestVideo.url), play: false);
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('视频嗅探失败: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    }
  }

  /// 选择最佳视频链接
  VideoInfo _selectBestVideo(List<VideoInfo> videos) {
    // 优先级：直接视频 > HLS > DASH > 其他
    final priorityOrder = [
      VideoType.direct,
      VideoType.hls,
      VideoType.dash,
      VideoType.meta,
      VideoType.jsonLd,
      VideoType.special,
      VideoType.link,
    ];

    for (final type in priorityOrder) {
      final candidates = videos.where((v) => v.type == type).toList();
      if (candidates.isNotEmpty) {
        // 如果有多个同类型的视频，选择分辨率最高的
        candidates.sort((a, b) {
          final aRes = (a.width ?? 0) * (a.height ?? 0);
          final bRes = (b.width ?? 0) * (b.height ?? 0);
          return bRes.compareTo(aRes);
        });
        return candidates.first;
      }
    }

    return videos.first;
  }

  @override
  void dispose() {
    player.dispose();
    _splitViewController.dispose();
    _nameController.dispose();
    _notesController.dispose();
    _newTagController.dispose();
    _tagFocusNode.dispose();
    _videoFocusNode.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _resetFormToBlank() {
    setState(() {
      _originalEditingClip = null;
      _formClip = OnlineVideoClip(
        id: 'online_clip_${DateTime.now().millisecondsSinceEpoch}',
        onlineVideoId: widget.video.id,
        name: '',
        startTime: Duration.zero,
        endTime: Duration.zero,
        coverFrameTime: Duration.zero,
      );
      _updateTextFieldsAndPreview();
    });

    _updateEndTimeToVideoDuration();
  }

  Future<void> _updateEndTimeToVideoDuration() async {
    int attempts = 0;
    const maxAttempts = 30;

    while (attempts < maxAttempts && mounted) {
      if (player.state.duration > Duration.zero) {
        setState(() {
          _formClip = _formClip.copyWith(endTime: player.state.duration);
        });
        return;
      }

      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
    }

    if (mounted && widget.video.duration != null) {
      setState(() {
        _formClip = _formClip.copyWith(endTime: widget.video.duration!);
      });
    }
  }

  void _startEditing(OnlineVideoClip clipToEdit, {bool fromInit = false}) {
    setState(() {
      _originalEditingClip = clipToEdit;
      _formClip = clipToEdit.copyWith();
      _updateTextFieldsAndPreview();
      player.seek(clipToEdit.startTime);
    });

    if (!fromInit) {
      _scrollToClip(clipToEdit.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Now editing: "${clipToEdit.name}"'),
          backgroundColor: Colors.orange.shade800,
        ),
      );
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToClip(clipToEdit.id);
      });
    }
  }

  void _scrollToClip(String clipId) {
    final appState = context.read<AppState>();
    final clipsForThisVideo = appState.onlineVideoClips
        .where((c) => c.onlineVideoId == widget.video.id)
        .toList();
    final index = clipsForThisVideo.indexWhere((c) => c.id == clipId);
    if (index != -1) {
      _itemScrollController.scrollTo(
        index: index,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  void _updateTextFieldsAndPreview() {
    if (_nameController.text != _formClip.name) {
      _nameController.text = _formClip.name;
    }
    if (_notesController.text != (_formClip.notes ?? '')) {
      _notesController.text = _formClip.notes ?? '';
    }

    final thumbnailService = context.read<ThumbnailService>();
    final appState = context.read<AppState>();
    final dbPath = appState.currentDbPath;

    if (dbPath != null && _formClip.thumbnailPath != null) {
      final thumbnailPath = thumbnailService.buildThumbnailPath(
        dbPath,
        _formClip.thumbnailPath!,
      );
      if (File(thumbnailPath).existsSync()) {
        _coverPreviewFullPath = thumbnailPath;
      }
    }
  }

  Future<void> _saveOrUpdateClip() async {
    if (_formClip.name.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a name for the clip'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    final appState = context.read<AppState>();
    final dbPath = appState.currentDbPath;

    if (dbPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Save failed: Database path not found.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      setState(() => _isSaving = false);
      return;
    }

    try {
      String? finalThumbnailPath = _tempThumbnailPath;

      if (finalThumbnailPath != null) {
        final thumbnailService = context.read<ThumbnailService>();
        final tempPath = thumbnailService.buildThumbnailPath(
          dbPath,
          finalThumbnailPath,
        );
        final finalFileName = thumbnailService.getThumbnailFileName(
          _formClip.id,
        );
        final finalPath = thumbnailService.buildThumbnailPath(
          dbPath,
          finalFileName,
        );

        final tempFile = File(tempPath);
        if (tempFile.existsSync()) {
          tempFile.renameSync(finalPath);
          finalThumbnailPath = finalFileName;
        }
      } else {
        final bool needsThumbUpdate =
            _formClip.thumbnailPath == null ||
            (_originalEditingClip != null &&
                _formClip.coverFrameTime !=
                    _originalEditingClip!.coverFrameTime);

        if (needsThumbUpdate) {
          final thumbnailService = context.read<ThumbnailService>();
          final coverTime = _formClip.coverFrameTime == Duration.zero
              ? _formClip.startTime
              : _formClip.coverFrameTime;

          // 对于在线视频，我们需要特殊处理缩略图生成
          // 这里暂时使用在线视频的缩略图URL
          if (widget.video.thumbnailUrl != null) {
            finalThumbnailPath = await _downloadAndSaveThumbnail(
              widget.video.thumbnailUrl!,
              _formClip.id,
              dbPath,
            );
          }
        }
      }

      if (finalThumbnailPath != null) {
        setState(() {
          _formClip = _formClip.copyWith(thumbnailPath: finalThumbnailPath);
        });
      }

      if (_originalEditingClip == null) {
        await appState.addOnlineVideoClip(_formClip);
      } else {
        await appState.updateOnlineVideoClip(_formClip);
        _originalEditingClip = _formClip.copyWith();
      }

      if (mounted) {
        _tempThumbnailPath = null;
        final thumbnailService = context.read<ThumbnailService>();
        thumbnailService.cleanupTempThumbnails(dbPath, _formClip.id);
        _clipsListTimestamp = DateTime.now().millisecondsSinceEpoch;
        setState(() {});

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Online clip "${_formClip.name}" saved!'),
            backgroundColor: Colors.green[700],
          ),
        );
        if (_originalEditingClip == null) {
          _resetFormToBlank();
        }
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<String?> _downloadAndSaveThumbnail(
    String thumbnailUrl,
    String clipId,
    String dbPath,
  ) async {
    try {
      final response = await http.get(
        Uri.parse(thumbnailUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        },
      );
      
      if (response.statusCode == 200) {
        final thumbnailService = context.read<ThumbnailService>();
        final fileName = thumbnailService.getThumbnailFileName(clipId);
        final filePath = thumbnailService.buildThumbnailPath(dbPath, fileName);
        
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        
        return fileName;
      } else {
        print('Failed to download thumbnail: HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('Failed to download thumbnail: $e');
    }
    return null;
  }

  void _deleteClip(OnlineVideoClip clip) {
    final appState = context.read<AppState>();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Online Clip'),
        content: Text('Are you sure you want to delete "${clip.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              appState.deleteOnlineVideoClip(clip.id);
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Online clip "${clip.name}" deleted'),
                  backgroundColor: Colors.red[700],
                ),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _resetFormChanges() {
    if (_originalEditingClip != null) {
      setState(() {
        _formClip = _originalEditingClip!.copyWith();
        _updateTextFieldsAndPreview();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Changes discarded'),
          backgroundColor: Colors.orange[700],
        ),
      );
    }
  }

  void _setStartTimeFromPlayer() {
    final currentTime = player.state.position;
    setState(() {
      _formClip = _formClip.copyWith(startTime: currentTime);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Start time set to ${formatDuration(currentTime)}'),
        backgroundColor: Colors.blue[700],
      ),
    );
  }

  void _setEndTimeFromPlayer() {
    final currentTime = player.state.position;
    setState(() {
      _formClip = _formClip.copyWith(endTime: currentTime);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('End time set to ${formatDuration(currentTime)}'),
        backgroundColor: Colors.blue[700],
      ),
    );
  }

  Future<void> _generateCoverAtTime(Duration time) async {
    if (_isSettingCover) return;

    setState(() => _isSettingCover = true);

    try {
      // 对于在线视频，暂时只设置封面时间，不生成缩略图
      setState(() {
        _formClip = _formClip.copyWith(coverFrameTime: time);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cover time set to ${formatDuration(time)} (thumbnail will be downloaded when saved)',
          ),
          backgroundColor: Colors.green[700],
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSettingCover = false);
    }
  }

  void _handleKeyPress(RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
      switch (event.logicalKey.keyLabel) {
        case ' ':
          _togglePlayPause();
          break;
        case 'S':
        case 's':
          _toggleMute();
          break;
        case 'F1':
          setState(() {
            _showHints = !_showHints;
          });
          break;
        case '1':
          _setStartTimeFromPlayer();
          break;
        case '2':
          _setEndTimeFromPlayer();
          break;
        case 'C':
        case 'c':
          _generateCoverAtTime(player.state.position);
          break;
      }
    }
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });

    if (_isMuted) {
      player.setVolume(0);
    } else {
      player.setVolume(100);
    }
  }

  void _togglePlayPause() {
    if (player.state.playing) {
      player.pause();
    } else {
      player.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final thumbnailService = context.read<ThumbnailService>();
    final isEditing = _originalEditingClip != null;

    if (isEditing) {
      final latestClipInState = appState.onlineVideoClips.where(
        (c) => c.id == _originalEditingClip!.id,
      ).firstOrNull;
      if (latestClipInState == null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _resetFormToBlank(),
        );
      } else if (latestClipInState != _originalEditingClip) {
        _originalEditingClip = latestClipInState;
      }
    }

    final bool hasChanges = isEditing && _formClip != _originalEditingClip;
    final saveShortcut = LogicalKeySet(
      Platform.isMacOS ? LogicalKeyboardKey.meta : LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyS,
    );

    return RawKeyboardListener(
      focusNode: _focusNode,
      onKey: _handleKeyPress,
      child: Shortcuts(
        shortcuts: <LogicalKeySet, Intent>{saveShortcut: const SaveIntent()},
        child: Actions(
          actions: <Type, Action<Intent>>{
            SaveIntent: CallbackAction<SaveIntent>(
              onInvoke: (i) => _saveOrUpdateClip(),
            ),
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(isEditing ? 'Edit Online Clip' : 'Create New Online Clip'),
              actions: [
                IconButton(
                  icon: Icon(
                    _showHints ? Icons.keyboard : Icons.keyboard_outlined,
                    color: _showHints ? Colors.blue : Colors.grey,
                  ),
                  tooltip: 'Toggle Keyboard Shortcuts (F1)',
                  onPressed: () {
                    setState(() {
                      _showHints = !_showHints;
                    });
                  },
                ),
                const SizedBox(width: 8),
                if (isEditing)
                  TextButton.icon(
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('New Clip'),
                    onPressed: _resetFormToBlank,
                  ),
                const SizedBox(width: 8),
                if (isEditing)
                  TextButton.icon(
                    icon: const Icon(Icons.undo),
                    label: const Text('Discard Changes'),
                    onPressed: hasChanges ? _resetFormChanges : null,
                    style: TextButton.styleFrom(
                      foregroundColor: hasChanges
                          ? Colors.orange.shade700
                          : Colors.grey,
                    ),
                  ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          isEditing ? Icons.check_circle_outline : Icons.save,
                        ),
                  label: Text(isEditing ? 'Update Clip' : 'Save New Clip'),
                  onPressed: (_isSaving || (isEditing && !hasChanges))
                      ? null
                      : _saveOrUpdateClip,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isEditing
                        ? (hasChanges ? Colors.orange.shade800 : Colors.grey)
                        : Colors.green.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 16),
              ],
            ),
            body: MultiSplitView(
              controller: _splitViewController,
              builder: (context, area) {
                if (area.data == 'editor') {
                  return _buildEditorPanel(appState);
                }
                return _buildClipList(appState, thumbnailService);
              },
            ),
          ),
        ),
      ),
    );
  }

    Widget _buildEditorPanel(AppState appState) {
    return Column(
      children: [
        // 视频播放器
        Expanded(
          flex: 4,
          child: Card(
            elevation: 4.0,
            margin: const EdgeInsets.all(8.0),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                // 视频播放器
                Focus(
                  focusNode: _videoFocusNode,
                  child: Shortcuts(
                    shortcuts: <LogicalKeySet, Intent>{
                      LogicalKeySet(LogicalKeyboardKey.space):
                          const TogglePlayPauseIntent(),
                    },
                    child: Actions(
                      actions: <Type, Action<Intent>>{
                        TogglePlayPauseIntent:
                            CallbackAction<TogglePlayPauseIntent>(
                              onInvoke: (Intent intent) => player.playOrPause(),
                            ),
                      },
                      child: GestureDetector(
                        onTap: () {
                          if (!_videoFocusNode.hasFocus) {
                            FocusScope.of(context).requestFocus(_videoFocusNode);
                          }
                          player.playOrPause();
                        },
                        child: Video(controller: controller),
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
                          _buildShortcutHint('S', 'Toggle Mute'),
                          _buildShortcutHint('1', 'Set Start Time'),
                          _buildShortcutHint('2', 'Set End Time'),
                          _buildShortcutHint('C', 'Set Cover'),
                          _buildShortcutHint('F1', 'Toggle Hints'),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // 进度条
        StreamBuilder<Duration>(
          stream: player.stream.duration,
          initialData: player.state.duration,
          builder: (context, snapshot) {
            final isReady = (snapshot.data ?? Duration.zero) > Duration.zero;
            if (!isReady) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 20.0),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              child: CustomProgressBar(
                player: player,
                startTime: _formClip.startTime,
                endTime: _formClip.endTime,
                coverTime: _formClip.coverFrameTime,
                onSetStart: (time) => setState(
                  () => _formClip = _formClip.copyWith(startTime: time),
                ),
                onSetEnd: (time) => setState(
                  () => _formClip = _formClip.copyWith(endTime: time),
                ),
                onSetCover: (time) => _generateCoverAtTime(time),
                showThumbnailPreview: false, // 在线视频禁用缩略图预览
                videoPath: widget.video.url, // 使用在线视频URL
              ),
            );
          },
        ),

        // 剪辑控制
        _buildClippingControls(),

        // 表单
        Expanded(
          flex: 3,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_originalEditingClip != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Chip(
                      label: Text('Editing: ${_originalEditingClip!.name}'),
                      backgroundColor: Colors.orange.shade100,
                      onDeleted: _resetFormToBlank,
                      deleteIcon: const Icon(Icons.cancel),
                    ),
                  ),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Clip Name',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _formClip = _formClip.copyWith(name: value);
                    });
                  },
                ),
                const SizedBox(height: 12),
                _buildTagsSection(appState),
                const SizedBox(height: 12),
                TextField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _formClip = _formClip.copyWith(notes: value);
                    });
                  },
                ),
                const SizedBox(height: 16),
                _buildCoverControls(),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }



  Widget _buildTagsSection(AppState appState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tags',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ..._formClip.tags.map((tag) => Chip(
              label: Text(tag),
              onDeleted: () {
                setState(() {
                  final newTags = List<String>.from(_formClip.tags)
                    ..remove(tag);
                  _formClip = _formClip.copyWith(tags: newTags);
                });
              },
            )),
            ActionChip(
              label: const Text('Add Tag'),
              onPressed: () => _showAddTagDialog(),
            ),
          ],
        ),
      ],
    );
  }

  void _showAddTagDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Tag'),
        content: TextField(
          controller: _newTagController,
          decoration: const InputDecoration(
            labelText: 'Tag Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              setState(() {
                final newTags = List<String>.from(_formClip.tags)
                  ..add(value.trim());
                _formClip = _formClip.copyWith(tags: newTags);
              });
              _newTagController.clear();
              Navigator.of(context).pop();
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final value = _newTagController.text.trim();
              if (value.isNotEmpty) {
                setState(() {
                  final newTags = List<String>.from(_formClip.tags)
                    ..add(value);
                  _formClip = _formClip.copyWith(tags: newTags);
                });
                _newTagController.clear();
                Navigator.of(context).pop();
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }



  Widget _buildCoverPlaceholder() {
    return Container(
      color: Colors.grey[300],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.image_not_supported, size: 40),
            const SizedBox(height: 8),
            Text(
              'Online Video\nCover will be downloaded when saved',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
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
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            action,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClippingControls() {
    final theme = Theme.of(context);
    final clipDuration = _formClip.endTime > _formClip.startTime
        ? _formClip.endTime - _formClip.startTime
        : Duration.zero;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildTimeDisplay(
                'Start',
                _formClip.startTime,
                theme.primaryColor,
              ),
              _buildTimeDisplay('End', _formClip.endTime, Colors.redAccent),
              _buildTimeDisplay('Duration', clipDuration, null),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.flag_circle_outlined),
                onPressed: _setStartTimeFromPlayer,
                label: const Text("Set Start"),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.flag_circle),
                onPressed: _setEndTimeFromPlayer,
                label: const Text("Set End"),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.secondaryContainer,
                ),
                icon: const Icon(Icons.slideshow),
                onPressed: () =>
                    _previewClip(_formClip.startTime, _formClip.endTime),
                label: const Text("Preview Clip"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeDisplay(String label, Duration time, Color? color) {
    return Text.rich(
      TextSpan(
        text: '$label: ',
        style: Theme.of(context).textTheme.bodyMedium,
        children: <TextSpan>[
          TextSpan(
            text: formatDuration(time),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color ?? Theme.of(context).colorScheme.onSurface,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverControls() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildTimeDisplay(
                  'Cover At',
                  _formClip.coverFrameTime,
                  Colors.teal,
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: _isSettingCover
                      ? null
                      : () => _generateCoverAtTime(player.state.position),
                  child: _isSettingCover
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Set Cover'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.settings_backup_restore),
                  tooltip: 'Reset cover to start time',
                  onPressed: _isSettingCover
                      ? null
                      : () {
                          // 先更新 coverFrameTime 为 startTime
                          setState(() {
                            _formClip = _formClip.copyWith(
                              coverFrameTime: _formClip.startTime,
                            );
                          });
                          // 然后生成封面图
                          _generateCoverAtTime(_formClip.startTime);
                        },
                ),
              ],
            ),
            if (_coverPreviewFullPath != null)
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Column(
                  children: [
                    const Divider(),
                    const Text(
                      "Cover Preview",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Image.file(
                      File(_coverPreviewFullPath!),
                      key: ValueKey(
                        '${_coverPreviewFullPath}_$_coverPreviewTimestamp',
                      ),
                      height: 120,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return _buildCoverPlaceholder();
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _previewClip(Duration startTime, Duration endTime) {
    if (startTime >= endTime) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid clip duration'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    player.seek(startTime);
    player.play();

    // 在结束时间停止播放
    Timer(Duration(milliseconds: (endTime - startTime).inMilliseconds), () {
      if (mounted) {
        player.pause();
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Previewing clip: ${formatDuration(startTime)} - ${formatDuration(endTime)}'),
        backgroundColor: Colors.blue[700],
        duration: Duration(seconds: (endTime - startTime).inSeconds + 1),
      ),
    );
  }

  Widget _buildClipList(AppState appState, ThumbnailService thumbnailService) {
    final clipsForThisVideo = appState.onlineVideoClips
        .where((c) => c.onlineVideoId == widget.video.id)
        .toList();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.list),
              const SizedBox(width: 8),
              Text(
                'Clips (${clipsForThisVideo.length})',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: clipsForThisVideo.isEmpty
              ? const Center(
                  child: Text(
                    'No clips yet.\nCreate your first clip!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                )
              : ScrollablePositionedList.builder(
                  itemCount: clipsForThisVideo.length,
                  itemScrollController: _itemScrollController,
                  itemBuilder: (context, index) {
                    final clip = clipsForThisVideo[index];
                    final isSelected = _originalEditingClip?.id == clip.id;
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      color: isSelected
                          ? Theme.of(context).primaryColor.withOpacity(0.1)
                          : null,
                      child: ListTile(
                        leading: SizedBox(
                          width: 60,
                          height: 40,
                          child: clip.thumbnailPath != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Image.file(
                                    File(thumbnailService.buildThumbnailPath(
                                      appState.currentDbPath!,
                                      clip.thumbnailPath!,
                                    )),
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        color: Colors.grey[300],
                                        child: const Icon(
                                          Icons.image_not_supported,
                                          size: 20,
                                        ),
                                      );
                                    },
                                  ),
                                )
                              : Container(
                                  color: Colors.grey[300],
                                  child: const Icon(
                                    Icons.image_not_supported,
                                    size: 20,
                                  ),
                                ),
                        ),
                        title: Text(
                          clip.name.isEmpty ? 'Untitled Clip' : clip.name,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${formatDuration(clip.startTime)} - ${formatDuration(clip.endTime)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            if (clip.tags.isNotEmpty)
                              Wrap(
                                spacing: 4,
                                children: clip.tags.take(3).map((tag) => Chip(
                                  label: Text(
                                    tag,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                )).toList(),
                              ),
                          ],
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            switch (value) {
                              case 'edit':
                                _startEditing(clip);
                                break;
                              case 'delete':
                                _deleteClip(clip);
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit),
                                  SizedBox(width: 8),
                                  Text('Edit'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Delete', style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
