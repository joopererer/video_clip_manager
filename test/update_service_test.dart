import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:video_clip_manager/services/update_service.dart';
import 'package:video_clip_manager/utils/semver.dart';

UpdateService _service(Future<http.Response> Function(http.Request) handler) =>
    UpdateService(
      client: MockClient(handler),
      latestReleaseUri: Uri.parse('https://example.test/releases/latest'),
      timeout: const Duration(seconds: 5),
    );

const _jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

String _releaseJson({
  String tag = 'v1.2.0',
  String name = 'v1.2.0',
  String body = '- 新增内容',
  String publishedAt = '2026-10-01T12:00:00Z',
  bool prerelease = false,
  bool draft = false,
}) => jsonEncode({
  'tag_name': tag,
  'name': name,
  'body': body,
  'published_at': publishedAt,
  'html_url': 'https://github.com/joopererer/video_clip_manager/releases/tag/$tag',
  'prerelease': prerelease,
  'draft': draft,
});

void main() {
  group('SemanticVersion', () {
    test('parses tags with and without a v prefix', () {
      expect(SemanticVersion.tryParse('v1.2.3')!.toString(), '1.2.3');
      expect(SemanticVersion.tryParse('1.2.3')!.toString(), '1.2.3');
      expect(SemanticVersion.tryParse('1.2')!.toString(), '1.2.0');
      expect(SemanticVersion.tryParse('v1')!.toString(), '1.0.0');
      expect(SemanticVersion.tryParse('not-a-version'), isNull);
    });

    test('orders numerically, not lexicographically', () {
      final older = SemanticVersion.tryParse('1.9.0')!;
      final newer = SemanticVersion.tryParse('1.10.0')!;
      expect(newer.isNewerThan(older), isTrue);
      expect(older.isNewerThan(newer), isFalse);
      expect(
        SemanticVersion.tryParse('1.1.0')!.isNewerThan(
          SemanticVersion.tryParse('1.1.0')!,
        ),
        isFalse,
      );
    });

    test('a pre-release is older than its stable release', () {
      final beta = SemanticVersion.tryParse('1.1.0-beta.2')!;
      final stable = SemanticVersion.tryParse('1.1.0')!;
      expect(beta.isPrerelease, isTrue);
      expect(stable.isNewerThan(beta), isTrue);
      expect(beta.isNewerThan(stable), isFalse);
    });
  });

  group('UpdateService', () {
    test('reports a newer stable release as an update', () async {
      final result = await _service(
        (_) async => http.Response(_releaseJson(), 200, headers: _jsonHeaders),
      ).checkForUpdate(currentVersion: '1.1.0');

      expect(result.ok, isTrue);
      expect(result.updateAvailable, isTrue);
      expect(result.latest!.version, '1.2.0');
      expect(result.latest!.notes, contains('新增'));
      expect(result.latest!.htmlUrl, contains('/releases/tag/v1.2.0'));
      expect(result.latest!.publishedLabel, contains('2026-10-01'));
    });

    test('same version is not an update', () async {
      final result = await _service(
        (_) async => http.Response(_releaseJson(tag: 'v1.1.0'), 200, headers: _jsonHeaders),
      ).checkForUpdate(currentVersion: '1.1.0');

      expect(result.ok, isTrue);
      expect(result.updateAvailable, isFalse);
    });

    test('an older release is never offered as an update', () async {
      final result = await _service(
        (_) async => http.Response(_releaseJson(tag: 'v1.0.1'), 200, headers: _jsonHeaders),
      ).checkForUpdate(currentVersion: '1.1.0');

      expect(result.updateAvailable, isFalse);
    });

    test('prerelease and draft releases are ignored', () async {
      final pre = await _service(
        (_) async => http.Response(_releaseJson(prerelease: true), 200, headers: _jsonHeaders),
      ).checkForUpdate(currentVersion: '1.1.0');
      expect(pre.ok, isTrue);
      expect(pre.updateAvailable, isFalse);

      final draft = await _service(
        (_) async => http.Response(_releaseJson(draft: true), 200, headers: _jsonHeaders),
      ).checkForUpdate(currentVersion: '1.1.0');
      expect(draft.updateAvailable, isFalse);
    });

    test('404 means nothing is published yet, without throwing', () async {
      final result = await _service(
        (_) async => http.Response('{"message":"Not Found"}', 404),
      ).checkForUpdate(currentVersion: '1.1.0');

      expect(result.ok, isFalse);
      expect(result.error, contains('尚未发布'));
    });

    test('server errors become data, not exceptions', () async {
      final result = await _service(
        (_) async => http.Response('boom', 500),
      ).checkForUpdate(currentVersion: '1.1.0');

      expect(result.ok, isFalse);
      expect(result.error, contains('500'));
    });

    test('network failure becomes data, not exceptions', () async {
      final result = await _service(
        (_) async => throw http.ClientException('offline'),
      ).checkForUpdate(currentVersion: '1.1.0');

      expect(result.ok, isFalse);
      expect(result.error, contains('检查更新失败'));
    });

    test('malformed payload is reported as an error', () async {
      final result = await _service(
        (_) async => http.Response('not json', 200),
      ).checkForUpdate(currentVersion: '1.1.0');

      expect(result.ok, isFalse);
    });

    test('release without a valid tag is reported as an error', () async {
      final result = await _service(
        (_) async => http.Response(_releaseJson(tag: 'latest'), 200, headers: _jsonHeaders),
      ).checkForUpdate(currentVersion: '1.1.0');

      expect(result.ok, isFalse);
      expect(result.error, contains('版本号'));
    });

    test('sends no user data, only a plain GET', () async {
      late http.Request captured;
      await _service((request) async {
        captured = request;
        return http.Response(_releaseJson(), 200, headers: _jsonHeaders);
      }).checkForUpdate(currentVersion: '1.1.0');

      expect(captured.method, 'GET');
      expect(captured.url.query, isEmpty, reason: 'no payload in the query');
      expect(captured.body, isEmpty);
    });
  });
}
