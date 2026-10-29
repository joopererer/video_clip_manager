import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_clip_manager/data/app_state.dart';
import 'package:video_clip_manager/data/models.dart';
import 'package:video_clip_manager/screens/tabs/videos_tab.dart';
import 'package:video_clip_manager/services/path_service.dart';
import 'package:video_clip_manager/services/thumbnail_service.dart';
import 'package:video_clip_manager/theme/app_theme.dart';
import 'package:video_clip_manager/utils/media_source.dart';
import 'package:video_clip_manager/utils/preview_source.dart';
import 'package:video_clip_manager/widgets/video_preview/preview_playback.dart';
import 'package:video_clip_manager/widgets/video_preview/video_preview_dialog.dart';

/// In-memory stand-in for the media_kit player. It counts creation, opening
/// and disposal so lifecycle rules can be asserted without native libraries.
class FakePlayback implements PreviewPlayback {
  FakePlayback(this.log) {
    log.created++;
  }

  final PlaybackLog log;
  final _playing = StreamController<bool>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _error = StreamController<String>.broadcast();
  final _width = StreamController<int?>.broadcast();
  final _height = StreamController<int?>.broadcast();

  bool _isPlaying = false;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  double _volume = 100;
  bool disposed = false;
  String? openedSource;

  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<Duration> get positionStream => _position.stream;
  @override
  Stream<Duration> get durationStream => _duration.stream;
  @override
  Stream<String> get errorStream => _error.stream;
  @override
  Stream<int?> get widthStream => _width.stream;
  @override
  Stream<int?> get heightStream => _height.stream;

  @override
  bool get isPlaying => _isPlaying;
  @override
  Duration get position => _pos;
  @override
  Duration get duration => _dur;
  @override
  double get volume => _volume;
  @override
  int? get width => 1920;
  @override
  int? get height => 1080;

  @override
  Future<void> open(String source, {Map<String, String>? httpHeaders}) async {
    log.opened++;
    openedSource = source;
    _dur = const Duration(minutes: 2);
    _duration.add(_dur);
    _width.add(1080);
    _height.add(1920);
    _isPlaying = true;
    _playing.add(true);
  }

  @override
  Future<void> play() async {
    _isPlaying = true;
    _playing.add(true);
  }

  @override
  Future<void> pause() async {
    _isPlaying = false;
    _playing.add(false);
  }

  @override
  Future<void> seek(Duration position) async {
    log.seeks.add(position);
    _pos = position;
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    log.volumes.add(volume);
  }

  @override
  Widget buildVideo() => ColoredBox(
    key: ValueKey('fake-video-${identityHashCode(this)}'),
    color: Colors.black,
  );

  @override
  Future<void> dispose() async {
    assert(!disposed, 'player disposed twice');
    disposed = true;
    log.disposed++;
    await _playing.close();
    await _position.close();
    await _duration.close();
    await _error.close();
    await _width.close();
    await _height.close();
  }
}

class PlaybackLog {
  int created = 0;
  int opened = 0;
  int disposed = 0;
  int prepared = 0;
  int released = 0;
  int nativeEnter = 0;
  int nativeExit = 0;
  final List<Duration> seeks = [];
  final List<double> volumes = [];
  final List<String> events = [];
  FakePlayback? last;
}

VideoPreviewEnvironment fakeEnvironment(
  PlaybackLog log, {
  PreviewSource? source,
}) {
  return VideoPreviewEnvironment(
    createPlayback: () {
      final p = FakePlayback(log);
      log.last = p;
      return p;
    },
    resolveSource: (_) async =>
        source ??
        const PreviewSource.playable(
          path: r'D:\视频 库\竖屏 clip.mp4',
          kind: MediaSourceKind.local,
        ),
    prepare: () async {
      log.prepared++;
      log.events.add('prepare');
    },
    release: () {
      log.released++;
      log.events.add('release');
    },
    enterNativeFullscreen: () async => log.nativeEnter++,
    exitNativeFullscreen: () async => log.nativeExit++,
  );
}

const _video = OriginalVideo(
  id: 'v1',
  name: '原始视频 一.mp4',
  path: r'D:\视频 库\竖屏 clip.mp4',
  duration: Duration(minutes: 2),
);

/// Opens the dialog from a button and records the result.
Widget host(
  PlaybackLog log, {
  Object video = _video,
  PreviewSource? source,
  void Function(PreviewAction?)? onResult,
}) {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () async {
              final result = await VideoPreviewDialog.show(
                context,
                video,
                clipCount: 3,
                environment: fakeEnvironment(log, source: source),
              );
              onResult?.call(result);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void sizeWindow(WidgetTester tester, [Size size = const Size(1280, 800)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _FakeThumbnailService extends Fake implements ThumbnailService {
  @override
  Future<String?> generateThumbnail(
    String videoPath,
    Duration time,
    String clipId, {
    String? dbPath,
  }) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('preview source rules', () {
    test('local file that exists is playable', () async {
      final s = await resolvePreviewSource(
        _video,
        fileExists: (_) async => true,
      );
      expect(s.isPlayable, isTrue);
      expect(s.kind, MediaSourceKind.local);
    });

    test('missing local file reports the file as missing', () async {
      final s = await resolvePreviewSource(
        _video,
        fileExists: (_) async => false,
      );
      expect(s.isPlayable, isFalse);
      expect(s.failureMessage, contains('文件不存在'));
    });

    test('local .m3u8 must exist, network .m3u8 is never checked', () async {
      final local = await resolvePreviewSource(
        const OriginalVideo(id: 'a', name: 'a', path: r'C:\x\list.m3u8'),
        fileExists: (_) async => false,
      );
      expect(local.isPlayable, isFalse);

      final net = await resolvePreviewSource(
        const OriginalVideo(
          id: 'b',
          name: 'b',
          path: 'https://cdn.example.com/a/index.m3u8?token=1',
        ),
        fileExists: (_) async => throw StateError('must not touch disk'),
      );
      expect(net.isPlayable, isTrue);
      expect(net.isNetwork, isTrue);
    });

    test('online video with a direct HLS url is playable', () async {
      final s = await resolvePreviewSource(
        const OnlineVideo(
          id: 'o',
          url: 'https://cdn.example.com/live/index.m3u8',
          title: 't',
          platform: 'unknown',
        ),
      );
      expect(s.isPlayable, isTrue);
      expect(s.path, 'https://cdn.example.com/live/index.m3u8');
    });

    test('online page url without a cached link is not playable', () async {
      final s = await resolvePreviewSource(
        const OnlineVideo(
          id: 'o',
          url: 'https://www.youtube.com/watch?v=abc',
          title: 't',
          platform: 'youtube',
        ),
      );
      expect(s.isPlayable, isFalse);
      expect(s.failureMessage, kPreviewNoDirectLink);
    });

    test(
      'online video prefers a fresh cached direct link and headers',
      () async {
        final s = await resolvePreviewSource(
          OnlineVideo(
            id: 'o',
            url: 'https://www.youtube.com/watch?v=abc',
            title: 't',
            platform: 'youtube',
            metadata: {
              'videoUrl': 'https://rr.example.com/video.mp4',
              'urlTimestamp': DateTime.now().toIso8601String(),
              'httpHeaders': {'Referer': 'https://www.youtube.com'},
            },
          ),
        );
        expect(s.isPlayable, isTrue);
        expect(s.path, 'https://rr.example.com/video.mp4');
        expect(s.httpHeaders['Referer'], 'https://www.youtube.com');
        expect(s.httpHeaders['User-Agent'], kPreviewUserAgent);
      },
    );

    test('expired cached link falls back to the page url rule', () async {
      final s = await resolvePreviewSource(
        OnlineVideo(
          id: 'o',
          url: 'https://www.youtube.com/watch?v=abc',
          title: 't',
          platform: 'youtube',
          metadata: {
            'videoUrl': 'https://rr.example.com/video.mp4',
            'urlTimestamp': DateTime.now()
                .subtract(const Duration(days: 3))
                .toIso8601String(),
          },
        ),
      );
      expect(s.isPlayable, isFalse);
    });

    test('formatPreviewClock', () {
      expect(formatPreviewClock(Duration.zero), '0:00');
      expect(formatPreviewClock(const Duration(seconds: 65)), '1:05');
      expect(formatPreviewClock(const Duration(seconds: 3725)), '1:02:05');
      expect(formatPreviewClock(const Duration(seconds: -4)), '0:00');
    });
  });

  group('VideoPreviewDialog lifecycle', () {
    testWidgets('shows name and facts, uses exactly one player', (
      tester,
    ) async {
      sizeWindow(tester);
      final log = PlaybackLog();
      await tester.pumpWidget(host(log));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('原始视频 一.mp4'), findsOneWidget);
      expect(find.textContaining('Local file'), findsOneWidget);
      expect(find.textContaining('3 clips'), findsOneWidget);
      expect(find.textContaining('1080×1920'), findsOneWidget);
      expect(find.textContaining('portrait'), findsOneWidget);
      expect(log.created, 1);
      expect(log.opened, 1);
      expect(log.prepared, 1);
      expect(log.last!.openedSource, r'D:\视频 库\竖屏 clip.mp4');
      expect(find.text('Create Clip'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
    });

    testWidgets('closing disposes the player once and releases services', (
      tester,
    ) async {
      sizeWindow(tester);
      final log = PlaybackLog();
      await tester.pumpWidget(host(log));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.byType(VideoPreviewDialog), findsNothing);
      expect(log.disposed, 1);
      expect(log.last!.disposed, isTrue);
      expect(log.released, 1);
    });

    testWidgets('Esc closes the dialog and releases the player', (
      tester,
    ) async {
      sizeWindow(tester);
      final log = PlaybackLog();
      await tester.pumpWidget(host(log));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(VideoPreviewDialog), findsNothing);
      expect(log.disposed, 1);
      expect(log.released, 1);
    });

    testWidgets('ten open/close rounds create and dispose ten players', (
      tester,
    ) async {
      sizeWindow(tester);
      final log = PlaybackLog();
      await tester.pumpWidget(host(log));
      for (var i = 0; i < 10; i++) {
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(log.created - log.disposed, 1, reason: 'round $i: one live');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(log.created - log.disposed, 0, reason: 'round $i: none live');
      }
      expect(log.created, 10);
      expect(log.disposed, 10);
      expect(log.released, 10);
    });

    testWidgets('missing file shows the message and creates no player', (
      tester,
    ) async {
      sizeWindow(tester);
      final log = PlaybackLog();
      await tester.pumpWidget(
        host(log, source: const PreviewSource.failed('文件不存在: 竖屏 clip.mp4')),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('文件不存在: 竖屏 clip.mp4'), findsOneWidget);
      expect(log.created, 0);
      final play = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.play_arrow),
      );
      expect(play.onPressed, isNull);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(log.disposed, 0);
      expect(log.released, 1);
    });
  });

  group('VideoPreviewDialog transport', () {
    testWidgets('play/pause toggles and shows position / duration', (
      tester,
    ) async {
      sizeWindow(tester);
      final log = PlaybackLog();
      await tester.pumpWidget(host(log));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // fake opens in the playing state
      expect(find.byTooltip('Pause'), findsOneWidget);
      expect(find.text('2:00'), findsWidgets);
      expect(find.text('0:00'), findsWidgets);

      await tester.tap(find.byTooltip('Pause'));
      await tester.pumpAndSettle();
      expect(log.last!.isPlaying, isFalse);
      expect(find.byTooltip('Play'), findsOneWidget);

      await tester.tap(find.byTooltip('Play'));
      await tester.pumpAndSettle();
      expect(log.last!.isPlaying, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    });

    testWidgets('dragging the slider seeks once to the released position', (
      tester,
    ) async {
      sizeWindow(tester);
      final log = PlaybackLog();
      await tester.pumpWidget(host(log));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final slider = find.byType(Slider);
      final rect = tester.getRect(slider);
      await tester.dragFrom(
        Offset(rect.left + 24, rect.center.dy),
        Offset(rect.width / 2, 0),
      );
      await tester.pumpAndSettle();

      expect(log.seeks, hasLength(1));
      final ms = log.seeks.single.inMilliseconds;
      expect(ms, greaterThan(30000));
      expect(ms, lessThan(100000));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    });

    testWidgets('mute sets volume 0 and unmute restores it', (tester) async {
      sizeWindow(tester);
      final log = PlaybackLog();
      await tester.pumpWidget(host(log));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Mute'));
      await tester.pumpAndSettle();
      expect(log.volumes, [0]);
      expect(find.byTooltip('Unmute'), findsOneWidget);

      await tester.tap(find.byTooltip('Unmute'));
      await tester.pumpAndSettle();
      expect(log.volumes, [0, 100]);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    });
  });

  group('VideoPreviewDialog fullscreen', () {
    testWidgets('toggle enters and exits without creating another player', (
      tester,
    ) async {
      sizeWindow(tester);
      final log = PlaybackLog();
      await tester.pumpWidget(host(log));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final player = log.last!;

      await tester.tap(find.byTooltip('Fullscreen'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Exit Fullscreen'), findsOneWidget);
      expect(log.nativeEnter, 1);
      expect(log.created, 1, reason: 'fullscreen must reuse the player');
      expect(log.disposed, 0);

      await tester.tap(find.byTooltip('Exit Fullscreen'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Fullscreen'), findsOneWidget);
      expect(log.nativeExit, 1);
      expect(log.created, 1);
      expect(log.disposed, 0);
      expect(identical(log.last, player), isTrue);
      expect(find.byType(VideoPreviewDialog), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(log.disposed, 1);
    });

    testWidgets('Esc leaves fullscreen first and keeps the dialog open', (
      tester,
    ) async {
      sizeWindow(tester);
      final log = PlaybackLog();
      await tester.pumpWidget(host(log));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Fullscreen'));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(VideoPreviewDialog), findsOneWidget);
      expect(find.byTooltip('Fullscreen'), findsOneWidget);
      expect(log.nativeExit, 1);
      expect(log.disposed, 0);
      expect(log.created, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(VideoPreviewDialog), findsNothing);
      expect(log.disposed, 1);
    });

    testWidgets('repeated fullscreen round trips keep one player', (
      tester,
    ) async {
      sizeWindow(tester);
      final log = PlaybackLog();
      await tester.pumpWidget(host(log));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip('Fullscreen'));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }
      expect(log.created, 1);
      expect(log.nativeEnter, 3);
      expect(log.nativeExit, 3);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(log.disposed, 1);
    });
  });

  group('Create Clip from the preview', () {
    testWidgets('releases the player before the dialog returns', (
      tester,
    ) async {
      sizeWindow(tester);
      final log = PlaybackLog();
      PreviewAction? result;
      var disposedWhenReturned = false;
      await tester.pumpWidget(
        host(
          log,
          onResult: (r) {
            result = r;
            disposedWhenReturned = log.last!.disposed;
          },
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create Clip'));
      await tester.pumpAndSettle();

      expect(result, PreviewAction.createClip);
      expect(disposedWhenReturned, isTrue);
      expect(log.disposed, 1);
      expect(log.released, 1);
      expect(find.byType(VideoPreviewDialog), findsNothing);
    });

    testWidgets('a second tap on Create Clip does not dispose twice', (
      tester,
    ) async {
      sizeWindow(tester);
      final log = PlaybackLog();
      await tester.pumpWidget(host(log));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create Clip'));
      await tester.pump();
      await tester.tap(find.text('Create Clip'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(log.disposed, 1);
      expect(log.released, 1);
    });
  });

  group('VideosTab to preview to editor', () {
    late Directory dir;
    late AppState state;
    late PathService paths;
    late ThumbnailService thumbs;

    Future<void> pumpTab(
      WidgetTester tester,
      PlaybackLog log,
      List<String> editorOpened,
      List<int> editorLiveWhenOpened, {
      bool grid = true,
    }) async {
      sizeWindow(tester);
      await tester.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('preview_flow_');
        final db = File('${dir.path}/db.json');
        await db.writeAsString('[]');
        SharedPreferences.setMockInitialValues({'db_path': db.path});
        final prefs = await SharedPreferences.getInstance();
        paths = PathService();
        thumbs = _FakeThumbnailService();
        state = AppState(
          prefs: prefs,
          pathService: paths,
          thumbnailService: thumbs,
        );
        await state.loadInitialData();
      });
      state.addOriginalVideo(_video);
      state.setVideosViewMode(grid);
      addTearDown(() async {
        await state.forceSave();
        state.dispose();
        await dir.delete(recursive: true);
      });
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<PathService>.value(value: paths),
            Provider<ThumbnailService>.value(value: thumbs),
            ChangeNotifierProvider<AppState>.value(value: state),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: VideosTab(
                searchQuery: '',
                selectedTags: const [],
                previewEnvironment: fakeEnvironment(log),
                onOpenEditor: (_, video) {
                  editorOpened.add(video.id as String);
                  editorLiveWhenOpened.add(log.created - log.disposed);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Offset cardPoint(WidgetTester tester, bool grid) {
      final card = find
          .ancestor(of: find.text('原始视频 一.mp4'), matching: find.byType(Card))
          .first;
      final rect = tester.getRect(card);
      return grid
          ? Offset(rect.center.dx, rect.top + 20)
          : Offset(rect.left + 40, rect.center.dy);
    }

    for (final grid in [true, false]) {
      final label = grid ? 'grid' : 'list';

      testWidgets('double click opens one preview dialog, not the editor '
          '($label)', (tester) async {
        final log = PlaybackLog();
        final editor = <String>[];
        await pumpTab(tester, log, editor, [], grid: grid);

        final p = cardPoint(tester, grid);
        await tester.tapAt(p);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tapAt(p);
        await tester.pumpAndSettle();

        expect(find.byType(VideoPreviewDialog), findsOneWidget);
        expect(log.created, 1);
        expect(editor, isEmpty);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(log.disposed, 1);
        expect(editor, isEmpty);
      });

      testWidgets('triple click still opens one player ($label)', (
        tester,
      ) async {
        final log = PlaybackLog();
        await pumpTab(tester, log, [], [], grid: grid);

        // The third click may land on the dialog barrier (list mode: the
        // card sits left of the centred dialog), which closes it. Either
        // way there must never be a second player.
        final p = cardPoint(tester, grid);
        for (var i = 0; i < 3; i++) {
          await tester.tapAt(p);
          await tester.pump(const Duration(milliseconds: 60));
        }
        await tester.pumpAndSettle();

        expect(log.created, 1);
        expect(
          find.byType(VideoPreviewDialog).evaluate().length,
          lessThanOrEqualTo(1),
        );

        if (find.byType(VideoPreviewDialog).evaluate().isNotEmpty) {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
        }
        expect(find.byType(VideoPreviewDialog), findsNothing);
        expect(log.disposed, 1, reason: 'the single player is released');
      });

      testWidgets('Preview button opens the dialog ($label)', (tester) async {
        final log = PlaybackLog();
        final editor = <String>[];
        await pumpTab(tester, log, editor, [], grid: grid);

        await tester.tap(find.byTooltip('Preview'));
        await tester.pumpAndSettle();
        expect(find.byType(VideoPreviewDialog), findsOneWidget);
        expect(editor, isEmpty);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(log.disposed, 1);
      });

      testWidgets('scissors button opens the editor without any player '
          '($label)', (tester) async {
        final log = PlaybackLog();
        final editor = <String>[];
        await pumpTab(tester, log, editor, [], grid: grid);

        await tester.tap(find.byTooltip('Create Clip'));
        await tester.pumpAndSettle();

        expect(editor, ['v1']);
        expect(find.byType(VideoPreviewDialog), findsNothing);
        expect(log.created, 0);
      });

      testWidgets('right click Play and Create Clip route correctly '
          '($label)', (tester) async {
        final log = PlaybackLog();
        final editor = <String>[];
        await pumpTab(tester, log, editor, [], grid: grid);

        Future<void> rightClick() async {
          final g = await tester.startGesture(
            cardPoint(tester, grid),
            kind: PointerDeviceKind.mouse,
            buttons: kSecondaryMouseButton,
          );
          await g.up();
          await tester.pumpAndSettle();
        }

        await rightClick();
        await tester.tap(find.text('Play'));
        await tester.pumpAndSettle();
        expect(find.byType(VideoPreviewDialog), findsOneWidget);
        expect(editor, isEmpty);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(log.disposed, 1);

        await rightClick();
        await tester.tap(find.text('Create Clip'));
        await tester.pumpAndSettle();
        expect(editor, ['v1']);
        expect(log.created, 1, reason: 'the editor path adds no preview');
      });

      testWidgets('Create Clip in the preview opens the editor only after '
          'the preview player is gone ($label)', (tester) async {
        final log = PlaybackLog();
        final editor = <String>[];
        final live = <int>[];
        await pumpTab(tester, log, editor, live, grid: grid);

        await tester.tap(find.byTooltip('Preview'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Create Clip'));
        await tester.pumpAndSettle();

        expect(editor, ['v1']);
        expect(live, [0], reason: 'no preview player alive at editor open');
        expect(log.created, 1);
        expect(log.disposed, 1);
        expect(log.released, 1);
        expect(find.byType(VideoPreviewDialog), findsNothing);
      });
    }
  });
}
