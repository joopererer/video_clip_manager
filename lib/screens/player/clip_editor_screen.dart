import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/app_state.dart';
import '../../widgets/custom_progress_bar.dart';
import '../../services/thumbnail_service.dart';
import '../../main.dart'; // for formatDuration

// --- 用于键盘操作的意图(Intent)类 ---
class SaveIntent extends Intent {
  const SaveIntent();
}

class TogglePlayPauseIntent extends Intent {
  const TogglePlayPauseIntent();
}

class ExitFullscreenIntent extends Intent {
  const ExitFullscreenIntent();
}

class ClipEditorScreen extends StatefulWidget {
  final OriginalVideo video;
  final VideoClip? initialClip;

  const ClipEditorScreen({super.key, required this.video, this.initialClip});

  @override
  State<ClipEditorScreen> createState() => _ClipEditorScreenState();
}

class _ClipEditorScreenState extends State<ClipEditorScreen> {
  final GlobalKey<VideoState> _videoKey = GlobalKey<VideoState>();

  late final Player player;
  late final VideoController controller;

  late VideoClip _currentClip;
  late VideoClip _originalClipForReset;

  bool _isNewClip = true;
  String? _coverPreviewPath;
  bool _isSettingCover = false;

  final _nameController = TextEditingController();
  final _notesController = TextEditingController();
  final _newTagController = TextEditingController();
  final _tagFocusNode = FocusNode();
  final _videoFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    player = Player();
    controller = VideoController(player);

    if (widget.initialClip != null) {
      _isNewClip = false;
      _currentClip = widget.initialClip!.copyWith();
      _originalClipForReset = widget.initialClip!.copyWith();
    } else {
      _isNewClip = true;
      final newClip = VideoClip(
        id: 'clip_${DateTime.now().millisecondsSinceEpoch}',
        videoPath: widget.video.path,
        name: 'New Clip for ${widget.video.name}',
        startTime: Duration.zero,
        endTime: Duration.zero,
        coverFrameTime: Duration.zero,
      );
      _currentClip = newClip;
      _originalClipForReset = newClip.copyWith();
    }

    _nameController.text = _currentClip.name;
    _notesController.text = _currentClip.notes ?? '';
    _coverPreviewPath = _currentClip.thumbnailPath;

    player.open(Media(widget.video.path), play: false).then((_) async {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      player.seek(_currentClip.startTime);
      setState(() {});
    });
  }

  @override
  void dispose() {
    player.dispose();
    _nameController.dispose();
    _notesController.dispose();
    _newTagController.dispose();
    _tagFocusNode.dispose();
    _videoFocusNode.dispose();
    super.dispose();
  }

  // ... [此处省略所有未改变的辅助方法，如 _saveClip, _buildRatingBar 等]
  // ... [您可以从您自己的文件中保留这部分代码]
  void _updateControllersAndPreviewFromClip() {
    _nameController.text = _currentClip.name;
    _notesController.text = _currentClip.notes ?? '';
    _coverPreviewPath = _currentClip.thumbnailPath;
  }

  void _resetFields() {
    setState(() {
      _currentClip = _originalClipForReset.copyWith();
      _updateControllersAndPreviewFromClip();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('所有字段已重置'), duration: Duration(seconds: 2)),
    );
  }

  void _setStartTimeFromPlayer() {
    final time = player.state.position;
    setState(() {
      if (_currentClip.endTime != Duration.zero &&
          time > _currentClip.endTime) {
        _currentClip.startTime = _currentClip.endTime;
      } else {
        _currentClip.startTime = time;
      }
    });
  }

  void _setEndTimeFromPlayer() {
    final time = player.state.position;
    setState(() {
      if (time < _currentClip.startTime) {
        _currentClip.endTime = _currentClip.startTime;
      } else {
        _currentClip.endTime = time;
      }
    });
  }

  Future<void> _previewClip() async {
    if (_currentClip.startTime >= _currentClip.endTime) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('终点必须在起点之后才能预览'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    await player.seek(_currentClip.startTime);
    await player.play();

    Future.delayed(_currentClip.endTime - _currentClip.startTime, () {
      if (mounted && player.state.playing) {
        player.pause();
      }
    });
  }

  Future<void> _generateCoverAtTime(Duration time) async {
    setState(() {
      _isSettingCover = true;
    });

    try {
      final thumbnailService = context.read<ThumbnailService>();
      final newThumbPath = await thumbnailService.generateThumbnail(
        widget.video.path,
        time,
        _currentClip.id,
      );

      if (!mounted) return;

      if (newThumbPath != null) {
        final imageProvider = FileImage(File(newThumbPath));
        await imageProvider.evict();

        setState(() {
          _currentClip = _currentClip.copyWith(
            coverFrameTime: time,
            thumbnailPath: newThumbPath,
          );
          _coverPreviewPath = newThumbPath;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cover frame updated!'),
            backgroundColor: Colors.teal,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: Failed to generate thumbnail.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('An error occurred: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSettingCover = false;
        });
      }
    }
  }

  Future<void> _setCoverFromCurrentFrame() async {
    await _generateCoverAtTime(player.state.position);
  }

  Future<void> _resetCoverToStartTime() async {
    await _generateCoverAtTime(_currentClip.startTime);
  }

  Future<void> _saveClip() async {
    if (_currentClip.endTime <= _currentClip.startTime) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('保存失败: 结束时间必须在开始时间之后'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    final appState = context.read<AppState>();

    _currentClip.name = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'Untitled Clip';
    _currentClip.notes = _notesController.text.trim();

    if (_currentClip.thumbnailPath == null ||
        !await File(_currentClip.thumbnailPath!).exists()) {
      if (_currentClip.coverFrameTime == Duration.zero) {
        _currentClip.coverFrameTime = _currentClip.startTime;
      }
      final thumbnailService = context.read<ThumbnailService>();
      _currentClip.thumbnailPath = await thumbnailService.generateThumbnail(
        widget.video.path,
        _currentClip.coverFrameTime,
        _currentClip.id,
      );
    }

    if (_isNewClip) {
      await appState.addClip(_currentClip);
      _isNewClip = false;
      _originalClipForReset = _currentClip.copyWith();
    } else {
      await appState.updateClip(_currentClip);
      _originalClipForReset = _currentClip.copyWith();
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Clip "${_currentClip.name}" saved!'),
          backgroundColor: Colors.green[700],
        ),
      );
    }
  }

  // --- WIDGET BUILDER METHODS ---

  Widget _buildRatingBar() {
    return Column(
      children: [
        const Text('Rating', style: TextStyle(fontWeight: FontWeight.bold)),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (index) {
            return IconButton(
              icon: Icon(
                index < _currentClip.rating ? Icons.star : Icons.star_border,
                color: index < _currentClip.rating ? Colors.amber : Colors.grey,
              ),
              onPressed: () {
                setState(() {
                  _currentClip.rating = (_currentClip.rating == index + 1)
                      ? 0
                      : index + 1;
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
            _currentClip.isFavorite ? Icons.favorite : Icons.favorite_border,
            color: _currentClip.isFavorite ? Colors.redAccent : Colors.grey,
          ),
          onPressed: () {
            setState(() {
              _currentClip.isFavorite = !_currentClip.isFavorite;
            });
          },
        ),
      ],
    );
  }

  Widget _buildClippingControls() {
    final theme = Theme.of(context);
    final clipDuration = _currentClip.endTime - _currentClip.startTime;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildTimeDisplay(
                'Start',
                _currentClip.startTime,
                theme.primaryColor,
              ),
              _buildTimeDisplay('End', _currentClip.endTime, Colors.redAccent),
              if (clipDuration > Duration.zero)
                _buildTimeDisplay(
                  'Duration',
                  clipDuration,
                  theme.textTheme.bodyLarge?.color,
                ),
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
                onPressed: _previewClip,
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
              color: color,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverControls() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildTimeDisplay(
                  'Cover Frame',
                  _currentClip.coverFrameTime,
                  Colors.teal,
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: _isSettingCover ? null : _setCoverFromCurrentFrame,
                  child: _isSettingCover
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Set Cover'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.settings_backup_restore),
                  tooltip: 'Reset cover time to start time',
                  onPressed: _isSettingCover ? null : _resetCoverToStartTime,
                ),
              ],
            ),
            if (_coverPreviewPath != null)
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
                      File(_coverPreviewPath!),
                      key: ValueKey(_currentClip.coverFrameTime),
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
        if (_currentClip.tags.isNotEmpty)
          Wrap(
            spacing: 6.0,
            runSpacing: 0.0,
            children: _currentClip.tags.map((tag) {
              return Chip(
                label: Text(tag),
                onDeleted: () {
                  setState(() {
                    _currentClip.tags.remove(tag);
                  });
                },
              );
            }).toList(),
          ),
        RawAutocomplete<String>(
          textEditingController: _newTagController,
          focusNode: _tagFocusNode,
          optionsBuilder: (TextEditingValue textEditingValue) {
            if (textEditingValue.text.isEmpty) {
              return appState.allTags.where(
                (tag) => !_currentClip.tags.contains(tag),
              );
            }
            return appState.allTags.where(
              (tag) =>
                  tag.toLowerCase().contains(
                    textEditingValue.text.toLowerCase(),
                  ) &&
                  !_currentClip.tags.contains(tag),
            );
          },
          onSelected: (String selection) {
            setState(() {
              if (selection.isNotEmpty &&
                  !_currentClip.tags.contains(selection)) {
                _currentClip.tags.add(selection);
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
                hintText: 'Type and press Enter to add',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (String value) {
                final newTag = value.trim();
                setState(() {
                  if (newTag.isNotEmpty &&
                      !_currentClip.tags.contains(newTag)) {
                    _currentClip.tags.add(newTag);
                  }
                });
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
                    itemBuilder: (BuildContext context, int index) {
                      final String option = options.elementAt(index);
                      return InkWell(
                        onTap: () {
                          onSelected(option);
                        },
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

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    final saveShortcut = LogicalKeySet(
      defaultTargetPlatform == TargetPlatform.macOS
          ? LogicalKeyboardKey.meta
          : LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyS,
    );

    // NEW: 使用 RawKeyboardListener 来捕获全局按键事件
    return Shortcuts(
      // 我们仍然为其他快捷键保留Shortcuts
      shortcuts: <LogicalKeySet, Intent>{saveShortcut: const SaveIntent()},
      child: Actions(
        actions: <Type, Action<Intent>>{
          SaveIntent: CallbackAction<SaveIntent>(
            onInvoke: (Intent intent) => _saveClip(),
          ),
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(_isNewClip ? 'Create Clip' : 'Edit Clip'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Reset Fields',
                onPressed: _resetFields,
              ),
              IconButton(
                icon: const Icon(Icons.save),
                tooltip: 'Save Clip (Ctrl+S)',
                onPressed: _saveClip,
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: Card(
                  elevation: 4.0,
                  margin: const EdgeInsets.all(8.0),
                  clipBehavior: Clip.antiAlias,
                  child: Focus(
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
                                onInvoke: (Intent intent) {
                                  player.playOrPause();
                                  return null;
                                },
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
                          child: Video(
                            key: _videoKey,
                            controller: controller,
                            controls: (state) => CustomPlayerControls(
                              player: player,
                              isFullscreen: state.isFullscreen(),
                              onToggleFullscreen: state.toggleFullscreen,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              CustomProgressBar(
                player: player,
                startTime: _currentClip.startTime,
                endTime: _currentClip.endTime,
                onSetStart: (time) =>
                    setState(() => _currentClip.startTime = time),
                onSetEnd: (time) => setState(() => _currentClip.endTime = time),
              ),
              _buildClippingControls(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
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
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildFavoriteButton(),
                              _buildRatingBar(),
                            ],
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
          ),
        ),
      ),
    );
  }
}

class CustomPlayerControls extends StatefulWidget {
  final Player player;
  final bool isFullscreen;
  final VoidCallback onToggleFullscreen;

  const CustomPlayerControls({
    super.key,
    required this.player,
    required this.isFullscreen,
    required this.onToggleFullscreen,
  });

  @override
  State<CustomPlayerControls> createState() => _CustomPlayerControlsState();
}

class _CustomPlayerControlsState extends State<CustomPlayerControls> {
  bool _areControlsVisible = true;
  double _currentVolume = 1.0;

  // NEW: 为控件自身创建一个焦点节点
  final FocusNode _controlsFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _currentVolume = widget.player.state.volume / 100.0;
  }

  @override
  void dispose() {
    // NEW: 记得销毁
    _controlsFocusNode.dispose();
    super.dispose();
  }

  void _toggleControlsVisibility() {
    setState(() {
      _areControlsVisible = !_areControlsVisible;
    });
  }

  @override
  Widget build(BuildContext context) {
    // NEW: 在最外层包裹一个 RawKeyboardListener
    return RawKeyboardListener(
      focusNode: _controlsFocusNode,
      autofocus: true, // 非常关键，让它一显示就尝试获取焦点
      onKey: (RawKeyEvent event) {
        if (event is RawKeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          print("--- ESCAPE KEY DETECTED BY *CONTROLS* LISTENER ---");
          widget.onToggleFullscreen();
        }
      },
      child: GestureDetector(
        onTap: _toggleControlsVisibility,
        child: Stack(
          children: [
            Container(color: Colors.transparent),
            StreamBuilder<bool>(
              stream: widget.player.stream.playing,
              initialData: widget.player.state.playing,
              builder: (context, snapshot) {
                final isPlaying = snapshot.data ?? false;
                return AnimatedOpacity(
                  opacity: _areControlsVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black38,
                          Colors.transparent,
                          Colors.black54,
                        ],
                      ),
                    ),
                    // _buildControlsContent 方法无需改动
                    child: _buildControlsContent(context, isPlaying),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // 这个方法原封不动
  Widget _buildControlsContent(BuildContext context, bool isPlaying) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const SizedBox.shrink(),
        if (!isPlaying)
          Center(
            child: IconButton.filled(
              iconSize: 50,
              icon: const Icon(Icons.play_arrow),
              onPressed: widget.player.play,
            ),
          ),
        Row(
          children: [
            IconButton(
              icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
              color: Colors.white,
              onPressed: widget.player.playOrPause,
            ),
            const Spacer(),
            PopupMenuButton(
              icon: Icon(
                _currentVolume <= 0
                    ? Icons.volume_off
                    : (_currentVolume < 0.5
                          ? Icons.volume_down
                          : Icons.volume_up),
                color: Colors.white,
              ),
              itemBuilder: (context) => [
                PopupMenuItem(
                  enabled: false,
                  child: SizedBox(
                    width: 200,
                    child: StreamBuilder<double>(
                      stream: widget.player.stream.volume,
                      builder: (context, snapshot) {
                        final volume =
                            snapshot.data ?? (widget.player.state.volume);
                        return Slider(
                          value: volume / 100.0,
                          onChanged: (value) {
                            widget.player.setVolume(value * 100);
                            setState(() => _currentVolume = value);
                          },
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
            IconButton(
              icon: Icon(
                widget.isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
              ),
              color: Colors.white,
              onPressed: widget.onToggleFullscreen,
            ),
          ],
        ),
      ],
    );
  }
}
