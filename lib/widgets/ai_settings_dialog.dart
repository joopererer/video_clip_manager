import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../data/app_state.dart';
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

  bool _isDownloadingModel = false;
  String? _downloadProgress;
  bool _localModelsReady = false;
  String? _localModelPath;

  bool _embeddingModelReady = false;
  String? _embeddingModelPath;
  bool _isDownloadingEmbeddingModel = false;
  String? _embeddingDownloadProgress;

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
    final dir = await appState.aiService.resolveEmbeddingModelDir();
    if (mounted) {
      setState(() {
        _embeddingModelReady = dir != null;
        _embeddingModelPath = dir;
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

  Future<void> _downloadEmbeddingModel() async {
    setState(() {
      _isDownloadingEmbeddingModel = true;
      _embeddingDownloadProgress = '正在启动下载脚本，从国内高速镜像拉取向量模型 (约 530MB)...';
    });
    try {
      await _runDownloadScript(
        candidates: const [
          r'scripts\fetch_embedding_models.ps1',
          r'D:\workspace\IdeaProjects\video_clip_manager\scripts\fetch_embedding_models.ps1',
          r'D:\workspace\FlutterProjects\video_clip_manager\scripts\fetch_embedding_models.ps1',
          r'D:\workspace\local-media-ai\scripts\fetch_embedding_models.ps1',
        ],
        scriptName: 'fetch_embedding_models.ps1',
        extraArgs: const [
          '-OutDir',
          'models',
          '-Mirror',
          'https://hf-mirror.com',
        ],
        onOutput: (t) => setState(() => _embeddingDownloadProgress = t),
      );
      await _checkEmbeddingModelStatus();
      if (mounted) {
        setState(() => _embeddingDownloadProgress = '下载完成并通过哈希校验，本地已就绪。');
      }
    } catch (e) {
      if (mounted) setState(() => _embeddingDownloadProgress = '下载异常: $e');
    } finally {
      if (mounted) setState(() => _isDownloadingEmbeddingModel = false);
    }
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

      final endpoint = url.endsWith('/')
          ? '${url}chat/completions'
          : '$url/chat/completions';

      final headers = <String, String>{'Content-Type': 'application/json'};
      if (key.isNotEmpty) headers['Authorization'] = 'Bearer $key';

      final body = jsonEncode({
        'model': model,
        'messages': [
          {'role': 'user', 'content': 'ping'},
        ],
        'max_tokens': 5,
      });

      final stopwatch = Stopwatch()..start();
      final response = await http
          .post(Uri.parse(endpoint), headers: headers, body: body)
          .timeout(const Duration(seconds: 10));
      stopwatch.stop();
      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        setState(() {
          _testState = _TestState.success;
          _testMessage = '连接成功，耗时 ${stopwatch.elapsedMilliseconds}ms';
        });
      } else {
        setState(() {
          _testState = _TestState.failure;
          _testMessage =
              '连接失败 (HTTP ${response.statusCode}): ${response.body.takePrefix(120)}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testState = _TestState.failure;
        _testMessage = '连接异常: $e';
      });
    }
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
            _caption(
              colors,
              _embeddingModelReady
                  ? '路径: $_embeddingModelPath\n已支持自然语言秒搜关键帧画面 (HIT 徽章)。'
                  : '约 530MB。用于在搜索框用自然语言查找画面，并高亮最佳帧。',
            ),
            if (_embeddingDownloadProgress != null) ...[
              const SizedBox(height: 6),
              _caption(colors, _embeddingDownloadProgress!, color: colors.info),
            ],
            const SizedBox(height: 10),
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
                    : (_embeddingModelReady ? '重新校验 / 更新' : '一键下载 (国内镜像)'),
              ),
              onPressed: _isDownloadingEmbeddingModel
                  ? null
                  : _downloadEmbeddingModel,
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
        OutlinedButton.icon(
          icon: running
              ? _spinner()
              : const Icon(Icons.network_check, size: 16),
          label: Text(running ? '正在探测...' : '测试连接'),
          onPressed: running ? null : _testConnection,
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

extension on String {
  String takePrefix(int len) {
    if (length <= len) return this;
    return '${substring(0, len)}...';
  }
}
