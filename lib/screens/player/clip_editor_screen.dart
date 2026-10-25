import '../../widgets/ai_settings_dialog.dart';
import 'dart:async';
import 'dart:io';
import '../../services/frame_embedding_pool.dart';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:multi_split_view/multi_split_view.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../services/thumbnail_service.dart';
import '../../utils/tag_utils.dart';
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

class ClipEditorScreen extends StatefulWidget {
  final OriginalVideo video;
  final VideoClip? clipToEdit;

  const ClipEditorScreen({super.key, required this.video, this.clipToEdit});

  @override
  State<ClipEditorScreen> createState() => _ClipEditorScreenState();
}

class _ClipEditorScreenState extends State<ClipEditorScreen> {
  late final Player player;
  late final VideoController controller;
  final MultiSplitViewController _splitViewController =
      MultiSplitViewController(
        areas: [
          Area(flex: 13, data: 'editor'),
          Area(flex: 7, data: 'list'),
        ],
      );

  late VideoClip _formClip;
  VideoClip? _originalEditingClip;

  bool _isSaving = false;
  String? _coverPreviewFullPath;
  bool _isSettingCover = false;
  int _coverPreviewTimestamp = 0; // 用于强制刷新封面预览
  int _clipsListTimestamp = 0; // 用于强制刷新clips列表
  String? _tempThumbnailPath;
  bool _isGeneratingAiCaption = false; // 临时封面路径，只有保存后才同步到clip

  final _nameController = TextEditingController();
  final _notesController = TextEditingController();
  final _newTagController = TextEditingController();
  final _tagFocusNode = FocusNode();
  final _videoFocusNode = FocusNode();
  final ItemScrollController _itemScrollController = ItemScrollController();
  bool _isMuted = false; // 静音状态

  // 新增：快捷键提示控制
  bool _showHints = false; // 控制快捷键提示显示
  late final FocusNode _focusNode; // 全局焦点节点

  @override
  void initState() {
    super.initState();
    player = Player();
    controller = VideoController(player);
    _focusNode = FocusNode(); // 初始化焦点节点

    if (widget.clipToEdit != null) {
      _startEditing(widget.clipToEdit!, fromInit: true);
    } else {
      _resetFormToBlank();
    }

    player.open(Media(widget.video.path), play: false);

    // 延迟请求焦点，确保组件完全初始化
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
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
    _focusNode.dispose(); // 释放焦点节点
    super.dispose();
  }

  void _resetFormToBlank() {
    setState(() {
      _originalEditingClip = null;
      _formClip = VideoClip(
        id: 'clip_${DateTime.now().millisecondsSinceEpoch}',
        videoPath: widget.video.path,
        name: '',
        startTime: Duration.zero,
        endTime: Duration.zero, // 将在播放器准备好后更新为视频总时长
        coverFrameTime: Duration.zero,
      );
      _updateTextFieldsAndPreview();
    });

    // 等待播放器准备好后设置 endTime 为视频总时长
    _updateEndTimeToVideoDuration();
  }

  // 新增：更新 endTime 为视频总时长
  Future<void> _updateEndTimeToVideoDuration() async {
    // 等待播放器加载完成，最多等待3秒
    int attempts = 0;
    const maxAttempts = 30; // 30次 * 100ms = 3秒

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

    // 如果超时，尝试使用 widget.video.duration（如果可用）
    if (mounted && widget.video.duration != null) {
      setState(() {
        _formClip = _formClip.copyWith(endTime: widget.video.duration!);
      });
    }
  }

  void _startEditing(VideoClip clipToEdit, {bool fromInit = false}) {
    setState(() {
      _originalEditingClip = clipToEdit;
      _formClip = clipToEdit.copyWith();
      _updateTextFieldsAndPreview();
      if (!fromInit) {
        player.seek(clipToEdit.startTime);
      }
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
        player.seek(clipToEdit.startTime);
      });
    }
  }

  void _scrollToClip(String clipId) {
    final appState = context.read<AppState>();
    final clipsForThisVideo = appState.clips
        .where((c) => c.videoPath == widget.video.path)
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
    final dbPath = context.read<AppState>().currentDbFullPath;

    // 优先使用临时封面路径，如果没有则使用clip的封面路径
    final thumbnailPath = _tempThumbnailPath ?? _formClip.thumbnailPath;
    if (thumbnailPath != null && dbPath != null) {
      _coverPreviewFullPath = thumbnailService.buildThumbnailPath(
        dbPath,
        thumbnailPath,
      );
    } else {
      _coverPreviewFullPath = null;
    }
  }

  void _resetFormChanges() {
    if (_originalEditingClip == null) return;

    // 清理临时封面文件
    final thumbnailService = context.read<ThumbnailService>();
    final dbPath = context.read<AppState>().currentDbFullPath;
    if (dbPath != null) {
      thumbnailService.cleanupTempThumbnails(dbPath, _formClip.id);
    }

    // 先重置所有状态
    setState(() {
      _formClip = _originalEditingClip!.copyWith();
      _tempThumbnailPath = null; // 重置临时封面路径
      _updateTextFieldsAndPreview();
    });

    // 重新生成封面图以匹配原始状态
    if (_originalEditingClip!.coverFrameTime > Duration.zero) {
      // 立即更新 coverFrameTime，确保进度条和 Cover At 显示正确
      setState(() {
        _formClip = _formClip.copyWith(
          coverFrameTime: _originalEditingClip!.coverFrameTime,
        );
      });
      // 然后生成封面图
      _generateCoverAtTime(_originalEditingClip!.coverFrameTime);
    } else if (_originalEditingClip!.thumbnailPath != null) {
      // 如果有原始封面路径，直接使用它
      final thumbnailService = context.read<ThumbnailService>();
      final dbPath = context.read<AppState>().currentDbFullPath;
      if (dbPath != null) {
        _coverPreviewFullPath = thumbnailService.buildThumbnailPath(
          dbPath,
          _originalEditingClip!.thumbnailPath!,
        );
        setState(() {
          _coverPreviewTimestamp = DateTime.now().millisecondsSinceEpoch;
        });
      }
    } else {
      // 如果原始clip没有封面，清除封面预览
      setState(() {
        _coverPreviewFullPath = null;
        _coverPreviewTimestamp = DateTime.now().millisecondsSinceEpoch;
      });
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Changes discarded.'),
        backgroundColor: Colors.grey,
      ),
    );
  }

    Future<void> _generateAiCaption(AppState appState) async {
    final startMs = _formClip.startTime.inMilliseconds;
    final endMs = _formClip.endTime.inMilliseconds;
    if (endMs <= startMs) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('片段起止时间无效，请先调整区间')),
      );
      return;
    }

    setState(() => _isGeneratingAiCaption = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('正在抽帧并由 Qwen2-VL 进行智能解构，请稍候...'),
        duration: Duration(seconds: 4),
      ),
    );

    try {
      final frames = await appState.aiService.extractClipFrames(
        videoPathOrUrl: widget.video.path,
        startMs: startMs,
        endMs: endMs,
        strategy: 'interval',
        everyMs: 2000,
        maxFrames: 6,
      );

      if (frames.isEmpty) {
        throw Exception('未能从视频片段中抽取到有效画面');
      }

      final caption = await appState.aiService.generateCaption(
        frames: frames,
        framePaths: frames.map((f) => f.path).toList(),
        apiUrl: appState.vlmApiUrl,
        apiKey: appState.vlmApiKey,
        model: appState.vlmModel,
      );

      if (!mounted) return;

      final newNotes = caption.summary.isNotEmpty
          ? '${caption.summary}\n[场景]: ${caption.scene}\n[主体]: ${caption.mainSubject}'
          : caption.scene;

      _notesController.text = newNotes;

      final currentTags = Set<String>.from(_formClip.tags);
      for (final tag in caption.keyActions) {
        final clean = tag.trim();
        if (clean.isNotEmpty &&
            clean.length <= 10 &&
            !clean.contains(RegExp(r'[,，、;；。!！?？]'))) {
          currentTags.add(clean);
        }
      }
      if (caption.scene.isNotEmpty &&
          caption.scene.length <= 6 &&
          !caption.scene.contains(RegExp(r'[,，、;；。!！?？]'))) {
        currentTags.add(caption.scene.trim());
      }

      setState(() {
        _formClip = _formClip.copyWith(
          notes: newNotes,
          tags: currentTags.toList(),
          aiSummary: caption.summary,
          aiScene: caption.scene,
          aiActions: caption.keyActions,
        );
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✨ AI 解构成功！已自动填充剧情描述与推荐标签'),
          backgroundColor: Colors.green,
        ),
      );
        } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI 解构失败: $e'),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: '配置引擎',
              textColor: Colors.amberAccent,
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => const AiSettingsDialog(),
                );
              },
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingAiCaption = false);
      }
    }
  }

Future<void> _saveOrUpdateClip() async {
    if (_isSaving) return;

    final name = _nameController.text.trim();
    final notes = _notesController.text.trim();

    setState(() {
      _formClip = _formClip.copyWith(
        name: name.isEmpty ? 'Untitled Clip' : name,
        notes: notes.isEmpty ? null : notes,
      );
    });

    if (_formClip.endTime <= _formClip.startTime) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Save failed: End time must be after start time.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    final appState = context.read<AppState>();
    final dbPath = appState.currentDbFullPath;

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
      // 如果有临时封面路径，将其转换为正式封面；否则检查是否需要生成封面
      String? finalThumbnailPath = _tempThumbnailPath;

      if (finalThumbnailPath != null) {
        // 将临时封面转换为正式封面
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

        // 重命名临时文件为正式文件
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

          finalThumbnailPath = await thumbnailService.generateThumbnail(
            widget.video.path,
            coverTime,
            _formClip.id,
            dbPath: dbPath,
          );
        }
      }

      // 更新clip的thumbnailPath
      if (finalThumbnailPath != null) {
        setState(() {
          _formClip = _formClip.copyWith(thumbnailPath: finalThumbnailPath);
        });
      }

      if (_originalEditingClip == null) {
        await appState.addClip(_formClip);
      } else {
        await appState.updateClip(_formClip);
        // 更新 _originalEditingClip 为当前保存的状态
        _originalEditingClip = _formClip.copyWith();
      }

            // 增量同步母视频帧池（后台异步运行，不阻塞当前保存流程）
      unawaited(
        appState.deltaEngine
            .syncClipRange(
              videoPathOrUrl: widget.video.path,
              startMs: _formClip.startTime.inMilliseconds,
              endMs: _formClip.endTime.inMilliseconds,
              modelDir: 'models',
            )
            .catchError((err) {
              debugPrint('[ClipEditorScreen] Background delta sync error: $err');
              return <VideoFrameEmbeddingRecord>[];
            }),
      );

if (mounted) {
        // 清除临时封面路径
        _tempThumbnailPath = null;

        // 清理所有临时封面文件
        final thumbnailService = context.read<ThumbnailService>();
        thumbnailService.cleanupTempThumbnails(dbPath, _formClip.id);

        // 更新时间戳，强制刷新clips列表
        _clipsListTimestamp = DateTime.now().millisecondsSinceEpoch;

        // 强制刷新UI，确保clips列表更新
        setState(() {});

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Clip "${_formClip.name}" saved!'),
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

  void _deleteClip(VideoClip clip) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: Text(
          'Are you sure you want to delete the clip "${clip.name}"?',
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
            onPressed: () {
              if (_originalEditingClip?.id == clip.id) {
                _resetFormToBlank();
              }
              context.read<AppState>().deleteClip(clip.id);
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  void _setStartTimeFromPlayer() {
    final time = player.state.position;
    setState(() {
      _formClip = _formClip.copyWith(
        startTime: time,
        endTime: (time > _formClip.endTime && _formClip.endTime > Duration.zero)
            ? time
            : _formClip.endTime,
      );
    });
  }

  void _setEndTimeFromPlayer() {
    final time = player.state.position;
    setState(() {
      _formClip = _formClip.copyWith(
        endTime: time < _formClip.startTime ? _formClip.startTime : time,
      );
    });
  }

  Future<void> _previewClip(Duration start, Duration end) async {
    if (start >= end) return;
    await player.seek(start);
    await player.play();

    Future.delayed(end - start, () {
      if (mounted && player.state.playing) {
        player.pause();
      }
    });
  }

  Future<void> _generateCoverAtTime(Duration time) async {
    setState(() => _isSettingCover = true);
    final thumbnailService = context.read<ThumbnailService>();
    final dbPath = context.read<AppState>().currentDbFullPath;

    if (dbPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot generate cover: Database path not found.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      setState(() => _isSettingCover = false);
      return;
    }

    try {
      // 使用临时封面生成，避免覆盖原始封面
      final newThumbFileName = await thumbnailService.generateTempThumbnail(
        widget.video.path,
        time,
        _formClip.id,
        dbPath: dbPath,
      );

      if (!mounted) return;

      if (newThumbFileName != null) {
        final newFullPath = thumbnailService.buildThumbnailPath(
          dbPath,
          newThumbFileName,
        );

        // 清除所有相关图片缓存
        FileImage(File(newFullPath)).evict();
        if (_coverPreviewFullPath != null) {
          FileImage(File(_coverPreviewFullPath!)).evict();
        }

        // 强制触发UI更新
        if (mounted) {
          setState(() {
            _formClip = _formClip.copyWith(coverFrameTime: time);
            // 只更新临时封面路径，不更新clip的thumbnailPath
            _tempThumbnailPath = newThumbFileName;
            _coverPreviewFullPath = newFullPath;
            _coverPreviewTimestamp =
                DateTime.now().millisecondsSinceEpoch; // 更新时间戳
          });

          // 显示成功提示
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Cover set at ${formatDuration(time)} (will be saved when you update the clip)',
              ),
              backgroundColor: Colors.green[700],
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isSettingCover = false);
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
        case 'S':
        case 's':
          // S键：切换静音
          _toggleMute();
          break;
        case 'F1':
          // F1键：显示/隐藏快捷键提示
          setState(() {
            _showHints = !_showHints;
          });
          break;
        case '1':
          // 1键：设置开始时间
          _setStartTimeFromPlayer();
          break;
        case '2':
          // 2键：设置结束时间
          _setEndTimeFromPlayer();
          break;
        case 'C':
        case 'c':
          // C键：设置封面截图
          _generateCoverAtTime(player.state.position);
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
      print('ClipEditor: Audio muted');
    } else {
      player.setVolume(100);
      print('ClipEditor: Audio unmuted');
    }
  }

  // 切换播放/暂停
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
      final latestClipInState = appState.clips.firstWhereOrNull(
        (c) => c.id == _originalEditingClip!.id,
      );
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
      focusNode: _focusNode, // 使用全局焦点节点
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
              title: Text(isEditing ? 'Edit Clip' : 'Create New Clip'),
              actions: [
                // 快捷键提示按钮
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
        Expanded(
          flex: 4,
          child: Card(
            elevation: 4.0,
            margin: const EdgeInsets.all(8.0),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
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
                            FocusScope.of(
                              context,
                            ).requestFocus(_videoFocusNode);
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
                showThumbnailPreview: true,
                videoPath: _originalEditingClip?.videoPath,
              ),
            );
          },
        ),
        _buildClippingControls(),
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
                ),
                const SizedBox(height: 12),
                _buildTagEditor(appState),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'Notes & AI 智能解构',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.settings, size: 16),
                      tooltip: '配置 VLM 视觉大模型引擎',
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => const AiSettingsDialog(),
                        );
                      },
                    ),
                    _isGeneratingAiCaption
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TextButton.icon(
                            icon: const Icon(Icons.auto_awesome, size: 14),
                            label: const Text(
                              '✨ AI 智能解构',
                              style: TextStyle(fontSize: 12),
                            ),
                            onPressed: () => _generateAiCaption(appState),
                          ),
                  ],
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [_buildRatingBar(), _buildFavoriteButton()],
                    ),
                  ),
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
                      height: 100,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.error, color: Colors.red),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagEditor(AppState appState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
          child: Text('Tags:', style: Theme.of(context).textTheme.titleSmall),
        ),
        if (_formClip.tags.isNotEmpty)
          Wrap(
            spacing: 6.0,
            runSpacing: 0.0,
            children: _formClip.tags.map((tag) {
              return Chip(
                label: Text(tag),
                onDeleted: () {
                  setState(() {
                    final newTags = List<String>.from(_formClip.tags)
                      ..remove(tag);
                    _formClip = _formClip.copyWith(tags: newTags);
                  });
                },
              );
            }).toList(),
          ),
        RawAutocomplete<String>(
          textEditingController: _newTagController,
          focusNode: _tagFocusNode,
          optionsBuilder: (TextEditingValue textEditingValue) {
            final query = textEditingValue.text.toLowerCase();
            if (query.isEmpty) {
              return appState.allTags.where(
                (tag) => !_formClip.tags.contains(tag),
              );
            }
            return appState.allTags.where(
              (tag) =>
                  tag.toLowerCase().contains(query) &&
                  !_formClip.tags.contains(tag),
            );
          },
          onSelected: (String selection) {
            setState(() {
              if (selection.isNotEmpty && !_formClip.tags.contains(selection)) {
                final newTags = List<String>.from(_formClip.tags)
                  ..add(selection);
                _formClip = _formClip.copyWith(tags: newTags);
              }
            });
            _newTagController.clear();
            _tagFocusNode.requestFocus();
          },
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              decoration: const InputDecoration(
                labelText: 'Add a Tag',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (String value) {
                final newTag = value.trim();
                if (newTag.isNotEmpty && !_formClip.tags.contains(newTag)) {
                  setState(() {
                    final newTags = List<String>.from(_formClip.tags)
                      ..add(newTag);
                    _formClip = _formClip.copyWith(tags: newTags);
                  });
                }
                controller.clear();
                focusNode.requestFocus();
              },
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4.0,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final String option = options.elementAt(index);
                      return InkWell(
                        onTap: () => onSelected(option),
                        child: ListTile(title: Text(option)),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildRatingBar() {
    return Column(
      children: [
        const Text('Rating', style: TextStyle(fontWeight: FontWeight.bold)),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (index) {
            return IconButton(
              icon: Icon(
                index < _formClip.rating ? Icons.star : Icons.star_border,
                color: index < _formClip.rating ? Colors.amber : Colors.grey,
              ),
              onPressed: () {
                setState(() {
                  final newRating = (_formClip.rating == index + 1)
                      ? 0
                      : index + 1;
                  _formClip = _formClip.copyWith(rating: newRating);
                });
              },
            );
          }),
        ),
      ],
    );
  }

  Widget _buildFavoriteButton() {
    return Column(
      children: [
        const Text('Favorite', style: TextStyle(fontWeight: FontWeight.bold)),
        IconButton(
          iconSize: 32,
          tooltip: 'Toggle Favorite',
          icon: Icon(
            _formClip.isFavorite ? Icons.favorite : Icons.favorite_border,
            color: _formClip.isFavorite ? Colors.redAccent : Colors.grey,
          ),
          onPressed: () {
            setState(() {
              _formClip = _formClip.copyWith(isFavorite: !_formClip.isFavorite);
            });
          },
        ),
      ],
    );
  }

  Widget _buildClipList(AppState appState, ThumbnailService thumbnailService) {
    final clipsForThisVideo = appState.clips
        .where((c) => c.videoPath == widget.video.path)
        .toList();
    final dbPath = appState.currentDbFullPath;

    return Scaffold(
      appBar: AppBar(
        title: Text('Clips (${clipsForThisVideo.length})'),
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        centerTitle: true,
        toolbarHeight: 40,
      ),
      body: clipsForThisVideo.isEmpty
          ? const Center(
              child: Text(
                'No clips yet.\nUse the panel on the left to create one.',
                textAlign: TextAlign.center,
              ),
            )
          : ScrollablePositionedList.builder(
              itemCount: clipsForThisVideo.length,
              itemScrollController: _itemScrollController,
              itemBuilder: (context, index) {
                final clip = clipsForThisVideo[index];
                final isEditingThis = _originalEditingClip?.id == clip.id;
                final duration = clip.endTime - clip.startTime;

                String? thumbFullPath;
                if (clip.thumbnailPath != null && dbPath != null) {
                  thumbFullPath = thumbnailService.buildThumbnailPath(
                    dbPath,
                    clip.thumbnailPath!,
                  );
                }

                return Card(
                  elevation: isEditingThis ? 6 : 2,
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  color: isEditingThis ? Colors.orange.shade50 : null,
                  shape: isEditingThis
                      ? RoundedRectangleBorder(
                          side: BorderSide(
                            color: Colors.orange.shade700,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        )
                      : null,
                  child: InkWell(
                    onTap: () => _startEditing(clip),
                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 缩略图
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  width: 120,
                                  height: 90,
                                  child: thumbFullPath != null
                                      ? Image.file(
                                          File(thumbFullPath),
                                          key: ValueKey(
                                            '${thumbFullPath}_$_clipsListTimestamp',
                                          ),
                                          fit: BoxFit.cover,
                                          errorBuilder: (c, e, s) =>
                                              const Icon(Icons.error_outline),
                                        )
                                      : Container(
                                          color: Colors.grey.shade300,
                                          child: const Icon(
                                            Icons.movie_creation_outlined,
                                            size: 24,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // 主要内容区域
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // 标题和时间信息
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            clip.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          formatDuration(duration),
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 14,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    // 时间范围
                                    Text(
                                      '${formatDuration(clip.startTime)} - ${formatDuration(clip.endTime)}',
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    // 标签显示
                                    if (clip.tags.isNotEmpty)
                                      Wrap(
                                        spacing: 4,
                                        runSpacing: 2,
                                        children: clip.tags.take(3).map((tag) {
                                          final color = generateTagColor(tag);
                                          return Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: color.withValues(
                                                alpha: 0.2,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                color: color.withValues(
                                                  alpha: 0.6,
                                                ),
                                                width: 1,
                                              ),
                                            ),
                                            child: Text(
                                              tag,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: color,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    if (clip.tags.length > 3)
                                      Text(
                                        '+${clip.tags.length - 3} more',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    const SizedBox(height: 4),
                                    // 评分和收藏状态
                                    Row(
                                      children: [
                                        if (clip.isFavorite)
                                          const Icon(
                                            Icons.favorite,
                                            color: Colors.redAccent,
                                            size: 16,
                                          ),
                                        if (clip.rating > 0) ...[
                                          if (clip.isFavorite)
                                            const SizedBox(width: 4),
                                          Row(
                                            children: List.generate(
                                              clip.rating,
                                              (i) => const Icon(
                                                Icons.star,
                                                color: Colors.amber,
                                                size: 16,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 操作按钮 - 定位到整个Card的右下角
                        Positioned(
                          bottom: 4,
                          right: 4,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.play_circle_outline),
                                color: Colors.green,
                                iconSize: 20,
                                tooltip: 'Play Clip',
                                onPressed: () =>
                                    _previewClip(clip.startTime, clip.endTime),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_forever_outlined),
                                color: Colors.red.shade700,
                                iconSize: 20,
                                tooltip: 'Delete Clip',
                                onPressed: () => _deleteClip(clip),
                              ),
                            ],
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

  // 新增：构建快捷键提示
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
}
