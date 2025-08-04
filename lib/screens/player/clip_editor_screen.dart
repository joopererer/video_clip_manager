import 'dart:io';

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
      MultiSplitViewController(areas: [Area(flex: 13, data: 'editor'), Area(flex: 7, data: 'list')]);

  late VideoClip _formClip;
  VideoClip? _originalEditingClip;

  bool _isSaving = false;
  String? _coverPreviewFullPath;
  bool _isSettingCover = false;

  final _nameController = TextEditingController();
  final _notesController = TextEditingController();
  final _newTagController = TextEditingController();
  final _tagFocusNode = FocusNode();
  final _videoFocusNode = FocusNode();
  final ItemScrollController _itemScrollController = ItemScrollController();

  @override
  void initState() {
    super.initState();
    player = Player();
    controller = VideoController(player);

    if (widget.clipToEdit != null) {
      _startEditing(widget.clipToEdit!, fromInit: true);
    } else {
      _resetFormToBlank();
    }

    player.open(Media(widget.video.path), play: false);
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
        endTime: Duration.zero,
        coverFrameTime: Duration.zero,
      );
      _updateTextFieldsAndPreview();
    });
  }

  void _startEditing(VideoClip clipToEdit, {bool fromInit = false}) {
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
    final clipsForThisVideo =
        appState.clips.where((c) => c.videoPath == widget.video.path).toList();
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
    if (_formClip.thumbnailPath != null && dbPath != null) {
      _coverPreviewFullPath =
          thumbnailService.buildThumbnailPath(dbPath, _formClip.thumbnailPath!);
    } else {
      _coverPreviewFullPath = null;
    }
  }

  void _resetFormChanges() {
    if (_originalEditingClip == null) return;
    setState(() {
      _formClip = _originalEditingClip!.copyWith();
      _updateTextFieldsAndPreview();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Changes discarded.'),
        backgroundColor: Colors.grey,
      ),
    );
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Save failed: End time must be after start time.'),
          backgroundColor: Colors.redAccent,
      ));
      return;
    }

    setState(() => _isSaving = true);
    final appState = context.read<AppState>();
    final dbPath = appState.currentDbFullPath;

    if (dbPath == null) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Save failed: Database path not found.'),
        backgroundColor: Colors.redAccent,
      ));
      setState(() => _isSaving = false);
      return;
    }

    try {
      final bool needsThumbUpdate = _formClip.thumbnailPath == null ||
          (_originalEditingClip != null &&
              _formClip.coverFrameTime != _originalEditingClip!.coverFrameTime);

      if (needsThumbUpdate) {
      final thumbnailService = context.read<ThumbnailService>();
        final coverTime = _formClip.coverFrameTime == Duration.zero
            ? _formClip.startTime
            : _formClip.coverFrameTime;

        final newThumbFileName = await thumbnailService.generateThumbnail(
        widget.video.path,
          coverTime,
        _formClip.id,
          dbPath: dbPath,
        );
        setState(() {
          _formClip = _formClip.copyWith(
            thumbnailPath: newThumbFileName,
            coverFrameTime: coverTime,
          );
        });
      }

      if (_originalEditingClip == null) {
      await appState.addClip(_formClip);
    } else {
      await appState.updateClip(_formClip);
        _originalEditingClip = _formClip.copyWith();
    }

    if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Clip "${_formClip.name}" saved!'),
          backgroundColor: Colors.green[700],
        ));
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
         endTime: (time > _formClip.endTime && _formClip.endTime > Duration.zero) ? time : _formClip.endTime,
       );
    });
  }

  void _setEndTimeFromPlayer() {
    final time = player.state.position;
    setState(() {
      _formClip = _formClip.copyWith(
          endTime: time < _formClip.startTime ? _formClip.startTime : time);
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Cannot generate cover: Database path not found.'),
        backgroundColor: Colors.redAccent,
      ));
      setState(() => _isSettingCover = false);
      return;
    }

    try {
      final newThumbFileName = await thumbnailService.generateThumbnail(
        widget.video.path,
        time,
        _formClip.id,
        dbPath: dbPath,
      );

      if (!mounted) return;

      if (newThumbFileName != null) {
        final newFullPath = thumbnailService.buildThumbnailPath(dbPath, newThumbFileName);
        FileImage(File(newFullPath)).evict();

        setState(() {
          _formClip = _formClip.copyWith(
            coverFrameTime: time,
            thumbnailPath: newThumbFileName,
          );
          _coverPreviewFullPath = newFullPath;
        });
      }
    } finally {
      if (mounted) setState(() => _isSettingCover = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final thumbnailService = context.read<ThumbnailService>();
    final isEditing = _originalEditingClip != null;

    if (isEditing) {
      final latestClipInState =
          appState.clips.firstWhereOrNull((c) => c.id == _originalEditingClip!.id);
      if (latestClipInState == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _resetFormToBlank());
      } else if (latestClipInState != _originalEditingClip) {
        _originalEditingClip = latestClipInState;
      }
    }

    final bool hasChanges = isEditing && _formClip != _originalEditingClip;
    final saveShortcut = LogicalKeySet(
      Platform.isMacOS
          ? LogicalKeyboardKey.meta
          : LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyS,
    );

    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{saveShortcut: const SaveIntent()},
      child: Actions(
        actions: <Type, Action<Intent>>{
          SaveIntent:
              CallbackAction<SaveIntent>(onInvoke: (i) => _saveOrUpdateClip()),
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(isEditing ? 'Edit Clip' : 'Create New Clip'),
            actions: [
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
                      foregroundColor:
                          hasChanges ? Colors.orange.shade700 : Colors.grey),
                ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(isEditing ? Icons.check_circle_outline : Icons.save),
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
    );
  }

  Widget _buildEditorPanel(AppState appState) {
    return Column(
      children: [
        Expanded(
          flex: 2,
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
                    child: Video(
                      controller: controller,
                      controls: (state) => CustomPlayerControls(
                        player: player,
                        videoState: state,
                      ),
                    ),
                  ),
                ),
              ),
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
            return CustomProgressBar(
              player: player,
              startTime: _formClip.startTime,
              endTime: _formClip.endTime,
              onSetStart: (time) =>
                  setState(() => _formClip = _formClip.copyWith(startTime: time)),
              onSetEnd: (time) =>
                  setState(() => _formClip = _formClip.copyWith(endTime: time)),
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
                      labelText: 'Clip Name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                _buildTagEditor(appState),
                const SizedBox(height: 12),
                TextField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Notes', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
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
              _buildTimeDisplay('Start', _formClip.startTime, theme.primaryColor),
              _buildTimeDisplay('End', _formClip.endTime, Colors.redAccent),
              if (clipDuration > Duration.zero)
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
                    backgroundColor: theme.colorScheme.secondaryContainer),
                icon: const Icon(Icons.slideshow),
                onPressed: () => _previewClip(_formClip.startTime, _formClip.endTime),
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
      margin: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildTimeDisplay('Cover At', _formClip.coverFrameTime, Colors.teal),
                const Spacer(),
                ElevatedButton(
                  onPressed: _isSettingCover ? null : () => _generateCoverAtTime(player.state.position),
                  child: _isSettingCover
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Set Cover'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.settings_backup_restore),
                  tooltip: 'Reset cover to start time',
                  onPressed: _isSettingCover ? null : () => _generateCoverAtTime(_formClip.startTime),
                ),
              ],
            ),
            if (_coverPreviewFullPath != null)
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Column(
                  children: [
                    const Divider(),
                    const Text("Cover Preview", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Image.file(
                      File(_coverPreviewFullPath!),
                      key: ValueKey(_coverPreviewFullPath),
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
                    final newTags = List<String>.from(_formClip.tags)..remove(tag);
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
              return appState.allTags.where((tag) => !_formClip.tags.contains(tag));
            }
            return appState.allTags.where((tag) =>
                tag.toLowerCase().contains(query) && !_formClip.tags.contains(tag));
          },
          onSelected: (String selection) {
            setState(() {
              if (selection.isNotEmpty && !_formClip.tags.contains(selection)) {
                final newTags = List<String>.from(_formClip.tags)..add(selection);
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
                  labelText: 'Add a Tag', border: OutlineInputBorder()),
              onSubmitted: (String value) {
                final newTag = value.trim();
                  if (newTag.isNotEmpty && !_formClip.tags.contains(newTag)) {
                  setState(() {
                    final newTags = List<String>.from(_formClip.tags)..add(newTag);
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
                  final newRating = (_formClip.rating == index + 1) ? 0 : index + 1;
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
    final clipsForThisVideo =
        appState.clips.where((c) => c.videoPath == widget.video.path).toList();
    final dbPath = appState.currentDbFullPath;

    return Scaffold(
      appBar: AppBar(
        title: Text('Clips (${clipsForThisVideo.length})'),
        backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
        centerTitle: true,
        toolbarHeight: 40,
      ),
      body: clipsForThisVideo.isEmpty
          ? const Center(
              child: Text('No clips yet.\nUse the panel on the left to create one.',
                  textAlign: TextAlign.center))
          : ScrollablePositionedList.builder(
              itemCount: clipsForThisVideo.length,
              itemScrollController: _itemScrollController,
              itemBuilder: (context, index) {
                final clip = clipsForThisVideo[index];
                final isEditingThis = _originalEditingClip?.id == clip.id;
                final duration = clip.endTime - clip.startTime;

                String? thumbFullPath;
                if (clip.thumbnailPath != null && dbPath != null) {
                  thumbFullPath =
                      thumbnailService.buildThumbnailPath(dbPath, clip.thumbnailPath!);
                }

                return Card(
                  elevation: isEditingThis ? 6 : 2,
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  color: isEditingThis ? Colors.orange.shade50 : null,
                  shape: isEditingThis
                      ? RoundedRectangleBorder(
                          side: BorderSide(color: Colors.orange.shade700, width: 2),
                          borderRadius: BorderRadius.circular(12),
                        )
                      : null,
                  child: Column(
                    children: [
                      ListTile(
                        leading: SizedBox(
                                width: 100,
                                height: 56,
                          child: thumbFullPath != null
                              ? Image.file(
                                  File(thumbFullPath),
                                  key: ValueKey(thumbFullPath),
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) =>
                                      const Icon(Icons.error_outline),
                              )
                            : Container(
                                color: Colors.grey.shade300,
                                  child: const Icon(Icons.movie_creation_outlined),
                                ),
                              ),
                        title: Text(clip.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          '${formatDuration(clip.startTime)} - ${formatDuration(clip.endTime)} (${formatDuration(duration)})',
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                        onTap: () => _startEditing(clip),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (clip.isFavorite)
                              const Icon(Icons.favorite, color: Colors.redAccent, size: 20),
                            if (clip.rating > 0) ...[
                                const SizedBox(width: 4),
                                Row(
                                  children: List.generate(
                                    clip.rating,
                                    (i) => const Icon(Icons.star, color: Colors.amber, size: 20),
                                  ),
                                )
                            ],
                            const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.play_circle_outline),
                            color: Colors.green,
                            tooltip: 'Play Clip',
                              onPressed: () => _previewClip(clip.startTime, clip.endTime),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_note),
                            color: Colors.blue.shade700,
                            tooltip: 'Edit Clip',
                            onPressed: () => _startEditing(clip),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_forever_outlined),
                            color: Colors.red.shade700,
                            tooltip: 'Delete Clip',
                            onPressed: () => _deleteClip(clip),
                          ),
                        ],
                      ),
                      )
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class CustomPlayerControls extends StatelessWidget {
  final Player player;
  final VideoState videoState;

  const CustomPlayerControls({
    super.key,
    required this.player,
    required this.videoState,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialVideoControls(videoState);
  }
}

