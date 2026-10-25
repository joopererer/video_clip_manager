import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../data/app_state.dart';

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
  bool _isTesting = false;
  bool _isDownloadingModel = false;
  String? _downloadProgress;
  bool _localModelsReady = false;
  String? _localModelPath;
  String? _testResult;
  bool _testSuccess = false;

  final Map<String, Map<String, String>> _presets = {
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
    'custom': {
      'name': '自定义 (OpenAI 兼容协议)',
      'url': '',
      'model': '',
      'key': '',
    },
  };

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _selectedMode = appState.vlmMode;
    _apiUrlController = TextEditingController(text: appState.vlmApiUrl);
    _apiKeyController = TextEditingController(text: appState.vlmApiKey);
    _modelController = TextEditingController(text: appState.vlmModel);
    _checkLocalModelStatus();
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

  Future<void> _downloadBuiltInModel() async {
    setState(() {
      _isDownloadingModel = true;
      _downloadProgress = '正在启动下载脚本，从国内高速镜像拉取模型文件...';
    });

    try {
      final scriptCandidates = [
        r'D:\workspace\local-media-ai\scripts\fetch_qwen2vl_models.ps1',
        r'D:\workspace\FlutterProjects\video_clip_manager\scripts\fetch_qwen2vl_models.ps1',
        r'scripts\fetch_qwen2vl_models.ps1',
      ];
      String? scriptPath;
      for (final s in scriptCandidates) {
        if (File(s).existsSync()) {
          scriptPath = s;
          break;
        }
      }

      if (scriptPath == null) {
        throw Exception('未找到下载脚本 scripts/fetch_qwen2vl_models.ps1');
      }

      final proc = await Process.start(
        'powershell',
        [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          scriptPath,
          '-Mirror',
          'https://hf-mirror.com',
        ],
      );

      proc.stdout.transform(const SystemEncoding().decoder).listen((data) {
        if (mounted) {
          setState(() {
            _downloadProgress = data.trim();
          });
        }
      });

      final exitCode = await proc.exitCode;
      if (exitCode == 0) {
        await _checkLocalModelStatus();
        if (mounted) {
          setState(() {
            _downloadProgress = '模型下载完成并通过哈希校验！本地已就绪。';
          });
        }
      } else {
        throw Exception('下载退出代码: $exitCode');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadProgress = '下载异常: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloadingModel = false);
      }
    }
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  void _onModeChanged(String mode) {
    setState(() {
      _selectedMode = mode;
      final preset = _presets[mode];
      if (preset != null && mode != 'custom') {
        _apiUrlController.text = preset['url'] ?? '';
        _modelController.text = preset['model'] ?? '';
      }
      _testResult = null;
    });
  }

  Future<void> _testConnection() async {
    final url = _apiUrlController.text.trim();
    final key = _apiKeyController.text.trim();
    final model = _modelController.text.trim();

    if (url.isEmpty || model.isEmpty) {
      setState(() {
        _testResult = '请先填写完整的 API 地址与模型名称';
        _testSuccess = false;
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    try {
      final appState = context.read<AppState>();
      if ((url.contains('localhost:11434') || url.contains('127.0.0.1:11434')) &&
          !(await appState.aiService.isServerHealthy(url))) {
        setState(() => _testResult = '正在检测并启动内置 llama.cpp 推理守护服务...');
        await appState.aiService.ensureBuiltInLlamaServerRunning(port: '11434');
      }

      final endpoint = url.endsWith('/')
          ? '${url}chat/completions'
          : '$url/chat/completions';

      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (key.isNotEmpty) {
        headers['Authorization'] = 'Bearer $key';
      }

      final body = jsonEncode({
        'model': model,
        'messages': [
          {
            'role': 'user',
            'content': 'ping',
          }
        ],
        'max_tokens': 5,
      });

      final stopwatch = Stopwatch()..start();
      final response = await http
          .post(Uri.parse(endpoint), headers: headers, body: body)
          .timeout(const Duration(seconds: 10));
      stopwatch.stop();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        setState(() {
          _testSuccess = true;
          _testResult =
              '连接成功！耗时 ${stopwatch.elapsedMilliseconds}ms，服务响应正常。';
        });
      } else {
        setState(() {
          _testSuccess = false;
          _testResult =
              '连接失败 (HTTP ${response.statusCode}): ${response.body.takePrefix(120)}';
        });
      }
    } catch (e) {
      setState(() {
        _testSuccess = false;
        _testResult = '连接异常: $e';
      });
    } finally {
      setState(() => _isTesting = false);
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
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('AI 多模态推理配置已保存'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.auto_awesome, color: Colors.purple.shade700),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI 视觉大模型 (VLM) 引擎配置',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '驱动视频片段剧情浓缩、场景解析与动作自动打标',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '服务模式 / 预设模板',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: _selectedMode,
                            items: _presets.entries.map((e) {
                              return DropdownMenuItem<String>(
                                value: e.key,
                                child: Text(e.value['name'] ?? e.key),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) _onModeChanged(val);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_selectedMode == 'ollama') ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: _localModelsReady ? Colors.green.shade50 : Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _localModelsReady ? Colors.green.shade200 : Colors.blue.shade200,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    _localModelsReady ? Icons.check_circle : Icons.download_for_offline,
                                    color: _localModelsReady ? Colors.green.shade700 : Colors.blue.shade700,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _localModelsReady
                                        ? '本地内置模型已就绪 (免装 Ollama，支持 Vulkan GPU 加速)'
                                        : '本地内置模型尚未下载 (约 2.2GB)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: _localModelsReady ? Colors.green.shade900 : Colors.blue.shade900,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _localModelsReady
                                    ? '路径: $_localModelPath'
                                    : '使用与 EmbeddingGemma 2 相同的机制，一键从国内镜像拉取 Qwen2-VL 模型：',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _localModelsReady ? Colors.green.shade800 : Colors.blue.shade800,
                                ),
                              ),
                              if (!_localModelsReady) ...[
                                const SizedBox(height: 8),
                                if (_downloadProgress != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8.0),
                                    child: Text(
                                      _downloadProgress!,
                                      style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                                    ),
                                  ),
                                FilledButton.tonalIcon(
                                  icon: _isDownloadingModel
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.download, size: 16),
                                  label: Text(_isDownloadingModel ? '正在高速下载并校验...' : '一键下载本地 Qwen2-VL 模型 (国内镜像)'),
                                  onPressed: _isDownloadingModel ? null : _downloadBuiltInModel,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      TextField(
                        controller: _apiUrlController,
                        decoration: const InputDecoration(
                          labelText: 'API Base URL',
                          hintText: '如 http://localhost:11434/v1',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.link),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _modelController,
                        decoration: const InputDecoration(
                          labelText: '模型名称 (Model)',
                          hintText: '如 qwen2-vl:2b 或 qwen-vl-max',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.memory),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _apiKeyController,
                        obscureText: _obscureApiKey,
                        decoration: InputDecoration(
                          labelText: 'API Key (本地 Ollama/LM Studio 可留空)',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.key),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureApiKey ? Icons.visibility : Icons.visibility_off,
                            ),
                            onPressed: () =>
                                setState(() => _obscureApiKey = !_obscureApiKey),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_testResult != null)
                        Container(
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: _testSuccess
                                ? Colors.green.shade50
                                : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _testSuccess
                                  ? Colors.green.shade300
                                  : Colors.red.shade300,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _testSuccess ? Icons.check_circle : Icons.error,
                                color: _testSuccess ? Colors.green : Colors.red,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _testResult!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _testSuccess
                                        ? Colors.green.shade900
                                        : Colors.red.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            icon: _isTesting
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.network_check, size: 16),
                            label: Text(_isTesting ? '正在探测...' : '测试连接'),
                            onPressed: _isTesting ? null : _testConnection,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _save,
                    child: const Text('保存配置'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on String {
  String takePrefix(int len) {
    if (length <= len) return this;
    return '${substring(0, len)}...';
  }
}
