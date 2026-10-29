import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_clip_manager/theme/app_colors.dart';
import 'package:video_clip_manager/theme/app_theme.dart';
import 'package:video_clip_manager/utils/clip_range.dart';
import 'package:video_clip_manager/utils/timecode.dart';
import 'package:video_clip_manager/widgets/clip_editor_key_handler.dart';
import 'package:video_clip_manager/widgets/clip_range_timeline.dart';
import 'package:video_clip_manager/widgets/timecode_field.dart';

Duration ms(int v) => Duration(milliseconds: v);

Widget host(Widget child, {Size size = const Size(900, 300)}) {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  group('TimecodeField', () {
    late List<Duration> committed;
    final source = ms(10000);

    Widget field({Duration value = const Duration(seconds: 2)}) {
      return host(
        TimecodeField(
          label: 'IN',
          value: value,
          validator: (c) => ClipRangeRules.validate(c, ms(8000), source) == null
              ? null
              : 'out of range',
          onCommitted: committed.add,
        ),
      );
    }

    setUp(() => committed = []);

    testWidgets('shows the value as HH:MM:SS.mmm', (tester) async {
      await tester.pumpWidget(field(value: ms(61005)));
      expect(find.text('00:01:01.005'), findsOneWidget);
    });

    testWidgets('Enter commits valid text', (tester) async {
      await tester.pumpWidget(field());
      await tester.enterText(find.byType(TextField), '00:00:03.250');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(committed, [ms(3250)]);
    });

    testWidgets('full-width IME punctuation is accepted', (tester) async {
      await tester.pumpWidget(field());
      await tester.enterText(find.byType(TextField), '00：00：04。500');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(committed, [ms(4500)]);
    });

    testWidgets('malformed text shows a hint and does not commit', (
      tester,
    ) async {
      await tester.pumpWidget(field());
      await tester.enterText(find.byType(TextField), '00:99:00');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(committed, isEmpty);
      expect(find.text('Use HH:MM:SS.mmm'), findsOneWidget);
    });

    testWidgets('validator rejection shows its reason and does not commit', (
      tester,
    ) async {
      await tester.pumpWidget(field());
      await tester.enterText(find.byType(TextField), '00:00:09');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(committed, isEmpty);
      expect(find.text('out of range'), findsOneWidget);
    });

    testWidgets('Esc reverts the edit', (tester) async {
      await tester.pumpWidget(field());
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '00:00:05');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('00:00:02.000'), findsOneWidget);
      expect(committed, isEmpty);
    });

    testWidgets('losing focus with invalid text reverts silently', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          Column(
            children: [
              TimecodeField(
                label: 'IN',
                value: ms(2000),
                onCommitted: committed.add,
              ),
              const TextField(key: Key('other')),
            ],
          ),
        ),
      );
      await tester.tap(find.byType(TimecodeField));
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'garbage');
      await tester.tap(find.byKey(const Key('other')));
      await tester.pump();
      expect(committed, isEmpty);
      expect(find.text('00:00:02.000'), findsOneWidget);
    });

    testWidgets('arrow up/down nudge by 100 ms, Shift 1 s, Ctrl 10 ms', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          TimecodeField(
            label: 'IN',
            value: ms(2000),
            onCommitted: committed.add,
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(committed.last, ms(2100));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(committed.last, ms(1100));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(committed.last, ms(1110));
    });

    testWidgets('nudging never goes below zero', (tester) async {
      await tester.pumpWidget(
        host(
          TimecodeField(label: 'IN', value: ms(50), onCommitted: committed.add),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(committed.last, Duration.zero);
    });

    testWidgets('the shown value follows the model while not being edited', (
      tester,
    ) async {
      await tester.pumpWidget(field(value: ms(1000)));
      await tester.pumpWidget(field(value: ms(2500)));
      expect(find.text('00:00:02.500'), findsOneWidget);
    });
  });

  group('resolveClipEditorKey', () {
    ClipEditorKeyBinding? r(
      LogicalKeyboardKey k, {
      bool shift = false,
      bool control = false,
      bool alt = false,
      bool meta = false,
    }) => resolveClipEditorKey(
      k,
      shift: shift,
      control: control,
      alt: alt,
      meta: meta,
    );

    test('plain keys map to commands', () {
      expect(
        r(LogicalKeyboardKey.space)?.command,
        ClipEditorCommand.togglePlay,
      );
      expect(r(LogicalKeyboardKey.keyI)?.command, ClipEditorCommand.setIn);
      expect(r(LogicalKeyboardKey.digit1)?.command, ClipEditorCommand.setIn);
      expect(r(LogicalKeyboardKey.keyO)?.command, ClipEditorCommand.setOut);
      expect(r(LogicalKeyboardKey.digit2)?.command, ClipEditorCommand.setOut);
      expect(r(LogicalKeyboardKey.keyS)?.command, ClipEditorCommand.toggleMute);
      expect(r(LogicalKeyboardKey.keyC)?.command, ClipEditorCommand.setCover);
      expect(r(LogicalKeyboardKey.f1)?.command, ClipEditorCommand.toggleHints);
    });

    test('Ctrl+S (save) does not toggle mute; Ctrl+C is left to copy', () {
      expect(r(LogicalKeyboardKey.keyS, control: true), isNull);
      expect(r(LogicalKeyboardKey.keyC, control: true), isNull);
      expect(r(LogicalKeyboardKey.keyI, alt: true), isNull);
      expect(r(LogicalKeyboardKey.keyS, meta: true), isNull);
    });

    test('arrow steps follow modifiers', () {
      expect(r(LogicalKeyboardKey.arrowLeft)?.step, ms(100));
      expect(r(LogicalKeyboardKey.arrowLeft, shift: true)?.step, ms(1000));
      expect(r(LogicalKeyboardKey.arrowRight, control: true)?.step, ms(10));
      expect(
        r(LogicalKeyboardKey.arrowLeft)?.command,
        ClipEditorCommand.seekBack,
      );
      expect(
        r(LogicalKeyboardKey.arrowRight)?.command,
        ClipEditorCommand.seekForward,
      );
      expect(r(LogicalKeyboardKey.arrowRight, alt: true), isNull);
    });

    test('unrelated keys are ignored', () {
      expect(r(LogicalKeyboardKey.keyA), isNull);
      expect(r(LogicalKeyboardKey.enter), isNull);
    });
  });

  group('ClipEditorKeyHandler focus guard', () {
    late List<ClipEditorCommand> commands;
    late FocusNode keyNode;
    late FocusNode fieldNode;
    late FocusNode buttonNode;
    late TextEditingController text;

    setUp(() {
      commands = [];
      keyNode = FocusNode();
      fieldNode = FocusNode();
      buttonNode = FocusNode();
      text = TextEditingController();
    });

    tearDown(() {
      keyNode.dispose();
      fieldNode.dispose();
      buttonNode.dispose();
      text.dispose();
    });

    Widget app() => host(
      ClipEditorKeyHandler(
        focusNode: keyNode,
        onCommand: (c, _) => commands.add(c),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            KeyboardClaimRegion(
              focusNode: keyNode,
              child: const ColoredBox(
                key: Key('stage'),
                color: Colors.black,
                child: SizedBox(width: 200, height: 80),
              ),
            ),
            TextField(
              key: const Key('notes'),
              controller: text,
              focusNode: fieldNode,
              maxLines: 3,
            ),
            ElevatedButton(
              key: const Key('btn'),
              focusNode: buttonNode,
              onPressed: () {},
              child: const Text('btn'),
            ),
          ],
        ),
      ),
    );

    testWidgets('shortcuts fire when the editor owns the keyboard', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      keyNode.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(commands, [
        ClipEditorCommand.togglePlay,
        ClipEditorCommand.setIn,
        ClipEditorCommand.setOut,
        ClipEditorCommand.toggleMute,
        ClipEditorCommand.seekForward,
      ]);
    });

    testWidgets('typing in a text field never triggers a command', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.tap(find.byKey(const Key('notes')));
      await tester.pump();
      expect(fieldNode.hasPrimaryFocus, isTrue);
      for (final k in [
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.keyI,
        LogicalKeyboardKey.keyO,
        LogicalKeyboardKey.keyS,
        LogicalKeyboardKey.keyC,
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.arrowLeft,
      ]) {
        await tester.sendKeyEvent(k);
      }
      expect(commands, isEmpty);
    });

    testWidgets('IME composition text (enterText) stays in the field', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.tap(find.byKey(const Key('notes')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('notes')), '你好 i o s');
      expect(text.text, '你好 i o s');
      expect(commands, isEmpty);
    });

    testWidgets('Space on a focused button is left for the button', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      buttonNode.requestFocus();
      await tester.pump();
      expect(buttonNode.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(commands, isNot(contains(ClipEditorCommand.togglePlay)));
    });

    testWidgets('clicking the stage after typing hands shortcuts back', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.tap(find.byKey(const Key('notes')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      expect(commands, isEmpty);

      await tester.tap(find.byKey(const Key('stage')));
      await tester.pump();
      await tester.pump();
      expect(keyNode.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      expect(commands, [ClipEditorCommand.setIn]);
    });

    testWidgets('Ctrl+S is not consumed by the handler', (tester) async {
      await tester.pumpWidget(app());
      keyNode.requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(commands, isEmpty);
    });

    testWidgets('held keys repeat only for seeking', (tester) async {
      await tester.pumpWidget(app());
      keyNode.requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyI);
      expect(commands, [ClipEditorCommand.setIn]);

      commands.clear();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      expect(commands.length, 3);
    });
  });

  group('TimelineGeometry / ticks', () {
    test('round trip between time and pixels is stable', () {
      final g = TimelineGeometry(
        width: 828,
        source: const Duration(minutes: 3),
      );
      expect(g.timeToDx(Duration.zero), TimelineGeometry.padding);
      expect(
        g.timeToDx(const Duration(minutes: 3)),
        g.width - TimelineGeometry.padding,
      );
      for (final t in [ms(0), ms(1234), ms(90000), ms(179999), ms(180000)]) {
        final back = g.dxToTime(g.timeToDx(t));
        // One pixel at this zoom is ~220 ms; the round trip stays within it.
        expect((back - t).abs() <= ms(250), isTrue, reason: '$t -> $back');
      }
    });

    test('dxToTime clamps to [0, source] and returns whole milliseconds', () {
      final g = TimelineGeometry(width: 500, source: ms(10000));
      expect(g.dxToTime(-100), Duration.zero);
      expect(g.dxToTime(9999), ms(10000));
      expect(g.dxToTime(123.456).inMicroseconds % 1000, 0);
    });

    test('a zero source does not divide by zero', () {
      final g = TimelineGeometry(width: 500, source: Duration.zero);
      expect(g.timeToDx(ms(100)), TimelineGeometry.padding);
      expect(g.dxToTime(200), Duration.zero);
    });

    test('tick interval keeps labels apart and is a round value', () {
      final short = niceTickInterval(const Duration(seconds: 10), 800);
      final long = niceTickInterval(const Duration(hours: 2), 800);
      expect(short < long, isTrue);
      expect(
        (const Duration(seconds: 10).inMicroseconds / short.inMicroseconds) <=
            800 / 84 + 1e-9,
        isTrue,
      );
      expect(niceTickInterval(Duration.zero, 800), const Duration(seconds: 1));
    });
  });

  group('ClipRangeTimeline', () {
    late ValueNotifier<Duration> position;
    late List<Duration> seeks;
    late List<(Duration, Duration)> ranges;
    late List<bool> scrubs;
    const width = 800.0;
    final source = ms(10000);

    setUp(() {
      position = ValueNotifier(Duration.zero);
      seeks = [];
      ranges = [];
      scrubs = [];
    });

    tearDown(() => position.dispose());

    Widget timeline({Duration? start, Duration? end, bool enabled = true}) =>
        host(
          SizedBox(
            width: width,
            child: ClipRangeTimeline(
              source: source,
              start: start ?? ms(2000),
              end: end ?? ms(6000),
              position: position,
              enabled: enabled,
              onSeek: seeks.add,
              onRangeChanged: (s, e) => ranges.add((s, e)),
              onScrubChanged: scrubs.add,
            ),
          ),
          size: const Size(900, 300),
        );

    /// Real mice report many small moves; one big jump only delivers the
    /// slop-adjusted first update, so drag in steps.
    Future<void> drag(WidgetTester tester, Offset from, Offset to) async {
      final gesture = await tester.startGesture(from);
      const steps = 12;
      for (var i = 1; i <= steps; i++) {
        await gesture.moveTo(Offset.lerp(from, to, i / steps)!);
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();
    }

    Offset pointAt(WidgetTester tester, Duration t) {
      final box = tester.getRect(find.byType(ClipRangeTimeline));
      final g = TimelineGeometry(width: box.width, source: source);
      return Offset(box.left + g.timeToDx(t), box.center.dy);
    }

    testWidgets('renders without overflow at 900 px', (tester) async {
      await tester.pumpWidget(timeline());
      expect(tester.takeException(), isNull);
      expect(find.byType(ClipRangeTimeline), findsOneWidget);
    });

    testWidgets('clicking the track seeks to that absolute time', (
      tester,
    ) async {
      await tester.pumpWidget(timeline());
      final target = pointAt(tester, ms(8000));
      await tester.tapAt(target);
      await tester.pump();
      expect(seeks, isNotEmpty);
      expect((seeks.last - ms(8000)).abs() <= ms(30), isTrue);
      expect(ranges, isEmpty);
    });

    testWidgets('dragging the IN handle moves only the start, in ms', (
      tester,
    ) async {
      await tester.pumpWidget(timeline());
      final from = pointAt(tester, ms(2000));
      final to = pointAt(tester, ms(3000));
      await drag(tester, from, to);
      expect(ranges, isNotEmpty);
      final (s, e) = ranges.last;
      expect(e, ms(6000));
      expect((s - ms(3000)).abs() <= ms(30), isTrue, reason: '$s');
      expect(s.inMicroseconds % 1000, 0);
      expect(scrubs.isNotEmpty, isTrue);
      expect(scrubs.last, isFalse);
    });

    testWidgets('dragging the OUT handle moves only the end', (tester) async {
      await tester.pumpWidget(timeline());
      await drag(tester, pointAt(tester, ms(6000)), pointAt(tester, ms(7500)));
      final (s, e) = ranges.last;
      expect(s, ms(2000));
      expect((e - ms(7500)).abs() <= ms(30), isTrue, reason: '$e');
    });

    testWidgets('IN cannot be dragged past OUT', (tester) async {
      await tester.pumpWidget(timeline());
      await drag(tester, pointAt(tester, ms(2000)), pointAt(tester, ms(9500)));
      for (final (s, e) in ranges) {
        expect(ClipRangeRules.validate(s, e, source), isNull, reason: '$s $e');
      }
      expect(ranges.last.$1 < ms(6000), isTrue);
    });

    testWidgets('OUT cannot be dragged before IN or past the source', (
      tester,
    ) async {
      await tester.pumpWidget(timeline());
      await drag(tester, pointAt(tester, ms(6000)), pointAt(tester, ms(500)));
      for (final (s, e) in ranges) {
        expect(ClipRangeRules.validate(s, e, source), isNull, reason: '$s $e');
      }
      expect(ranges.last.$2 > ms(2000), isTrue);

      ranges.clear();
      await tester.pumpWidget(timeline());
      await drag(
        tester,
        pointAt(tester, ms(6000)),
        pointAt(tester, ms(10000)) + const Offset(300, 0),
      );
      expect(ranges.last.$2 <= source, isTrue);
    });

    testWidgets('a disabled timeline ignores input', (tester) async {
      await tester.pumpWidget(timeline(enabled: false));
      await tester.tapAt(pointAt(tester, ms(5000)));
      await drag(tester, pointAt(tester, ms(2000)), pointAt(tester, ms(3000)));
      expect(seeks, isEmpty);
      expect(ranges, isEmpty);
    });

    testWidgets('playhead updates do not rebuild the widget tree', (
      tester,
    ) async {
      await tester.pumpWidget(timeline());
      position.value = ms(4000);
      await tester.pump();
      position.value = ms(4010);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('tiny and full-length selections lay out', (tester) async {
      await tester.pumpWidget(timeline(start: ms(5000), end: ms(5001)));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(timeline(start: Duration.zero, end: source));
      expect(tester.takeException(), isNull);
    });
  });

  test('app colour extension used by the editor is available in the theme', () {
    final ext = AppTheme.darkTheme.extension<AppColorExtension>();
    expect(ext, isNotNull);
    expect(formatTimecode(ms(1)), '00:00:00.001');
  });
}
