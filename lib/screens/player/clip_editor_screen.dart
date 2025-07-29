import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:multi_split_view/multi_split_view.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../data/models.dart';
import '../../data/app_state.dart';
import '../../widgets/custom_progress_bar.dart';
import '../../services/thumbnail_service.dart';
import '../../main.dart';

// --- Keyboard Intent Classes (Unchanged) ---
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
  final VideoClip? clipToEdit;

  const ClipEditorScreen({super.key, required this.video, this.clipToEdit});

  @override
  State<ClipEditorScreen> createState() => _ClipEditorScreenState();
}

class _ClipEditorScreenState extends State<ClipEditorScreen> {
  final GlobalKey<VideoState> _videoKey = GlobalKey<VideoState>();

  // --- Player and Controllers ---
  late final Player player;
  late final VideoController controller;
  final MultiSplitViewController _splitViewController =
      MultiSplitViewController(
        areas: [
          Area(flex: 13, min: 10, max: 14, data: 'editor'),
          Area(flex: 7, min: 6, max: 10, data: 'list'),
        ],
      );

  // --- State Management for Clips ---
  late VideoClip _formClip;
  VideoClip? _editingClip;

  // --- UI State ---
  bool _isSaving = false;
  String? _coverPreviewPath;
  bool _isSettingCover = false;

  // --- Text and Focus Controllers ---
  final _nameController = TextEditingController();
  final _notesController = TextEditingController();
  final _newTagController = TextEditingController();
  final _tagFocusNode = FocusNode();
  final _videoFocusNode = FocusNode();
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  final FocusNode _formFocusNode = FocusNode();

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

    player.open(Media(widget.video.path), play: false).then((_) {
      if (!mounted) return;
      setState(() {});
    });

    // NOUVEAU: Ajout de listeners pour synchroniser le nom et les notes avec _formClip
    _nameController.addListener(() {
      if (_formClip.name != _nameController.text) {
        setState(() {
          _formClip = _formClip.copyWith(name: _nameController.text);
        });
      }
    });
    _notesController.addListener(() {
      if (_formClip.notes != _notesController.text) {
        setState(() {
          _formClip = _formClip.copyWith(notes: _notesController.text);
        });
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
    _formFocusNode.dispose();
    super.dispose();
  }

  // --- CORE LOGIC METHODS ---

  void _resetFormToBlank() {
    setState(() {
      _editingClip = null;
      final newClip = VideoClip(
        id: 'clip_${DateTime.now().millisecondsSinceEpoch}',
        videoPath: widget.video.path,
        name: '',
        startTime: Duration.zero,
        endTime: Duration.zero,
        coverFrameTime: Duration.zero,
      );
      _formClip = newClip;
      _updateControllersAndPreviewFromClip(
        true,
      ); // MODIFIÉ: Force la mise à jour des controllers
    });
  }

  void _startEditing(VideoClip clipToEdit, {bool fromInit = false}) {
    setState(() {
      // Stocke la version originale et crée une copie pour le formulaire
      _editingClip = clipToEdit;
      _formClip = clipToEdit.copyWith();
      _updateControllersAndPreviewFromClip(
        true,
      ); // MODIFIÉ: Force la mise à jour des controllers
      player.seek(clipToEdit.startTime);
    });

    final appState = context.read<AppState>();
    final clipsForThisVideo = appState.clips
        .where((c) => c.videoPath == widget.video.path)
        .toList();
    final index = clipsForThisVideo.indexWhere((c) => c.id == clipToEdit.id);

    if (index != -1) {
      if (fromInit) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _itemScrollController.scrollTo(
            index: index,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
          );
        });
      } else {
        _itemScrollController.scrollTo(
          index: index,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
    }

    if (!fromInit) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Now editing: "${clipToEdit.name}"'),
          backgroundColor: Colors.orange.shade800,
        ),
      );
    }
  }

  // MODIFIÉ: La méthode peut forcer la mise à jour des controllers texte
  void _updateControllersAndPreviewFromClip([bool forceUpdate = false]) {
    // Met à jour les controllers uniquement si le texte est différent ou si c'est forcé
    if (forceUpdate || _nameController.text != _formClip.name) {
      _nameController.text = _formClip.name;
    }
    if (forceUpdate || _notesController.text != (_formClip.notes ?? '')) {
      _notesController.text = _formClip.notes ?? '';
    }
    _coverPreviewPath = _formClip.thumbnailPath;
  }

  // NOUVEAU: Méthode pour annuler les changements dans le formulaire
  void _resetFormChanges() {
    if (_editingClip == null) return;
    setState(() {
      _formClip = _editingClip!.copyWith();
      _updateControllersAndPreviewFromClip(true); // Force la mise à jour
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

    // Le nom et les notes sont déjà synchronisés, on les récupère directement depuis _formClip
    if (_formClip.name.trim().isEmpty) {
      _formClip = _formClip.copyWith(name: 'Untitled Clip');
    }

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

    // Génération de la miniature si nécessaire
    if (_formClip.thumbnailPath == null ||
        !await File(_formClip.thumbnailPath!).exists() ||
        (_editingClip != null &&
            _formClip.coverFrameTime != _editingClip!.coverFrameTime)) {
      if (_formClip.coverFrameTime == Duration.zero) {
        _formClip = _formClip.copyWith(coverFrameTime: _formClip.startTime);
      }
      final thumbnailService = context.read<ThumbnailService>();
      final newThumbPath = await thumbnailService.generateThumbnail(
        widget.video.path,
        _formClip.coverFrameTime,
        _formClip.id,
      );
      _formClip = _formClip.copyWith(thumbnailPath: newThumbPath);
    }

    if (_editingClip == null) {
      await appState.addClip(_formClip);
    } else {
      await appState.updateClip(_formClip);
      // Mettre à jour _editingClip pour refléter l'état sauvegardé
      _editingClip = _formClip.copyWith();
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Clip "${_formClip.name}" saved!'),
          backgroundColor: Colors.green[700],
        ),
      );
      if (_editingClip == null) {
        _resetFormToBlank();
      }
    }
    setState(() => _isSaving = false);
  }

  void _deleteClip(VideoClip clip) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: Text(
          'Are you sure you want to delete the clip "${clip.name}"? This cannot be undone.',
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
              if (_editingClip?.id == clip.id) {
                _resetFormToBlank();
              }
              context.read<AppState>().deleteClip(clip.id);
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Clip deleted.'),
                  backgroundColor: Colors.redAccent,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _setStartTimeFromPlayer() {
    final time = player.state.position;
    setState(() {
      if (_formClip.endTime != Duration.zero && time > _formClip.endTime) {
        // On remplace la variable _formClip par une nouvelle copie
        _formClip = _formClip.copyWith(startTime: _formClip.endTime);
      } else {
        _formClip = _formClip.copyWith(startTime: time);
      }
    });
  }

  void _setEndTimeFromPlayer() {
    final time = player.state.position;
    setState(() {
      if (time < _formClip.startTime) {
        // On remplace la variable _formClip par une nouvelle copie
        _formClip = _formClip.copyWith(endTime: _formClip.startTime);
      } else {
        _formClip = _formClip.copyWith(endTime: time);
      }
    });
  }

  Future<void> _previewClip(Duration start, Duration end) async {
    if (start >= end) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End time must be after start time to preview.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
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
    try {
      final thumbnailService = context.read<ThumbnailService>();
      final newThumbPath = await thumbnailService.generateThumbnail(
        widget.video.path,
        time,
        _formClip.id,
      );
      if (!mounted) return;
      if (newThumbPath != null) {
        final imageProvider = FileImage(File(newThumbPath));
        await imageProvider.evict();
        setState(() {
          _formClip = _formClip.copyWith(
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
      }
    } finally {
      if (mounted) setState(() => _isSettingCover = false);
    }
  }

  Future<void> _setCoverFromCurrentFrame() async {
    await _generateCoverAtTime(player.state.position);
  }

  Future<void> _resetCoverToStartTime() async {
    await _generateCoverAtTime(_formClip.startTime);
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
                // Redonner le focus au formulaire
                _formFocusNode.requestFocus();
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
            // Redonner le focus au formulaire
            _formFocusNode.requestFocus();
          },
        ),
      ],
    );
  }

  Widget _buildClippingControls() {
    final theme = Theme.of(context);
    final clipDuration = _formClip.endTime - _formClip.startTime;

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
                  _formClip.coverFrameTime,
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
                      key: ValueKey(_coverPreviewPath),
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
                    // CORRECTION: Créer une nouvelle liste et un nouveau clip
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
            if (textEditingValue.text.isEmpty) {
              return appState.allTags.where(
                (tag) => !_formClip.tags.contains(tag),
              );
            }
            return appState.allTags.where(
              (tag) =>
                  tag.toLowerCase().contains(
                    textEditingValue.text.toLowerCase(),
                  ) &&
                  !_formClip.tags.contains(tag),
            );
          },
          onSelected: (String selection) {
            setState(() {
              if (selection.isNotEmpty && !_formClip.tags.contains(selection)) {
                // CORRECTION: Créer une nouvelle liste et un nouveau clip
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
                hintText: 'Type and press Enter to add',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (String value) {
                final newTag = value.trim();
                setState(() {
                  if (newTag.isNotEmpty && !_formClip.tags.contains(newTag)) {
                    // CORRECTION: Créer une nouvelle liste et un nouveau clip
                    final newTags = List<String>.from(_formClip.tags)
                      ..add(newTag);
                    _formClip = _formClip.copyWith(tags: newTags);
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
                      key: _videoKey,
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
            ),
          ),
        ),
        StreamBuilder<Duration>(
          stream: player.stream.duration,
          initialData: player.state.duration,
          builder: (context, snapshot) {
            final isReady = (snapshot.data ?? Duration.zero) > Duration.zero;

            if (isReady) {
              return CustomProgressBar(
                player: player,
                startTime: _formClip.startTime,
                endTime: _formClip.endTime,
                onSetStart: (time) => setState(
                  () => _formClip = _formClip.copyWith(startTime: time),
                ),
                onSetEnd: (time) => setState(
                  () => _formClip = _formClip.copyWith(endTime: time),
                ),
                showThumbnailPreview: true,
              );
            }
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20.0),
              child: Center(child: CircularProgressIndicator()),
            );
          },
        ),
        _buildClippingControls(),
        Expanded(
          flex: 3,
          child: Focus(
            focusNode: _formFocusNode,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_editingClip != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Chip(
                        label: Text('Editing: ${_editingClip!.name}'),
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
        ),
      ],
    );
  }

  /// The right panel displaying the list of saved clips for this video.
  Widget _buildClipList(AppState appState) {
    // Le reste de cette méthode est identique à la version précédente
    final clipsForThisVideo = appState.clips
        .where((c) => c.videoPath == widget.video.path)
        .toList();

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
                'No clips created yet.\nUse the panel on the left to create one.',
                textAlign: TextAlign.center,
              ),
            )
          : ScrollablePositionedList.builder(
              itemCount: clipsForThisVideo.length,
              itemScrollController: _itemScrollController,
              itemPositionsListener: _itemPositionsListener,
              itemBuilder: (context, index) {
                final clip = clipsForThisVideo[index];
                final isEditingThis = _editingClip?.id == clip.id;
                final duration = clip.endTime - clip.startTime;

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
                  child: Column(
                    children: [
                      ListTile(
                        leading: clip.thumbnailPath != null
                            ? Image.file(
                                File(clip.thumbnailPath!),
                                width: 100,
                                height: 56,
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) =>
                                    const Icon(Icons.hide_image),
                              )
                            : Container(
                                width: 100,
                                height: 56,
                                color: Colors.grey.shade300,
                                child: const Icon(
                                  Icons.movie_creation_outlined,
                                ),
                              ),
                        title: Text(
                          clip.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${formatDuration(clip.startTime)} - ${formatDuration(clip.endTime)} (${formatDuration(duration)})',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                        onTap: () => _startEditing(clip),
                      ),
                      if (clip.tags.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: clip.tags
                                .map(
                                  (t) => Chip(
                                    label: Text(t),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Row(
                              children: List.generate(5, (starIndex) {
                                return IconButton(
                                  icon: Icon(
                                    starIndex < clip.rating
                                        ? Icons.star
                                        : Icons.star_border,
                                    color: starIndex < clip.rating
                                        ? Colors.amber.shade600
                                        : Theme.of(context).disabledColor,
                                  ),
                                  onPressed: () {
                                    final newRating =
                                        clip.rating == starIndex + 1
                                        ? 0
                                        : starIndex + 1;
                                    final updatedClip = clip.copyWith(
                                      rating: newRating,
                                    );
                                    context.read<AppState>().updateClip(
                                      updatedClip,
                                    );
                                  },
                                );
                              }),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Toggle Favorite',
                              icon: Icon(
                                clip.isFavorite
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: clip.isFavorite
                                    ? Colors.redAccent
                                    : Theme.of(context).disabledColor,
                              ),
                              onPressed: () {
                                final updatedClip = clip.copyWith(
                                  isFavorite: !clip.isFavorite,
                                );
                                context.read<AppState>().updateClip(
                                  updatedClip,
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.play_circle_outline),
                            color: Colors.green,
                            tooltip: 'Play Clip',
                            onPressed: () =>
                                _previewClip(clip.startTime, clip.endTime),
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
                    ],
                  ),
                );
              },
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isEditing = _editingClip != null;

    // --- LOGIQUE DE SYNCHRONISATION CORRIGÉE ---
    if (isEditing) {
      try {
        final latestClipVersionInState = appState.clips.firstWhere(
          (c) => c.id == _editingClip!.id,
        );

        // On compare la version dans l'état global avec la version originale de notre session d'édition (_editingClip).
        // Cette condition n'est vraie que si une modification a eu lieu DEPUIS LA LISTE DE DROITE.
        if (latestClipVersionInState != _editingClip) {
          // Un changement externe a eu lieu. On met à jour l'éditeur pour refléter ce changement.
          // On utilise addPostFrameCallback pour éviter un setState pendant un build.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // C'est une bonne pratique d'informer l'utilisateur.
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Clip data refreshed due to external changes.'),
                backgroundColor: Colors.blueAccent,
              ),
            );

            setState(() {
              // On met à jour la "base" de l'édition.
              _editingClip = latestClipVersionInState.copyWith();
              // On réinitialise le formulaire avec cette nouvelle base.
              _formClip = latestClipVersionInState.copyWith();
              // On force la mise à jour des contrôleurs de texte.
              _updateControllersAndPreviewFromClip(true);
            });
          });
        }
      } catch (e) {
        // Le clip a probablement été supprimé. On réinitialise le formulaire.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _resetFormToBlank();
        });
      }
    }

    // Détermine si des changements non sauvegardés existent
    final bool hasChanges = isEditing && _formClip != _editingClip;

    final saveShortcut = LogicalKeySet(
      defaultTargetPlatform == TargetPlatform.macOS
          ? LogicalKeyboardKey.meta
          : LogicalKeyboardKey.control,
      LogicalKeyboardKey.keyS,
    );

    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{saveShortcut: const SaveIntent()},
      child: Actions(
        actions: <Type, Action<Intent>>{
          SaveIntent: CallbackAction<SaveIntent>(
            onInvoke: (Intent intent) => _saveOrUpdateClip(),
          ),
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(isEditing ? 'Edit Clip' : 'Create Clips'),
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
                  label: const Text('Reset'),
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
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(isEditing ? Icons.check_circle_outline : Icons.save),
                label: Text(isEditing ? 'Update' : 'Save New'),
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
            dividerBuilder:
                (axis, index, resizable, dragging, highlighted, themeData) =>
                    Container(
                      color: dragging
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      width: 8,
                      child: const Icon(Icons.drag_indicator, size: 16),
                    ),
            builder: (context, area) {
              if (area.data == 'editor') {
                return _buildEditorPanel(appState);
              }
              return _buildClipList(appState);
            },
          ),
        ),
      ),
    );
  }
}

// La classe CustomPlayerControls reste inchangée.
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
  final FocusNode _controlsFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _currentVolume = widget.player.state.volume / 100.0;
  }

  @override
  void dispose() {
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
    return RawKeyboardListener(
      focusNode: _controlsFocusNode,
      autofocus: true,
      onKey: (RawKeyEvent event) {
        if (event is RawKeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape &&
            widget.isFullscreen) {
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
