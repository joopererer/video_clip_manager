import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_clip_manager/data/app_state.dart';
import 'package:video_clip_manager/data/models.dart';
import 'package:video_clip_manager/screens/tabs/videos_tab.dart';
import 'package:video_clip_manager/services/path_service.dart';
import 'package:video_clip_manager/services/thumbnail_service.dart';
import 'package:video_clip_manager/theme/app_theme.dart';

class _FakeThumbnailService extends Fake implements ThumbnailService {
  @override
  Future<String?> generateThumbnail(
    String videoPath,
    Duration time,
    String clipId, {
    String? dbPath,
  }) async => null;
}

class _Services {
  _Services(this.dir, this.state, this.paths, this.thumbs);
  final Directory dir;
  final AppState state;
  final PathService paths;
  final ThumbnailService thumbs;
}

Future<_Services> _createServices() async {
  final dir = await Directory.systemTemp.createTemp('videos_tab_test_');
  final db = File('${dir.path}/db.json');
  await db.writeAsString('[]');
  SharedPreferences.setMockInitialValues({'db_path': db.path});
  final prefs = await SharedPreferences.getInstance();
  final paths = PathService();
  final thumbs = _FakeThumbnailService();
  final state = AppState(
    prefs: prefs,
    pathService: paths,
    thumbnailService: thumbs,
  );
  await state.loadInitialData();
  state.addOriginalVideo(
    const OriginalVideo(
      id: 'v1',
      name: '原始视频 一.mp4',
      path: r'Z:\missing\one.mp4',
    ),
  );
  state.addOriginalVideo(
    const OriginalVideo(
      id: 'v2',
      name: '原始视频 二.mp4',
      path: r'Z:\missing\two.mp4',
    ),
  );
  return _Services(dir, state, paths, thumbs);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final grid in [true, false]) {
    final label = grid ? 'grid' : 'list';
    group('VideosTab card interaction ($label)', () {
      late List<String> opened;
      late List<String> previews;

      Future<_Services> pump(WidgetTester tester) async {
        opened = [];
        previews = [];
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final services = (await tester.runAsync(_createServices))!;
        services.state.setVideosViewMode(grid);
        addTearDown(() async {
          await services.state.forceSave();
          services.state.dispose();
          await services.dir.delete(recursive: true);
        });
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<PathService>.value(value: services.paths),
              Provider<ThumbnailService>.value(value: services.thumbs),
              ChangeNotifierProvider<AppState>.value(value: services.state),
            ],
            child: MaterialApp(
              theme: AppTheme.darkTheme,
              home: Scaffold(
                body: VideosTab(
                  searchQuery: '',
                  selectedTags: const [],
                  onOpenEditor: (_, video) => opened.add(video.id as String),
                  onOpenPreview: (_, video) => previews.add(video.id as String),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        return services;
      }

      Finder card(String name) =>
          find.ancestor(of: find.text(name), matching: find.byType(Card)).first;

      Offset body(WidgetTester tester, String name) {
        final rect = tester.getRect(card(name));
        return grid
            ? Offset(rect.center.dx, rect.top + 20)
            // Card's rect includes its 8px margin; aim at the thumbnail area.
            : Offset(rect.left + 40, rect.center.dy);
      }

      bool selected(WidgetTester tester, String name) {
        final shape = tester.widget<Card>(card(name)).shape;
        return shape is RoundedRectangleBorder && shape.side.width > 0;
      }

      testWidgets('single click selects at once and opens nothing', (
        tester,
      ) async {
        await pump(tester);
        expect(selected(tester, '原始视频 一.mp4'), isFalse);
        await tester.tapAt(body(tester, '原始视频 一.mp4'));
        await tester.pump();
        expect(selected(tester, '原始视频 一.mp4'), isTrue);
        expect(selected(tester, '原始视频 二.mp4'), isFalse);
        await tester.pump(const Duration(milliseconds: 600));
        expect(opened, isEmpty);
      });

      testWidgets('selection moves to the last clicked card', (tester) async {
        await pump(tester);
        await tester.tapAt(body(tester, '原始视频 一.mp4'));
        await tester.pump(const Duration(milliseconds: 600));
        await tester.tapAt(body(tester, '原始视频 二.mp4'));
        await tester.pump(const Duration(milliseconds: 600));
        expect(selected(tester, '原始视频 一.mp4'), isFalse);
        expect(selected(tester, '原始视频 二.mp4'), isTrue);
      });

      testWidgets('double click opens the preview once, not the editor', (
        tester,
      ) async {
        await pump(tester);
        final p = body(tester, '原始视频 一.mp4');
        await tester.tapAt(p);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tapAt(p);
        await tester.pump(const Duration(milliseconds: 600));
        expect(previews, ['v1']);
        expect(opened, isEmpty);
      });

      testWidgets('double click does not open on a different card', (
        tester,
      ) async {
        await pump(tester);
        await tester.tapAt(body(tester, '原始视频 一.mp4'));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tapAt(body(tester, '原始视频 二.mp4'));
        await tester.pump(const Duration(milliseconds: 600));
        expect(
          previews.length,
          lessThanOrEqualTo(1),
          reason: 'one tap per card must never open two previews',
        );
        expect(opened, isEmpty);
      });

      testWidgets('right click selects and shows Play and Create Clip', (
        tester,
      ) async {
        await pump(tester);
        final g = await tester.startGesture(
          body(tester, '原始视频 一.mp4'),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await g.up();
        await tester.pumpAndSettle();
        expect(selected(tester, '原始视频 一.mp4'), isTrue);
        expect(find.text('Play'), findsOneWidget);
        expect(find.text('Create Clip'), findsOneWidget);
        expect(find.text('Delete Video'), findsOneWidget);
        expect(opened, isEmpty);
        expect(previews, isEmpty);

        await tester.tap(find.text('Create Clip'));
        await tester.pumpAndSettle();
        expect(opened, ['v1']);
        expect(previews, isEmpty);
      });

      testWidgets('right click Play opens the preview, not the editor', (
        tester,
      ) async {
        await pump(tester);
        final g = await tester.startGesture(
          body(tester, '原始视频 一.mp4'),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await g.up();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Play'));
        await tester.pumpAndSettle();
        expect(previews, ['v1']);
        expect(opened, isEmpty);
      });

      testWidgets('Preview button opens the preview and does not select', (
        tester,
      ) async {
        await pump(tester);
        final button = find.descendant(
          of: card('原始视频 一.mp4'),
          matching: find.byTooltip('Preview'),
        );
        expect(button, findsOneWidget);
        await tester.tap(button);
        await tester.pump(const Duration(milliseconds: 600));
        expect(previews, ['v1']);
        expect(opened, isEmpty);
        expect(selected(tester, '原始视频 一.mp4'), isFalse);
      });

      testWidgets('explicit Create Clip button stays available and works', (
        tester,
      ) async {
        await pump(tester);
        final button = find.descendant(
          of: card('原始视频 一.mp4'),
          matching: find.byTooltip('Create Clip'),
        );
        expect(button, findsOneWidget);
        await tester.tap(button);
        await tester.pump(const Duration(milliseconds: 600));
        expect(opened, ['v1']);
        expect(
          selected(tester, '原始视频 一.mp4'),
          isFalse,
          reason: 'a button must not select the card',
        );
      });

      testWidgets('more menu button does not select or open', (tester) async {
        await pump(tester);
        final more = find.descendant(
          of: card('原始视频 一.mp4'),
          matching: find.byTooltip('More'),
        );
        await tester.tap(more);
        await tester.pumpAndSettle();
        expect(find.text('Clip from Whole Video'), findsOneWidget);
        expect(opened, isEmpty);
        expect(selected(tester, '原始视频 一.mp4'), isFalse);
      });
    });
  }
}
