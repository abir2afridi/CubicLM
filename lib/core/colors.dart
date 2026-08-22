import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Cubic Custom Palette ──
  static const Color primary = Color(0xFF6366F1); // Indigo 500
  static const Color primaryLight = Color(0xFF818CF8);
  static const Color primaryDark = Color(0xFF4F46E5);
  
  static const Color secondary = Color(0xFF10B981); // Emerald 500
  
  // Semantic
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // Backgrounds & Surfaces (Dark)
  static const Color bg = Color(0xFF0F172A); // Slate 900
  static const Color surface = Color(0xFF1E293B); // Slate 800
  static const Color surfaceLight = Color(0xFF334155); // Slate 700
  static const Color surfaceLighter = Color(0xFF475569); // Slate 600
  
  // Text
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  // Chat Bubbles
  static const LinearGradient userGradient = LinearGradient(
    colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const Color aiBubble = Color(0xFF1E293B);
  static const Color cmdBubble = Color(0xFF064E3B); // Dark Emerald

  // Borders
  static const Color border = Color(0xFF334155);
  static const Color borderLight = Color(0xFF475569);
  
  // Light Mode (Optional mapping or separate class)
  static const Color bgLight = Color(0xFFF8FAFC);
  static const Color surfaceLightMode = Color(0xFFFFFFFF);
  static const Color borderLightMode = Color(0xFFE2E8F0);
}
