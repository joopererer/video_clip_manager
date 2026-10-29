import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Dark Media Workspace 字体与排版规范
class AppTypography {
  AppTypography._();

  // 页面标题与大标题 (22-24px)
  static const TextStyle pageTitle = TextStyle(
    fontSize: 22.0,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    color: AppColors.textPrimary,
  );

  // 区块与卡片标题 (16-18px)
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 16.0,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: AppColors.textPrimary,
  );

  // 子标题与加粗说明 (14-15px)
  static const TextStyle subtitle = TextStyle(
    fontSize: 14.0,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  // 正文主体 (13-14px)
  static const TextStyle body = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: AppColors.textPrimary,
  );

  // 次级说明文本 (12-13px)
  static const TextStyle bodySecondary = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  // 小号附注与统计标签 (11-12px)
  static const TextStyle caption = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
  );

  // 按钮文本 (13-14px)
  static const TextStyle button = TextStyle(
    fontSize: 13.0,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );

  // 等宽数字样式（用于毫秒时间码、时长计算、统计数字）
  static const TextStyle tabularNumbers = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
  );

  // 综合时间码样式
  static TextStyle timecode({
    double fontSize = 12.0,
    FontWeight fontWeight = FontWeight.w600,
    Color color = AppColors.textPrimary,
  }) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
      letterSpacing: 0.5,
    );
  }

  /// 统一时间码格式化工具 (HH:MM:SS 或 MM:SS.mmm)
  static String formatTimecode(
    Duration duration, {
    bool showMs = false,
    bool forceHours = false,
  }) {
    final totalSeconds = duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final ms = duration.inMilliseconds % 1000;

    final mStr = minutes.toString().padLeft(2, '0');
    final sStr = seconds.toString().padLeft(2, '0');

    String result;
    if (hours > 0 || forceHours) {
      final hStr = hours.toString().padLeft(2, '0');
      result = '$hStr:$mStr:$sStr';
    } else {
      result = '$mStr:$sStr';
    }

    if (showMs) {
      final msStr = ms.toString().padLeft(3, '0');
      result += '.$msStr';
    }

    return result;
  }
}
