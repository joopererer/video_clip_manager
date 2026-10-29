import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 一套可选配色方案：由 id、显示名与完整的 [AppColorExtension] 组成。
@immutable
class AppPalette {
  final String id;
  final String name;
  final AppColorExtension colors;

  const AppPalette({
    required this.id,
    required this.name,
    required this.colors,
  });

  /// 自定义配色使用的固定 id
  static const String customId = 'custom';
  static const String defaultId = 'violet';

  /// 自定义强调色的默认值（与默认方案一致）
  static const Color defaultCustomAccent = Color(0xFF8B7CF6);

  /// 内置预设（顺序即为设置页展示顺序）
  static final List<AppPalette> presets = [
    const AppPalette(id: 'violet', name: '暮光紫', colors: AppColorExtension.dark),
    _preset(
      id: 'ocean',
      name: '深海蓝',
      background: 0xFF111A24,
      sidebar: 0xFF172230,
      surface: 0xFF1D293A,
      elevated: 0xFF273649,
      highlight: 0xFF314358,
      border: 0xFF37495F,
      subtle: 0xFF253347,
      accent: 0xFF4DA3FF,
    ),
    _preset(
      id: 'emerald',
      name: '森林绿',
      background: 0xFF111A18,
      sidebar: 0xFF17231F,
      surface: 0xFF1E2C28,
      elevated: 0xFF283A35,
      highlight: 0xFF334A43,
      border: 0xFF39504A,
      subtle: 0xFF26352F,
      accent: 0xFF34C795,
    ),
    _preset(
      id: 'amber',
      name: '琥珀橙',
      background: 0xFF1A1714,
      sidebar: 0xFF221E1A,
      surface: 0xFF2B2621,
      elevated: 0xFF39332C,
      highlight: 0xFF473F36,
      border: 0xFF4D453B,
      subtle: 0xFF332D26,
      accent: 0xFFF2A144,
    ),
    _preset(
      id: 'rose',
      name: '玫瑰粉',
      background: 0xFF1B161A,
      sidebar: 0xFF231C22,
      surface: 0xFF2C242B,
      elevated: 0xFF3A2F39,
      highlight: 0xFF483B47,
      border: 0xFF4F404D,
      subtle: 0xFF352B33,
      accent: 0xFFF0709B,
    ),
    _preset(
      id: 'graphite',
      name: '石墨灰',
      background: 0xFF161617,
      sidebar: 0xFF1D1D1F,
      surface: 0xFF252527,
      elevated: 0xFF303033,
      highlight: 0xFF3B3B3F,
      border: 0xFF434347,
      subtle: 0xFF2C2C2F,
      accent: 0xFF5CC8D6,
    ),
  ];

  static AppPalette byId(String? id) {
    for (final p in presets) {
      if (p.id == id) return p;
    }
    return presets.first;
  }

  /// 根据任意强调色生成一套协调的深色方案：
  /// 取其色相，使用低饱和度的深色作为背景/表面层级。
  static AppPalette custom(Color accent) {
    final hue = HSLColor.fromColor(accent).hue;
    Color tone(double saturation, double lightness) =>
        HSLColor.fromAHSL(1.0, hue, saturation, lightness).toColor();

    return AppPalette(
      id: customId,
      name: '自定义',
      colors: _build(
        background: tone(0.16, 0.09),
        sidebar: tone(0.16, 0.12),
        surface: tone(0.15, 0.155),
        elevated: tone(0.14, 0.20),
        highlight: tone(0.13, 0.25),
        border: tone(0.12, 0.27),
        subtle: tone(0.14, 0.19),
        accent: accent,
      ),
    );
  }

  static AppPalette _preset({
    required String id,
    required String name,
    required int background,
    required int sidebar,
    required int surface,
    required int elevated,
    required int highlight,
    required int border,
    required int subtle,
    required int accent,
  }) {
    return AppPalette(
      id: id,
      name: name,
      colors: _build(
        background: Color(background),
        sidebar: Color(sidebar),
        surface: Color(surface),
        elevated: Color(elevated),
        highlight: Color(highlight),
        border: Color(border),
        subtle: Color(subtle),
        accent: Color(accent),
      ),
    );
  }

  static AppColorExtension _build({
    required Color background,
    required Color sidebar,
    required Color surface,
    required Color elevated,
    required Color highlight,
    required Color border,
    required Color subtle,
    required Color accent,
  }) {
    // 悬停色：向白色提亮；容器色：强调色与背景按比例混合
    final hover = Color.lerp(accent, Colors.white, 0.18) ?? accent;
    final container = Color.lerp(background, accent, 0.28) ?? accent;
    // 浅色强调色（如琥珀、森林绿）上使用深色文字以保证对比度
    final onAccent = accent.computeLuminance() > 0.38
        ? const Color(0xFF14161B)
        : Colors.white;

    return AppColorExtension(
      background: background,
      sidebar: sidebar,
      surface: surface,
      surfaceElevated: elevated,
      surfaceHighlight: highlight,
      border: border,
      borderSubtle: subtle,
      focusRing: accent,
      primary: accent,
      primaryHover: hover,
      primaryContainer: container,
      onPrimary: onAccent,
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
  }
}
