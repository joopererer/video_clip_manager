import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_clip_manager/app_info.dart';
import 'package:video_clip_manager/services/update_service.dart';
import 'package:video_clip_manager/theme/app_theme.dart';
import 'package:video_clip_manager/widgets/about_dialog.dart';

class _StubUpdateService extends UpdateService {
  _StubUpdateService(this.result);

  final UpdateCheckResult result;
  int calls = 0;

  @override
  Future<UpdateCheckResult> checkForUpdate({
    required String currentVersion,
  }) async {
    calls++;
    return result;
  }
}

const _version = AppVersion(version: '1.1.0', buildNumber: '3');

Future<void> _pumpAbout(WidgetTester tester, UpdateService service) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(body: AppAboutDialog(version: _version, updateService: service)),
    ),
  );
  await tester.pump();
}

ReleaseInfo _release({String version = '1.2.0'}) => ReleaseInfo(
  tagName: 'v$version',
  version: version,
  name: 'v$version',
  notes: '- 语义检索结果增加相似度分数\n- 检查更新',
  htmlUrl: 'https://github.com/joopererer/video_clip_manager/releases/tag/v$version',
  publishedAt: DateTime(2026, 10, 1, 12),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows the packaged version, build number and repository', (
    tester,
  ) async {
    await _pumpAbout(tester, _StubUpdateService(
      const UpdateCheckResult(currentVersion: '1.1.0'),
    ));

    expect(find.textContaining('版本 1.1.0'), findsWidgets);
    expect(
      tester.widget<Text>(find.byKey(const Key('about-version-value'))).data,
      '1.1.0',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('about-build-value'))).data,
      '3',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('about-repo-value'))).data,
      AppInfo.repositoryUrl,
    );
    expect(find.byKey(const Key('about-license-value')), findsOneWidget);
  });

  testWidgets('manual check reports "already up to date"', (tester) async {
    final service = _StubUpdateService(
      const UpdateCheckResult(currentVersion: '1.1.0', latest: null),
    );
    await _pumpAbout(tester, service);

    await tester.tap(find.byKey(const Key('about-check-update-button')));
    await tester.pump();
    await tester.pump();

    expect(service.calls, 1);
    expect(find.byKey(const Key('about-update-up-to-date')), findsOneWidget);
    expect(find.byKey(const Key('about-update-available')), findsNothing);
  });

  testWidgets('a newer release shows version, date, notes and download link', (
    tester,
  ) async {
    final release = _release();
    await _pumpAbout(
      tester,
      _StubUpdateService(
        UpdateCheckResult(
          currentVersion: '1.1.0',
          latest: release,
          updateAvailable: true,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('about-check-update-button')));
    await tester.pump();
    await tester.pump();

    expect(find.text('发现新版本 v1.2.0'), findsOneWidget);
    expect(find.textContaining('2026-10-01'), findsOneWidget);
    expect(find.textContaining('相似度分数'), findsOneWidget);
    expect(find.byKey(const Key('about-open-release-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed check surfaces the reason without breaking the dialog', (
    tester,
  ) async {
    await _pumpAbout(
      tester,
      _StubUpdateService(
        const UpdateCheckResult(
          currentVersion: '1.1.0',
          error: '检查更新失败：offline',
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('about-check-update-button')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('about-update-error')), findsOneWidget);
    expect(find.byKey(const Key('about-update-available')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
