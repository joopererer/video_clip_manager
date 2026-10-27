import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// Dark Media Workspace 全局主题构建器
class AppTheme {
  AppTheme._();

  /// 默认深色工作台主题（紫罗兰）
  static ThemeData get darkTheme => fromColors(AppColorExtension.dark);

  /// 根据任意配色方案构建完整主题，保证所有 Material 组件跟随配色
  static ThemeData fromColors(AppColorExtension c) {
    final colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: c.primary,
      onPrimary: c.onPrimary,
      primaryContainer: c.primaryContainer,
      onPrimaryContainer: AppColors.onPrimaryContainer,
      secondary: c.primaryHover,
      onSecondary: c.onPrimary,
      surface: c.surface,
      onSurface: c.textPrimary,
      onSurfaceVariant: c.textSecondary,
      surfaceContainerLowest: c.background,
      surfaceContainerLow: c.sidebar,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.surfaceElevated,
      surfaceContainerHighest: c.surfaceHighlight,
      outline: c.border,
      outlineVariant: c.borderSubtle,
      error: c.danger,
      onError: Colors.white,
      errorContainer: AppColors.dangerContainer,
      onErrorContainer: const Color(0xFFFFD9DD),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      extensions: [c],
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: AppTypography.sectionTitle,
        iconTheme: IconThemeData(color: c.textSecondary, size: 20),
        actionsIconTheme: IconThemeData(color: c.textSecondary, size: 20),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.borderCard,
          side: BorderSide(color: c.border, width: 1.0),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.borderModal,
          side: BorderSide(color: c.border, width: 1.0),
        ),
        titleTextStyle: AppTypography.sectionTitle,
        contentTextStyle: AppTypography.body,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        hintStyle: TextStyle(color: c.textMuted, fontSize: 13),
        labelStyle: TextStyle(color: c.textSecondary, fontSize: 13),
        prefixIconColor: c.textSecondary,
        suffixIconColor: c.textSecondary,
        border: _inputBorder(c.border),
        enabledBorder: _inputBorder(c.border),
        focusedBorder: _inputBorder(c.focusRing, width: 1.5),
        errorBorder: _inputBorder(c.danger),
        focusedErrorBorder: _inputBorder(c.danger, width: 1.5),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          textStyle: AppTypography.button,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.surfaceHighlight,
          foregroundColor: c.textPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          textStyle: AppTypography.button,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textPrimary,
          side: BorderSide(color: c.border),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          textStyle: AppTypography.button,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.primary,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
          textStyle: AppTypography.button,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: c.textSecondary,
          hoverColor: c.primary.withValues(alpha: 0.12),
          highlightColor: c.primary.withValues(alpha: 0.24),
          focusColor: c.focusRing.withValues(alpha: 0.20),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        elevation: 2,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.primary,
        linearTrackColor: c.surfaceHighlight,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.onPrimary : c.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? c.primary : c.surfaceHighlight,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.surfaceElevated,
        contentTextStyle: TextStyle(color: c.textPrimary, fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: c.border),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 6,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceElevated,
        deleteIconColor: c.textSecondary,
        disabledColor: c.borderSubtle,
        selectedColor: c.primary.withValues(alpha: 0.25),
        secondarySelectedColor: c.primary.withValues(alpha: 0.25),
        labelStyle: TextStyle(color: c.textPrimary, fontSize: 12),
        secondaryLabelStyle: TextStyle(
          color: c.primary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        side: BorderSide(color: c.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: c.border),
        ),
        textStyle: AppTypography.body,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.surfaceElevated,
          borderRadius: BorderRadius.circular(AppRadius.xs),
          border: Border.all(color: c.border),
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        textStyle: TextStyle(color: c.textPrimary, fontSize: 12),
        waitDuration: const Duration(milliseconds: 350),
      ),
      dividerTheme: DividerThemeData(
        color: c.border,
        thickness: 1.0,
        space: 1.0,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: c.primary,
        unselectedLabelColor: c.textSecondary,
        indicatorColor: c.primary,
        dividerColor: c.border,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return c.primary;
          return Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll(c.onPrimary),
        side: BorderSide(color: c.border, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.dragged)) {
            return c.textMuted;
          }
          return c.border;
        }),
        trackColor: const WidgetStatePropertyAll(Colors.transparent),
        radius: AppRadius.radiusXs,
        thickness: const WidgetStatePropertyAll(6.0),
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1.0}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  /// 亮色备用主题（为将来用户偏好自由切换预留）
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
      ),
      extensions: const [AppColorExtension.light],
    );
  }
}
