import 'package:flutter/material.dart';

class ToastUtils {
  static void showSuccess(BuildContext context, String message) {
    _showSnackBar(
      context,
      message,
      backgroundColor: Colors.green,
      icon: Icons.check_circle,
    );
  }

  static void showError(BuildContext context, String message) {
    _showSnackBar(
      context,
      message,
      backgroundColor: Colors.red,
      icon: Icons.error,
    );
  }

  static void showWarning(BuildContext context, String message) {
    _showSnackBar(
      context,
      message,
      backgroundColor: Colors.orange,
      icon: Icons.warning,
    );
  }

  static void showInfo(BuildContext context, String message) {
    _showSnackBar(
      context,
      message,
      backgroundColor: Colors.blue,
      icon: Icons.info,
    );
  }

  static void showCustom(
    BuildContext context,
    String message, {
    Color? backgroundColor,
    IconData? icon,
    Duration? duration,
  }) {
    _showSnackBar(
      context,
      message,
      backgroundColor: backgroundColor,
      icon: icon,
      duration: duration,
    );
  }

  static void _showSnackBar(
    BuildContext context,
    String message, {
    Color? backgroundColor,
    IconData? icon,
    Duration? duration,
  }) {
    if (!context.mounted) return;

    final snackBar = SnackBar(
      content: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
          ],
          Expanded(child: Text(message)),
        ],
      ),
      backgroundColor: backgroundColor,
      duration: duration ?? const Duration(seconds: 3),
      behavior: SnackBarBehavior.fixed,
      // behavior: SnackBarBehavior.floating,
      // margin: const EdgeInsets.all(8),
    );

    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }
}
