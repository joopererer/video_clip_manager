/// Millisecond-precision timecode helpers for the clip editor.
///
/// Everything here works on [Duration] values that represent *absolute time
/// inside the source video*. Clip metadata is persisted as whole milliseconds
/// (`start` / `end` in JSON), so UI values are rounded to milliseconds before
/// they are shown or stored.
library;

/// Rounds [d] to the nearest whole millisecond (player positions are
/// microsecond based, the JSON format is millisecond based).
Duration roundToMs(Duration d) =>
    Duration(milliseconds: (d.inMicroseconds / 1000).round());

/// Clamps [value] into `[min, max]`. If `max < min` the result is [min].
Duration clampDuration(Duration value, Duration min, Duration max) {
  if (max < min) return min;
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

String _two(int v) => v.toString().padLeft(2, '0');

/// Formats [d] as `HH:MM:SS.mmm`. Negative values are shown as zero.
String formatTimecode(Duration d) {
  final ms = d.isNegative ? 0 : roundToMs(d).inMilliseconds;
  final hours = ms ~/ 3600000;
  final minutes = (ms % 3600000) ~/ 60000;
  final seconds = (ms % 60000) ~/ 1000;
  final millis = (ms % 1000).toString().padLeft(3, '0');
  return '${_two(hours)}:${_two(minutes)}:${_two(seconds)}.$millis';
}

/// Formats a duration for compact labels (`MM:SS.mmm`, or `H:MM:SS.mmm`).
String formatTimecodeShort(Duration d) {
  final full = formatTimecode(d);
  return full.startsWith('00:')
      ? full.substring(3)
      : full.replaceFirst(RegExp(r'^0'), '');
}

final RegExp _timecodePattern = RegExp(
  r'^(\d{1,9}(?::\d{1,9}){0,2})(?:[.,](\d{1,3}))?$',
);

/// Parses user input into a [Duration].
///
/// Accepted forms (fraction is optional, at most three digits, so no false
/// sub-millisecond precision is implied):
/// * `HH:MM:SS.mmm`, `H:MM:SS`
/// * `MM:SS.mmm`
/// * `SS.mmm` / `SS` (plain seconds)
///
/// Full-width punctuation produced by Chinese IMEs (`：` `。` `．`) is
/// normalised. Returns `null` when the text is not a valid timecode or a
/// minute/second field is out of range (e.g. `00:75:00`).
Duration? parseTimecode(String input) {
  final text = input
      .trim()
      .replaceAll('：', ':')
      .replaceAll('。', '.')
      .replaceAll('．', '.');
  final match = _timecodePattern.firstMatch(text);
  if (match == null) return null;

  final fields = match.group(1)!.split(':').map(int.parse).toList();
  if (fields.length > 1 && fields.last >= 60) return null;
  if (fields.length == 3 && fields[1] >= 60) return null;

  var seconds = 0;
  for (final field in fields) {
    seconds = seconds * 60 + field;
  }
  final fraction = match.group(2);
  final millis = fraction == null ? 0 : int.parse(fraction.padRight(3, '0'));
  return Duration(milliseconds: seconds * 1000 + millis);
}

/// Step sizes used by keyboard nudging. These are *time* steps, not frame
/// steps: no frame rate or seek-accuracy guarantee is implied.
class NudgeStep {
  NudgeStep._();

  static const Duration fine = Duration(milliseconds: 10);
  static const Duration normal = Duration(milliseconds: 100);
  static const Duration coarse = Duration(seconds: 1);

  /// Ctrl = fine, Shift = coarse, otherwise normal.
  static Duration forModifiers({required bool shift, required bool control}) {
    if (control) return fine;
    if (shift) return coarse;
    return normal;
  }
}
