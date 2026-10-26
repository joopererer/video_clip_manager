import 'package:flutter/material.dart';

/// Dark Media Workspace 颜色体系
class AppColors {
  AppColors._();

  // 基础背景与表面色
  static const Color background = Color(0xFF171A20);
  static const Color sidebar = Color(0xFF1E222B);
  static const Color surface = Color(0xFF252A34);
  static const Color surfaceElevated = Color(0xFF303644);
  static const Color surfaceHighlight = Color(0xFF3A4252);

  // 边框与分割线
  static const Color border = Color(0xFF3B414E);
  static const Color borderSubtle = Color(0xFF2B303C);
  static const Color focusRing = Color(0xFF8B7CF6);

  // 主题主强调色 (Violet)
  static const Color primary = Color(0xFF8B7CF6);
  static const Color primaryHover = Color(0xFF9E91F8);
  static const Color primaryPressed = Color(0xFF7766EE);
  static const Color primaryContainer = Color(0xFF352F5A);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onPrimaryContainer = Color(0xFFE4DFFF);

  // 文本色彩阶梯
  static const Color textPrimary = Color(0xFFF1F2F6);
  static const Color textSecondary = Color(0xFFA5ACBA);
  static const Color textMuted = Color(0xFF727988);
  static const Color textDisabled = Color(0xFF505663);

  // 语义反馈色
  static const Color success = Color(0xFF7BD6B6);
  static const Color successContainer = Color(0xFF1B3D34);
  static const Color warning = Color(0xFFFFBC70);
  static const Color warningContainer = Color(0xFF453018);
  static const Color danger = Color(0xFFF07887);
  static const Color dangerContainer = Color(0xFF421C22);
  static const Color info = Color(0xFF60A5FA);

  // 媒体与评分专用色
  static const Color starActive = Color(0xFFFFC65C);
  static const Color favoriteActive = Color(0xFFF07887);
}

/// 支持在 ThemeData 中注入的颜色扩展，保证支持未来浅色/深色主题动态切换
@immutable
class AppColorExtension extends ThemeExtension<AppColorExtension> {
  final Color background;
  final Color sidebar;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceHighlight;
  final Color border;
  final Color borderSubtle;
  final Color focusRing;
  final Color primary;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final Color starActive;
  final Color favoriteActive;

  const AppColorExtension({
    required this.background,
    required this.sidebar,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceHighlight,
    required this.border,
    required this.borderSubtle,
    required this.focusRing,
    required this.primary,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.starActive,
    required this.favoriteActive,
  });

  /// 默认现代深色配置
  static const dark = AppColorExtension(
    background: AppColors.background,
    sidebar: AppColors.sidebar,
    surface: AppColors.surface,
    surfaceElevated: AppColors.surfaceElevated,
    surfaceHighlight: AppColors.surfaceHighlight,
    border: AppColors.border,
    borderSubtle: AppColors.borderSubtle,
    focusRing: AppColors.focusRing,
    primary: AppColors.primary,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    textMuted: AppColors.textMuted,
    success: AppColors.success,
    warning: AppColors.warning,
    danger: AppColors.danger,
    info: AppColors.info,
    starActive: AppColors.starActive,
    favoriteActive: AppColors.favoriteActive,
  );

  /// 亮色备用配置（为未来主题切换预留）
  static const light = AppColorExtension(
    background: Color(0xFFF6F8FA),
    sidebar: Color(0xFFEDF1F5),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFF0F3F7),
    surfaceHighlight: Color(0xFFE4E8EE),
    border: Color(0xFFD4DAE2),
    borderSubtle: Color(0xFFE5E9F0),
    focusRing: Color(0xFF7C6BE8),
    primary: Color(0xFF7C6BE8),
    textPrimary: Color(0xFF1E242B),
    textSecondary: Color(0xFF5A6372),
    textMuted: Color(0xFF8892A0),
    success: Color(0xFF289E78),
    warning: Color(0xFFD97706),
    danger: Color(0xFFDC2626),
    info: Color(0xFF2563EB),
    starActive: Color(0xFFF59E0B),
    favoriteActive: Color(0xFFE11D48),
  );

  @override
  AppColorExtension copyWith({
    Color? background,
    Color? sidebar,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceHighlight,
    Color? border,
    Color? borderSubtle,
    Color? focusRing,
    Color? primary,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    Color? starActive,
    Color? favoriteActive,
  }) {
    return AppColorExtension(
      background: background ?? this.background,
      sidebar: sidebar ?? this.sidebar,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceHighlight: surfaceHighlight ?? this.surfaceHighlight,
      border: border ?? this.border,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      focusRing: focusRing ?? this.focusRing,
      primary: primary ?? this.primary,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      starActive: starActive ?? this.starActive,
      favoriteActive: favoriteActive ?? this.favoriteActive,
    );
  }

  @override
  AppColorExtension lerp(ThemeExtension<AppColorExtension>? other, double t) {
    if (other is! AppColorExtension) return this;
    return AppColorExtension(
      background: Color.lerp(background, other.background, t) ?? background,
      sidebar: Color.lerp(sidebar, other.sidebar, t) ?? sidebar,
      surface: Color.lerp(surface, other.surface, t) ?? surface,
      surfaceElevated:
          Color.lerp(surfaceElevated, other.surfaceElevated, t) ??
          surfaceElevated,
      surfaceHighlight:
          Color.lerp(surfaceHighlight, other.surfaceHighlight, t) ??
          surfaceHighlight,
      border: Color.lerp(border, other.border, t) ?? border,
      borderSubtle:
          Color.lerp(borderSubtle, other.borderSubtle, t) ?? borderSubtle,
      focusRing: Color.lerp(focusRing, other.focusRing, t) ?? focusRing,
      primary: Color.lerp(primary, other.primary, t) ?? primary,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textSecondary:
          Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
      textMuted: Color.lerp(textMuted, other.textMuted, t) ?? textMuted,
      success: Color.lerp(success, other.success, t) ?? success,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      danger: Color.lerp(danger, other.danger, t) ?? danger,
      info: Color.lerp(info, other.info, t) ?? info,
      starActive: Color.lerp(starActive, other.starActive, t) ?? starActive,
      favoriteActive:
          Color.lerp(favoriteActive, other.favoriteActive, t) ?? favoriteActive,
    );
  }
}

/// 快捷语法糖，方便通过 context.appColors 访问颜色
extension AppColorExtensionContext on BuildContext {
  AppColorExtension get appColors =>
      Theme.of(this).extension<AppColorExtension>() ?? AppColorExtension.dark;
}
