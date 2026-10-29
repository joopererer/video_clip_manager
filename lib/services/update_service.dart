import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_info.dart';
import '../utils/semver.dart';

/// A GitHub release as shown in the "check for updates" sheet.
class ReleaseInfo {
  final String tagName;
  final String version;
  final String name;
  final String notes;
  final String htmlUrl;
  final DateTime? publishedAt;
  final bool isPrerelease;
  final bool isDraft;

  const ReleaseInfo({
    required this.tagName,
    required this.version,
    required this.name,
    required this.notes,
    required this.htmlUrl,
    this.publishedAt,
    this.isPrerelease = false,
    this.isDraft = false,
  });

  static ReleaseInfo? fromGitHubJson(Map<String, dynamic> json) {
    final tag = (json['tag_name'] as String?)?.trim() ?? '';
    final parsed = SemanticVersion.tryParse(tag);
    if (parsed == null) return null;
    final notes = (json['body'] as String?)?.trim() ?? '';
    final url = (json['html_url'] as String?)?.trim() ?? '';
    if (url.isEmpty) return null;
    return ReleaseInfo(
      tagName: tag,
      version: parsed.toString(),
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : tag,
      notes: notes,
      htmlUrl: url,
      publishedAt: DateTime.tryParse(
        (json['published_at'] as String?) ?? '',
      )?.toLocal(),
      isPrerelease: json['prerelease'] == true,
      isDraft: json['draft'] == true,
    );
  }

  String get publishedLabel {
    final at = publishedAt;
    if (at == null) return '发布日期未知';
    String two(int v) => v.toString().padLeft(2, '0');
    return '发布于 ${at.year}-${two(at.month)}-${two(at.day)}';
  }
}

/// Outcome of an update check. Failures are data, never exceptions, so the
/// caller can stay silent on network problems.
class UpdateCheckResult {
  final String currentVersion;
  final ReleaseInfo? latest;
  final bool updateAvailable;
  final String? error;

  const UpdateCheckResult({
    required this.currentVersion,
    this.latest,
    this.updateAvailable = false,
    this.error,
  });

  bool get ok => error == null;
  bool get hasUpdate => ok && updateAvailable;
}

/// Non-intrusive update check against the project's GitHub Releases.
///
/// The service only performs a GET on the public releases endpoint: no user
/// media, model or vector data is ever sent to it.
class UpdateService {
  final http.Client? client;
  final Uri latestReleaseUri;
  final Duration timeout;

  UpdateService({
    this.client,
    Uri? latestReleaseUri,
    this.timeout = const Duration(seconds: 10),
  }) : latestReleaseUri =
           latestReleaseUri ?? Uri.parse(AppInfo.latestReleaseApiUrl);

  static const String _userAgent = 'video_clip_manager-update-check';

  Future<UpdateCheckResult> checkForUpdate({
    required String currentVersion,
  }) async {
    final current = SemanticVersion.tryParse(currentVersion);
    if (current == null) {
      return UpdateCheckResult(
        currentVersion: currentVersion,
        error: '无法解析当前版本号：$currentVersion',
      );
    }

    final http.Client effectiveClient = client ?? http.Client();
    final bool ownsClient = client == null;

    try {
      final res = await effectiveClient
          .get(
            latestReleaseUri,
            headers: const {
              'Accept': 'application/vnd.github+json',
              'User-Agent': _userAgent,
            },
          )
          .timeout(timeout);

      if (res.statusCode == 404) {
        return UpdateCheckResult(
          currentVersion: currentVersion,
          error: '尚未发布任何正式版本',
        );
      }
      if (res.statusCode != 200) {
        return UpdateCheckResult(
          currentVersion: currentVersion,
          error: '更新服务返回 HTTP ${res.statusCode}',
        );
      }

      final decoded = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
      if (decoded is! Map<String, dynamic>) {
        return UpdateCheckResult(
          currentVersion: currentVersion,
          error: '更新信息格式无法识别',
        );
      }

      final release = ReleaseInfo.fromGitHubJson(decoded);
      if (release == null) {
        return UpdateCheckResult(
          currentVersion: currentVersion,
          error: '更新信息缺少有效版本号',
        );
      }

      // 预发布/草稿以及不高于当前版本的 tag 都不是"更新"
      if (release.isPrerelease || release.isDraft) {
        return UpdateCheckResult(
          currentVersion: currentVersion,
          latest: release,
        );
      }

      final latestVersion = SemanticVersion.tryParse(release.version);
      final updateAvailable =
          latestVersion != null && latestVersion.isNewerThan(current);

      return UpdateCheckResult(
        currentVersion: currentVersion,
        latest: release,
        updateAvailable: updateAvailable,
      );
    } on TimeoutException {
      return UpdateCheckResult(
        currentVersion: currentVersion,
        error: '检查更新超时，请稍后重试',
      );
    } catch (e) {
      return UpdateCheckResult(
        currentVersion: currentVersion,
        error: '检查更新失败：$e',
      );
    } finally {
      if (ownsClient) effectiveClient.close();
    }
  }
}
