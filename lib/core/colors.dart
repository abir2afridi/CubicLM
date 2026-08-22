import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Apple System Colors ──
  static const Color primary = Color(0xFF007AFF);
  static const Color primaryDim = Color(0xFF0A84FF);
  static const Color secondary = Color(0xFF5856D6);

  // Semantic
  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFF9500);
  static const Color error = Color(0xFFFF3B30);
  static const Color info = Color(0xFF5AC8FA);

  // Text (dark mode defaults — theme overrides for light)
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF98989D);
  static const Color textMuted = Color(0xFF636366);

  // Backgrounds (dark mode)
  static const Color bg = Color(0xFF000000);
  static const Color surface = Color(0xFF1C1C1E);
  static const Color surfaceLight = Color(0xFF2C2C2E);
  static const Color card = Color(0xFF1C1C1E);

  // Chat Bubbles
  static const Color userBubble = Color(0xFF007AFF);
  static const Color aiBubble = Color(0xFF1C1C1E);
  static const Color cmdBubble = Color(0xFF1A2E1A);

  // Border
  static const Color border = Color(0xFF38383A);
  static const Color borderLight = Color(0xFF48484A);
}
