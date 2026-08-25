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

  // Backgrounds & Surfaces (Dark — warm Claude palette, no blue cast)
  static const Color bg = Color(0xFF262624); // warm dark canvas
  static const Color surface = Color(0xFF30302E); // warm dark card
  static const Color surfaceLight = Color(0xFF3A3937); // warm pills/chips
  static const Color surfaceLighter = Color(0xFF4A4946);

  // Text (warm)
  static const Color textPrimary = Color(0xFFEDE6DC);
  static const Color textSecondary = Color(0xFFA8A099);
  static const Color textMuted = Color(0xFF78716C);

  // Chat Bubbles
  static const LinearGradient userGradient = LinearGradient(
    colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient glassGradient = LinearGradient(
    colors: [Colors.white10, Color(0x0DFFFFFF)], // 0x0D is roughly 5% opacity
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const Color aiBubble = Color(0xFF30302E);
  static const Color cmdBubble = Color(0xFF064E3B); // Dark Emerald

  // Borders (warm)
  static const Color border = Color(0xFF3F3E3B);
  static const Color borderLight = Color(0xFF4A4946);

  // Light Mode (warm Claude palette)
  static const Color bgLight = Color(0xFFF8F4ED); // parchment canvas
  static const Color surfaceLightMode = Color(0xFFFBF9F4); // paper white
  static const Color surfaceHighLightMode = Color(0xFFF0EAE0); // surface warm
  static const Color borderLightMode = Color(0xFFDDD2BD); // hairline

  // Glass Styles
  static BoxDecoration glassDecoration(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark ? bg.withValues(alpha: 0.7) : bgLight.withValues(alpha: 0.7),
      border: Border(
        top: BorderSide(
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05),
          width: 0.5,
        ),
      ),
    );
  }
}
