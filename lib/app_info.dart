import 'package:package_info_plus/package_info_plus.dart';

/// Version and repository metadata for this build.
///
/// The displayed version always comes from the packaged build (on Windows the
/// EXE version resource written from `pubspec.yaml` through `Runner.rc`), so the
/// About dialog, the file properties and the release package cannot drift.
/// [fallbackVersion]/[fallbackBuildNumber] are only used when the platform
/// channel is unavailable (tests, or a host without the plugin registered) and
/// are pinned by `test/version_consistency_test.dart`.
class AppInfo {
  AppInfo._();

  static const String appDisplayName = 'Video Clip Manager';
  static const String repositoryUrl =
      'https://github.com/joopererer/video_clip_manager';
  static const String releasesUrl = '$repositoryUrl/releases';
  static const String licenseUrl = '$repositoryUrl/blob/master/LICENSE';
  static const String latestReleaseApiUrl =
      'https://api.github.com/repos/joopererer/video_clip_manager/releases/latest';

  static const String fallbackVersion = '1.1.0';
  static const String fallbackBuildNumber = '3';

  static const AppVersion fallback = AppVersion(
    version: fallbackVersion,
    buildNumber: fallbackBuildNumber,
  );

  static Future<AppVersion> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      if (version.isEmpty) return fallback;
      return AppVersion(
        version: version,
        buildNumber: info.buildNumber.trim(),
      );
    } catch (_) {
      return fallback;
    }
  }
}

class AppVersion {
  final String version;
  final String buildNumber;

  const AppVersion({required this.version, required this.buildNumber});

  /// `1.1.0`
  String get semver => version;

  /// `1.1.0+3`
  String get fullVersion =>
      buildNumber.isEmpty ? version : '$version+$buildNumber';

  /// `版本 1.1.0 · 构建 3`
  String get displayLabel =>
      buildNumber.isEmpty ? '版本 $version' : '版本 $version · 构建 $buildNumber';

  @override
  String toString() => fullVersion;
}
