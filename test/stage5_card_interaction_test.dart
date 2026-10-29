import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_clip_manager/data/models.dart';
import 'package:video_clip_manager/theme/app_theme.dart';
import 'package:video_clip_manager/widgets/clip_card.dart';
import 'package:video_clip_manager/widgets/clip_list_row.dart';
import 'package:video_clip_manager/widgets/common/media_card_activation.dart';

const _missing = r'Z:\definitely\missing\视频 01.mp4';

VideoClip _clip() => const VideoClip(
  id: 'c1',
  name: '测试片段',
  videoPath: _missing,
  endTime: Duration(seconds: 5),
);

enum _Mode { grid, list }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final mode in _Mode.values) {
    group('ClipsTab card interaction (${mode.name})', () {
      late List<String> log;
      late VideoClip clip;

      Future<void> pump(WidgetTester tester) async {
        log = [];
        clip = _clip();
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        Widget card() => mode == _Mode.grid
            ? ClipCard(
                clip: clip,
                onSelect: () => log.add('select'),
                onPlay: () => log.add('play'),
                onEdit: () => log.add('edit'),
                onDelete: () => log.add('delete'),
                onAddToPlaylist: () => log.add('playlist'),
                onRatingChanged: (r) => log.add('rate$r'),
                onFavoriteToggled: (f) => log.add('fav$f'),
              )
            : ClipListRow(
                clip: clip,
                onSelect: () => log.add('select'),
                onPlay: () => log.add('play'),
                onEdit: () => log.add('edit'),
                onDelete: () => log.add('delete'),
                onAddToPlaylist: () => log.add('playlist'),
                onRatingChanged: (r) => log.add('rate$r'),
                onFavoriteToggled: (f) => log.add('fav$f'),
              );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: mode == _Mode.grid ? 300 : 1000,
                  height: mode == _Mode.grid ? 300 : 96,
                  child: card(),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }

      Finder surface() =>
          find.byType(mode == _Mode.grid ? ClipCard : ClipListRow);

      // A point on the card body that is not on any button.
      Offset bodyPoint(WidgetTester tester) {
        final rect = tester.getRect(surface());
        return mode == _Mode.grid
            ? Offset(rect.left + 150, rect.top + 200)
            : Offset(rect.left + 6, rect.center.dy);
      }

      testWidgets('single click selects at once and does not play', (
        tester,
      ) async {
        await pump(tester);
        await tester.tapAt(bodyPoint(tester));
        expect(log, ['select'], reason: 'no wait for a double-tap window');
        await tester.pump(const Duration(milliseconds: 600));
        expect(log, ['select']);
      });

      testWidgets('double click plays exactly once', (tester) async {
        await pump(tester);
        final p = bodyPoint(tester);
        await tester.tapAt(p);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tapAt(p);
        await tester.pump(const Duration(milliseconds: 600));
        expect(log, ['select', 'select', 'play']);
        expect(log.where((e) => e == 'play').length, 1);
      });

      testWidgets('triple click does not play twice in a row', (tester) async {
        await pump(tester);
        final p = bodyPoint(tester);
        for (var i = 0; i < 3; i++) {
          await tester.tapAt(p);
          await tester.pump(const Duration(milliseconds: 80));
        }
        await tester.pump(const Duration(milliseconds: 600));
        expect(log.where((e) => e == 'play').length, 1);
      });

      testWidgets('two slow clicks never play', (tester) async {
        await pump(tester);
        final p = bodyPoint(tester);
        await tester.tapAt(p);
        await tester.pump(const Duration(milliseconds: 700));
        await tester.tapAt(p);
        await tester.pump(const Duration(milliseconds: 700));
        expect(log, ['select', 'select']);
      });

      testWidgets('right click selects, opens the menu, does not play', (
        tester,
      ) async {
        await pump(tester);
        final g = await tester.startGesture(
          bodyPoint(tester),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await g.up();
        await tester.pumpAndSettle();
        expect(log, ['select']);
        expect(find.text('编辑时间范围与元数据'), findsOneWidget);

        // Choosing an item runs only that item.
        await tester.tap(find.text('添加到播放列表'));
        await tester.pumpAndSettle();
        expect(log, ['select', 'playlist']);
      });

      testWidgets('menu "play" item plays once, without double select', (
        tester,
      ) async {
        await pump(tester);
        final g = await tester.startGesture(
          bodyPoint(tester),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await g.up();
        await tester.pumpAndSettle();
        await tester.tap(find.text('播放片段'));
        await tester.pumpAndSettle();
        expect(log, ['select', 'play']);
      });

      testWidgets('favorite and rating buttons never select or play', (
        tester,
      ) async {
        await pump(tester);
        await tester.tap(find.byTooltip('加入收藏'));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(find.byTooltip('评为 3 星'));
        await tester.pump(const Duration(milliseconds: 600));
        expect(log, ['favtrue', 'rate3']);
      });

      testWidgets('rapid double click on favorite does not play', (
        tester,
      ) async {
        await pump(tester);
        final fav = find.byTooltip('加入收藏');
        await tester.tap(fav);
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tap(fav);
        await tester.pump(const Duration(milliseconds: 600));
        expect(log.contains('play'), isFalse);
        expect(log.contains('select'), isFalse);
      });

      testWidgets('edit and add-to-playlist buttons only run themselves', (
        tester,
      ) async {
        await pump(tester);
        // Hover/focus reveals the overlay buttons in the grid card.
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(surface()));
        await tester.pump(const Duration(milliseconds: 200));

        await tester.tap(find.byTooltip(mode == _Mode.grid ? '编辑片段' : '编辑'));
        await tester.pump(const Duration(milliseconds: 100));
        if (mode == _Mode.grid) {
          await tester.tap(find.byTooltip('加入播放列表'));
          await tester.pump(const Duration(milliseconds: 600));
          expect(log, ['edit', 'playlist']);
        } else {
          await tester.pump(const Duration(milliseconds: 600));
          expect(log, ['edit']);
        }
      });

      testWidgets('explicit play button plays immediately, once', (
        tester,
      ) async {
        await pump(tester);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(surface()));
        await tester.pump(const Duration(milliseconds: 200));

        await tester.tap(find.byTooltip(mode == _Mode.grid ? '播放片段' : '播放'));
        await tester.pump(const Duration(milliseconds: 600));
        expect(log, ['play']);
      });

      testWidgets('Enter on the focused card plays; selection stays visible', (
        tester,
      ) async {
        await pump(tester);
        await tester.tapAt(bodyPoint(tester));
        await tester.pump(const Duration(milliseconds: 600));
        log.clear();
        // Focus the card surface itself, as Tab traversal would.
        final surfaceFocus = tester
            .widgetList<Focus>(
              find.descendant(of: surface(), matching: find.byType(Focus)),
            )
            .firstWhere((f) => f.focusNode?.debugLabel == 'MediaCardSurface');
        surfaceFocus.focusNode!.requestFocus();
        await tester.pump();
        expect(surfaceFocus.focusNode!.hasPrimaryFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(log, ['play']);
      });
    });
  }

  group('MediaCardInteractor', () {
    Future<List<String>> pumpGeneric(WidgetTester tester) async {
      final log = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: SizedBox(
                width: 200,
                height: 100,
                child: MediaCardInteractor(
                  onSelect: () => log.add('select'),
                  onActivate: () => log.add('play'),
                  onSecondaryTapDown: (_) => log.add('menu'),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      tooltip: 'inner',
                      icon: const Icon(Icons.star),
                      onPressed: () => log.add('inner'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      return log;
    }

    testWidgets('inner button taps do not bubble to the card', (tester) async {
      final log = await pumpGeneric(tester);
      await tester.tap(find.byTooltip('inner'));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.byTooltip('inner'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(log, ['inner', 'inner']);
    });

    testWidgets('Enter on an inner button does not play the card', (
      tester,
    ) async {
      final log = await pumpGeneric(tester);
      Focus.of(tester.element(find.byIcon(Icons.star))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(log.contains('play'), isFalse);
    });

    testWidgets('right click selects first, then opens the menu', (
      tester,
    ) async {
      final log = await pumpGeneric(tester);
      final g = await tester.startGesture(
        tester.getTopLeft(find.byType(MediaCardInteractor)) +
            const Offset(10, 10),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await g.up();
      await tester.pump();
      expect(log, ['select', 'menu']);
    });
  });
}
