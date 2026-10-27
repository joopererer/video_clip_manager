import 'package:flutter/material.dart';

/// Dark Media Workspace 默认颜色体系（紫罗兰预设）。
///
/// 文本色与语义反馈色在所有预设中保持一致；
/// 背景/表面/强调色请通过 `context.appColors` 获取，以便跟随用户选择的配色方案。
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
  static const Color infoContainer = Color(0xFF16304D);

  // 媒体与评分专用色
  static const Color starActive = Color(0xFFFFC65C);
  static const Color favoriteActive = Color(0xFFF07887);
}

/// 支持在 ThemeData 中注入的颜色扩展，支持用户切换配色方案。
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
  final Color primaryHover;
  final Color primaryContainer;
  final Color onPrimary;
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
    required this.primaryHover,
    required this.primaryContainer,
    required this.onPrimary,
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

  /// 默认现代深色配置（紫罗兰）
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
    primaryHover: AppColors.primaryHover,
    primaryContainer: AppColors.primaryContainer,
    onPrimary: AppColors.onPrimary,
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
    primaryHover: Color(0xFF6A59DA),
    primaryContainer: Color(0xFFE6E2FB),
    onPrimary: Color(0xFFFFFFFF),
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
    Color? primaryHover,
    Color? primaryContainer,
    Color? onPrimary,
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
      primaryHover: primaryHover ?? this.primaryHover,
      primaryContainer: primaryContainer ?? this.primaryContainer,
      onPrimary: onPrimary ?? this.onPrimary,
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
    Color mix(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return AppColorExtension(
      background: mix(background, other.background),
      sidebar: mix(sidebar, other.sidebar),
      surface: mix(surface, other.surface),
      surfaceElevated: mix(surfaceElevated, other.surfaceElevated),
      surfaceHighlight: mix(surfaceHighlight, other.surfaceHighlight),
      border: mix(border, other.border),
      borderSubtle: mix(borderSubtle, other.borderSubtle),
      focusRing: mix(focusRing, other.focusRing),
      primary: mix(primary, other.primary),
      primaryHover: mix(primaryHover, other.primaryHover),
      primaryContainer: mix(primaryContainer, other.primaryContainer),
      onPrimary: mix(onPrimary, other.onPrimary),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textMuted: mix(textMuted, other.textMuted),
      success: mix(success, other.success),
      warning: mix(warning, other.warning),
      danger: mix(danger, other.danger),
      info: mix(info, other.info),
      starActive: mix(starActive, other.starActive),
      favoriteActive: mix(favoriteActive, other.favoriteActive),
    );
  }
}

/// 快捷语法糖，方便通过 context.appColors 访问颜色
extension AppColorExtensionContext on BuildContext {
  AppColorExtension get appColors =>
      Theme.of(this).extension<AppColorExtension>() ?? AppColorExtension.dark;
}
