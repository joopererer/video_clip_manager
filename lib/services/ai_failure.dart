import 'ai_model_downloader.dart' show redactSecrets;

/// Which step of the semantic-index pipeline failed.
enum AiStage {
  /// Cutting key frames out of the source video (sidecar + FFmpeg).
  extraction,

  /// Turning frames into vectors (sidecar + ONNX Runtime + model files).
  inference,

  /// Reading or writing the on-disk frame cache.
  storage,

  /// A bug in the app itself (unexpected exception type).
  internal,
}

/// Why a step failed. Each kind implies a different user action.
enum AiFailureKind {
  /// `local-media-ai` could not be started.
  cliMissing,

  /// The sidecar could not find or run FFmpeg.
  ffmpegMissing,

  /// `onnxruntime.dll` could not be located or loaded.
  ortMissing,

  /// EmbeddingGemma files are missing or unreadable.
  modelMissing,

  /// The source file does not exist (moved, renamed, drive offline).
  sourceMissing,

  /// An http/m3u8 source could not be reached.
  sourceUnreachable,

  /// FFmpeg opened the source but cannot decode it.
  sourceUnsupported,

  /// Start/end do not describe a positive range.
  invalidRange,

  /// The clip means "until the end" (end == 0) but the video length is unknown.
  unknownDuration,

  /// The extraction succeeded but returned no image (range beyond the video).
  noFrames,

  /// The sidecar did not finish in time and was stopped.
  timeout,

  /// The sidecar exited with an error that does not match a known pattern.
  processFailed,

  /// The sidecar answered with something that is not the expected JSON.
  outputInvalid,

  /// The frame cache could not be written or replaced.
  storageFailed,

  unknown,
}

/// A failure in one stage of frame extraction / embedding / caching.
///
/// [toString] is the user-facing message so `'$e'` stays readable; the raw
/// command, exit code and stderr/stdout tail are kept in separate fields for
/// the details view.
class AiStageException implements Exception {
  const AiStageException({
    required this.stage,
    required this.kind,
    required this.message,
    this.detail,
    this.videoPath,
    this.startMs,
    this.endMs,
    this.command,
    this.exitCode,
  });

  final AiStage stage;
  final AiFailureKind kind;
  final String message;

  /// Redacted tail of the sidecar output or the OS error text.
  final String? detail;
  final String? videoPath;
  final int? startMs;
  final int? endMs;

  /// The sidecar sub-command line, with frame payloads and secrets removed.
  final String? command;
  final int? exitCode;

  /// True when every other clip would fail the same way, so a batch should
  /// stop instead of repeating the error for each clip.
  bool get isEnvironmental => switch (kind) {
    AiFailureKind.cliMissing ||
    AiFailureKind.ffmpegMissing ||
    AiFailureKind.ortMissing ||
    AiFailureKind.modelMissing => true,
    _ => false,
  };

  String get stageLabel => switch (stage) {
    AiStage.extraction => '提取视频帧',
    AiStage.inference => '模型推理',
    AiStage.storage => '索引存储',
    AiStage.internal => '程序内部',
  };

  /// Multi-line text for "copy details".
  String report() => [
    '阶段: $stageLabel (${stage.name})',
    '类型: ${kind.name}',
    '信息: $message',
    if (videoPath != null) '视频: ${redactSecrets(videoPath!)}',
    if (startMs != null || endMs != null)
      '范围: ${startMs ?? '?'} - ${endMs ?? '?'} ms',
    if (command != null) '命令: $command',
    if (exitCode != null) '退出码: $exitCode',
    if (detail != null && detail!.isNotEmpty) '详情:\n$detail',
  ].join('\n');

  @override
  String toString() => message;
}

/// Maps the text FFmpeg / the sidecar prints on failure to a [AiFailureKind].
///
/// Patterns come from observed output of the sidecar built from
/// `D:\workspace\local-media-ai` (missing file, truncated mp4, unreachable
/// m3u8, `-to` smaller than `-ss`). The "FFmpeg missing", "ONNX Runtime
/// missing" and "model missing" patterns are written from the sidecar's likely
/// wording and were **not** reproduced against the real binary.
AiFailureKind classifySidecarText(
  String text, {
  AiStage stage = AiStage.extraction,
}) {
  final t = text.toLowerCase();
  bool has(String s) => t.contains(s.toLowerCase());

  if (stage == AiStage.inference) {
    // Inference only reads frame PNGs we just wrote and the model folder, so
    // "file not found" or "decoder" wording says nothing about the source video.
    if (has('onnxruntime') || has('ort-lib') || has('ort_lib')) {
      return AiFailureKind.ortMissing;
    }
    if (has('tokenizer') || has('model')) return AiFailureKind.modelMissing;
    return AiFailureKind.processFailed;
  }

  if (has('视频不存在') ||
      has('no such file') ||
      has('does not exist') ||
      has('cannot find the file') ||
      has('系统找不到指定的文件')) {
    return AiFailureKind.sourceMissing;
  }
  if (has('-to value smaller than -ss') ||
      has('end must be greater') ||
      has('invalid range')) {
    return AiFailureKind.invalidRange;
  }
  if (has('connection to tcp') ||
      has('connection refused') ||
      has('connection timed out') ||
      has('server returned 4') ||
      has('server returned 5') ||
      has('http error') ||
      has('name or service not known') ||
      has('failed to resolve') ||
      has('could not resolve') ||
      has('tls') && has('error in the pull function')) {
    return AiFailureKind.sourceUnreachable;
  }
  if (has('moov atom not found') ||
      has('invalid data found') ||
      has('unsupported codec') ||
      has('decoder') && has('not found') ||
      has('error opening input')) {
    return AiFailureKind.sourceUnsupported;
  }
  if ((has('ffmpeg') || has('ffprobe')) &&
      (has('not found') ||
          has('找不到') ||
          has('未找到') ||
          has('cannot run') ||
          has('program not found'))) {
    return AiFailureKind.ffmpegMissing;
  }
  if (has('onnxruntime') || has('ort-lib') || has('ort_lib')) {
    return AiFailureKind.ortMissing;
  }
  if (has('tokenizer') ||
      (has('model') &&
          (has('not found') || has('no such file') || has('missing')))) {
    return AiFailureKind.modelMissing;
  }
  return AiFailureKind.processFailed;
}

/// User-facing explanation and next step for [kind] in [stage].
String describeAiFailure(
  AiStage stage,
  AiFailureKind kind, {
  String? videoPath,
}) {
  final v = videoPath != null ? ' (${redactSecrets(videoPath)})' : '';
  switch (kind) {
    case AiFailureKind.cliMissing:
      return '找不到 AI 组件 local-media-ai.exe，无法提取帧或生成向量。请确认它与程序放在同一目录或在系统 PATH 中。';
    case AiFailureKind.ffmpegMissing:
      return '找不到 FFmpeg，无法提取视频帧。请安装 FFmpeg 并加入 PATH，或在 AI 设置中指定路径。';
    case AiFailureKind.ortMissing:
      return '找不到或无法加载 ONNX Runtime (onnxruntime.dll)，无法生成向量。';
    case AiFailureKind.modelMissing:
      return '语义检索模型文件缺失或不完整，请在 AI 设置中点击“修复 / 补全下载”。';
    case AiFailureKind.sourceMissing:
      return '源视频文件不存在或已被移动$v。请恢复文件后重试，该片段已有的缓存不受影响。';
    case AiFailureKind.sourceUnreachable:
      return '无法访问在线视频源$v，请检查网络或链接是否过期。';
    case AiFailureKind.sourceUnsupported:
      return 'FFmpeg 无法解码该视频$v，文件可能损坏或格式不受支持。';
    case AiFailureKind.invalidRange:
      return '片段的起止时间无效 (结束时间不大于开始时间)。';
    case AiFailureKind.unknownDuration:
      return '该片段没有结束时间 (表示播放到视频末尾)，但尚未获知该视频的时长，已跳过。请先在“原始视频”中刷新元数据。';
    case AiFailureKind.noFrames:
      return '在该时间范围内没有取到任何画面$v，范围可能超出了视频长度（视频是否被替换为更短的文件？）。';
    case AiFailureKind.timeout:
      return stage == AiStage.inference
          ? '生成向量超时，已停止该任务。'
          : '提取视频帧超时，已停止该任务$v。视频可能位于慢速磁盘或网络位置。';
    case AiFailureKind.processFailed:
      return stage == AiStage.inference ? '模型推理失败，详见错误详情。' : '提取视频帧失败，详见错误详情。';
    case AiFailureKind.outputInvalid:
      return 'AI 组件返回了无法解析的结果，详见错误详情。';
    case AiFailureKind.storageFailed:
      return '无法写入向量缓存文件。请检查磁盘空间和应用数据目录的写入权限。';
    case AiFailureKind.unknown:
      return '未分类的错误，详见错误详情。';
  }
}

/// One clip that could not be indexed, kept so the UI can list it and the
/// next run can try it again.
class ClipIndexFailure {
  const ClipIndexFailure({
    required this.clipId,
    required this.clipName,
    required this.videoPath,
    required this.startMs,
    required this.endMs,
    required this.stage,
    required this.kind,
    required this.message,
    required this.report,
  });

  final String clipId;
  final String clipName;
  final String videoPath;

  /// Range that was attempted (after resolving an `end == 0` clip).
  final int startMs;
  final int endMs;
  final AiStage stage;
  final AiFailureKind kind;
  final String message;

  /// Full multi-line detail for "copy".
  final String report;
}

/// Last [max] characters of [text], with credentials removed.
String tailForLog(String text, {int max = 2000}) {
  final cleaned = redactSecrets(text.trim());
  if (cleaned.length <= max) return cleaned;
  return '…${cleaned.substring(cleaned.length - max)}';
}
