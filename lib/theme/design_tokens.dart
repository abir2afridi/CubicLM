import 'package:flutter/material.dart';

/// Design tokens reverse-engineered from a minimalistic reference chat app
/// (see docs/ClaudeAPK_UIdesign.md). Every UI value below is measured;
/// reference these constants instead of inline hex/magic numbers.
///
/// Light-theme values; dark theme keeps AppColors' existing surfaces.
abstract class Dt {
  // ── Colors ──
  static const Color canvas = Color(0xFFF9F9F6); // screen background
  static const Color card = Color(0xFFFFFFFF); // composer, sheets, rows
  static const Color pillMuted = Color(0xFFEFEDEB); // secondary pills/circles
  static const Color sidebar = Color(0xFFF2F2EF); // drawer background

  static const Color textPrimary = Color(0xFF111111);
  static const Color textSecondary = Color(0xFF7D7D7C);
  static const Color textPlaceholder = Color(0xFF9A9A97);

  // Brand accent — CubicLM primary slot (same treatment as reference coral).
  static const Color accent = Color(0xFFCC6F52);
  static const Color link = Color(0xFF6D5FE8); // upsell/indigo links
  static const Color selected = Color(0xFF0A3B7B); // selected row (deep navy)
  static const Color badgeBg = Color(0xFFE7F1F9);
  static const Color badgeText = Color(0xFF275890);

  static const Color divider = Color(0xFFE4E3E0);
  static const Color iconDefault = Color(0xFF3A3A37);

  static const Color toggleTrackOn = Color(0xFF3B82F6);
  static const Color toggleTrackOff = Color(0xFFD6D6D3);
  static const Color sheetHandle = Color(0xFFD6D6D3);

  /// Solid near-black used for the single high-contrast voice/send CTA.
  static const Color ctaFill = Color(0xFF0B0907);

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
