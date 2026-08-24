import 'package:flutter/material.dart';

/// Design tokens reverse-engineered from a minimalistic reference chat app
/// (see docs/ClaudeAPK_UIdesign.md). Every UI value below is measured;
/// reference these constants instead of inline hex/magic numbers.
///
/// Light-theme values; dark theme keeps AppColors' existing surfaces.
abstract class Dt {
  // ── Colors (measured from Claude APK) ──
  static const Color canvas = Color(0xFFF8F4ED); // parchment screen background
  static const Color card = Color(0xFFFBF9F4); // paper-white cards/composer
  static const Color pillMuted = Color(0xFFF0EAE0); // surface-warm pills/chips
  static const Color sidebar = Color(0xFFF0EAE0); // drawer background
  static const Color hairline = Color(0xFFDDD2BD); // warm 1px card border

  // Warm dark surfaces (reference dark theme)
  static const Color canvasDark = Color(0xFF262624);
  static const Color cardDark = Color(0xFF30302E);
  static const Color pillMutedDark = Color(0xFF3A3937);

  /// Page background for any screen, both modes.
  static Color pageBg(bool isDark) => isDark ? canvasDark : canvas;

  /// Card/row background for any surface, both modes.
  static Color cardBg(bool isDark) => isDark ? cardDark : card;

  /// Muted pill/chip background, both modes.
  static Color pillBg(bool isDark) => isDark ? pillMutedDark : pillMuted;

  /// Warm hairline border for cards/rows, both modes.
  static Color borderColor(bool isDark) =>
      isDark ? Colors.white.withValues(alpha: 0.07) : hairline;

  static const Color textPrimary = Color(0xFF2D2520);
  static const Color textSecondary = Color(0xFF5A4F44);
  static const Color textPlaceholder = Color(0xFF8A7E72);
  static const Color textMuted = Color(0xFF8A7E72);

  // Brand accent — Claude Orange.
  static const Color accent = Color(0xFFD97757);
  static const Color accentMuted = Color(0xFFE8E0D2); // idle send/mic surface
  static const Color link = Color(0xFF6D5FE8); // upsell/indigo links
  static const Color selected = Color(0xFF0A3B7B); // selected row (deep navy)
  static const Color badgeBg = Color(0xFFE7F1F9);
  static const Color badgeText = Color(0xFF275890);

  static const Color divider = Color(0xFFE8E0D2);
  static const Color iconDefault = Color(0xFF2D2520);

  static const Color toggleTrackOn = Color(0xFFD97757);
  static const Color toggleTrackOff = Color(0xFFE8E0D2);
  static const Color sheetHandle = Color(0xFFD6CFC2);

  /// Solid near-black used for the single high-contrast voice/send CTA.
  static const Color ctaFill = Color(0xFFD97757);

  static const Color scrim = Color(0x73000000); // black @ 45%

  // ── Radii ──
  static const double rComposer = 18; // composer card corner
  static const double rSheet = 17; // bottom-sheet top corners (16–18 range)
  static const double rRowCard = 12; // stacked row cards inside sheets
  static const double rDrawerEdge = 24;

  // ── Sizing ──
  static const double hPadding = 14; // screen horizontal padding (~4%)
  static const double circleBtnDiameter = 28; // +/mic round controls
  static const double circleIconDiameter = 56; // big tile icons in sheets
  static const double iconCircleDiameter = 40; // leading icons in rows
  static const double iconSize = 24; // standard line-icon size
  static const double pillHeight = 28; // model-selector pill height
  static const double sheetHandleW = 24;
  static const double sheetHandleH = 2.5;

  // ── Motion ──
  static const Duration sheetOpen = Duration(milliseconds: 260);
  static const Duration sheetClose = Duration(milliseconds: 200);
  static const Curve sheetOpenCurve = Curves.easeOutCubic;
  static const Curve sheetCloseCurve = Curves.easeInCubic;
}
