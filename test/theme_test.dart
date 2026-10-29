import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_clip_manager/theme/app_colors.dart';
import 'package:video_clip_manager/theme/app_theme.dart';
import 'package:video_clip_manager/theme/app_typography.dart';
import 'package:video_clip_manager/widgets/common/timecode_chip.dart';

void main() {
  group('AppTheme & Tokens Tests', () {
    test('darkTheme has expected dark workspace tokens', () {
      final theme = AppTheme.darkTheme;
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, AppColors.background);
      expect(theme.colorScheme.primary, AppColors.primary);
      expect(theme.colorScheme.surface, AppColors.surface);

      final ext = theme.extension<AppColorExtension>();
      expect(ext, isNotNull);
      expect(ext!.sidebar, AppColors.sidebar);
      expect(ext.surfaceElevated, AppColors.surfaceElevated);
      expect(ext.border, AppColors.border);
    });

    test('AppTypography.formatTimecode formats durations correctly', () {
      // 0 duration
      expect(AppTypography.formatTimecode(Duration.zero), '00:00');
      expect(
        AppTypography.formatTimecode(Duration.zero, showMs: true),
        '00:00.000',
      );

      // under an hour
      final d1 = const Duration(minutes: 1, seconds: 21, milliseconds: 50);
      expect(AppTypography.formatTimecode(d1), '01:21');
      expect(AppTypography.formatTimecode(d1, showMs: true), '01:21.050');

      // over an hour
      final d2 = const Duration(
        hours: 2,
        minutes: 5,
        seconds: 9,
        milliseconds: 800,
      );
      expect(AppTypography.formatTimecode(d2), '02:05:09');
      expect(AppTypography.formatTimecode(d2, showMs: true), '02:05:09.800');
    });

    testWidgets('TimecodeChip renders timecode and optional label', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: TimecodeChip(
              duration: Duration(seconds: 45, milliseconds: 120),
              label: 'IN',
              showMs: true,
            ),
          ),
        ),
      );

      expect(find.text('IN'), findsOneWidget);
      expect(find.text('00:45.120'), findsOneWidget);
    });
  });
}
