import 'dart:io';

import 'package:collection/collection.dart';
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
import '../../services/online_video_service.dart';
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
    player.open(Media(widget.video.url), play: false);

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
      final response = await http.get(Uri.parse(thumbnailUrl));
      if (response.statusCode == 200) {
        final thumbnailService = context.read<ThumbnailService>();
        final fileName = thumbnailService.getThumbnailFileName(clipId);
        final filePath = thumbnailService.buildThumbnailPath(dbPath, fileName);
        
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        
        return fileName;
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
        const SnackBar(
          content: Text('Changes discarded'),
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
      final appState = context.read<AppState>();
      final dbPath = appState.currentDbPath;

      if (dbPath != null) {
        final thumbnailService = context.read<ThumbnailService>();
        final newThumbFileName = await thumbnailService.generateThumbnail(
          widget.video.url, // 使用在线视频URL
          time,
          _formClip.id,
          dbPath: dbPath,
        );

        if (newThumbFileName != null) {
          final newFullPath = thumbnailService.buildThumbnailPath(
            dbPath,
            newThumbFileName,
          );

          if (mounted) {
            setState(() {
              _formClip = _formClip.copyWith(coverFrameTime: time);
              _tempThumbnailPath = newThumbFileName;
              _coverPreviewFullPath = newFullPath;
              _coverPreviewTimestamp = DateTime.now().millisecondsSinceEpoch;
            });

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
      }
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
      final latestClipInState = appState.onlineVideoClips.firstWhereOrNull(
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
          flex: 3,
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Video(
                controller: controller,
                controls: NoVideoControls,
              ),
            ),
          ),
        ),

        // 播放控制
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              IconButton(
                onPressed: _togglePlayPause,
                icon: Icon(
                  player.state.playing ? Icons.pause : Icons.play_arrow,
                ),
                tooltip: 'Play/Pause (Space)',
              ),
              IconButton(
                onPressed: _toggleMute,
                icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up),
                tooltip: 'Mute/Unmute (S)',
              ),
              const SizedBox(width: 16),
              Expanded(
                child: CustomProgressBar(
                  player: player,
                  showThumbnailPreview: true,
                  videoPath: widget.video.url, // 使用在线视频URL
                ),
              ),
            ],
          ),
        ),

        // 编辑控制
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: _setStartTimeFromPlayer,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Set Start (1)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[600],
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _setEndTimeFromPlayer,
                icon: const Icon(Icons.stop),
                label: const Text('Set End (2)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[600],
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _generateCoverAtTime(player.state.position),
                icon: const Icon(Icons.image),
                label: const Text('Set Cover (C)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[600],
                  foregroundColor: Colors.white,
                ),
              ),
              const Spacer(),
              Text(
                '${formatDuration(_formClip.startTime)} - ${formatDuration(_formClip.endTime)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),

        // 表单
        Expanded(
          flex: 2,
          child: _buildFormPanel(appState),
        ),
      ],
    );
  }

  Widget _buildFormPanel(AppState appState) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
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
          const SizedBox(height: 16),

          // 备注
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(
              labelText: 'Notes',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            onChanged: (value) {
              setState(() {
                _formClip = _formClip.copyWith(notes: value);
              });
            },
          ),
          const SizedBox(height: 16),

          // 标签
          _buildTagsSection(appState),
          const SizedBox(height: 16),

          // 封面预览
          _buildCoverPreview(),
        ],
      ),
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

  Widget _buildCoverPreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Cover Preview',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Container(
          height: 120,
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: _coverPreviewFullPath != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(_coverPreviewFullPath!),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey[300],
                        child: const Icon(Icons.image_not_supported, size: 40),
                      );
                    },
                  ),
                )
              : Container(
                  color: Colors.grey[300],
                  child: const Center(
                    child: Icon(Icons.image_not_supported, size: 40),
                  ),
                ),
        ),
      ],
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
