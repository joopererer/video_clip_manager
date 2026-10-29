import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_clip_manager/app_info.dart';
import 'package:video_clip_manager/utils/semver.dart';

/// The About dialog, the EXE file properties and the release package must all
/// report the same version. `Runner.rc` derives its version from the pubspec
/// through the Flutter CMake glue, so pinning pubspec ↔ AppInfo is enough.
void main() {
  final pubspec = File('pubspec.yaml');
  final runnerRc = File('windows/runner/Runner.rc');

  test('pubspec.yaml, AppInfo fallback and Runner.rc agree on the version', () {
    expect(pubspec.existsSync(), isTrue, reason: 'run from the repo root');

    final line = pubspec
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'), orElse: () => '');
    expect(line, isNotEmpty, reason: 'pubspec.yaml has a version line');

    final raw = line.split(':').last.trim(); // e.g. 1.1.0+3
    final parts = raw.split('+');
    final version = parts.first;
    final buildNumber = parts.length > 1 ? parts[1] : '';

    expect(
      version,
      AppInfo.fallbackVersion,
      reason: 'AppInfo.fallbackVersion must match pubspec.yaml',
    );
    expect(
      buildNumber,
      AppInfo.fallbackBuildNumber,
      reason: 'AppInfo.fallbackBuildNumber must match pubspec.yaml',
    );
    expect(
      SemanticVersion.tryParse(version),
      isNotNull,
      reason: 'version must be valid SemVer for the update check',
    );
  });

  test('Runner.rc keeps deriving the file version from the Flutter defines', () {
    expect(runnerRc.existsSync(), isTrue);
    final content = runnerRc.readAsStringSync();
    expect(content, contains('FLUTTER_VERSION_MAJOR'));
    expect(content, contains('VERSION_AS_NUMBER FLUTTER_VERSION_MAJOR'));
    expect(content, contains('VALUE "ProductVersion", VERSION_AS_STRING'));
    expect(content, contains('VALUE "ProductName", "Video Clip Manager"'));
  });

  test('AppVersion formats version, build and label', () {
    const version = AppVersion(version: '1.1.0', buildNumber: '3');
    expect(version.semver, '1.1.0');
    expect(version.fullVersion, '1.1.0+3');
    expect(version.displayLabel, contains('1.1.0'));
    expect(version.displayLabel, contains('3'));
  });

  test('the repository and release URLs point at the official project', () {
    expect(AppInfo.repositoryUrl, 'https://github.com/joopererer/video_clip_manager');
    expect(AppInfo.releasesUrl, startsWith(AppInfo.repositoryUrl));
    expect(AppInfo.latestReleaseApiUrl, contains('api.github.com'));
    expect(
      AppInfo.latestReleaseApiUrl,
      endsWith('/releases/latest'),
      reason: 'the latest-release endpoint already skips pre-releases',
    );
  });
}
