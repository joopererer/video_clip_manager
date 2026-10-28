import 'package:flutter_test/flutter_test.dart';
import 'package:video_clip_manager/utils/playlist_playback_layout.dart';

void main() {
  group('playbackLayoutFor', () {
    test('uses bottom queue at 900 and just below the breakpoint', () {
      expect(playbackLayoutFor(900), PlaybackLayout.bottomQueue);
      expect(
        playbackLayoutFor(kPlaybackSideQueueBreakpoint - 1),
        PlaybackLayout.bottomQueue,
      );
    });

    test('uses side queue at the breakpoint, 1280 and 1600', () {
      expect(
        playbackLayoutFor(kPlaybackSideQueueBreakpoint),
        PlaybackLayout.sideQueue,
      );
      expect(playbackLayoutFor(1280), PlaybackLayout.sideQueue);
      expect(playbackLayoutFor(1600), PlaybackLayout.sideQueue);
    });

    test('side queue width grows on wide windows', () {
      expect(playbackSideQueueWidth(1280), 320);
      expect(playbackSideQueueWidth(1600), 380);
    });
  });

  group('playbackBottomQueueHeight', () {
    test('is clamped between 112 and 220', () {
      expect(playbackBottomQueueHeight(300), 112);
      expect(playbackBottomQueueHeight(700), closeTo(182, 0.001));
      expect(playbackBottomQueueHeight(2000), 220);
    });
  });

  group('queueScrollOffsetFor', () {
    test('returns 0 for empty lists or empty viewports', () {
      expect(
        queueScrollOffsetFor(
          index: 0,
          rowExtent: 60,
          viewport: 300,
          itemCount: 0,
        ),
        0,
      );
      expect(
        queueScrollOffsetFor(
          index: 3,
          rowExtent: 60,
          viewport: 0,
          itemCount: 10,
        ),
        0,
      );
    });

    test('stays at 0 when everything fits', () {
      expect(
        queueScrollOffsetFor(
          index: 2,
          rowExtent: 60,
          viewport: 600,
          itemCount: 5,
        ),
        0,
      );
    });

    test('centres a middle row', () {
      // 20 rows of 60 = 1200, viewport 300. Row 10 starts at 600; centred
      // offset = 600 - (300 - 60) / 2 = 480.
      expect(
        queueScrollOffsetFor(
          index: 10,
          rowExtent: 60,
          viewport: 300,
          itemCount: 20,
        ),
        480,
      );
    });

    test('clamps at both ends', () {
      expect(
        queueScrollOffsetFor(
          index: 0,
          rowExtent: 60,
          viewport: 300,
          itemCount: 20,
        ),
        0,
      );
      expect(
        queueScrollOffsetFor(
          index: 19,
          rowExtent: 60,
          viewport: 300,
          itemCount: 20,
        ),
        900,
      );
    });
  });

  group('playbackPercent', () {
    test('is 0 for an empty total', () {
      expect(playbackPercent(const Duration(seconds: 1), Duration.zero), 0);
    });

    test('uses milliseconds so sub-second playlists report progress', () {
      expect(
        playbackPercent(
          const Duration(milliseconds: 250),
          const Duration(milliseconds: 500),
        ),
        50,
      );
    });

    test('clamps to 0..100', () {
      expect(
        playbackPercent(
          const Duration(seconds: 20),
          const Duration(seconds: 10),
        ),
        100,
      );
      expect(
        playbackPercent(
          const Duration(seconds: -5),
          const Duration(seconds: 10),
        ),
        0,
      );
    });
  });
}
