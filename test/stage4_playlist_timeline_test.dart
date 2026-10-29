import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_clip_manager/data/models.dart';
import 'package:video_clip_manager/theme/app_theme.dart';
import 'package:video_clip_manager/utils/timeline_layout.dart';
import 'package:video_clip_manager/widgets/playlist_timeline_view.dart';

double sum(List<double> v) => v.fold(0.0, (a, b) => a + b);

PlaylistItemWithClip entry(String id, int ms, {int? idx}) {
  final clip = VideoClip(
    id: id,
    name: 'Clip $id',
    videoPath: 'v.mp4',
    startTime: Duration.zero,
    endTime: Duration(milliseconds: ms),
  );
  return PlaylistItemWithClip(
    item: PlaylistItem(id: 'i$id', clipId: id, order: idx ?? 0),
    clip: clip,
  );
}

void main() {
  group('computeTimelineLayout', () {
    test('is proportional when nothing is below the floor', () {
      final l = computeTimelineLayout([1000, 3000], 400, minSegment: 8);
      expect(l.widths[0], closeTo(100, 1e-9));
      expect(l.widths[1], closeTo(300, 1e-9));
      expect(l.expanded, [false, false]);
    });

    test('tiny clips get the floor and the total stays exact', () {
      final l = computeTimelineLayout([1, 60000, 250], 600, minSegment: 8);
      expect(l.widths[0], 8);
      expect(l.widths[2], 8);
      expect(l.widths[1], closeTo(584, 1e-9));
      expect(sum(l.widths), closeTo(600, 1e-9));
      expect(l.expanded, [true, false, true]);
    });

    test('large segments keep their ratios to each other', () {
      final l = computeTimelineLayout([1, 10000, 30000], 800, minSegment: 8);
      expect(l.widths[2] / l.widths[1], closeTo(3, 1e-9));
    });

    test('pinning cascades until stable', () {
      // 3rd would be 19.9px at first, then drops below the floor once the
      // first two are pinned.
      final l = computeTimelineLayout([1, 1, 12, 988], 100, minSegment: 12);
      expect(l.widths.every((w) => w >= 12 - 1e-9), isTrue);
      expect(sum(l.widths), closeTo(100, 1e-9));
    });

    test('too narrow for the floor falls back to equal widths', () {
      final l = computeTimelineLayout([1, 5000, 1], 20, minSegment: 8);
      expect(l.widths, everyElement(closeTo(20 / 3, 1e-9)));
    });

    test('degenerate inputs', () {
      expect(computeTimelineLayout([], 100).widths, isEmpty);
      expect(computeTimelineLayout([0, 0], 100).widths, [50, 50]);
      expect(computeTimelineLayout([5, 5], 0).widths, [0, 0]);
      expect(computeTimelineLayout([-5, 10], 100, minSegment: 8).widths[0], 8);
    });

    test('segmentAt and nearestSlot', () {
      final l = computeTimelineLayout([1000, 1000, 2000], 400, minSegment: 8);
      expect(l.boundaries, [0, 100, 200, 400]);
      expect(l.segmentAt(0), 0);
      expect(l.segmentAt(150), 1);
      expect(l.segmentAt(399), 2);
      expect(l.segmentAt(9999), 2);
      expect(l.nearestSlot(10), 0);
      expect(l.nearestSlot(90), 1);
      expect(l.nearestSlot(160), 2);
      expect(l.nearestSlot(380), 3);
    });
  });

  group('finalIndexForSlot', () {
    test('no-op slots return null', () {
      expect(finalIndexForSlot(2, 2), isNull);
      expect(finalIndexForSlot(2, 3), isNull);
    });
    test('moving forward and backward', () {
      expect(finalIndexForSlot(0, 3), 2);
      expect(finalIndexForSlot(0, 4), 3);
      expect(finalIndexForSlot(3, 0), 0);
      expect(finalIndexForSlot(3, 1), 1);
    });
  });

  group('PlaylistTimelineView', () {
    Future<void> pump(
      WidgetTester tester,
      List<PlaylistItemWithClip> items, {
      double width = 700,
      ValueChanged<int>? onTap,
      bool reorder = false,
      void Function(int, int)? onReorder,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: PlaylistTimelineView(
                  items: items,
                  height: 64,
                  showScale: true,
                  selectedIndex: 1,
                  onItemTap: onTap,
                  enableReorder: reorder,
                  onReorder: onReorder,
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('renders a 1 ms clip next to a 60 s clip without overflow', (
      tester,
    ) async {
      await pump(tester, [entry('a', 1), entry('b', 60000), entry('c', 250)]);
      expect(tester.takeException(), isNull);
      // Every segment is wide enough to hit.
      final segs = find.byType(GestureDetector);
      expect(segs, findsNWidgets(3));
      for (final e in segs.evaluate()) {
        expect(
          tester.getSize(find.byWidget(e.widget)).width,
          greaterThanOrEqualTo(8),
        );
      }
    });

    testWidgets('tapping the narrowest segment reports its real index', (
      tester,
    ) async {
      int? tapped;
      await pump(tester, [
        entry('a', 1),
        entry('b', 60000),
        entry('c', 250),
      ], onTap: (i) => tapped = i);
      final first = find.byType(GestureDetector).first;
      await tester.tap(first);
      expect(tapped, 0);
    });

    testWidgets('scale shows the exact millisecond total', (tester) async {
      await pump(tester, [entry('a', 1), entry('b', 60000), entry('c', 250)]);
      expect(find.text('0:00'), findsOneWidget);
      expect(find.text('1:00.251'), findsOneWidget);
    });

    testWidgets('empty list shows placeholder', (tester) async {
      await pump(tester, []);
      expect(find.text('暂无片段'), findsOneWidget);
    });

    testWidgets('tooltip shows real times, not widths', (tester) async {
      await pump(tester, [entry('a', 1), entry('b', 60000), entry('c', 250)]);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(
        tester.getCenter(find.byType(GestureDetector).first),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.textContaining('时长 0:00.001', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('列表位置 0:00.000 – 0:00.001', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('dragging a segment reports (from, finalIndex)', (
      tester,
    ) async {
      (int, int)? moved;
      await pump(
        tester,
        [
          entry('a', 1000),
          entry('b', 1000),
          entry('c', 1000),
          entry('d', 1000),
        ],
        reorder: true,
        onReorder: (f, t) => moved = (f, t),
      );
      final first = tester.getCenter(find.byType(Draggable<int>).first);
      final gesture = await tester.startGesture(first);
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.moveTo(Offset(first.dx + 400, first.dy));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(moved, isNotNull);
      expect(moved!.$1, 0);
      expect(moved!.$2, greaterThan(0));
    });
  });
}
