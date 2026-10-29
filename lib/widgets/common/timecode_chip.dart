import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// 统一时间码徽章组件，用于展示毫秒/微秒精度的等宽数字时间码
class TimecodeChip extends StatelessWidget {
  final Duration duration;
  final String? label;
  final Color? labelColor;
  final Color? timeColor;
  final Color? backgroundColor;
  final Color? borderColor;
  final bool showMs;
  final IconData? icon;
  final VoidCallback? onTap;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  const TimecodeChip({
    super.key,
    required this.duration,
    this.label,
    this.labelColor,
    this.timeColor,
    this.backgroundColor,
    this.borderColor,
    this.showMs = false,
    this.icon,
    this.onTap,
    this.fontSize = 11.5,
    this.padding = const EdgeInsets.symmetric(horizontal: 7.0, vertical: 3.5),
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final effectiveBg = backgroundColor ?? colors.surfaceElevated;
    final effectiveBorder = borderColor ?? colors.border;
    final effectiveTimeColor = timeColor ?? colors.textPrimary;
    final effectiveLabelColor = labelColor ?? colors.textSecondary;

    final formatted = AppTypography.formatTimecode(duration, showMs: showMs);

    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: fontSize + 1, color: effectiveLabelColor),
          const SizedBox(width: 4.0),
        ],
        if (label != null && label!.isNotEmpty) ...[
          Text(
            label!,
            style: TextStyle(
              fontSize: fontSize * 0.9,
              fontWeight: FontWeight.w600,
              color: effectiveLabelColor,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 5.0),
        ],
        Text(
          formatted,
          style: AppTypography.timecode(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: effectiveTimeColor,
          ),
        ),
      ],
    );

    final decoration = BoxDecoration(
      color: effectiveBg,
      borderRadius: BorderRadius.circular(AppRadius.xs),
      border: Border.all(color: effectiveBorder, width: 0.8),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.xs),
          child: Container(
            padding: padding,
            decoration: decoration,
            child: content,
          ),
        ),
      );
    }

    return Container(padding: padding, decoration: decoration, child: content);
  }
}
