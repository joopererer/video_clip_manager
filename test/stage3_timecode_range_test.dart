import 'package:flutter_test/flutter_test.dart';
import 'package:video_clip_manager/data/models.dart';
import 'package:video_clip_manager/utils/clip_edit_rules.dart';
import 'package:video_clip_manager/utils/clip_range.dart';
import 'package:video_clip_manager/utils/timecode.dart';

const _ms = Duration(milliseconds: 1);
Duration ms(int v) => Duration(milliseconds: v);

void main() {
  group('formatTimecode', () {
    test('formats HH:MM:SS.mmm', () {
      expect(formatTimecode(Duration.zero), '00:00:00.000');
      expect(formatTimecode(ms(1)), '00:00:00.001');
      expect(formatTimecode(ms(61005)), '00:01:01.005');
      expect(
        formatTimecode(const Duration(hours: 2, minutes: 5, seconds: 9)),
        '02:05:09.000',
      );
    });

    test('negative values are shown as zero', () {
      expect(formatTimecode(const Duration(seconds: -3)), '00:00:00.000');
    });

    test('microseconds round to the nearest millisecond', () {
      expect(
        formatTimecode(const Duration(microseconds: 1499)),
        '00:00:00.001',
      );
      expect(
        formatTimecode(const Duration(microseconds: 1500)),
        '00:00:00.002',
      );
    });

    test('short format drops leading hours', () {
      expect(formatTimecodeShort(ms(61005)), '01:01.005');
      expect(
        formatTimecodeShort(const Duration(hours: 1, minutes: 2)),
        '1:02:00.000',
      );
    });
  });

  group('parseTimecode', () {
    test('accepts the documented forms', () {
      expect(parseTimecode('00:01:01.005'), ms(61005));
      expect(parseTimecode('1:01.005'), ms(61005));
      expect(parseTimecode('01:01'), ms(61000));
      expect(parseTimecode('61.5'), ms(61500));
      expect(parseTimecode('7'), ms(7000));
      expect(parseTimecode('  00:00:01.250 '), ms(1250));
    });

    test('short fractions are fractions of a second, not milliseconds', () {
      expect(parseTimecode('0:00:01.5'), ms(1500));
      expect(parseTimecode('0:00:01.05'), ms(1050));
      expect(parseTimecode('0:00:01.005'), ms(1005));
    });

    test('accepts comma and full-width IME punctuation', () {
      expect(parseTimecode('00：00：01。250'), ms(1250));
      expect(parseTimecode('00:00:01,250'), ms(1250));
      expect(parseTimecode('00:00:01．250'), ms(1250));
    });

    test('rejects invalid input', () {
      for (final bad in [
        '',
        'abc',
        '00:60:00',
        '00:00:60',
        '1:75',
        '00:00:01.2345',
        '-1',
        '1:2:3:4',
        '00:00:01.',
        '.5',
      ]) {
        expect(parseTimecode(bad), isNull, reason: bad);
      }
    });

    test('format -> parse round-trips every millisecond value tested', () {
      for (final v in [0, 1, 999, 1000, 59999, 3600000, 7322123]) {
        expect(parseTimecode(formatTimecode(ms(v))), ms(v), reason: '$v');
      }
    });
  });

  group('roundToMs / clampDuration / NudgeStep', () {
    test('roundToMs', () {
      expect(roundToMs(const Duration(microseconds: 999)), ms(1));
      expect(roundToMs(const Duration(microseconds: 400)), Duration.zero);
    });

    test('clampDuration, including max < min', () {
      expect(clampDuration(ms(5), ms(10), ms(20)), ms(10));
      expect(clampDuration(ms(25), ms(10), ms(20)), ms(20));
      expect(clampDuration(ms(15), ms(10), ms(20)), ms(15));
      expect(clampDuration(ms(15), ms(10), ms(5)), ms(10));
    });

    test('NudgeStep modifiers', () {
      expect(NudgeStep.forModifiers(shift: false, control: false), ms(100));
      expect(NudgeStep.forModifiers(shift: true, control: false), ms(1000));
      expect(NudgeStep.forModifiers(shift: false, control: true), ms(10));
      expect(NudgeStep.forModifiers(shift: true, control: true), ms(10));
    });
  });

  group('ClipRangeRules.validate  (0 <= start < end <= source)', () {
    final source = ms(10000);

    test('legal ranges', () {
      expect(ClipRangeRules.validate(Duration.zero, ms(1), source), isNull);
      expect(ClipRangeRules.validate(ms(2000), ms(5000), source), isNull);
      expect(ClipRangeRules.validate(ms(9999), source, source), isNull);
      expect(ClipRangeRules.validate(Duration.zero, source, source), isNull);
    });

    test('illegal ranges', () {
      expect(
        ClipRangeRules.validate(
          const Duration(milliseconds: -1),
          ms(5),
          source,
        ),
        ClipRangeError.startNegative,
      );
      expect(
        ClipRangeRules.validate(ms(5), ms(5), source),
        ClipRangeError.endNotAfterStart,
      );
      expect(
        ClipRangeRules.validate(ms(6), ms(5), source),
        ClipRangeError.endNotAfterStart,
      );
      expect(
        ClipRangeRules.validate(ms(10001), ms(10002), source),
        ClipRangeError.startBeyondSource,
      );
      expect(
        ClipRangeRules.validate(ms(1), ms(10001), source),
        ClipRangeError.endBeyondSource,
      );
    });

    test('an unknown (zero) source disables the upper bound only', () {
      expect(
        ClipRangeRules.validate(ms(1), ms(99999999), Duration.zero),
        isNull,
      );
      expect(
        ClipRangeRules.validate(ms(5), ms(5), Duration.zero),
        ClipRangeError.endNotAfterStart,
      );
    });

    test('every error has a message mentioning the source when relevant', () {
      for (final e in ClipRangeError.values) {
        expect(ClipRangeRules.message(e, sourceDuration: source), isNotEmpty);
      }
      expect(
        ClipRangeRules.message(
          ClipRangeError.endBeyondSource,
          sourceDuration: source,
        ),
        contains('00:00:10.000'),
      );
    });
  });

  group('ClipRangeRules edits', () {
    final source = ms(10000);

    test('trySetStart accepts a legal IN and leaves OUT untouched', () {
      final r = ClipRangeRules.trySetStart(
        ms(1234),
        start: ms(0),
        end: ms(5000),
        source: source,
      );
      expect(r.isValid, isTrue);
      expect(r.start, ms(1234));
      expect(r.end, ms(5000));
    });

    test('trySetStart rejects IN >= OUT and keeps the previous range', () {
      final r = ClipRangeRules.trySetStart(
        ms(5000),
        start: ms(1000),
        end: ms(5000),
        source: source,
      );
      expect(r.error, ClipRangeError.endNotAfterStart);
      expect((r.start, r.end), (ms(1000), ms(5000)));
    });

    test(
      'trySetStart does not blame IN for a legacy OUT beyond the source',
      () {
        final r = ClipRangeRules.trySetStart(
          ms(500),
          start: ms(0),
          end: ms(10500),
          source: source,
        );
        expect(r.isValid, isTrue);
        expect(r.end, ms(10500));
      },
    );

    test('trySetEnd rejects OUT beyond the source / before IN', () {
      expect(
        ClipRangeRules.trySetEnd(
          ms(10001),
          start: ms(0),
          end: ms(5000),
          source: source,
        ).error,
        ClipRangeError.endBeyondSource,
      );
      expect(
        ClipRangeRules.trySetEnd(
          ms(1000),
          start: ms(1000),
          end: ms(5000),
          source: source,
        ).error,
        ClipRangeError.endNotAfterStart,
      );
      final ok = ClipRangeRules.trySetEnd(
        source,
        start: ms(0),
        end: ms(5000),
        source: source,
      );
      expect(ok.isValid, isTrue);
      expect(ok.end, source);
    });

    test('edits round sub-millisecond input', () {
      final r = ClipRangeRules.trySetEnd(
        const Duration(microseconds: 2600),
        start: ms(0),
        end: ms(5000),
        source: source,
      );
      expect(r.end, ms(3));
    });

    test('clampStart / clampEnd keep drags legal', () {
      expect(ClipRangeRules.clampStart(ms(-50), ms(5000)), Duration.zero);
      expect(ClipRangeRules.clampStart(ms(9000), ms(5000)), ms(5000) - _ms);
      expect(ClipRangeRules.clampEnd(ms(0), ms(1000), source), ms(1000) + _ms);
      expect(ClipRangeRules.clampEnd(ms(20000), ms(1000), source), source);
    });

    test('length is never negative; relativePosition is clip-relative', () {
      expect(ClipRangeRules.length(ms(1000), ms(3500)), ms(2500));
      expect(ClipRangeRules.length(ms(3500), ms(1000)), Duration.zero);
      expect(
        ClipRangeRules.relativePosition(ms(2000), ms(1000), ms(3000)),
        ms(1000),
      );
      expect(
        ClipRangeRules.relativePosition(ms(500), ms(1000), ms(3000)),
        isNull,
      );
      expect(
        ClipRangeRules.relativePosition(ms(3001), ms(1000), ms(3000)),
        isNull,
      );
    });

    test('normalizeSource floors to whole milliseconds', () {
      expect(
        ClipRangeRules.normalizeSource(const Duration(microseconds: 10000999)),
        ms(10000),
      );
    });
  });

  group('clip_edit_rules (save / cancel semantics)', () {
    VideoClip base() => VideoClip(
      id: 'c1',
      name: 'Intro',
      videoPath: r'D:\视频\clip.mp4',
      startTime: ms(1000),
      endTime: ms(4000),
      coverFrameTime: ms(1500),
      tags: const ['a', 'b'],
      notes: 'hello',
      rating: 3,
      isFavorite: true,
      thumbnailPath: 't.jpg',
    );

    test('an untouched form is not dirty', () {
      final b = base();
      expect(
        isClipDirty(composeClip(b, name: b.name, notes: b.notes ?? ''), b),
        isFalse,
      );
    });

    test(
      'a legacy clip with null notes / empty name is not dirty untouched',
      () {
        final legacy = VideoClip(id: 'x', videoPath: 'p', endTime: ms(10));
        expect(
          isClipDirty(composeClip(legacy, name: '', notes: ''), legacy),
          isFalse,
        );
      },
    );

    test('whitespace-only edits to name / notes are not changes', () {
      final b = base();
      expect(
        isClipDirty(composeClip(b, name: '  Intro  ', notes: ' hello\n'), b),
        isFalse,
      );
    });

    test('name, notes, range, tags, rating and cover each make it dirty', () {
      final b = base();
      bool dirty(VideoClip f, {String? name, String? notes}) => isClipDirty(
        composeClip(f, name: name ?? f.name, notes: notes ?? (f.notes ?? '')),
        b,
      );
      expect(dirty(b, name: 'Other'), isTrue);
      expect(dirty(b, notes: 'changed'), isTrue);
      expect(dirty(b.copyWith(startTime: ms(1001))), isTrue);
      expect(dirty(b.copyWith(endTime: ms(4001))), isTrue);
      expect(dirty(b.copyWith(tags: ['a'])), isTrue);
      expect(dirty(b.copyWith(rating: 4)), isTrue);
      expect(dirty(b.copyWith(isFavorite: false)), isTrue);
      expect(dirty(b.copyWith(coverFrameTime: ms(2000))), isTrue);
    });

    test('clearing the notes yields null, not an empty string', () {
      final composed = composeClip(base(), name: 'Intro', notes: '   ');
      expect(composed.notes, isNull);
      expect(isClipDirty(composed, base()), isTrue);
    });

    test('empty name is saved as Untitled Clip', () {
      expect(composeClip(base(), name: ' ', notes: '').name, 'Untitled Clip');
    });

    test('composeClip preserves every untouched field', () {
      final b = base();
      final c = composeClip(b, name: b.name, notes: b.notes!);
      expect(c, b);
    });

    test('composed clip keeps the serialized JSON format', () {
      final json = composeClip(base(), name: 'Intro', notes: 'hello').toJson();
      expect(json['start'], 1000);
      expect(json['end'], 4000);
      expect(json['coverFrameTime'], 1500);
      expect(
        json.keys,
        containsAll(<String>['id', 'name', 'videoPath', 'tags']),
      );
      expect(VideoClip.fromJson(json), base());
    });

    test('validateClipForSave', () {
      final source = ms(10000);
      expect(validateClipForSave(base(), source: source), isNull);
      expect(
        validateClipForSave(base().copyWith(endTime: ms(1000)), source: source),
        isNotNull,
      );
      expect(
        validateClipForSave(
          base().copyWith(endTime: ms(10001)),
          source: source,
        ),
        isNotNull,
      );
    });

    test(
      'legacy OUT beyond the source can still be saved if the range is unchanged',
      () {
        final legacy = base().copyWith(endTime: ms(10500));
        final tagEdit = legacy.copyWith(tags: ['z']);
        expect(
          validateClipForSave(tagEdit, original: legacy, source: ms(10000)),
          isNull,
        );
        // ...but changing the range re-enables the upper bound.
        final rangeEdit = legacy.copyWith(endTime: ms(10400));
        expect(
          validateClipForSave(rangeEdit, original: legacy, source: ms(10000)),
          isNotNull,
        );
      },
    );
  });
}
