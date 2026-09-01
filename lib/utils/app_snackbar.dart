import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/notification_history_service.dart';
import '../theme/design_tokens.dart';

/// Premium top-anchored snackbar that slides from the status-bar area
/// with a soft spring — replaces the default bottom Get.snackbar for
/// model-switch feedback.
class AppSnackbar {
  AppSnackbar._();

  static void _logHistory(
    String title, String message, String type, String iconName) {
    try {
      if (Get.isRegistered<NotificationHistoryService>()) {
        Get.find<NotificationHistoryService>().add(
          title: title,
          message: message,
          type: type,
          iconName: iconName,
        );
      }
    } catch (_) {}
  }

  static void showTop(
    String title,
    String message, {
    IconData icon = LucideIcons.sparkles,
    String type = 'general',
    String iconName = 'sparkles',
    Duration duration = const Duration(seconds: 2),
    bool logHistory = true,
    TextButton? mainButton,
    VoidCallback? onTap,
  }) {
    if (logHistory && type != 'general') {
      _logHistory(title, message, type, iconName);
    }
    final ctx = Get.overlayContext ?? Get.context;
    final isDark = ctx != null
        ? Theme.of(ctx).brightness == Brightness.dark
        : Get.isDarkMode;

    // Colors — warm card with accent icon, matching Claude palette.
    final bg = isDark ? const Color(0xFF2E2E2C) : Colors.white;
    final titleColor = isDark ? Colors.white : Dt.textPrimary;
    final msgColor = isDark ? Colors.white70 : Dt.textSecondary;

    Get.snackbar(
      title,
      message,
      snackPosition: SnackPosition.TOP,
      snackStyle: SnackStyle.FLOATING,
      // Float below the status bar.
      margin: EdgeInsets.fromLTRB(
        16,
        (ctx != null ? MediaQuery.of(ctx).padding.top : 24) + 8,
        16,
        0,
      ),
      borderRadius: 18,
      backgroundColor: bg,
      colorText: titleColor,
      // Icon on the left.
      icon: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Dt.accent.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: Dt.accent),
      ),
      shouldIconPulse: false,
      // Typography.
      titleText: Text(
        title,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: titleColor,
          letterSpacing: -0.2,
        ),
      ),
      messageText: Text(
        message,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: msgColor,
          height: 1.3,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      // Animation — slide from top with a subtle spring.
      animationDuration: const Duration(milliseconds: 520),
      forwardAnimationCurve: Curves.easeOutBack,
      reverseAnimationCurve: Curves.easeInCubic,
      duration: duration,
      isDismissible: true,
      dismissDirection: DismissDirection.up,
      barBlur: 12,
      overlayBlur: 0,
      boxShadows: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ],
      borderColor: isDark
          ? Colors.white.withValues(alpha: 0.07)
          : Dt.hairline.withValues(alpha: 0.5),
      borderWidth: 1,
      mainButton: mainButton,
      onTap: onTap == null ? null : (_) => onTap(),
    );
  }

  /// Model successfully loaded / switched.
  static void modelSwitched(String modelName) {
    showTop(
      'Model switched',
      modelName,
      icon: LucideIcons.layers,
      type: 'model_switched',
      iconName: 'layers',
      duration: const Duration(seconds: 2),
    );
  }

  /// Cloud provider / model active.
  static void cloudActive(String label) {
    showTop(
      'Cloud active',
      label,
      icon: LucideIcons.cloud,
      type: 'cloud_active',
      iconName: 'cloud',
      duration: const Duration(seconds: 2),
    );
  }

  /// Switched back to local.
  static void localActive(String label) {
    showTop(
      'Back to local',
      label.isEmpty ? 'Ready' : label,
      icon: LucideIcons.cpu,
      type: 'local_active',
      iconName: 'cpu',
      duration: const Duration(seconds: 2),
    );
  }
}
