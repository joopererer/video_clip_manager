import 'timecode.dart';

/// Why a `[start, end]` pair is not a legal clip range.
enum ClipRangeError {
  /// `start < 0`
  startNegative,

  /// `end <= start` (covers zero-length and reversed ranges)
  endNotAfterStart,

  /// `start > sourceDuration` (only checked when the duration is known)
  startBeyondSource,

  /// `end > sourceDuration` (only checked when the duration is known)
  endBeyondSource,
}

/// Result of a proposed IN/OUT edit.
class ClipRangeEdit {
  final Duration start;
  final Duration end;
  final ClipRangeError? error;

  const ClipRangeEdit(this.start, this.end, [this.error]);

  bool get isValid => error == null;
}

/// Pure range rules for the clip editor.
///
/// Legal range: `0 <= start < end <= sourceDuration`, all values being
/// *absolute times inside the source video* in whole milliseconds.
/// A [sourceDuration] of [Duration.zero] means "not known yet": the upper
/// bound is then not enforced (e.g. the source file is missing).
class ClipRangeRules {
  ClipRangeRules._();

  /// Shortest clip the editor accepts.
  static const Duration minLength = Duration(milliseconds: 1);

  /// Floors a player-reported duration to whole milliseconds, which is how
  /// clip ends are persisted (`inMilliseconds`).
  static Duration normalizeSource(Duration d) =>
      Duration(milliseconds: d.inMilliseconds);

  static ClipRangeError? validate(
    Duration start,
    Duration end,
    Duration sourceDuration,
  ) {
    final hasSource = sourceDuration > Duration.zero;
    if (start.isNegative) return ClipRangeError.startNegative;
    if (end <= start) return ClipRangeError.endNotAfterStart;
    if (hasSource && start > sourceDuration) {
      return ClipRangeError.startBeyondSource;
    }
    if (hasSource && end > sourceDuration) {
      return ClipRangeError.endBeyondSource;
    }
    return null;
  }

  static String message(ClipRangeError error, {Duration? sourceDuration}) {
    switch (error) {
      case ClipRangeError.startNegative:
        return 'IN cannot be before 00:00:00.000';
      case ClipRangeError.endNotAfterStart:
        return 'OUT must be after IN';
      case ClipRangeError.startBeyondSource:
        return 'IN is past the end of the source'
            '${sourceDuration == null ? '' : ' (${formatTimecode(sourceDuration)})'}';
      case ClipRangeError.endBeyondSource:
        return 'OUT is past the end of the source'
            '${sourceDuration == null ? '' : ' (${formatTimecode(sourceDuration)})'}';
    }
  }

  /// Applies a new IN. The range is *not* changed when the result would be
  /// illegal; the caller gets the reason instead. OUT is never moved silently.
  ///
  /// An OUT that already exceeds the source (legacy data) is not the IN's
  /// fault, so [ClipRangeError.endBeyondSource] does not reject an IN edit.
  static ClipRangeEdit trySetStart(
    Duration candidate, {
    required Duration start,
    required Duration end,
    required Duration source,
  }) {
    final c = roundToMs(candidate);
    final error = validate(c, end, source);
    if (error == null || error == ClipRangeError.endBeyondSource) {
      return ClipRangeEdit(c, end);
    }
    return ClipRangeEdit(start, end, error);
  }

  /// Applies a new OUT. See [trySetStart].
  static ClipRangeEdit trySetEnd(
    Duration candidate, {
    required Duration start,
    required Duration end,
    required Duration source,
  }) {
    final c = roundToMs(candidate);
    final error = validate(start, c, source);
    return error == null
        ? ClipRangeEdit(start, c)
        : ClipRangeEdit(start, end, error);
  }

  /// Clamps a dragged/nudged IN into its legal interval
  /// `[0, end - minLength]`.
  static Duration clampStart(Duration candidate, Duration end) =>
      clampDuration(roundToMs(candidate), Duration.zero, end - minLength);

  /// Clamps a dragged/nudged OUT into its legal interval
  /// `[start + minLength, source]` (no upper bound while source is unknown).
  static Duration clampEnd(
    Duration candidate,
    Duration start,
    Duration source,
  ) {
    final lower = start + minLength;
    final upper = source > Duration.zero ? source : roundToMs(candidate);
    return clampDuration(
      roundToMs(candidate),
      lower,
      upper < lower ? lower : upper,
    );
  }

  /// Length of the selected range, never negative.
  static Duration length(Duration start, Duration end) =>
      end > start ? end - start : Duration.zero;

  /// Playhead position relative to the clip start, or `null` when the
  /// playhead is outside `[start, end]`. This is *clip-relative* progress and
  /// must not be confused with the absolute source position.
  static Duration? relativePosition(
    Duration position,
    Duration start,
    Duration end,
  ) {
    if (position < start || position > end) return null;
    return position - start;
  }
}
