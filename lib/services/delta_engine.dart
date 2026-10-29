import 'dart:math';
import 'package:flutter/foundation.dart';

import 'ai_failure.dart';
import 'ai_service.dart';
import 'frame_embedding_pool.dart';

/// 增量同步规划结果
class DeltaSyncPlan {
  /// 规划期望的时间戳列表
  final List<int> expectedTimestamps;

  /// 已命中的缓存时间戳列表
  final List<int> cachedTimestamps;

  /// 缺失需要抽帧及计算 Embedding 的时间戳列表
  final List<int> missingTimestamps;

  const DeltaSyncPlan({
    required this.expectedTimestamps,
    required this.cachedTimestamps,
    required this.missingTimestamps,
  });

  /// 是否完全命中缓存（无需任何计算，0 开销）
  bool get isFullCacheHit => missingTimestamps.isEmpty;

  /// 缓存复用率（0.0 ~ 1.0）
  double get reuseRatio {
    if (expectedTimestamps.isEmpty) return 1.0;
    return cachedTimestamps.length / expectedTimestamps.length;
  }

  @override
  String toString() =>
      'DeltaSyncPlan(expected: , cached: , missing: , reuseRatio: %)';
}

/// MaxSim 匹配结果
class MaxSimResult {
  final double score;
  final int hitTimestampMs;
  final VideoFrameEmbeddingRecord? bestFrame;

  const MaxSimResult({
    required this.score,
    required this.hitTimestampMs,
    this.bestFrame,
  });

  @override
  String toString() => 'MaxSimResult(score: , hitTime: ms)';
}

/// The source-video range that should be indexed for a clip.
class ClipIndexRange {
  const ClipIndexRange({
    required this.startMs,
    required this.endMs,
    this.problem,
  });

  /// Positions in the **source video** (not clip-relative, not playlist time).
  final int startMs;
  final int endMs;

  /// Set when no usable range exists; [startMs]/[endMs] are then the inputs.
  final AiFailureKind? problem;

  bool get isUsable => problem == null;
}

/// Resolves what to index for a clip.
///
/// A saved clip with `end == 0` means "until the end of the video" (the player
/// only enforces the end when it is positive), so it is resolved with the
/// source duration. An end past the real duration is clamped, otherwise the
/// planner would keep expecting frames that can never exist and re-extract
/// them on every run. Nothing here changes the stored clip.
ClipIndexRange resolveClipIndexRange({
  required int startMs,
  required int endMs,
  int? videoDurationMs,
}) {
  var end = endMs;
  if (end <= 0) {
    if (videoDurationMs == null || videoDurationMs <= 0) {
      return ClipIndexRange(
        startMs: startMs,
        endMs: endMs,
        problem: AiFailureKind.unknownDuration,
      );
    }
    end = videoDurationMs;
  } else if (videoDurationMs != null &&
      videoDurationMs > 0 &&
      end > videoDurationMs) {
    end = videoDurationMs;
  }
  if (startMs < 0 || end <= startMs) {
    return ClipIndexRange(
      startMs: startMs,
      endMs: end,
      problem: AiFailureKind.invalidRange,
    );
  }
  return ClipIndexRange(startMs: startMs, endMs: end);
}

/// 增量叠加同步引擎 (Delta Engine)
class DeltaEngine {
  final FrameEmbeddingPool pool;
  final AiService aiService;

  DeltaEngine({FrameEmbeddingPool? pool, AiService? aiService})
    : pool = pool ?? FrameEmbeddingPool(),
      aiService = aiService ?? AiService();

  /// 规划指定 Clip 区间的帧池差集
  DeltaSyncPlan planDelta({
    required String videoPathOrUrl,
    required int startMs,
    required int endMs,
    int stepMs = 2000,
    int toleranceMs = 250,
  }) {
    final expected = <int>[];
    if (endMs >= startMs) {
      if (endMs - startMs < stepMs) {
        // 短片段至少取中点或起始
        expected.add(startMs + (endMs - startMs) ~/ 2);
      } else {
        for (int t = startMs; t <= endMs; t += stepMs) {
          expected.add(t);
        }
      }
    }

    final cachedSet = pool.getCachedTimestamps(videoPathOrUrl);
    final cached = <int>[];
    final missing = <int>[];

    for (final t in expected) {
      // 容差匹配：若已有帧在该时间点偏差 toleranceMs 内，视为命中
      final hit = cachedSet.any((c) => (c - t).abs() <= toleranceMs);
      if (hit) {
        cached.add(t);
      } else {
        missing.add(t);
      }
    }

    return DeltaSyncPlan(
      expectedTimestamps: expected,
      cachedTimestamps: cached,
      missingTimestamps: missing,
    );
  }

  /// 增量同步 Clip 区间帧
  /// - 缩短/已缓存：0 计算时间直接返回；
  /// - 延长/新区间：仅对 missing 部分抽帧并计算，最后合并返回。
  Future<List<VideoFrameEmbeddingRecord>> syncClipRange({
    required String videoPathOrUrl,
    required int startMs,
    required int endMs,
    int stepMs = 2000,
    String strategy = 'interval',
    required String modelDir,
    String? ortLib,
    String? customStorageDir,
  }) async {
    // 1. 优先加载磁盘中的历史帧缓存
    await pool.loadFromDisk(videoPathOrUrl, customStorageDir: customStorageDir);

    // 2. 规划差集
    final plan = planDelta(
      videoPathOrUrl: videoPathOrUrl,
      startMs: startMs,
      endMs: endMs,
      stepMs: stepMs,
    );

    if (plan.isFullCacheHit) {
      debugPrint(
        '[DeltaEngine] 100% 缓存命中，零计算复用已有 ${plan.cachedTimestamps.length} 帧',
      );
      return pool.getFramesInRange(videoPathOrUrl, startMs, endMs);
    }

    debugPrint(
      '[DeltaEngine] 增量规划: 期望 ${plan.expectedTimestamps.length} 帧, 命中 ${plan.cachedTimestamps.length} 帧, 缺失 ${plan.missingTimestamps.length} 帧',
    );

    // 3. 针对缺失边界执行抽帧
    final minMissing = plan.missingTimestamps.reduce(min);
    final maxMissing = plan.missingTimestamps.reduce(max);

    // A single missing point (short clip) has min == max; the extractor
    // rejects an empty range, so ask for one step starting at that point.
    final extractEnd = maxMissing > minMissing
        ? maxMissing
        : minMissing + stepMs;

    final extracted = await aiService.extractClipFrames(
      videoPathOrUrl: videoPathOrUrl,
      startMs: minMissing,
      endMs: extractEnd,
      strategy: strategy,
      everyMs: stepMs,
    );

    if (extracted.isEmpty) {
      throw AiStageException(
        stage: AiStage.extraction,
        kind: AiFailureKind.noFrames,
        message: describeAiFailure(
          AiStage.extraction,
          AiFailureKind.noFrames,
          videoPath: videoPathOrUrl,
        ),
        videoPath: videoPathOrUrl,
        startMs: minMissing,
        endMs: extractEnd,
      );
    }

    // 4. 计算缺失帧的 Embedding
    final embeddingsData = await aiService.embedFrames(
      frames: extracted,
      modelDir: modelDir,
      ortLib: ortLib,
    );

    final now = DateTime.now().millisecondsSinceEpoch;
    final newRecords = <VideoFrameEmbeddingRecord>[];

    for (int i = 0; i < extracted.length; i++) {
      final frame = extracted[i];
      if (i >= embeddingsData.length) continue;
      final rawVec = embeddingsData[i]['vector'];
      if (rawVec is! List || rawVec.isEmpty) continue;
      // Only real vectors are cached. A frame without one stays "missing" and
      // is retried on the next run instead of counting as a cache hit.
      newRecords.add(
        VideoFrameEmbeddingRecord(
          tMs: frame.tMs,
          vector: rawVec.map((v) => (v as num).toDouble()).toList(),
          frameImagePath: frame.path,
          createdAtMs: now,
        ),
      );
    }

    if (newRecords.isEmpty) {
      throw AiStageException(
        stage: AiStage.inference,
        kind: AiFailureKind.outputInvalid,
        message:
            '模型没有为任何帧返回向量 (提取 ${extracted.length} 帧，返回 ${embeddingsData.length} 个结果)。',
        videoPath: videoPathOrUrl,
        startMs: minMissing,
        endMs: extractEnd,
      );
    }

    // 5. 合并入池并持久化 (旧缓存先加载，因此只增不减)
    pool.putFrames(videoPathOrUrl, newRecords);
    await pool.saveToDisk(videoPathOrUrl, customStorageDir: customStorageDir);

    // 6. 返回合并后的区间帧记录
    return pool.getFramesInRange(videoPathOrUrl, startMs, endMs);
  }

  /// MaxSim 匹配算法：计算文本 Query 与 Clip 内部各帧的最高相似度
  MaxSimResult computeMaxSim({
    required List<double> queryVector,
    required List<VideoFrameEmbeddingRecord> frames,
  }) {
    if (frames.isEmpty || queryVector.isEmpty) {
      return const MaxSimResult(score: 0.0, hitTimestampMs: 0);
    }

    double maxScore = -1.0;
    int bestTime = frames.first.tMs;
    VideoFrameEmbeddingRecord? bestRecord;

    for (final frame in frames) {
      final sim = frame.cosineSimilarity(queryVector);
      if (sim > maxScore) {
        maxScore = sim;
        bestTime = frame.tMs;
        bestRecord = frame;
      }
    }

    return MaxSimResult(
      score: maxScore,
      hitTimestampMs: bestTime,
      bestFrame: bestRecord,
    );
  }
}
