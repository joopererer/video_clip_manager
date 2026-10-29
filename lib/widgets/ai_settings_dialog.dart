import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../services/ai_model_downloader.dart';
import '../services/ai_model_manifest.dart';
import '../services/ai_model_verifier.dart';
import '../services/vlm_connection_probe.dart';
import '../theme/app_colors.dart';

/// 连接测试的状态：检测中使用蓝色（信息），而不是错误色。
enum _TestState { idle, running, success, failure }

class AiSettingsDialog extends StatefulWidget {
  const AiSettingsDialog({super.key});

  @override
  State<AiSettingsDialog> createState() => _AiSettingsDialogState();
}

class _AiSettingsDialogState extends State<AiSettingsDialog> {
  late String _selectedMode;
  late final TextEditingController _apiUrlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelController;

  bool _obscureApiKey = true;
  _TestState _testState = _TestState.idle;
  String? _testMessage;

  /// Model ids reported by the service's `GET /models`, shown as choices.
  List<String> _serverModels = const [];

  bool _isDownloadingModel = false;
  String? _downloadProgress;
  bool _localModelsReady = false;
  String? _localModelPath;

  bool _embeddingModelReady = false;
  String? _embeddingModelPath;
  bool _isDownloadingEmbeddingModel = false;
  String? _embeddingDownloadProgress;
  double? _embeddingDownloadFraction;
  bool _cancelEmbeddingDownload = false;
  bool _modelDirBusy = false;

  /// Cheap (size-only) state of the model folder, refreshed after each action.
  ModelVerification? _embeddingInspection;

  /// Result of the last download/verify attempt, shown with full details.
  ModelInstallResult? _lastInstall;
  bool _showInstallDetails = false;

  static const Map<String, Map<String, String>> _presets = {
    'ollama': {
      'name': 'Ollama (本地离线推荐)',
      'url': 'http://localhost:11434/v1',
      'model': 'qwen2-vl:2b',
      'key': '',
    },
    'lm_studio': {
      'name': 'LM Studio (本地离线)',
      'url': 'http://localhost:1234/v1',
      'model': 'qwen2-vl',
      'key': '',
    },
    'dashscope': {
      'name': '通义千问 DashScope (阿里云极速)',
      'url': 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      'model': 'qwen-vl-max',
      'key': '',
    },
    'siliconflow': {
      'name': '硅基流动 SiliconFlow',
      'url': 'https://api.siliconflow.cn/v1',
      'model': 'Qwen/Qwen2-VL-7B-Instruct',
      'key': '',
    },
    'custom': {'name': '自定义 (OpenAI 兼容协议)', 'url': '', 'model': '', 'key': ''},
  };

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _selectedMode = _presets.containsKey(appState.vlmMode)
        ? appState.vlmMode
        : 'custom';
    _apiUrlController = TextEditingController(text: appState.vlmApiUrl);
    _apiKeyController = TextEditingController(text: appState.vlmApiKey);
    _modelController = TextEditingController(text: appState.vlmModel);
    _checkLocalModelStatus();
    _checkEmbeddingModelStatus();
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _checkEmbeddingModelStatus() async {
    final appState = context.read<AppState>();
    final ai = appState.aiService;
    final dir = await ai.resolveEmbeddingModelDir();
    final inspection = await ai.inspectEmbeddingModel();
    if (mounted) {
      setState(() {
        _embeddingModelReady = dir != null;
        _embeddingModelPath = dir ?? inspection.dir;
        _embeddingInspection = inspection;
      });
    }
  }

  Future<void> _checkLocalModelStatus() async {
    final appState = context.read<AppState>();
    final models = await appState.aiService.resolveLocalQwenModels();
    if (mounted) {
      setState(() {
        _localModelsReady = models != null;
        _localModelPath = models?['model'];
      });
    }
  }

  Future<void> _chooseModelDir() async {
    final appState = context.read<AppState>();
    final ai = appState.aiService;
    if (_isDownloadingEmbeddingModel ||
        appState.isIndexingEmbeddings ||
        ai.isInstallingEmbeddingModel) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('模型正在下载、推理或构建特征，请完成后再切换目录')));
      return;
    }
    final picked = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择 EmbeddingGemma 模型目录',
    );
    if (picked == null || !mounted) return;

    // 验证存在性与读写权限
    final dir = Directory(picked);
    if (!await dir.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('目录不存在，请重新选择')));
      }
      return;
    }
    final probe = File(p.join(picked, '.vcm_write_test'));
    try {
      await probe.writeAsString('ok');
      await probe.delete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('目录不可写，请选择有写入权限的文件夹')));
      }
      return;
    }

    final current = _embeddingModelPath;
    if (current != null && p.equals(current, picked)) return;

    final hasExisting = current != null && Directory(current).existsSync();
    String choice = 'use';
    if (!mounted) return;
    if (hasExisting) {
      choice =
          await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('切换模型目录'),
              content: const Text(
                '检测到已有模型文件。请选择：\n'
                '• 仅使用新路径：不复制文件\n'
                '• 复制现有模型：将旧目录文件复制到新目录并校验\n'
                '• 取消：保持原目录',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop('cancel'),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop('use'),
                  child: const Text('仅使用新路径'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop('copy'),
                  child: const Text('复制现有模型'),
                ),
              ],
            ),
          ) ??
          'cancel';
      if (choice == 'cancel') return;
    }

    final oldDir = current;
    final copied = <String>[];
    setState(() => _modelDirBusy = true);
    try {
      if (choice == 'copy' && oldDir != null) {
        await _copyModelDir(oldDir, picked, created: copied);
        final v = await ModelVerifier().verify(picked, embeddingGemmaManifest);
        if (!v.isComplete) {
          throw StateError('copy verification failed');
        }
      }
      await appState.setAiModelDir(picked);
      await _checkEmbeddingModelStatus();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('模型目录已更新')));
      }
    } catch (e) {
      // 回滚已复制文件与配置，保留旧目录和目标目录中原有文件
      for (final path in copied.reversed) {
        try {
          final f = File(path);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      if (oldDir != null) await appState.setAiModelDir(oldDir);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('切换失败：$e，已保留旧目录')));
      }
    } finally {
      if (mounted) setState(() => _modelDirBusy = false);
    }
  }

  Future<void> _restoreDefaultModelDir() async {
    final appState = context.read<AppState>();
    if (_isDownloadingEmbeddingModel ||
        appState.isIndexingEmbeddings ||
        appState.aiService.isInstallingEmbeddingModel) {
      return;
    }
    await appState.setAiModelDir(null);
    await _checkEmbeddingModelStatus();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已恢复默认模型目录')));
    }
  }

  Future<void> _copyModelDir(
    String from,
    String to, {
    required List<String> created,
  }) async {
    final fromDir = Directory(from);
    final toDir = Directory(to);
    if (!await toDir.exists()) await toDir.create(recursive: true);
    await for (final entity in fromDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        final rel = p.relative(entity.path, from: from);
        final dest = File(p.join(to, rel));
        // Never overwrite a file that already exists in the target directory.
        if (await dest.exists()) {
          throw FileSystemException('目标目录已存在同名文件，拒绝覆盖', dest.path);
        }
        await dest.parent.create(recursive: true);
        await entity.copy(dest.path);
        created.add(dest.path);
      }
    }
  }

  /// 运行 PowerShell 下载脚本，实时回传输出；成功返回 true。
  Future<bool> _runDownloadScript({
    required List<String> candidates,
    required String scriptName,
    required List<String> extraArgs,
    required void Function(String) onOutput,
  }) async {
    String? scriptPath;
    for (final s in candidates) {
      if (File(s).existsSync()) {
        scriptPath = s;
        break;
      }
    }
    if (scriptPath == null) {
      throw Exception('未找到下载脚本 scripts/$scriptName');
    }

    final proc = await Process.start('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      scriptPath,
      ...extraArgs,
    ]);

    proc.stdout.transform(const SystemEncoding().decoder).listen((data) {
      if (mounted) onOutput(data.trim());
    });

    final exitCode = await proc.exitCode;
    if (exitCode != 0) throw Exception('下载退出代码: $exitCode');
    return true;
  }

  static String _mbText(int bytes) =>
      (bytes / (1024 * 1024)).toStringAsFixed(1);

  String _progressText(ModelProgress p) {
    final file = p.file != null ? ' ${p.file}' : '';
    switch (p.phase) {
      case ModelPhase.preparing:
        return '正在检查模型目录...';
      case ModelPhase.checking:
        return '正在校验已有文件 (sha256)$file';
      case ModelPhase.downloading:
        return '正在下载$file  ${_mbText(p.fileBytesDone)} / ${_mbText(p.fileBytesTotal)} MB'
            '  (总计 ${_mbText(p.overallBytesDone)} / ${_mbText(p.overallBytesTotal)} MB)';
      case ModelPhase.verifying:
        return '正在校验下载结果$file';
      case ModelPhase.finishing:
        return '正在收尾...';
    }
  }

  /// Verifies every file (sha256) and downloads only what is missing or wrong.
  /// Used for both "download" and "re-verify / update": valid files are left
  /// alone, so running it on a healthy install changes nothing.
  Future<void> _downloadEmbeddingModel() async {
    final ai = context.read<AppState>().aiService;
    setState(() {
      _isDownloadingEmbeddingModel = true;
      _cancelEmbeddingDownload = false;
      _embeddingDownloadFraction = null;
      _embeddingDownloadProgress = '正在检查模型目录...';
      _lastInstall = null;
    });
    ModelInstallResult? result;
    try {
      result = await ai.installEmbeddingModel(
        isCancelled: () => _cancelEmbeddingDownload,
        onProgress: (p) {
          if (!mounted) return;
          setState(() {
            _embeddingDownloadProgress = _progressText(p);
            _embeddingDownloadFraction = p.fraction;
          });
        },
      );
    } catch (e, st) {
      debugPrint('EmbeddingGemma install crashed: $e\n$st');
      if (mounted) {
        setState(
          () => _embeddingDownloadProgress =
              '下载过程出现内部错误：${redactSecrets(e.toString())}',
        );
      }
    }
    // The folder is the truth: re-read readiness from disk, never from the
    // outcome of the attempt.
    await _checkEmbeddingModelStatus();
    if (!mounted) return;
    setState(() {
      _isDownloadingEmbeddingModel = false;
      _embeddingDownloadFraction = null;
      if (result != null) {
        _lastInstall = result;
        if (result.succeeded) {
          _embeddingDownloadProgress = result.downloadedFiles.isEmpty
              ? '已校验：所有 ${result.skippedFiles.length} 个文件完整，无需下载。'
              : '已下载 ${result.downloadedFiles.length} 个文件并通过 sha256 校验，本地已就绪。';
        } else if (result.failure != null) {
          _embeddingDownloadProgress = null;
        }
      }
    });
  }

  Future<void> _copyInstallLog() async {
    final r = _lastInstall;
    if (r == null) return;
    final f = r.failure;
    final text = [
      if (f != null) ...[
        'kind: ${f.kind.name}',
        'message: ${f.message}',
        if (f.file != null) 'file: ${f.file}',
        if (f.targetPath != null) 'path: ${f.targetPath}',
        if (f.url != null) 'url: ${f.url}',
        if (f.httpStatus != null) 'http: ${f.httpStatus}',
        if (f.osErrorCode != null) 'os errno: ${f.osErrorCode}',
        if (f.technical != null) 'detail: ${f.technical}',
        '',
      ],
      r.logText,
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已复制错误详情 (已隐藏凭证)')));
    }
  }

  /// Failure box: what happened, which file, what to do, plus Retry/Details.
  Widget _buildInstallFailure(AppColorExtension colors) {
    final r = _lastInstall;
    final f = r?.failure;
    if (r == null || f == null) return const SizedBox.shrink();
    final cancelled = f.kind == ModelFailureKind.cancelled;
    final accent = cancelled ? colors.info : colors.danger;
    final stillReady = r.isReady;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            f.message,
            style: TextStyle(fontSize: 12, height: 1.4, color: accent),
          ),
          const SizedBox(height: 4),
          _caption(
            colors,
            stillReady
                ? '现有模型文件完整，仍可正常使用，未受影响。'
                : '现有的有效文件均已保留；重试只会补充缺失或损坏的部分。',
          ),
          if (f.file != null || f.targetPath != null) ...[
            const SizedBox(height: 4),
            SelectableText(
              [
                if (f.file != null) '文件: ${f.file}',
                if (f.targetPath != null) '路径: ${f.targetPath}',
              ].join('\n'),
              style: TextStyle(fontSize: 11, color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilledButton.tonalIcon(
                icon: const Icon(Icons.replay, size: 16),
                label: const Text('重试'),
                onPressed: _isDownloadingEmbeddingModel
                    ? null
                    : _downloadEmbeddingModel,
              ),
              TextButton.icon(
                icon: Icon(
                  _showInstallDetails ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                ),
                label: Text(_showInstallDetails ? '收起详情' : '错误详情'),
                onPressed: () =>
                    setState(() => _showInstallDetails = !_showInstallDetails),
              ),
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('复制'),
                onPressed: _copyInstallLog,
              ),
            ],
          ),
          if (_showInstallDetails)
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 160),
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.surfaceHighlight,
                borderRadius: BorderRadius.circular(6),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  [
                    if (f.technical != null) f.technical!,
                    r.logText,
                  ].join('\n\n'),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontFamily: 'Consolas',
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// One-line state of the model folder, derived from the size-only check.
  String _embeddingStateSummary() {
    final v = _embeddingInspection;
    if (_embeddingModelReady) {
      return '路径: $_embeddingModelPath\n所有 ${v?.reports.length ?? 0} 个文件齐全。'
          '点击“重新校验”可逐文件核对 sha256。\n已支持自然语言秒搜关键帧画面 (HIT 徽章)。';
    }
    if (v == null) return '正在检查...';
    if (!v.anyFilePresent && !v.hasUnreadable) {
      return '约 530MB。用于在搜索框用自然语言查找画面，并高亮最佳帧。\n将下载到: ${v.dir}';
    }
    return '模型不完整 (${v.problems.length}/${v.reports.length} 个文件有问题)，'
        '语义搜索不可用。点击“修复 / 补全下载”仅补充缺失或损坏的文件，已有的有效文件不会被改动。\n'
        '路径: ${v.dir}\n${v.describeProblems()}';
  }

  Future<void> _downloadBuiltInModel() async {
    setState(() {
      _isDownloadingModel = true;
      _downloadProgress = '正在启动下载脚本，从国内高速镜像拉取模型文件...';
    });
    try {
      await _runDownloadScript(
        candidates: const [
          r'D:\workspace\local-media-ai\scripts\fetch_qwen2vl_models.ps1',
          r'D:\workspace\FlutterProjects\video_clip_manager\scripts\fetch_qwen2vl_models.ps1',
          r'scripts\fetch_qwen2vl_models.ps1',
        ],
        scriptName: 'fetch_qwen2vl_models.ps1',
        extraArgs: const ['-Mirror', 'https://hf-mirror.com'],
        onOutput: (t) => setState(() => _downloadProgress = t),
      );
      await _checkLocalModelStatus();
      if (mounted) {
        setState(() => _downloadProgress = '下载完成并通过哈希校验，本地已就绪。');
      }
    } catch (e) {
      if (mounted) setState(() => _downloadProgress = '下载异常: $e');
    } finally {
      if (mounted) setState(() => _isDownloadingModel = false);
    }
  }

  void _onModeChanged(String mode) {
    setState(() {
      _selectedMode = mode;
      final preset = _presets[mode];
      if (preset != null && mode != 'custom') {
        _apiUrlController.text = preset['url'] ?? '';
        _modelController.text = preset['model'] ?? '';
      }
      _testState = _TestState.idle;
      _testMessage = null;
      _serverModels = const [];
    });
  }

  Future<void> _testConnection() async {
    final url = _apiUrlController.text.trim();
    final key = _apiKeyController.text.trim();
    final model = _modelController.text.trim();

    if (url.isEmpty || model.isEmpty) {
      setState(() {
        _testState = _TestState.failure;
        _testMessage = '请先填写完整的 API 地址与模型名称';
      });
      return;
    }

    setState(() {
      _testState = _TestState.running;
      _testMessage = '正在探测服务连通性...';
    });

    try {
      final appState = context.read<AppState>();
      if ((url.contains('localhost:11434') ||
              url.contains('127.0.0.1:11434')) &&
          !(await appState.aiService.isServerHealthy(url))) {
        if (mounted) {
          setState(() => _testMessage = '正在启动内置 llama.cpp 推理守护服务...');
        }
        await appState.aiService.ensureBuiltInLlamaServerRunning(port: '11434');
      }

      // Same two requests for every preset: GET /models, then the unchanged
      // minimal POST /chat/completions (Ollama request format is untouched).
      final result = await VlmConnectionProbe().probe(
        baseUrl: url,
        model: model,
        apiKey: key,
        isLmStudio: _selectedMode == 'lm_studio',
      );
      if (!mounted) return;

      setState(() {
        if (result.models.isNotEmpty) _serverModels = result.models;
        _testState = result.isOk ? _TestState.success : _TestState.failure;
        _testMessage = result.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testState = _TestState.failure;
        _testMessage = '连接异常: $e';
      });
    }
  }

  /// Lists the model ids the service reports. Needs only the address, so the
  /// user can pick a real id instead of typing one blind.
  Future<void> _fetchServerModels() async {
    final url = _apiUrlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _testState = _TestState.failure;
        _testMessage = '请先填写 API 地址';
      });
      return;
    }
    setState(() {
      _testState = _TestState.running;
      _testMessage = '正在获取服务模型列表...';
    });
    final result = await VlmConnectionProbe().listModels(
      baseUrl: url,
      apiKey: _apiKeyController.text.trim(),
      isLmStudio: _selectedMode == 'lm_studio',
    );
    if (!mounted) return;
    setState(() {
      _testState = result.isOk ? _TestState.success : _TestState.failure;
      _testMessage = result.message;
      _serverModels = result.models;
    });
  }

  Future<void> _save() async {
    final appState = context.read<AppState>();
    await appState.saveVlmConfig(
      mode: _selectedMode,
      apiUrl: _apiUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      model: _modelController.text.trim(),
    );
    if (mounted) {
      final colors = context.appColors;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: const Text('AI 多模态推理配置已保存'),
          backgroundColor: colors.success.withValues(alpha: 0.9),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final appState = context.watch<AppState>();
    final stats = appState.getEmbeddingStats();

    return Dialog(
      backgroundColor: colors.surface,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 640),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            final left = _buildLeftColumn(colors, appState, stats);
            final right = _buildRightColumn(colors);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(colors),
                Divider(height: 1, color: colors.borderSubtle),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: SingleChildScrollView(child: left),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: SingleChildScrollView(child: right),
                              ),
                            ],
                          )
                        : SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                right,
                                const SizedBox(height: 16),
                                left,
                              ],
                            ),
                          ),
                  ),
                ),
                Divider(height: 1, color: colors.borderSubtle),
                _buildFooter(colors),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(AppColorExtension colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.auto_awesome, color: colors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI 视觉大模型 (VLM) 引擎配置',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '驱动视频片段剧情浓缩、场景解析与动作自动打标',
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '关闭',
            icon: Icon(Icons.close, color: colors.textSecondary),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(AppColorExtension colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: _save, child: const Text('保存配置')),
        ],
      ),
    );
  }

  // ---- 通用小部件 ----

  Widget _section({
    required AppColorExtension colors,
    required IconData icon,
    required Color accent,
    required String title,
    Widget? trailing,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceElevated.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _caption(AppColorExtension colors, String text, {Color? color}) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11.5,
        height: 1.4,
        color: color ?? colors.textSecondary,
      ),
    );
  }

  Widget _spinner() => const SizedBox(
    width: 14,
    height: 14,
    child: CircularProgressIndicator(strokeWidth: 2),
  );

  InputDecoration _fieldDecoration(
    AppColorExtension colors, {
    required String label,
    String? hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: true,
      prefixIcon: Icon(icon, size: 18),
      suffixIcon: suffix,
    );
  }

  // ---- 左列：语义检索模型 + 向量库 ----

  Widget _buildLeftColumn(
    AppColorExtension colors,
    AppState appState,
    Map<String, int> stats,
  ) {
    final indexed = stats['indexed'] ?? 0;
    final total = stats['total'] ?? 0;
    final allIndexed = total > 0 && indexed == total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(
          colors: colors,
          icon: _embeddingModelReady
              ? Icons.check_circle_outline
              : Icons.download_for_offline_outlined,
          accent: _embeddingModelReady ? colors.success : colors.warning,
          title: '语义检索模型 (EmbeddingGemma 2)',
          trailing: _pill(
            _embeddingModelReady ? '已就绪' : '未下载',
            _embeddingModelReady ? colors.success : colors.warning,
          ),
          children: [
            _caption(colors, _embeddingStateSummary()),
            if (_isDownloadingEmbeddingModel) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _embeddingDownloadFraction,
                backgroundColor: colors.surfaceHighlight,
                color: colors.primary,
                minHeight: 4,
                borderRadius: BorderRadius.circular(2),
              ),
            ],
            if (_embeddingDownloadProgress != null) ...[
              const SizedBox(height: 6),
              _caption(colors, _embeddingDownloadProgress!, color: colors.info),
            ],
            _buildInstallFailure(colors),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilledButton.tonalIcon(
                  icon: _isDownloadingEmbeddingModel
                      ? _spinner()
                      : Icon(
                          _embeddingModelReady ? Icons.refresh : Icons.download,
                          size: 16,
                        ),
                  label: Text(
                    _isDownloadingEmbeddingModel
                        ? '正在下载并校验...'
                        : _embeddingModelReady
                        ? '重新校验'
                        : (_embeddingInspection?.anyFilePresent ?? false)
                        ? '修复 / 补全下载'
                        : '一键下载 (国内镜像)',
                  ),
                  onPressed: _isDownloadingEmbeddingModel
                      ? null
                      : _downloadEmbeddingModel,
                ),
                if (_isDownloadingEmbeddingModel)
                  TextButton(
                    onPressed: _cancelEmbeddingDownload
                        ? null
                        : () => setState(() => _cancelEmbeddingDownload = true),
                    child: Text(_cancelEmbeddingDownload ? '正在取消...' : '取消'),
                  ),
              ],
            ),
          ],
        ),
        _section(
          colors: colors,
          icon: Icons.folder_outlined,
          accent: colors.info,
          title: '模型目录 (仅应用内 EmbeddingGemma)',
          children: [
            _caption(
              colors,
              '此目录仅用于 Video Clip Manager 自身管理的 EmbeddingGemma 模型，'
              '不涉及 LM Studio/Ollama 外部服务管理的模型。',
            ),
            const SizedBox(height: 6),
            SelectableText(
              _embeddingModelPath ?? '(默认)',
              style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  icon: _modelDirBusy
                      ? _spinner()
                      : const Icon(Icons.folder_open, size: 16),
                  label: const Text('浏览'),
                  onPressed: _modelDirBusy ? null : _chooseModelDir,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.restore, size: 16),
                  label: const Text('恢复默认'),
                  onPressed: _modelDirBusy ? null : _restoreDefaultModelDir,
                ),
              ],
            ),
          ],
        ),
        _section(
          colors: colors,
          icon: Icons.view_array_rounded,
          accent: colors.primary,
          title: '片段特征向量库',
          trailing: _pill(
            '已索引 $indexed / $total',
            allIndexed ? colors.success : colors.info,
          ),
          children: [
            _caption(
              colors,
              '已缓存 ${stats['totalFrames'] ?? 0} 帧特征 (每 2 秒 1 帧，768 维)。\n'
              '• 保存/编辑片段时后台静默增量同步\n'
              '• 搜索时自动补全未索引片段',
            ),
            if (appState.isIndexingEmbeddings) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: appState.indexingProgress > 0
                    ? appState.indexingProgress
                    : null,
                backgroundColor: colors.surfaceHighlight,
                color: colors.primary,
                minHeight: 4,
                borderRadius: BorderRadius.circular(2),
              ),
              const SizedBox(height: 6),
              _caption(
                colors,
                appState.indexingStatus ?? '正在提取片段关键帧特征...',
                color: colors.info,
              ),
            ] else if (appState.indexingStatus != null) ...[
              const SizedBox(height: 6),
              _caption(colors, appState.indexingStatus!, color: colors.success),
            ],
            const SizedBox(height: 10),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                FilledButton.tonalIcon(
                  icon: appState.isIndexingEmbeddings
                      ? _spinner()
                      : const Icon(Icons.bolt, size: 16),
                  label: Text(
                    appState.isIndexingEmbeddings
                        ? '构建中 (${(appState.indexingProgress * 100).toInt()}%)'
                        : (allIndexed ? '重新扫描并增量同步' : '为所有片段构建特征'),
                  ),
                  onPressed:
                      appState.isIndexingEmbeddings || !_embeddingModelReady
                      ? null
                      : () async {
                          await appState.indexAllClips();
                        },
                ),
                if (!_embeddingModelReady)
                  Text(
                    '请先下载上方模型',
                    style: TextStyle(fontSize: 11, color: colors.warning),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // ---- 右列：VLM 服务配置 + 连接测试 ----

  Widget _buildRightColumn(AppColorExtension colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(
          colors: colors,
          icon: Icons.hub_outlined,
          accent: colors.primary,
          title: '推理服务',
          children: [
            DropdownButtonFormField<String>(
              initialValue: _selectedMode,
              isExpanded: true,
              isDense: true,
              dropdownColor: colors.surfaceElevated,
              decoration: _fieldDecoration(
                colors,
                label: '服务模式 / 预设模板',
                icon: Icons.dns_outlined,
              ),
              items: _presets.entries
                  .map(
                    (e) => DropdownMenuItem<String>(
                      value: e.key,
                      child: Text(
                        e.value['name'] ?? e.key,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) _onModeChanged(v);
              },
            ),
            if (_selectedMode == 'ollama') ...[
              const SizedBox(height: 12),
              _buildBuiltInModelHint(colors),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _apiUrlController,
              decoration: _fieldDecoration(
                colors,
                label: 'API Base URL',
                hint: '如 http://localhost:11434/v1',
                icon: Icons.link,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _modelController,
              decoration: _fieldDecoration(
                colors,
                label: '模型名称 (Model)',
                hint: '如 qwen2-vl:2b 或 qwen-vl-max',
                icon: Icons.memory,
              ),
            ),
            if (_serverModels.isNotEmpty) ...[
              const SizedBox(height: 8),
              _caption(colors, '服务返回的可用模型 (点击选用)：'),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final id in _serverModels)
                    ChoiceChip(
                      label: Text(id, style: const TextStyle(fontSize: 12)),
                      selected: _modelController.text.trim() == id,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) =>
                          setState(() => _modelController.text = id),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _apiKeyController,
              obscureText: _obscureApiKey,
              decoration: _fieldDecoration(
                colors,
                label: 'API Key (本地服务可留空)',
                icon: Icons.key,
                suffix: IconButton(
                  tooltip: _obscureApiKey ? '显示' : '隐藏',
                  icon: Icon(
                    _obscureApiKey ? Icons.visibility : Icons.visibility_off,
                    size: 18,
                  ),
                  onPressed: () =>
                      setState(() => _obscureApiKey = !_obscureApiKey),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildTestRow(colors),
          ],
        ),
      ],
    );
  }

  Widget _buildBuiltInModelHint(AppColorExtension colors) {
    final ready = _localModelsReady;
    final accent = ready ? colors.success : colors.info;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ready
                    ? Icons.check_circle_outline
                    : Icons.download_for_offline_outlined,
                size: 16,
                color: accent,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  ready
                      ? '内置 Qwen2-VL 已就绪 (免装 Ollama)'
                      : '内置 Qwen2-VL 未下载 (约 2.2GB)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (ready && _localModelPath != null) ...[
            const SizedBox(height: 4),
            _caption(colors, '路径: $_localModelPath'),
          ],
          if (_downloadProgress != null) ...[
            const SizedBox(height: 4),
            _caption(colors, _downloadProgress!, color: colors.info),
          ],
          if (!ready) ...[
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              icon: _isDownloadingModel
                  ? _spinner()
                  : const Icon(Icons.download, size: 16),
              label: Text(_isDownloadingModel ? '正在下载并校验...' : '一键下载 (国内镜像)'),
              onPressed: _isDownloadingModel ? null : _downloadBuiltInModel,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTestRow(AppColorExtension colors) {
    final running = _testState == _TestState.running;

    // 检测中: 蓝色 + 转圈; 成功: 绿色; 失败: 橙色(警示但不刺眼), 避免红色惊叹号误导
    late final Color tone;
    late final Widget leading;
    switch (_testState) {
      case _TestState.running:
        tone = colors.info;
        leading = SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: tone),
        );
      case _TestState.success:
        tone = colors.success;
        leading = Icon(Icons.check_circle, size: 18, color: tone);
      case _TestState.failure:
        tone = colors.warning;
        leading = Icon(Icons.warning_amber_rounded, size: 18, color: tone);
      case _TestState.idle:
        tone = colors.textSecondary;
        leading = const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              icon: running
                  ? _spinner()
                  : const Icon(Icons.network_check, size: 16),
              label: Text(running ? '正在探测...' : '测试连接'),
              onPressed: running ? null : _testConnection,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.list_alt, size: 16),
              label: const Text('获取服务模型列表'),
              onPressed: running ? null : _fetchServerModels,
            ),
          ],
        ),
        if (_testState != _TestState.idle && _testMessage != null) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: tone.withValues(alpha: 0.4)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                leading,
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    _testMessage!,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
