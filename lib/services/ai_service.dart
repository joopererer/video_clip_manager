import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'ai_model_downloader.dart';
import 'ai_model_manifest.dart';
import 'ai_model_verifier.dart';

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

  List<String> get tags => keyActions;

  const ClipCaptionInfo({
    required this.scene,
    required this.mainSubject,
    required this.keyActions,
    required this.summary,
    required this.searchDocument,
  });

  factory ClipCaptionInfo.fromJson(Map<String, dynamic> json) {
    final rawTags = json['tags'] ?? json['key_actions'] ?? json['actions'];
    final scene = json['scene'] as String? ?? '';
    final subject = (json['main_subject'] ?? json['subject']) as String? ?? '';
    final sanitized = AiService.sanitizeTags(
      rawTags,
      scene: scene,
      mainSubject: subject,
    );
    return ClipCaptionInfo(
      scene: scene,
      mainSubject: subject,
      keyActions: sanitized,
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
    final tempDir =
        customOutDir ??
        p.join(
          (await getTemporaryDirectory()).path,
          'clip_frames_${DateTime.now().millisecondsSinceEpoch}',
        );
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

  /// 自动探测并解析 ONNX Runtime 动态链接库路径 (Windows: onnxruntime.dll)
  Future<String?> resolveOrtLibPath() async {
    final candidates = [
      'onnxruntime.dll',
      'runtime/ort/onnxruntime.dll',
      r'D:\workspace\FlutterProjects\file_organizer\temp\ort_extracted\onnxruntime-win-x64-1.30.0\lib\onnxruntime.dll',
      r'D:\workspace\local-media-ai\target\release\onnxruntime.dll',
      r'D:\workspace\local-media-ai\runtime\ort\onnxruntime.dll',
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return File(c).absolute.path;
    }
    return null;
  }

  /// 文本向量提取 (768 维)
  Future<List<double>> embedText({
    required String text,
    String prefix = '',
    required String modelDir,
    String? ortLib,
  }) async {
    final cli = await resolveCliPath();
    var effectiveModelDir = modelDir;
    if (!File(p.join(effectiveModelDir, 'tokenizer.json')).existsSync()) {
      final autoDir = await resolveEmbeddingModelDir();
      if (autoDir != null) {
        effectiveModelDir = autoDir;
      }
    }

    final args = [
      'embed-text',
      '--text',
      text,
      '--prefix',
      prefix,
      '--model-dir',
      effectiveModelDir,
    ];
    final resolvedOrt = ortLib ?? await resolveOrtLibPath();
    if (resolvedOrt != null && resolvedOrt.isNotEmpty) {
      args.addAll(['--ort-lib', resolvedOrt]);
    }

    final res = await Process.run(cli ?? 'local-media-ai', args);
    if (res.exitCode != 0) {
      String errMsg = (res.stderr as String).trim();
      if (errMsg.isEmpty && (res.stdout as String).isNotEmpty) {
        try {
          final j = jsonDecode(res.stdout as String);
          errMsg = j['error'] ?? res.stdout;
        } catch (_) {
          errMsg = res.stdout;
        }
      }
      throw Exception('文本向量生成失败: $errMsg');
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
    var effectiveModelDir = modelDir;
    if (!File(p.join(effectiveModelDir, 'tokenizer.json')).existsSync()) {
      final autoDir = await resolveEmbeddingModelDir();
      if (autoDir != null) {
        effectiveModelDir = autoDir;
      }
    }

    final framesPayload = jsonEncode(frames.map((f) => f.toJson()).toList());

    final args = [
      'embed-frames',
      '--frames-json',
      framesPayload,
      '--model-dir',
      effectiveModelDir,
      '--soft-tokens',
      softTokens.toString(),
    ];
    final resolvedOrt = ortLib ?? await resolveOrtLibPath();
    if (resolvedOrt != null && resolvedOrt.isNotEmpty) {
      args.addAll(['--ort-lib', resolvedOrt]);
    }

    final res = await Process.run(cli ?? 'local-media-ai', args);
    if (res.exitCode != 0) {
      String errMsg = (res.stderr as String).trim();
      if (errMsg.isEmpty && (res.stdout as String).isNotEmpty) {
        try {
          final j = jsonDecode(res.stdout as String);
          errMsg = j['error'] ?? res.stdout;
        } catch (_) {
          errMsg = res.stdout;
        }
      }
      throw Exception('批量帧向量生成失败: $errMsg');
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
      if ((trimmedUrl.contains('localhost:11434') ||
              trimmedUrl.contains('127.0.0.1:11434')) &&
          !(await isServerHealthy(trimmedUrl))) {
        await ensureBuiltInLlamaServerRunning(port: '11434');
      }
      return _generateCaptionViaApi(
        paths: paths,
        apiUrl: apiUrl.trim(),
        apiKey: apiKey?.trim(),
        model: (model != null && model.trim().isNotEmpty)
            ? model.trim()
            : 'qwen2-vl:2b',
        instruction: instruction,
      );
    }

    // 2. 否则通过本地 Sidecar CLI 进程执行
    final cli = await resolveCliPath();
    final args = ['caption', '--frames', paths.join(',')];
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

    final headers = <String, String>{'Content-Type': 'application/json'};
    if (apiKey != null && apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiKey';
    }

    final promptText =
        instruction ??
        '你是一位资深视频镜头与媒体资产分析专家。'
            '请仔细观察按时间先后顺序排列的一组视频连续关键帧画面，提炼该视频片段的核心事件、环境场景、主要主体与专业分类标签。\n\n'
            '【关键输出要求】：\n'
            '1. 必须严格且仅输出标准纯 JSON 格式（不要使用 Markdown 代码块或外部额外文本）。\n'
            '2. Schema 结构必须包含以下字段：\n'
            '{\n'
            '  "scene": "精炼场景环境名词（不超过8个字，例如：雪山、雨夜街道、办公室）",\n'
            '  "main_subject": "画面的核心主角/主体（不超过6个字，例如：女人、跑车、金毛犬）",\n'
            '  "tags": ["标签1", "标签2", "标签3", "标签4", "标签5"],\n'
            '  "key_actions": ["动作动名词1", "动作动名词2"],\n'
            '  "summary": "一段生动连贯的自然语言剧情概要，详细描述整个片段发生了什么故事"\n'
            '}\n\n'
            '【标签规范（非常重要）】：\n'
            '- "tags" 是面向专业视频素材管理系统（如 Eagle、Adobe Premiere、素材库）的分类关键词列表（建议 5-10 个）。\n'
            '- 必须全部为【独立的原子关键词/名词/动名词】（2~4字为佳，如：女人、雪山、木棍、大雾、徒步、冬季、户外、远足）。\n'
            '- 严禁包含整句或短语！严禁出现标点符号（绝不允许出现逗号、顿号、分号，如“行走，手持木棍”是严重错误的）！\n'
            '- 请将动作与物体完全拆开为原子词，例如应输出 "徒步", "木棍"，而不是 "手持木棍行走"。';

    final contentItems = <Map<String, dynamic>>[
      {'type': 'text', 'text': promptText},
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
          'image_url': {'url': 'data:$mime;base64,$base64Str'},
        });
      }
    }

    final payload = {
      'model': model,
      'messages': [
        {'role': 'user', 'content': contentItems},
      ],
      'temperature': 0.2,
      'max_tokens': 1024,
    };

    final res = await http
        .post(Uri.parse(endpoint), headers: headers, body: jsonEncode(payload))
        .timeout(
          const Duration(seconds: 180),
          onTimeout: () => throw Exception(
            '连接 VLM 服务超时 (180s)。首次加载本地多模态大模型至显存可能需要较长时间，请稍后重试或检查服务状态',
          ),
        );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(
        'VLM 服务请求失败 (HTTP ${res.statusCode}): ${utf8.decode(res.bodyBytes, allowMalformed: true)}',
      );
    }

    final respJson =
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final choices = respJson['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw Exception('VLM 服务未返回有效选择结果: ${res.body}');
    }

    final message = choices.first['message'] as Map<String, dynamic>?;
    final rawText = message?['content'] as String? ?? '';

    return parseCaptionFromRaw(rawText);
  }

  /// 对模型输出的原始标签列表进行专业级媒体素材标签清洗与原子化：
  /// 1. 拆分被逗号、顿号、分号、斜杠、空格等粘连的复合短句（如“行走，手持木棍” -> “行走”, “木棍”）
  /// 2. 剥离无意义停用前缀词（如“一个”、“手持”、“手拿”、“身穿”、“在”）
  /// 3. 过滤纯标点、无意义单字及过长句子（保留 2~8 字符的标准原子关键词）
  /// 4. 融合主体名词与场景提炼词，去重并返回规范标签列表
  static List<String> sanitizeTags(
    dynamic rawTags, {
    String? scene,
    String? mainSubject,
  }) {
    final result = <String>{};

    void processCandidate(String raw) {
      if (raw.trim().isEmpty) return;
      // 1. 按常见中英文分隔符切分（逗号、顿号、分号、竖线、斜杠、空格、换行）
      final tokens = raw.split(RegExp(r'[,，、;；|/\\\s\n\r]+'));
      for (final token in tokens) {
        var clean = token
            .replaceAll(
              RegExp(r'^[^\w\u4e00-\u9fa5]+|[^\w\u4e00-\u9fa5]+$'),
              '',
            )
            .trim();
        if (clean.isEmpty) continue;

        // 剥离常见谓词/助词前缀，提取核心物体或动作名词
        // 例如："手持木棍" -> "木棍", "身穿蓝衣" -> "蓝衣", "一个女人" -> "女人"
        for (final prefix in [
          '一个',
          '一根',
          '一只',
          '一部',
          '一片',
          '手持',
          '手拿',
          '手提',
          '身穿',
          '佩戴',
          '背着',
          '站在',
          '走在',
          '正在',
          '在',
        ]) {
          if (clean.startsWith(prefix) && clean.length > prefix.length + 1) {
            clean = clean.substring(prefix.length).trim();
            break;
          }
        }

        // 剥离后缀助词
        for (final suffix in ['的', '中', '着', '了']) {
          if (clean.endsWith(suffix) && clean.length > suffix.length + 1) {
            clean = clean.substring(0, clean.length - suffix.length).trim();
            break;
          }
        }

        // 过滤长度不符合原子标签规范的项（通常原子标签长度在 2 到 8 个字之间）
        if (clean.length >= 2 && clean.length <= 8) {
          result.add(clean);
        }
      }
    }

    // 处理 rawTags（兼容 List 或逗号隔开的 String）
    if (rawTags is List) {
      for (final item in rawTags) {
        if (item != null) processCandidate(item.toString());
      }
    } else if (rawTags is String) {
      processCandidate(rawTags);
    }

    // 智能补充主体名词（若有效）
    if (mainSubject != null && mainSubject.trim().isNotEmpty) {
      processCandidate(mainSubject);
    }

    // 智能提取场景中的精炼名词（若场景很短 <= 6 字直接加入，若长则尝试提取环境高频词）
    if (scene != null && scene.trim().isNotEmpty) {
      final s = scene.trim();
      if (s.length >= 2 &&
          s.length <= 6 &&
          !s.contains(RegExp(r'[,，、。!！?？]'))) {
        processCandidate(s);
      } else {
        // 如果 scene 是一长串描述，提取其中可能出现的高频环境词
        for (final envKeyword in [
          '雪山',
          '海滩',
          '森林',
          '沙漠',
          '草原',
          '街道',
          '办公室',
          '会议室',
          '城市',
          '公路',
          '星空',
          '雾气',
          '大雾',
          '晴天',
          '雨夜',
          '室内',
          '户外',
          '山脉',
          '湖泊',
          '河流',
          '日落',
          '日出',
          '夜景',
        ]) {
          if (s.contains(envKeyword)) {
            result.add(envKeyword);
          }
        }
      }
    }

    return result.toList();
  }

  /// 鲁棒 JSON 解析器，自动剥离 Markdown 代码块并容错
  ClipCaptionInfo parseCaptionFromRaw(String rawText) {
    String clean = rawText.trim();
    if (clean.contains('```')) {
      final match = RegExp(
        r'```(?:json)?\s*([\s\S]*?)\s*```',
      ).firstMatch(clean);
      if (match != null) {
        clean = match.group(1)?.trim() ?? clean;
      }
    }

    try {
      final map = jsonDecode(clean) as Map<String, dynamic>;
      final scene = map['scene']?.toString() ?? '视频场景';
      final mainSubject =
          (map['main_subject'] ?? map['subject'])?.toString() ?? '主体';
      final rawTags = map['tags'] ?? map['key_actions'] ?? map['actions'] ?? [];
      final keyActions = sanitizeTags(
        rawTags,
        scene: scene,
        mainSubject: mainSubject,
      );
      final summary = map['summary']?.toString() ?? clean;

      final searchDoc =
          'Scene: $scene\nMain Subject: $mainSubject\nActions: ${keyActions.join(", ")}\nSummary: $summary';

      return ClipCaptionInfo(
        scene: scene,
        mainSubject: mainSubject,
        keyActions: keyActions,
        summary: summary,
        searchDocument: searchDoc,
      );
    } catch (_) {
      final keyActions = sanitizeTags(rawText);
      return ClipCaptionInfo(
        scene: '视频片段',
        mainSubject: '主体',
        keyActions: keyActions.isNotEmpty ? keyActions : const ['视频'],
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
      final mmprojFile = File(
        p.join(dir, 'mmproj-Qwen2-VL-2B-Instruct-f16.gguf'),
      );
      if (modelFile.existsSync() && mmprojFile.existsSync()) {
        return {'model': modelFile.path, 'mmproj': mmprojFile.path};
      }
    }
    return null;
  }

  /// Folders searched for the EmbeddingGemma 2 model, in priority order.
  /// Unchanged from earlier releases so existing installs keep working.
  /// Download, verification, loading and the settings page all read this
  /// list (or [embeddingInstallDir]); nothing else decides where the model is.
  List<String> embeddingModelCandidateDirs() => const [
    'models',
    r'models\embeddinggemma2',
    r'D:\workspace\IdeaProjects\video_clip_manager\models',
    r'D:\workspace\FlutterProjects\video_clip_manager\models',
    r'D:\workspace\local-media-ai\runtime\models',
  ];

  static const ModelVerifier _modelVerifier = ModelVerifier();

  /// True while [installEmbeddingModel] runs. Used to refuse actions that
  /// would pull files out from under it (for example changing the model dir).
  bool get isInstallingEmbeddingModel => _installingEmbeddingModel;
  bool _installingEmbeddingModel = false;

  /// 检测多模态语义检索 (EmbeddingGemma 2 ONNX) 模型是否就绪。
  ///
  /// A folder counts only when every file of the pinned manifest exists with
  /// the expected size. Earlier releases accepted a folder that merely had two
  /// files, which reported "ready" for half-finished downloads. The sha256
  /// check is the (slow) explicit verify in [installEmbeddingModel].
  Future<String?> resolveEmbeddingModelDir() async {
    for (final dir in embeddingModelCandidateDirs()) {
      if (!Directory(dir).existsSync()) continue;
      final v = await _modelVerifier.verify(dir, embeddingGemmaManifest);
      if (v.isComplete) return Directory(dir).absolute.path;
    }
    return null;
  }

  /// Folder a download goes to: the first candidate that already holds part of
  /// the model (so a repair completes that install instead of starting a
  /// second copy), otherwise the default `models` folder.
  Future<String> embeddingInstallDir() async {
    for (final dir in embeddingModelCandidateDirs()) {
      if (!Directory(dir).existsSync()) continue;
      final v = await _modelVerifier.verify(dir, embeddingGemmaManifest);
      if (v.anyFilePresent) return Directory(dir).absolute.path;
    }
    return Directory(embeddingModelCandidateDirs().first).absolute.path;
  }

  /// Cheap state of the folder the model lives in (or would be installed to).
  Future<ModelVerification> inspectEmbeddingModel() async {
    final dir = await resolveEmbeddingModelDir() ?? await embeddingInstallDir();
    return _modelVerifier.verify(dir, embeddingGemmaManifest);
  }

  /// Verifies sha256 of every file, downloads only what is missing or wrong
  /// (resuming `.part` files) and re-measures the folder at the end.
  /// Valid files are never rewritten. Only one install runs at a time.
  Future<ModelInstallResult> installEmbeddingModel({
    String mirror = 'https://hf-mirror.com',
    void Function(ModelProgress)? onProgress,
    bool Function()? isCancelled,
    ModelDownloader? downloader,
  }) async {
    if (_installingEmbeddingModel) {
      throw StateError('EmbeddingGemma 模型正在下载或校验中');
    }
    _installingEmbeddingModel = true;
    try {
      final dir = await embeddingInstallDir();
      return await (downloader ?? ModelDownloader()).install(
        manifest: embeddingGemmaManifest,
        dir: dir,
        mirror: mirror,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
    } finally {
      _installingEmbeddingModel = false;
    }
  }

  /// 检测指定 URL 的服务是否存活
  Future<bool> isServerHealthy(String baseUrl) async {
    try {
      final healthUri = Uri.parse(
        baseUrl.endsWith('/') ? '${baseUrl}health' : '$baseUrl/health',
      );
      final res = await http
          .get(healthUri)
          .timeout(const Duration(milliseconds: 1200));
      if (res.statusCode >= 200 && res.statusCode < 400) return true;
    } catch (_) {}

    try {
      final modelsUri = Uri.parse(
        baseUrl.endsWith('/') ? '${baseUrl}models' : '$baseUrl/models',
      );
      final res = await http
          .get(modelsUri)
          .timeout(const Duration(milliseconds: 1200));
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
      _localServerProcess = await Process.start(exe, [
        '-m',
        models['model']!,
        '--mmproj',
        models['mmproj']!,
        '--port',
        port,
        '-ngl',
        '99',
        '--ctx-size',
        '4096',
      ], mode: ProcessStartMode.detached);

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
