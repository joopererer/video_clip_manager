import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_clip_manager/data/models.dart';
import 'package:video_clip_manager/utils/media_source.dart';

void main() {
  group('classifyMediaSource', () {
    test('local Windows paths, including Unicode and .m3u8', () {
      expect(classifyMediaSource(r'D:\视频\电影 01.mp4'), MediaSourceKind.local);
      expect(classifyMediaSource(r'C:\a\b\index.m3u8'), MediaSourceKind.local);
      expect(classifyMediaSource('/home/u/a.mkv'), MediaSourceKind.local);
    });

    test('http, https and other network schemes, case-insensitive', () {
      expect(
        classifyMediaSource('https://cdn.example.com/a/index.m3u8?token=1'),
        MediaSourceKind.network,
      );
      expect(
        classifyMediaSource('HTTP://example.com/x.m3u8'),
        MediaSourceKind.network,
      );
      expect(
        classifyMediaSource('rtmp://example.com/live/s'),
        MediaSourceKind.network,
      );
    });

    test('empty and host-less URLs are invalid', () {
      expect(classifyMediaSource(''), MediaSourceKind.invalid);
      expect(classifyMediaSource('   '), MediaSourceKind.invalid);
      expect(classifyMediaSource('https://'), MediaSourceKind.invalid);
      expect(classifyMediaSource('http:///x.m3u8'), MediaSourceKind.invalid);
    });
  });

  group('isM3u8Source', () {
    test('detects local and remote playlists, ignoring the query string', () {
      expect(isM3u8Source(r'C:\a\index.M3U8'), isTrue);
      expect(isM3u8Source('https://h/a/index.m3u8?sig=abc'), isTrue);
      expect(isM3u8Source('https://h/a/video.mp4'), isFalse);
      expect(isM3u8Source(r'D:\a\movie.mp4'), isFalse);
    });
  });

  group('resolveMediaSource', () {
    Future<bool> never(String _) async {
      fail('File existence must not be checked for this source');
    }

    test('existing local video is usable', () async {
      final r = await resolveMediaSource(
        r'D:\v\a.mp4',
        fileExists: (_) async => true,
      );
      expect(r.kind, MediaSourceKind.local);
      expect(r.isUsable, isTrue);
    });

    test('missing local video reports localFileMissing', () async {
      final r = await resolveMediaSource(
        r'D:\v\gone.mp4',
        fileExists: (_) async => false,
      );
      expect(r.failure, MediaSourceFailure.localFileMissing);
      expect(r.isUsable, isFalse);
    });

    test('existing local .m3u8 is usable; missing one is not', () async {
      final ok = await resolveMediaSource(
        r'D:\v\index.m3u8',
        fileExists: (_) async => true,
      );
      expect(ok.isUsable, isTrue);
      final missing = await resolveMediaSource(
        r'D:\v\index.m3u8',
        fileExists: (_) async => false,
      );
      expect(missing.failure, MediaSourceFailure.localFileMissing);
    });

    test('http and https m3u8 never hit the file system', () async {
      for (final url in [
        'http://example.com/live/index.m3u8',
        'https://example.com/a/index.m3u8?token=x&e=1',
      ]) {
        final r = await resolveMediaSource(url, fileExists: never);
        expect(r.kind, MediaSourceKind.network, reason: url);
        expect(r.isUsable, isTrue, reason: url);
      }
    });

    test('invalid URL and empty path are classified separately', () async {
      final bad = await resolveMediaSource('https://', fileExists: never);
      expect(bad.failure, MediaSourceFailure.invalidUrl);
      final empty = await resolveMediaSource('  ', fileExists: never);
      expect(empty.failure, MediaSourceFailure.emptyPath);
    });

    test('file check that throws is treated as missing', () async {
      final r = await resolveMediaSource(
        r'D:\v\a.mp4',
        fileExists: (_) async => throw const FormatException('boom'),
      );
      expect(r.failure, MediaSourceFailure.localFileMissing);
    });
  });

  group('error classification and messages', () {
    test('timeouts and other open errors are not "file missing"', () {
      expect(
        classifyOpenError(TimeoutException('t')),
        MediaSourceFailure.openTimeout,
      );
      expect(
        classifyOpenError(Exception('403 Forbidden')),
        MediaSourceFailure.openFailed,
      );
    });

    test('messages: only local failures say the file does not exist', () {
      const url = 'https://cdn.example.com/a/index.m3u8?token=secret';
      expect(
        mediaFailureMessage(MediaSourceFailure.openFailed, url),
        isNot(contains('文件不存在')),
      );
      expect(
        mediaFailureMessage(MediaSourceFailure.openFailed, url),
        isNot(contains('secret')),
        reason: 'query string (tokens) must not be shown',
      );
      expect(
        mediaFailureMessage(MediaSourceFailure.openTimeout, url),
        contains('超时'),
      );
      expect(
        mediaFailureMessage(MediaSourceFailure.localFileMissing, r'D:\v\a.mp4'),
        '文件不存在: a.mp4',
      );
      expect(mediaFailureMessage(MediaSourceFailure.none, 'x'), isNull);
    });
  });

  group('playlist time mapping with custom IN/OUT', () {
    VideoClip clip(String id, String path, int startMs, int endMs) => VideoClip(
      id: id,
      name: id,
      videoPath: path,
      startTime: Duration(milliseconds: startMs),
      endTime: Duration(milliseconds: endMs),
      coverFrameTime: Duration.zero,
    );

    test('custom range overrides clip range and stays in source time', () {
      final c = clip('c1', 'https://h/a.m3u8', 10000, 20000);
      final plain = PlaylistItem(id: 'i1', clipId: 'c1', order: 0);
      final custom = PlaylistItem(
        id: 'i2',
        clipId: 'c1',
        order: 1,
        customStartTime: const Duration(milliseconds: 12500),
        customEndTime: const Duration(milliseconds: 13250),
      );
      final a = PlaylistItemWithClip(item: plain, clip: c);
      final b = PlaylistItemWithClip(item: custom, clip: c);
      expect(a.effectiveDuration, const Duration(seconds: 10));
      expect(b.effectiveDuration, const Duration(milliseconds: 750));
    });

    test('accumulated playlist time is the sum, not source time', () {
      final c1 = clip('c1', r'D:\a.mp4', 60000, 65000);
      final c2 = clip('c2', 'https://h/b.m3u8', 3600000, 3603000);
      final items = [
        PlaylistItemWithClip(
          item: PlaylistItem(id: 'i1', clipId: 'c1', order: 0),
          clip: c1,
        ),
        PlaylistItemWithClip(
          item: PlaylistItem(id: 'i2', clipId: 'c2', order: 1),
          clip: c2,
        ),
      ];
      final total = items.fold<Duration>(
        Duration.zero,
        (s, e) => s + e.effectiveDuration,
      );
      expect(total, const Duration(seconds: 8));
    });
  });
}
