import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 诊断信息
class AiDoctorInfo {
  final bool cliFound;
  final String cliPath;
  final bool ffmpegFound;
  final String ffmpegPath;

  const AiDoctorInfo({
    required this.cliFound,
    required this.cliPath,
    required this.ffmpegFound,
    required this.ffmpegPath,
  });

  bool get isReady => cliFound && ffmpegFound;

  @override
  String toString() =>
      'AiDoctorInfo(cliFound: $cliFound, ffmpegFound: $ffmpegFound, cliPath: $cliPath)';
}

/// 抽取的片段单帧
class ExtractedClipFrame {
  final int tMs;
  final String path;
  final int sizeBytes;

  const ExtractedClipFrame({
    required this.tMs,
    required this.path,
    required this.sizeBytes,
  });

  factory ExtractedClipFrame.fromJson(Map<String, dynamic> json) {
    return ExtractedClipFrame(
      tMs: json['t_ms'] as int? ?? 0,
      path: json['path'] as String? ?? '',
      sizeBytes: json['size_bytes'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    't_ms': tMs,
    'path': path,
    'size_bytes': sizeBytes,
  };
}

/// VLM 结构化视频描述
class ClipCaptionInfo {
  final String scene;
  final String mainSubject;
  final List<String> keyActions;
  final String summary;
  final String searchDocument;

  const ClipCaptionInfo({
    required this.scene,
    required this.mainSubject,
    required this.keyActions,
    required this.summary,
    required this.searchDocument,
  });

  factory ClipCaptionInfo.fromJson(Map<String, dynamic> json) {
    return ClipCaptionInfo(
      scene: json['scene'] as String? ?? '',
      mainSubject: json['main_subject'] as String? ?? '',
      keyActions: (json['key_actions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      summary: json['summary'] as String? ?? '',
      searchDocument: json['search_document'] as String? ?? '',
    );
  }
}

/// AI Sidecar 服务层（桥接 local-media-ai 独立子进程）
class AiService {
  static final AiService _instance = AiService._internal();
  factory AiService() => _instance;
  AiService._internal();

  String? _cachedCliPath;

  /// 解析 local-media-ai 可执行文件路径
  Future<String?> resolveCliPath() async {
    if (_cachedCliPath != null && await File(_cachedCliPath!).exists()) {
      return _cachedCliPath;
    }

    // 探测候选路径（工作区本地构建路径 / 环境变量 / 系统 PATH）
    final candidates = [
      r'D:\workspace\local-media-ai\target\debug\local-media-ai.exe',
      r'D:\workspace\local-media-ai\target\release\local-media-ai.exe',
      p.join(Directory.current.path, 'local-media-ai.exe'),
      p.join(Directory.current.path, 'bin', 'local-media-ai.exe'),
    ];

    for (final c in candidates) {
      if (await File(c).exists()) {
        _cachedCliPath = c;
        return c;
      }
    }

    _cachedCliPath = 'local-media-ai';
    return _cachedCliPath;
  }

  /// 检查底层运行环境
  Future<AiDoctorInfo> checkDoctor({String? customFfmpeg}) async {
    final cli = await resolveCliPath();
    final args = ['doctor'];
    if (customFfmpeg != null && customFfmpeg.isNotEmpty) {
      args.addAll(['--ffmpeg', customFfmpeg]);
    }

    try {
      final res = await Process.run(cli ?? 'local-media-ai', args);
      if (res.exitCode == 0) {
        final json = jsonDecode(res.stdout as String) as Map<String, dynamic>;
        if (json['ok'] == true && json['data'] != null) {
          final data = json['data'] as Map<String, dynamic>;
          return AiDoctorInfo(
            cliFound: true,
            cliPath: cli ?? 'local-media-ai',
            ffmpegFound: data['ffmpeg_found'] as bool? ?? false,
            ffmpegPath: data['ffmpeg_path'] as String? ?? '',
          );
        }
      }
    } catch (e) {
      debugPrint('[AiService] checkDoctor failed: $e');
    }

    return AiDoctorInfo(
      cliFound: false,
      cliPath: cli ?? 'not found',
      ffmpegFound: false,
      ffmpegPath: '',
    );
  }

  /// 抽取视频片段区间帧
  Future<List<ExtractedClipFrame>> extractClipFrames({
    required String videoPathOrUrl,
    required int startMs,
    required int endMs,
    String strategy = 'interval',
    int everyMs = 2000,
    double threshold = 0.4,
    int maxFrames = 12,
    int maxEdge = 768,
    String? customOutDir,
  }) async {
    final cli = await resolveCliPath();
    final tempDir = customOutDir ??
        p.join((await getTemporaryDirectory()).path,
            'clip_frames_${DateTime.now().millisecondsSinceEpoch}');
    await Directory(tempDir).create(recursive: true);

    final args = [
      'extract-clip',
      '--video',
      videoPathOrUrl,
      '--start-ms',
      startMs.toString(),
      '--end-ms',
      endMs.toString(),
      '--strategy',
      strategy,
      '--every-ms',
      everyMs.toString(),
      '--threshold',
      threshold.toString(),
      '--out-dir',
      tempDir,
      '--max-frames',
      maxFrames.toString(),
      '--max-edge',
      maxEdge.toString(),
    ];

    final res = await Process.run(cli ?? 'local-media-ai', args);
    if (res.exitCode != 0) {
      throw Exception('抽取视频帧失败: ${res.stderr}');
    }

    final json = jsonDecode(res.stdout as String) as Map<String, dynamic>;
    if (json['ok'] != true || json['data'] == null) {
      throw Exception('抽帧结果解析失败: ${json['error']}');
    }

    final data = json['data'] as Map<String, dynamic>;
    final rawFrames = (data['frames'] as List<dynamic>?) ?? [];
    return rawFrames
        .map((f) => ExtractedClipFrame.fromJson(f as Map<String, dynamic>))
        .toList();
  }

  /// 文本向量提取 (768 维)
  Future<List<double>> embedText({
    required String text,
    String prefix = '',
    required String modelDir,
    String? ortLib,
  }) async {
    final cli = await resolveCliPath();
    final args = [
      'embed-text',
      '--text',
      text,
      '--prefix',
      prefix,
      '--model-dir',
      modelDir,
    ];
    if (ortLib != null && ortLib.isNotEmpty) {
      args.addAll(['--ort-lib', ortLib]);
    }

    final res = await Process.run(cli ?? 'local-media-ai', args);
    if (res.exitCode != 0) {
      throw Exception('文本向量生成失败: ${res.stderr}');
    }

    final json = jsonDecode(res.stdout as String) as Map<String, dynamic>;
    if (json['ok'] != true || json['data'] == null) {
      throw Exception('向量结果解析失败: ${json['error']}');
    }

    final data = json['data'] as Map<String, dynamic>;
    final rawVec = (data['vector'] as List<dynamic>?) ?? [];
    return rawVec.map((v) => (v as num).toDouble()).toList();
  }

  /// 批量视频帧向量提取
  Future<List<Map<String, dynamic>>> embedFrames({
    required List<ExtractedClipFrame> frames,
    required String modelDir,
    String? ortLib,
    int softTokens = 140,
  }) async {
    if (frames.isEmpty) return [];
    final cli = await resolveCliPath();
    final framesPayload = jsonEncode(frames.map((f) => f.toJson()).toList());

    final args = [
      'embed-frames',
      '--frames-json',
      framesPayload,
      '--model-dir',
      modelDir,
      '--soft-tokens',
      softTokens.toString(),
    ];
    if (ortLib != null && ortLib.isNotEmpty) {
      args.addAll(['--ort-lib', ortLib]);
    }

    final res = await Process.run(cli ?? 'local-media-ai', args);
    if (res.exitCode != 0) {
      throw Exception('批量帧向量生成失败: ${res.stderr}');
    }

    final json = jsonDecode(res.stdout as String) as Map<String, dynamic>;
    if (json['ok'] != true || json['data'] == null) {
      throw Exception('帧向量结果解析失败: ${json['error']}');
    }

    final data = json['data'] as Map<String, dynamic>;
    return (data['embeddings'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>()
            .toList() ??
        [];
  }

  /// VLM 结构化视频故事描述生成
    Future<ClipCaptionInfo> generateCaption({
    List<String>? framePaths,
    List<ExtractedClipFrame>? frames,
    String? instruction,
    String? mockResponse,
    String? apiUrl,
    String? apiKey,
    String? model,
  }) async {
    final paths = framePaths ?? frames?.map((f) => f.path).toList() ?? [];
    if (paths.isEmpty) {
      throw ArgumentError('At least one framePath or frame must be provided.');
    }

    // 优先处理显式 mock 响应（便于单元测试）
    if (mockResponse != null && mockResponse.isNotEmpty) {
      return parseCaptionFromRaw(mockResponse);
    }

    // 1. 若配置了 API 端点（Ollama / LM Studio / DashScope / OpenAI 兼容）
    if (apiUrl != null && apiUrl.trim().isNotEmpty) {
      final trimmedUrl = apiUrl.trim();
      if ((trimmedUrl.contains('localhost:11434') || trimmedUrl.contains('127.0.0.1:11434')) &&
          !(await isServerHealthy(trimmedUrl))) {
        await ensureBuiltInLlamaServerRunning(port: '11434');
      }
      return _generateCaptionViaApi(
        paths: paths,
        apiUrl: apiUrl.trim(),
        apiKey: apiKey?.trim(),
        model: (model != null && model.trim().isNotEmpty) ? model.trim() : 'qwen2-vl:2b',
        instruction: instruction,
      );
    }

    // 2. 否则通过本地 Sidecar CLI 进程执行
    final cli = await resolveCliPath();
    final args = [
      'caption',
      '--frames',
      paths.join(','),
    ];
    if (instruction != null && instruction.isNotEmpty) {
      args.addAll(['--instruction', instruction]);
    }

    final res = await Process.run(cli ?? 'local-media-ai', args);
    if (res.exitCode != 0) {
      throw Exception('VLM 解构失败: ${res.stderr}');
    }

    final json = jsonDecode(res.stdout as String) as Map<String, dynamic>;
    if (json['ok'] != true || json['data'] == null) {
      throw Exception('VLM 解构失败: ${json['error']}');
    }

    final data = json['data'] as Map<String, dynamic>;
    return ClipCaptionInfo.fromJson(data);
  }

  /// 通过 OpenAI 兼容多模态接口（Ollama/LM Studio/DashScope/SiliconFlow 等）执行 VLM 推理
  Future<ClipCaptionInfo> _generateCaptionViaApi({
    required List<String> paths,
    required String apiUrl,
    String? apiKey,
    required String model,
    String? instruction,
  }) async {
    final endpoint = apiUrl.endsWith('/')
        ? '${apiUrl}chat/completions'
        : '$apiUrl/chat/completions';

    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (apiKey != null && apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiKey';
    }

    final promptText = instruction ??
        '你是一位资深视频镜头与剧情分析专家。'
        '请按时间先后顺序仔细观察输入的一组视频连续关键帧画面，'
        '提炼该视频片段的核心事件、环境场景、主要主体与关键动作序列。\n'
        '【关键要求】：必须严格且仅输出标准纯 JSON 格式（不要使用任何外部 Markdown 标记），Schema 结构必须包含以下字段：\n'
        '{\n'
        '  "scene": "简短精准的场景环境描述，如：雨夜城市街道、海滩日落、办公室会议室",\n'
        '  "main_subject": "画面的核心主角/主体，如：红色跑车、冲浪运动员、演讲者",\n'
        '  "key_actions": ["动作1", "动作2", "动作3"],\n'
        '  "summary": "一段生动连贯的自然语言剧情概要，详细描述整个片段发生了什么故事"\n'
        '}';

    final contentItems = <Map<String, dynamic>>[
      {
        'type': 'text',
        'text': promptText,
      }
    ];

    for (final path in paths) {
      final file = File(path);
      if (file.existsSync()) {
        final bytes = await file.readAsBytes();
        final base64Str = base64Encode(bytes);
        final ext = p.extension(path).toLowerCase();
        final mime = ext == '.png' ? 'image/png' : 'image/jpeg';
        contentItems.add({
          'type': 'image_url',
          'image_url': {
            'url': 'data:$mime;base64,$base64Str',
          },
        });
      }
    }

    final payload = {
      'model': model,
      'messages': [
        {
          'role': 'user',
          'content': contentItems,
        }
      ],
      'temperature': 0.2,
      'max_tokens': 1024,
    };

    final res = await http
        .post(
          Uri.parse(endpoint),
          headers: headers,
          body: jsonEncode(payload),
        )
        .timeout(
          const Duration(seconds: 60),
          onTimeout: () => throw Exception('连接 VLM 服务超时 (60s)，请检查服务运行状态'),
        );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('VLM 服务请求失败 (HTTP ${res.statusCode}): ${utf8.decode(res.bodyBytes, allowMalformed: true)}');
    }

    final respJson = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final choices = respJson['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw Exception('VLM 服务未返回有效选择结果: ${res.body}');
    }

    final message = choices.first['message'] as Map<String, dynamic>?;
    final rawText = message?['content'] as String? ?? '';

    return parseCaptionFromRaw(rawText);
  }

  /// 鲁棒 JSON 解析器，自动剥离 Markdown 代码块并容错
  ClipCaptionInfo parseCaptionFromRaw(String rawText) {
    String clean = rawText.trim();
    if (clean.contains('```')) {
      final match = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```').firstMatch(clean);
      if (match != null) {
        clean = match.group(1)?.trim() ?? clean;
      }
    }

    try {
      final map = jsonDecode(clean) as Map<String, dynamic>;
      final scene = map['scene']?.toString() ?? '视频场景';
      final mainSubject = map['main_subject']?.toString() ?? '主体';
      final rawActions = (map['key_actions'] as List<dynamic>?) ?? [];
      final keyActions = rawActions.map((a) => a.toString()).toList();
      final summary = map['summary']?.toString() ?? clean;

      final searchDoc = 'Scene: $scene\nMain Subject: $mainSubject\nActions: ${keyActions.join(", ")}\nSummary: $summary';

      return ClipCaptionInfo(
        scene: scene,
        mainSubject: mainSubject,
        keyActions: keyActions,
        summary: summary,
        searchDocument: searchDoc,
      );
    } catch (_) {
      return ClipCaptionInfo(
        scene: '视频片段',
        mainSubject: '主体',
        keyActions: const ['动作'],
        summary: rawText,
        searchDocument: rawText,
      );
    }
  }

  Process? _localServerProcess;
  Process? get localServerProcess => _localServerProcess;

  /// 停止内置服务进程
  void stopBuiltInServer() {
    _localServerProcess?.kill();
    _localServerProcess = null;
  }

  /// 检测本地 llama-server.exe 执行程序
  Future<String?> resolveLlamaServerExe() async {
    final candidates = [
      r'D:\workspace\local-media-ai\runtime\llama\llama-server.exe',
      r'D:\workspace\FlutterProjects\video_clip_manager\runtime\llama\llama-server.exe',
      r'runtime\llama\llama-server.exe',
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  /// 检测本地 Qwen2-VL GGUF 权重文件
  Future<Map<String, String>?> resolveLocalQwenModels() async {
    final searchDirs = [
      r'D:\workspace\local-media-ai\runtime\models\qwen2-vl',
      r'D:\workspace\FlutterProjects\video_clip_manager\runtime\models\qwen2-vl',
      r'runtime\models\qwen2-vl',
    ];

    for (final dir in searchDirs) {
      final modelFile = File(p.join(dir, 'Qwen2-VL-2B-Instruct-Q4_K_M.gguf'));
      final mmprojFile = File(p.join(dir, 'mmproj-Qwen2-VL-2B-Instruct-f16.gguf'));
      if (modelFile.existsSync() && mmprojFile.existsSync()) {
        return {
          'model': modelFile.path,
          'mmproj': mmprojFile.path,
        };
      }
    }
    return null;
  }

  /// 检测指定 URL 的服务是否存活
  Future<bool> isServerHealthy(String baseUrl) async {
    try {
      final healthUri = Uri.parse(
        baseUrl.endsWith('/') ? '${baseUrl}health' : '$baseUrl/health',
      );
      final res = await http.get(healthUri).timeout(const Duration(milliseconds: 1200));
      if (res.statusCode >= 200 && res.statusCode < 400) return true;
    } catch (_) {}

    try {
      final modelsUri = Uri.parse(
        baseUrl.endsWith('/') ? '${baseUrl}models' : '$baseUrl/models',
      );
      final res = await http.get(modelsUri).timeout(const Duration(milliseconds: 1200));
      if (res.statusCode >= 200 && res.statusCode < 400) return true;
    } catch (_) {}

    return false;
  }

  /// 启动内置的 llama-server 守护进程
  Future<bool> ensureBuiltInLlamaServerRunning({String port = '11434'}) async {
    final baseUrl = 'http://127.0.0.1:$port';
    if (await isServerHealthy(baseUrl)) return true;

    final exe = await resolveLlamaServerExe();
    final models = await resolveLocalQwenModels();

    if (exe == null || models == null) {
      return false;
    }

    try {
      debugPrint('[AiService] Spawning built-in llama-server on port $port...');
      _localServerProcess = await Process.start(
        exe,
        [
          '-m', models['model']!,
          '--mmproj', models['mmproj']!,
          '--port', port,
          '-ngl', '99',
          '--ctx-size', '4096',
        ],
        mode: ProcessStartMode.detached,
      );

      // 轮询等待服务就绪
      for (int i = 0; i < 15; i++) {
        await Future.delayed(const Duration(milliseconds: 800));
        if (await isServerHealthy(baseUrl)) {
          debugPrint('[AiService] Built-in llama-server is ready!');
          return true;
        }
      }
    } catch (e) {
      debugPrint('[AiService] Failed to start built-in llama-server: $e');
    }
    return false;
  }

}
