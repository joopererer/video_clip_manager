import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';
import '../services/update_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// About sheet: version, build number, repository and license entry points plus
/// a manual, opt-in update check.
///
/// Everything shown here is derived from the packaged build ([AppVersion]) and
/// the public GitHub release feed; nothing about the user's library, models or
/// vectors leaves the machine.
class AppAboutDialog extends StatefulWidget {
  /// Injected for tests; production loads the packaged version.
  final AppVersion? version;

  /// Injected for tests; production hits GitHub Releases.
  final UpdateService? updateService;

  const AppAboutDialog({super.key, this.version, this.updateService});

  @override
  State<AppAboutDialog> createState() => _AppAboutDialogState();
}

enum _UpdateState { idle, checking, done, failed }

class _AppAboutDialogState extends State<AppAboutDialog> {
  AppVersion? _version;
  _UpdateState _updateState = _UpdateState.idle;
  UpdateCheckResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _version = widget.version;
    if (_version == null) {
      AppInfo.load().then((value) {
        if (mounted) setState(() => _version = value);
      });
    }
  }

  Future<void> _checkForUpdates() async {
    if (_updateState == _UpdateState.checking) return;
    final version = _version ?? AppInfo.fallback;
    setState(() {
      _updateState = _UpdateState.checking;
      _error = null;
      _result = null;
    });

    final service = widget.updateService ?? UpdateService();
    final result = await service.checkForUpdate(currentVersion: version.semver);

    if (!mounted) return;
    setState(() {
      _result = result;
      if (result.ok) {
        _updateState = _UpdateState.done;
      } else {
        _updateState = _UpdateState.failed;
        _error = result.error;
      }
    });
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开链接：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final version = _version;

    return AlertDialog(
      backgroundColor: colors.surface,
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(Icons.movie_filter, color: colors.primary, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppInfo.appDisplayName,
                  style: AppTypography.sectionTitle.copyWith(fontSize: 17),
                ),
                Text(
                  version == null ? '正在读取版本信息…' : version.displayLabel,
                  key: const Key('about-version-label'),
                  style: AppTypography.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _infoRow(
                context,
                icon: Icons.tag,
                label: '版本号',
                value: version?.version ?? AppInfo.fallback.version,
                valueKey: const Key('about-version-value'),
              ),
              _infoRow(
                context,
                icon: Icons.build_outlined,
                label: '构建号',
                value: version?.buildNumber ?? AppInfo.fallback.buildNumber,
                valueKey: const Key('about-build-value'),
              ),
              _infoRow(
                context,
                icon: Icons.code,
                label: '开源仓库',
                value: AppInfo.repositoryUrl,
                onTap: () => _openUrl(AppInfo.repositoryUrl),
                valueKey: const Key('about-repo-value'),
              ),
              _infoRow(
                context,
                icon: Icons.description_outlined,
                label: '许可证',
                value: 'MIT · 第三方许可清单',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: AppInfo.appDisplayName,
                  applicationVersion: version?.fullVersion ?? '',
                  applicationLegalese: 'MIT License',
                ),
                valueKey: const Key('about-license-value'),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.sm),
              _buildUpdateSection(context, colors),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _openUrl(AppInfo.releasesUrl),
          child: const Text('Releases 页面'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildUpdateSection(BuildContext context, AppColorExtension colors) {
    final result = _result;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.system_update_alt, size: 16),
            const SizedBox(width: 6),
            Text(
              '检查更新',
              style: AppTypography.body.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            OutlinedButton.icon(
              key: const Key('about-check-update-button'),
              onPressed: _updateState == _UpdateState.checking
                  ? null
                  : _checkForUpdates,
              icon: _updateState == _UpdateState.checking
                  ? const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 15),
              label: Text(
                _updateState == _UpdateState.checking ? '检查中…' : '检查更新',
                style: const TextStyle(fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (_updateState == _UpdateState.idle)
          Text(
            '从 GitHub Releases 查询最新正式版本；检查失败不会影响应用使用。',
            style: AppTypography.caption.copyWith(color: colors.textMuted),
          ),
        if (_updateState == _UpdateState.failed)
          Text(
            _error ?? '检查更新失败',
            key: const Key('about-update-error'),
            style: AppTypography.caption.copyWith(color: colors.warning),
          ),
        if (result != null && result.ok && !result.updateAvailable)
          Text(
            '当前已是最新版本 (${result.currentVersion})',
            key: const Key('about-update-up-to-date'),
            style: AppTypography.caption.copyWith(color: colors.success),
          ),
        if (result != null && result.updateAvailable) ...[
          Container(
            key: const Key('about-update-available'),
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: colors.primaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                color: colors.primary.withValues(alpha: 0.45),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '发现新版本 v${result.latest!.version}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: colors.primaryHover,
                  ),
                ),
                Text(
                  result.latest!.publishedLabel,
                  style: AppTypography.caption.copyWith(
                    fontSize: 11,
                    color: colors.textSecondary,
                  ),
                ),
                if (result.latest!.notes.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 120),
                    child: SingleChildScrollView(
                      child: Text(
                        result.latest!.notes,
                        style: AppTypography.caption.copyWith(
                          fontSize: 11,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    key: const Key('about-open-release-button'),
                    onPressed: () => _openUrl(result.latest!.htmlUrl),
                    icon: const Icon(Icons.open_in_new, size: 14),
                    label: const Text('打开 Release 页面下载'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _infoRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
    Key? valueKey,
  }) {
    final colors = context.appColors;
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: colors.textMuted),
        const SizedBox(width: 6),
        SizedBox(
          width: 68,
          child: Text(
            label,
            style: AppTypography.caption.copyWith(color: colors.textMuted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            key: valueKey,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption.copyWith(
              color: onTap == null ? colors.textSecondary : colors.primaryHover,
              decoration: onTap == null ? null : TextDecoration.underline,
            ),
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: onTap == null
          ? row
          : InkWell(onTap: onTap, child: row),
    );
  }
}
