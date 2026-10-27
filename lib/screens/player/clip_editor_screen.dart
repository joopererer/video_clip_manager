import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:multi_split_view/multi_split_view.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../services/frame_embedding_pool.dart';
import '../../services/preview_service.dart';
import '../../services/thumbnail_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../utils/clip_edit_rules.dart';
import '../../utils/clip_range.dart';
import '../../utils/timecode.dart';
import '../../widgets/ai_settings_dialog.dart';
import '../../widgets/clip_editor/clip_list_panel.dart';
import '../../widgets/clip_editor/clip_properties_panel.dart';
import '../../widgets/clip_editor_key_handler.dart';
import '../../widgets/clip_range_timeline.dart';
import '../../widgets/timecode_field.dart';

String formatDuration(Duration d) {
  final parts = d.toString().split('.').first.padLeft(8, '0').split(':');
  return '${parts[0]}:${parts[1]}:${parts[2]}';
}

bool _isNetworkSource(String path) {
  final lower = path.toLowerCase();
  return lower.startsWith('http://') ||
      lower.startsWith('https://') ||
      lower.startsWith('rtmp://') ||
      lower.startsWith('rtsp://');
}

class SaveIntent extends Intent {
  const SaveIntent();
}

class ClipEditorScreen extends StatefulWidget {
  final OriginalVideo video;
  final VideoClip? clipToEdit;

  const ClipEditorScreen({super.key, required this.video, this.clipToEdit});

  @override
  State<ClipEditorScreen> createState() => _ClipEditorScreenState();
}

class _ClipEditorScreenState extends State<ClipEditorScreen> {
  /// Width from which the properties / clip list sit beside the video.
  static const double _wideBreakpoint = 1000;

  late final Player player;
  late final VideoController controller;
  final MultiSplitViewController _splitViewController =
      MultiSplitViewController(
        areas: [
          Area(flex: 1, data: 'editor'),
          Area(size: 380, min: 300, max: 560, data: 'side'),
        ],
      );
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  late VideoClip _formClip;
  VideoClip? _originalEditingClip;
  late VideoClip _blankBaseline;

  bool _isSaving = false;
  String? _coverPreviewFullPath;
  bool _isSettingCover = false;
  int _coverPreviewTimestamp = 0;
  int _clipsListTimestamp = 0;
  String? _tempThumbnailPath;
  bool _isGeneratingAiCaption = false;
  bool _syncingText = false;

  final _nameController = TextEditingController();
  final _notesController = TextEditingController();
  final _newTagController = TextEditingController();
  final _tagFocusNode = FocusNode();
  final _keyFocusNode = FocusNode(debugLabel: 'clip-editor-shortcuts');
  final ItemScrollController _itemScrollController = ItemScrollController();
  bool _isMuted = false;
  bool _showHints = false;
  int _sideTab = 0;

  // Media state. The player is created once in initState and disposed once.
  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);
  Duration _sourceDuration = Duration.zero;
  bool _fileMissing = false;
  String? _loadError;
  bool _loadTimedOut = false;
  bool _scrubbing = false;
  bool _seeking = false;
  Duration? _queuedSeek;
  Duration? _previewEnd;
  bool _initialSeekPending = false;
  Duration _initialSeekTarget = Duration.zero;
  Timer? _loadTimer;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    PreviewService().pauseGlobalPreGeneration();
    player = Player();
    controller = VideoController(player);

    // Only local files can be "missing"; http(s)/m3u8 sources are opened by
    // the player directly and reported through its error stream.
    _fileMissing =
        !_isNetworkSource(widget.video.path) &&
        !File(widget.video.path).existsSync();
    final known = widget.video.duration;
    if (known != null && known > Duration.zero) {
      _sourceDuration = ClipRangeRules.normalizeSource(known);
    }
    _nameController.addListener(_onTextChanged);
    _notesController.addListener(_onTextChanged);

    if (widget.clipToEdit != null) {
      _startEditing(widget.clipToEdit!, fromInit: true);
    } else {
      _resetFormToBlank(confirmed: true);
    }

    _subscriptions.addAll([
      player.stream.position.listen(_onPlayerPosition),
      player.stream.duration.listen(_onPlayerDuration),
      player.stream.playing.listen(_onPlayerPlaying),
      player.stream.error.listen((message) {
        if (mounted && message.isNotEmpty) {
          setState(() => _loadError = message);
        }
      }),
    ]);

    unawaited(
      player.open(Media(widget.video.path), play: false).catchError((Object e) {
        if (mounted) setState(() => _loadError = '$e');
      }),
    );
    _loadTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && _sourceDuration == Duration.zero) {
        setState(() => _loadTimedOut = true);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keyFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _loadTimer?.cancel();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    PreviewService().resumeGlobalPreGeneration();
    player.dispose();
    _position.dispose();
    _splitViewController.dispose();
    _nameController.dispose();
    _notesController.dispose();
    _newTagController.dispose();
    _tagFocusNode.dispose();
    _keyFocusNode.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Player callbacks (no extra Player / VideoController is ever created)
  // ---------------------------------------------------------------------

  bool get _playerReady => player.state.duration > Duration.zero;

  void _onPlayerPosition(Duration p) {
    if (!mounted) return;
    if (!_scrubbing && !_seeking) _position.value = roundToMs(p);
    final end = _previewEnd;
    if (end != null && !_seeking && p >= end) {
      _previewEnd = null;
      unawaited(player.pause());
    }
  }

  void _onPlayerDuration(Duration d) {
    if (!mounted || d <= Duration.zero) return;
    final normalized = ClipRangeRules.normalizeSource(d);
    _loadTimer?.cancel();
    setState(() {
      _loadTimedOut = false;
      _loadError = null;
      _sourceDuration = normalized;
      // A pristine new clip follows the real duration reported by the player.
      if (_originalEditingClip == null &&
          _formClip.endTime == _blankBaseline.endTime) {
        _formClip = _formClip.copyWith(endTime: normalized);
        _blankBaseline = _blankBaseline.copyWith(endTime: normalized);
      }
    });
    if (_initialSeekPending) {
      _initialSeekPending = false;
      unawaited(_seekTo(_initialSeekTarget));
    }
  }

  void _onPlayerPlaying(bool playing) {
    if (!playing) _previewEnd = null;
  }

  Future<void>? _seekLoop;

  /// Moves the playhead to an absolute source time. Only one seek is ever in
  /// flight; while one is running, the latest request replaces older ones.
  Future<void> _seekTo(Duration target, {bool userInitiated = true}) {
    if (!mounted) return Future<void>.value();
    final upper = _sourceDuration > Duration.zero ? _sourceDuration : target;
    final t = clampDuration(roundToMs(target), Duration.zero, upper);
    if (userInitiated) _previewEnd = null;
    _position.value = t;
    if (!_playerReady) return Future<void>.value();
    _queuedSeek = t;
    return _seekLoop ??= _runSeekLoop();
  }

  Future<void> _runSeekLoop() async {
    _seeking = true;
    try {
      while (_queuedSeek != null) {
        final next = _queuedSeek!;
        _queuedSeek = null;
        try {
          await player.seek(next).timeout(const Duration(seconds: 5));
        } catch (e) {
          debugPrint('[ClipEditor] seek to $next failed: $e');
        }
        if (!mounted) return;
      }
    } finally {
      _seeking = false;
      _seekLoop = null;
    }
  }

  Future<void> _togglePlay() async {
    if (!_playerReady) return;
    try {
      await player.playOrPause();
    } catch (e) {
      debugPrint('[ClipEditor] play/pause failed: $e');
    }
  }

  void _nudgeSeek(Duration delta) {
    unawaited(_seekTo(_position.value + delta));
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    player.setVolume(_isMuted ? 0 : 100);
  }

  Future<void> _previewClip(Duration start, Duration end) async {
    if (start >= end || !_playerReady) return;
    await _seekTo(start);
    if (!mounted) return;
    _previewEnd = end;
    try {
      await player.play();
    } catch (e) {
      debugPrint('[ClipEditor] preview play failed: $e');
    }
  }

  // ---------------------------------------------------------------------
  // Form state (a local draft; nothing is persisted until Save)
  // ---------------------------------------------------------------------

  void _onTextChanged() {
    if (_syncingText || !mounted) return;
    setState(() {}); // refresh the dirty indicator
  }

  /// The clip exactly as Save would persist it.
  VideoClip get _composed => composeClip(
    _formClip,
    name: _nameController.text,
    notes: _notesController.text,
  );

  VideoClip get _baseline => _originalEditingClip ?? _blankBaseline;

  bool get _isDirty =>
      isClipDirty(_composed, _baseline) || _tempThumbnailPath != null;

  void _setControllerTexts(VideoClip clip) {
    _syncingText = true;
    _nameController.text = clip.name;
    _notesController.text = clip.notes ?? '';
    _syncingText = false;
  }

  void _resetFormToBlank({bool confirmed = false}) {
    _cleanupTempCover();
    final blank = VideoClip(
      id: 'clip_${DateTime.now().millisecondsSinceEpoch}',
      videoPath: widget.video.path,
      name: '',
      startTime: Duration.zero,
      endTime: _sourceDuration, // zero until the duration is known
      coverFrameTime: Duration.zero,
    );
    void apply() {
      _originalEditingClip = null;
      _blankBaseline = blank;
      _formClip = blank;
      _tempThumbnailPath = null;
      _setControllerTexts(blank);
      _refreshCoverPreview();
    }

    if (mounted && context.mounted && _initialized) {
      setState(apply);
    } else {
      apply();
    }
  }

  bool get _initialized => _initializedFlag;
  bool _initializedFlag = false;

  void _refreshCoverPreview() {
    final dbPath = context.read<AppState>().currentDbFullPath;
    final thumb = _tempThumbnailPath ?? _formClip.thumbnailPath;
    if (thumb != null && dbPath != null) {
      _coverPreviewFullPath = context
          .read<ThumbnailService>()
          .buildThumbnailPath(dbPath, thumb);
    } else {
      _coverPreviewFullPath = null;
    }
  }

  void _cleanupTempCover() {
    if (_tempThumbnailPath == null || !mounted) return;
    final dbPath = context.read<AppState>().currentDbFullPath;
    if (dbPath != null) {
      context.read<ThumbnailService>().cleanupTempThumbnails(
        dbPath,
        _formClip.id,
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initializedFlag = true;
  }

  void _startEditing(VideoClip clip, {bool fromInit = false}) {
    if (!fromInit) _cleanupTempCover();
    void apply() {
      _originalEditingClip = clip;
      _blankBaseline = clip;
      _formClip = clip.copyWith();
      _tempThumbnailPath = null;
      _setControllerTexts(clip);
      if (!fromInit) _refreshCoverPreview();
    }

    if (fromInit) {
      apply();
      _initialSeekTarget = clip.startTime;
      _initialSeekPending = clip.startTime > Duration.zero;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _refreshCoverPreview();
        setState(() {});
        _scrollToClip(clip.id);
      });
      return;
    }
    setState(apply);
    unawaited(_seekTo(clip.startTime));
    _scrollToClip(clip.id);
    _snack('Now editing "${clip.name}"');
  }

  Future<bool> _confirmDiscard(String action) async {
    if (!_isDirty) return true;
    final colors = context.appColors;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content: Text('You have unsaved changes. $action will discard them.'),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: colors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _requestStartEditing(VideoClip clip) async {
    if (clip.id == _originalEditingClip?.id) return;
    if (!await _confirmDiscard('Switching clips')) return;
    if (!mounted) return;
    _startEditing(clip);
  }

  Future<void> _requestNewClip() async {
    if (!await _confirmDiscard('Starting a new clip')) return;
    if (!mounted) return;
    _resetFormToBlank();
    unawaited(_seekTo(Duration.zero));
  }

  Future<void> _requestClose() async {
    if (await _confirmDiscard('Leaving the editor')) {
      _cleanupTempCover();
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _scrollToClip(String clipId) {
    final clips = context
        .read<AppState>()
        .clips
        .where((c) => c.videoPath == widget.video.path)
        .toList();
    final index = clips.indexWhere((c) => c.id == clipId);
    if (index != -1 && _itemScrollController.isAttached) {
      _itemScrollController.scrollTo(
        index: index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _snack(String message, {Color? color, Duration? duration}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          duration: duration ?? const Duration(seconds: 3),
        ),
      );
  }

  /// Reverts every edit to the clip as it was loaded.
  void _resetFormChanges() {
    final original = _originalEditingClip;
    if (original == null) {
      _cleanupTempCover();
      setState(() {
        _blankBaseline = _blankBaseline.copyWith(); // keep id
        _formClip = _blankBaseline;
        _tempThumbnailPath = null;
        _setControllerTexts(_blankBaseline);
        _refreshCoverPreview();
      });
      _snack('Changes discarded.');
      return;
    }
    _cleanupTempCover();
    setState(() {
      _formClip = original.copyWith();
      _tempThumbnailPath = null;
      _setControllerTexts(original);
      _refreshCoverPreview();
      _coverPreviewTimestamp = DateTime.now().millisecondsSinceEpoch;
    });
    _snack('Changes discarded.');
  }

  // ---------------------------------------------------------------------
  // IN / OUT editing. Every path goes through ClipRangeRules.
  // ---------------------------------------------------------------------

  String? _validateIn(Duration candidate) {
    final edit = ClipRangeRules.trySetStart(
      candidate,
      start: _formClip.startTime,
      end: _formClip.endTime,
      source: _sourceDuration,
    );
    return edit.error == null
        ? null
        : ClipRangeRules.message(edit.error!, sourceDuration: _sourceDuration);
  }

  String? _validateOut(Duration candidate) {
    final edit = ClipRangeRules.trySetEnd(
      candidate,
      start: _formClip.startTime,
      end: _formClip.endTime,
      source: _sourceDuration,
    );
    return edit.error == null
        ? null
        : ClipRangeRules.message(edit.error!, sourceDuration: _sourceDuration);
  }

  void _applyIn(Duration time, {bool seek = true}) {
    final edit = ClipRangeRules.trySetStart(
      time,
      start: _formClip.startTime,
      end: _formClip.endTime,
      source: _sourceDuration,
    );
    if (edit.error != null) {
      _snack(
        ClipRangeRules.message(edit.error!, sourceDuration: _sourceDuration),
        color: context.appColors.danger,
      );
      return;
    }
    setState(() => _formClip = _formClip.copyWith(startTime: edit.start));
    if (seek) unawaited(_seekTo(edit.start));
  }

  void _applyOut(Duration time, {bool seek = true}) {
    final edit = ClipRangeRules.trySetEnd(
      time,
      start: _formClip.startTime,
      end: _formClip.endTime,
      source: _sourceDuration,
    );
    if (edit.error != null) {
      _snack(
        ClipRangeRules.message(edit.error!, sourceDuration: _sourceDuration),
        color: context.appColors.danger,
      );
      return;
    }
    setState(() => _formClip = _formClip.copyWith(endTime: edit.end));
    if (seek) unawaited(_seekTo(edit.end));
  }

  void _setInFromPlayer() {
    if (!_playerReady) return;
    _applyIn(_position.value, seek: false);
  }

  void _setOutFromPlayer() {
    if (!_playerReady) return;
    _applyOut(_position.value, seek: false);
  }

  void _onRangeDragged(Duration start, Duration end) {
    setState(
      () => _formClip = _formClip.copyWith(startTime: start, endTime: end),
    );
  }

  // ---------------------------------------------------------------------
  // AI captioning, cover, save, delete (behaviour unchanged from Stage 2)
  // ---------------------------------------------------------------------

  Future<void> _generateAiCaption(AppState appState) async {
    final startMs = _formClip.startTime.inMilliseconds;
    final endMs = _formClip.endTime.inMilliseconds;
    if (endMs <= startMs) {
      _snack('片段起止时间无效，请先调整区间');
      return;
    }

    setState(() => _isGeneratingAiCaption = true);
    _snack(
      '正在抽帧并由 Qwen2-VL 进行智能解构，请稍候...',
      duration: const Duration(seconds: 4),
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
      final separators = RegExp(r'[,，、;；。!！?？]');
      for (final tag in caption.keyActions) {
        final clean = tag.trim();
        if (clean.isNotEmpty &&
            clean.length <= 10 &&
            !clean.contains(separators)) {
          currentTags.add(clean);
        }
      }
      if (caption.scene.isNotEmpty &&
          caption.scene.length <= 6 &&
          !caption.scene.contains(separators)) {
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
      _snack(
        'AI 解构成功！已自动填充剧情描述与推荐标签',
        color: context.appColors.success.withValues(alpha: 0.9),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('AI 解构失败: $e'),
          backgroundColor: context.appColors.danger,
          duration: const Duration(seconds: 8),
          action: SnackBarAction(label: '配置引擎', onPressed: _openAiSettings),
        ),
      );
    } finally {
      if (mounted) setState(() => _isGeneratingAiCaption = false);
    }
  }

  void _openAiSettings() {
    showDialog<void>(
      context: context,
      builder: (context) => const AiSettingsDialog(),
    );
  }

  Future<void> _generateCoverAtTime(Duration time) async {
    if (_isSettingCover) return;
    final thumbnailService = context.read<ThumbnailService>();
    final dbPath = context.read<AppState>().currentDbFullPath;
    if (dbPath == null) {
      _snack(
        'Cannot generate cover: Database path not found.',
        color: context.appColors.danger,
      );
      return;
    }
    setState(() => _isSettingCover = true);
    try {
      final fileName = await thumbnailService.generateTempThumbnail(
        widget.video.path,
        time,
        _formClip.id,
        dbPath: dbPath,
      );
      if (!mounted) return;
      if (fileName != null) {
        final fullPath = thumbnailService.buildThumbnailPath(dbPath, fileName);
        FileImage(File(fullPath)).evict();
        if (_coverPreviewFullPath != null) {
          FileImage(File(_coverPreviewFullPath!)).evict();
        }
        setState(() {
          _formClip = _formClip.copyWith(coverFrameTime: time);
          _tempThumbnailPath = fileName;
          _coverPreviewFullPath = fullPath;
          _coverPreviewTimestamp = DateTime.now().millisecondsSinceEpoch;
        });
        _snack(
          'Cover set at ${formatTimecode(time)} (applied when you save)',
          duration: const Duration(seconds: 2),
        );
      } else {
        _snack(
          'Could not capture a cover frame at ${formatTimecode(time)}.',
          color: context.appColors.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _isSettingCover = false);
    }
  }

  void _setCoverFromPlayer() {
    if (!_playerReady) return;
    unawaited(_generateCoverAtTime(_position.value));
  }

  void _resetCoverToIn() {
    final inPoint = _formClip.startTime;
    setState(() => _formClip = _formClip.copyWith(coverFrameTime: inPoint));
    unawaited(_generateCoverAtTime(inPoint));
  }

  bool get _canSave {
    if (_isSaving) return false;
    return _originalEditingClip == null || _isDirty;
  }

  Future<void> _saveOrUpdateClip() async {
    if (_isSaving) return;
    final composed = _composed;
    final problem = validateClipForSave(
      composed,
      original: _originalEditingClip,
      source: _sourceDuration,
    );
    if (problem != null) {
      _snack('Save failed: $problem', color: context.appColors.danger);
      return;
    }
    if (_originalEditingClip != null && !_isDirty) return;

    final appState = context.read<AppState>();
    final dbPath = appState.currentDbFullPath;
    if (dbPath == null) {
      _snack(
        'Save failed: Database path not found.',
        color: context.appColors.danger,
      );
      return;
    }
    final thumbnailService = context.read<ThumbnailService>();
    setState(() {
      _isSaving = true;
      _formClip = composed;
    });

    try {
      var clip = composed;
      String? finalThumbnailPath = _tempThumbnailPath;

      if (finalThumbnailPath != null) {
        final tempPath = thumbnailService.buildThumbnailPath(
          dbPath,
          finalThumbnailPath,
        );
        final finalFileName = thumbnailService.getThumbnailFileName(clip.id);
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
        final needsThumbUpdate =
            clip.thumbnailPath == null ||
            (_originalEditingClip != null &&
                clip.coverFrameTime != _originalEditingClip!.coverFrameTime);
        if (needsThumbUpdate) {
          final coverTime = clip.coverFrameTime == Duration.zero
              ? clip.startTime
              : clip.coverFrameTime;
          finalThumbnailPath = await thumbnailService.generateThumbnail(
            widget.video.path,
            coverTime,
            clip.id,
            dbPath: dbPath,
          );
        }
      }
      if (finalThumbnailPath != null) {
        clip = clip.copyWith(thumbnailPath: finalThumbnailPath);
      }

      final wasNew = _originalEditingClip == null;
      if (wasNew) {
        await appState.addClip(clip);
      } else {
        await appState.updateClip(clip);
      }

      // Background frame-pool sync; never blocks or fails the save.
      unawaited(
        appState.deltaEngine
            .syncClipRange(
              videoPathOrUrl: widget.video.path,
              startMs: clip.startTime.inMilliseconds,
              endMs: clip.endTime.inMilliseconds,
              modelDir: 'models',
            )
            .catchError((Object err) {
              debugPrint(
                '[ClipEditorScreen] Background delta sync error: $err',
              );
              return <VideoFrameEmbeddingRecord>[];
            }),
      );

      if (!mounted) return;
      thumbnailService.cleanupTempThumbnails(dbPath, clip.id);
      _clipsListTimestamp = DateTime.now().millisecondsSinceEpoch;
      setState(() {
        _tempThumbnailPath = null;
        _formClip = clip;
        if (!wasNew) {
          _originalEditingClip = clip;
          _blankBaseline = clip;
          _refreshCoverPreview();
          _coverPreviewTimestamp = _clipsListTimestamp;
        }
      });
      _snack(
        'Clip "${clip.name}" saved',
        color: context.appColors.success.withValues(alpha: 0.9),
      );
      if (wasNew) _resetFormToBlank();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _deleteClip(VideoClip clip) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete clip?'),
        content: Text(
          'Delete "${clip.name}"? The source video is not touched, but this '
          'clip and its settings will be removed.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: context.appColors.danger,
            ),
            child: const Text('Delete'),
            onPressed: () {
              if (_originalEditingClip?.id == clip.id) {
                _resetFormToBlank();
              }
              context.read<AppState>().deleteClip(clip.id);
              Navigator.of(ctx).pop();
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Keyboard
  // ---------------------------------------------------------------------

  void _onEditorCommand(ClipEditorCommand command, Duration? step) {
    switch (command) {
      case ClipEditorCommand.togglePlay:
        unawaited(_togglePlay());
      case ClipEditorCommand.setIn:
        _setInFromPlayer();
      case ClipEditorCommand.setOut:
        _setOutFromPlayer();
      case ClipEditorCommand.seekBack:
        _nudgeSeek(-(step ?? NudgeStep.normal));
      case ClipEditorCommand.seekForward:
        _nudgeSeek(step ?? NudgeStep.normal);
      case ClipEditorCommand.toggleMute:
        _toggleMute();
      case ClipEditorCommand.setCover:
        _setCoverFromPlayer();
      case ClipEditorCommand.toggleHints:
        setState(() => _showHints = !_showHints);
    }
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final colors = context.appColors;

    // Keep the baseline in sync with the stored clip, or drop out of edit
    // mode when the clip was deleted elsewhere.
    final editing = _originalEditingClip;
    if (editing != null) {
      VideoClip? latest;
      for (final c in appState.clips) {
        if (c.id == editing.id) {
          latest = c;
          break;
        }
      }
      if (latest == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _originalEditingClip?.id == editing.id) {
            _resetFormToBlank();
          }
        });
      } else if (latest != editing) {
        _originalEditingClip = latest;
      }
    }

    final isEditing = _originalEditingClip != null;
    final dirty = _isDirty;
    final saveShortcut = Platform.isMacOS
        ? const SingleActivator(LogicalKeyboardKey.keyS, meta: true)
        : const SingleActivator(LogicalKeyboardKey.keyS, control: true);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _wideBreakpoint;
        return PopScope(
          canPop: !dirty,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) unawaited(_requestClose());
          },
          child: Shortcuts(
            shortcuts: <ShortcutActivator, Intent>{
              saveShortcut: const SaveIntent(),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
                SaveIntent: CallbackAction<SaveIntent>(
                  onInvoke: (_) {
                    if (_canSave) unawaited(_saveOrUpdateClip());
                    return null;
                  },
                ),
              },
              child: ClipEditorKeyHandler(
                focusNode: _keyFocusNode,
                onCommand: _onEditorCommand,
                child: Scaffold(
                  key: _scaffoldKey,
                  backgroundColor: colors.background,
                  appBar: _buildTopBar(isEditing, dirty, wide),
                  endDrawer: wide
                      ? null
                      : Drawer(
                          width: 400,
                          backgroundColor: colors.sidebar,
                          child: SafeArea(child: _buildSidePanel(appState)),
                        ),
                  body: wide
                      ? MultiSplitViewTheme(
                          data: MultiSplitViewThemeData(
                            dividerThickness: 8,
                            dividerPainter: DividerPainters.background(
                              color: colors.background,
                              highlightedColor: colors.primary.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                          child: MultiSplitView(
                            controller: _splitViewController,
                            builder: (context, area) => area.data == 'editor'
                                ? _buildEditorColumn(wide)
                                : Padding(
                                    padding: const EdgeInsets.only(
                                      top: 8,
                                      right: 8,
                                      bottom: 8,
                                    ),
                                    child: _panelShell(
                                      _buildSidePanel(appState),
                                    ),
                                  ),
                          ),
                        )
                      : _buildEditorColumn(wide),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildTopBar(bool isEditing, bool dirty, bool wide) {
    final colors = context.appColors;
    final name = _nameController.text.trim();
    final title = isEditing
        ? (name.isEmpty ? _originalEditingClip!.name : name)
        : (name.isEmpty ? 'New clip' : name);
    final canDiscard = dirty;
    return AppBar(
      toolbarHeight: 60,
      backgroundColor: colors.sidebar,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: false,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: 'Back',
        onPressed: () => unawaited(_requestClose()),
      ),
      titleSpacing: 0,
      title: Row(
        children: [
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.sectionTitle.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  widget.video.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _StatusPill(
            label: isEditing ? 'Editing' : 'New',
            color: isEditing ? colors.info : colors.success,
          ),
          if (dirty) ...[
            const SizedBox(width: 6),
            _StatusPill(label: 'Unsaved', color: colors.warning),
          ],
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(
            _showHints ? Icons.keyboard : Icons.keyboard_outlined,
            color: _showHints ? colors.primary : null,
          ),
          tooltip: 'Keyboard shortcuts (F1)',
          onPressed: () => setState(() => _showHints = !_showHints),
        ),
        if (!wide)
          IconButton(
            icon: const Icon(Icons.view_sidebar_outlined),
            tooltip: 'Properties and clips',
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
        const SizedBox(width: 4),
        TextButton.icon(
          icon: const Icon(Icons.add_circle_outline, size: 18),
          label: const Text('New'),
          onPressed: () => unawaited(_requestNewClip()),
        ),
        TextButton.icon(
          icon: const Icon(Icons.undo, size: 18),
          label: const Text('Discard'),
          onPressed: canDiscard ? _resetFormChanges : null,
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'Save (Ctrl+S)',
          child: FilledButton.icon(
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(isEditing ? Icons.check : Icons.save_outlined, size: 18),
            label: Text(isEditing ? 'Update clip' : 'Save clip'),
            onPressed: _canSave ? () => unawaited(_saveOrUpdateClip()) : null,
          ),
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _panelShell(Widget child) {
    final colors = context.appColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.sidebar,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _buildSidePanel(AppState appState) {
    final colors = context.appColors;
    final clips = appState.clips
        .where((c) => c.videoPath == widget.video.path)
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                const ButtonSegment(
                  value: 0,
                  icon: Icon(Icons.tune, size: 16),
                  label: Text('Properties'),
                ),
                ButtonSegment(
                  value: 1,
                  icon: const Icon(Icons.video_library_outlined, size: 16),
                  label: Text('Clips (${clips.length})'),
                ),
              ],
              selected: {_sideTab},
              onSelectionChanged: (s) {
                setState(() => _sideTab = s.first);
                if (_sideTab == 1 && _originalEditingClip != null) {
                  final id = _originalEditingClip!.id;
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _scrollToClip(id),
                  );
                }
              },
            ),
          ),
        ),
        Divider(height: 1, color: colors.borderSubtle),
        Expanded(
          child: _sideTab == 0
              ? ClipPropertiesPanel(
                  clip: _formClip,
                  allTags: appState.allTags,
                  nameController: _nameController,
                  notesController: _notesController,
                  tagController: _newTagController,
                  tagFocusNode: _tagFocusNode,
                  onChanged: (clip) => setState(() => _formClip = clip),
                  isGeneratingAi: _isGeneratingAiCaption,
                  onGenerateAi: () => unawaited(_generateAiCaption(appState)),
                  onOpenAiSettings: _openAiSettings,
                  coverPreviewPath: _coverPreviewFullPath,
                  coverPreviewStamp: _coverPreviewTimestamp,
                  isSettingCover: _isSettingCover,
                  onSetCover: _setCoverFromPlayer,
                  onResetCover: _resetCoverToIn,
                )
              : ClipListPanel(
                  clips: clips,
                  dbPath: appState.currentDbFullPath,
                  thumbnailService: context.read<ThumbnailService>(),
                  selectedId: _originalEditingClip?.id,
                  listStamp: _clipsListTimestamp,
                  scrollController: _itemScrollController,
                  onSelect: (c) => unawaited(_requestStartEditing(c)),
                  onPlay: (c) =>
                      unawaited(_previewClip(c.startTime, c.endTime)),
                  onDelete: _deleteClip,
                ),
        ),
      ],
    );
  }

  Widget _buildEditorColumn(bool wide) {
    return KeyboardClaimRegion(
      focusNode: _keyFocusNode,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 8, wide ? 0 : 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _buildVideoStage()),
            const SizedBox(height: 8),
            _buildTransport(),
            const SizedBox(height: 4),
            _buildTimelinePanel(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Video stage, transport, timeline
  // ---------------------------------------------------------------------

  Widget _buildVideoStage() {
    final colors = context.appColors;
    Widget? overlay;
    if (_fileMissing) {
      overlay = _StageMessage(
        icon: Icons.error_outline,
        color: colors.danger,
        title: 'Video file not found',
        detail: widget.video.path,
      );
    } else if (_loadError != null) {
      overlay = _StageMessage(
        icon: Icons.error_outline,
        color: colors.danger,
        title: 'Could not load this video',
        detail: _loadError!,
      );
    } else if (_loadTimedOut) {
      overlay = _StageMessage(
        icon: Icons.hourglass_empty,
        color: colors.warning,
        title: 'Loading is taking longer than expected',
        detail: 'The file may be on a slow drive or in an unsupported format.',
      );
    } else if (_sourceDuration == Duration.zero) {
      overlay = const Center(child: CircularProgressIndicator());
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // BoxFit.contain keeps landscape and portrait sources uncropped.
            Video(
              controller: controller,
              controls: NoVideoControls,
              fit: BoxFit.contain,
              fill: Colors.black,
            ),
            if (overlay != null) overlay,
            Positioned(
              left: 12,
              bottom: 12,
              child: IgnorePointer(
                child: ValueListenableBuilder<Duration>(
                  valueListenable: _position,
                  builder: (context, pos, _) => _TimeBadge(
                    text:
                        '${formatTimecode(pos)} / ${formatTimecode(_sourceDuration)}',
                  ),
                ),
              ),
            ),
            if (_showHints)
              Positioned(
                top: 12,
                right: 12,
                child: _ShortcutHints(
                  onClose: () {
                    setState(() => _showHints = false);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransport() {
    final colors = context.appColors;
    final ready = _playerReady && !_fileMissing;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            StreamBuilder<bool>(
              stream: player.stream.playing,
              initialData: player.state.playing,
              builder: (context, snap) {
                final playing = snap.data ?? false;
                return IconButton.filled(
                  tooltip: playing ? 'Pause (Space)' : 'Play (Space)',
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  onPressed: ready ? () => unawaited(_togglePlay()) : null,
                );
              },
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Back 1 s (Shift+Left)',
              icon: const Icon(Icons.replay),
              onPressed: ready ? () => _nudgeSeek(-NudgeStep.coarse) : null,
            ),
            IconButton(
              tooltip: 'Back 100 ms (Left)',
              icon: const Icon(Icons.chevron_left),
              onPressed: ready ? () => _nudgeSeek(-NudgeStep.normal) : null,
            ),
            IconButton(
              tooltip: 'Forward 100 ms (Right)',
              icon: const Icon(Icons.chevron_right),
              onPressed: ready ? () => _nudgeSeek(NudgeStep.normal) : null,
            ),
            IconButton(
              tooltip: 'Forward 1 s (Shift+Right)',
              icon: const Icon(Icons.forward_10),
              onPressed: ready ? () => _nudgeSeek(NudgeStep.coarse) : null,
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Go to IN',
              icon: const Icon(Icons.first_page),
              onPressed: ready
                  ? () => unawaited(_seekTo(_formClip.startTime))
                  : null,
            ),
            IconButton(
              tooltip: 'Go to OUT',
              icon: const Icon(Icons.last_page),
              onPressed: ready
                  ? () => unawaited(_seekTo(_formClip.endTime))
                  : null,
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.slideshow, size: 18),
              label: const Text('Preview clip'),
              onPressed: ready
                  ? () => unawaited(
                      _previewClip(_formClip.startTime, _formClip.endTime),
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: _isMuted ? 'Unmute (S)' : 'Mute (S)',
              icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up),
              onPressed: _toggleMute,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelinePanel() {
    final colors = context.appColors;
    final ready = _sourceDuration > Duration.zero && !_fileMissing;
    final start = _formClip.startTime;
    final end = _formClip.endTime;
    final length = end > start ? end - start : Duration.zero;
    final rangeProblem = ready
        ? ClipRangeRules.validate(start, end, _sourceDuration)
        : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TimecodeField(
                label: 'IN',
                value: start,
                enabled: ready,
                accent: colors.success,
                validator: _validateIn,
                onCommitted: (t) => _applyIn(t),
              ),
              IconButton(
                tooltip: 'Set IN to playhead (I)',
                icon: const Icon(Icons.login, size: 18),
                onPressed: ready ? _setInFromPlayer : null,
              ),
              TimecodeField(
                label: 'OUT',
                value: end,
                enabled: ready,
                accent: colors.danger,
                validator: _validateOut,
                onCommitted: (t) => _applyOut(t),
              ),
              IconButton(
                tooltip: 'Set OUT to playhead (O)',
                icon: const Icon(Icons.logout, size: 18),
                onPressed: ready ? _setOutFromPlayer : null,
              ),
              _DurationChip(
                label: 'Length',
                value: formatTimecode(length),
                invalid: rangeProblem != null,
              ),
              ValueListenableBuilder<Duration>(
                valueListenable: _position,
                builder: (context, pos, _) {
                  // Clip-relative progress, distinct from the absolute time.
                  final inside = pos >= start && pos <= end;
                  return _DurationChip(
                    label: 'In clip',
                    value: inside ? formatTimecode(pos - start) : '--',
                  );
                },
              ),
              if (rangeProblem != null)
                Text(
                  ClipRangeRules.message(
                    rangeProblem,
                    sourceDuration: _sourceDuration,
                  ),
                  style: TextStyle(color: colors.danger, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (ready)
            ClipRangeTimeline(
              source: _sourceDuration,
              start: start,
              end: end,
              cover: _formClip.coverFrameTime,
              position: _position,
              onSeek: (t) => unawaited(_seekTo(t)),
              onRangeChanged: _onRangeDragged,
              onRequestSetStart: (t) => _applyIn(t, seek: false),
              onRequestSetEnd: (t) => _applyOut(t, seek: false),
              onRequestSetCover: (t) => unawaited(_generateCoverAtTime(t)),
              onScrubChanged: (v) => _scrubbing = v,
              previewLookup: (t) =>
                  PreviewService().getNearestKeyframe(widget.video.path, t),
            )
          else
            const SizedBox(height: 76),
        ],
      ),
    );
  }
}

class _StageMessage extends StatelessWidget {
  const _StageMessage({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 12),
            Text(title, style: AppTypography.sectionTitle),
            const SizedBox(height: 4),
            Text(
              detail,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTypography.caption,
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeBadge extends StatelessWidget {
  const _TimeBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: AppTypography.timecode(
          fontSize: 12,
          color: context.appColors.textPrimary,
        ),
      ),
    );
  }
}

class _DurationChip extends StatelessWidget {
  const _DurationChip({
    required this.label,
    required this.value,
    this.invalid = false,
  });

  final String label;
  final String value;
  final bool invalid;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final color = invalid ? colors.danger : colors.textPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: AppTypography.caption),
          const SizedBox(width: 8),
          Text(
            value,
            style: AppTypography.timecode(fontSize: 13, color: color),
          ),
        ],
      ),
    );
  }
}

class _ShortcutHints extends StatelessWidget {
  const _ShortcutHints({required this.onClose});

  final VoidCallback onClose;

  static const _rows = <(String, String)>[
    ('Space', 'Play / pause'),
    ('I  or  1', 'Set IN at playhead'),
    ('O  or  2', 'Set OUT at playhead'),
    ('Left / Right', 'Seek 100 ms'),
    ('Shift + Left / Right', 'Seek 1 s'),
    ('Ctrl + Left / Right', 'Seek 10 ms'),
    ('S', 'Mute'),
    ('C', 'Capture cover'),
    ('Ctrl + S', 'Save clip'),
    ('F1', 'Toggle this panel'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: 280,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceElevated.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Keyboard shortcuts',
                  style: AppTypography.sectionTitle,
                ),
              ),
              IconButton(
                tooltip: 'Close',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
                onPressed: onClose,
              ),
            ],
          ),
          for (final row in _rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(
                      row.$1,
                      style: AppTypography.timecode(
                        fontSize: 12,
                        color: colors.primary,
                      ),
                    ),
                  ),
                  Expanded(child: Text(row.$2, style: AppTypography.caption)),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Text(
            'Single-key shortcuts are disabled while typing in a field.',
            style: AppTypography.caption.copyWith(fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
