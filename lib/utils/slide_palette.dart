/// Resolved slide-canvas colors derived from a [SlideDeckTheme].
///
/// The in-app slide preview used to be hardcoded dark; every canvas color
/// now flows through here so one-click theme presets re-skin the preview
/// instantly (content untouched). Pure color math — unit-tested.
library;

import 'dart:ui';

import 'slide_deck.dart';

class SlidePalette {
  final Color bg;
  final Color bgDeep;
  final Color card;
  final Color cardBorder;
  final Color title;
  final Color body;
  final Color muted;
  final Color accent;
  final Color accentBorder;
  final Color onAccent;
  final Color secondary;
  final String headingFont;
  final String bodyFont;
  final bool isDark;

  const SlidePalette({
    required this.bg,
    required this.bgDeep,
    required this.card,
    required this.cardBorder,
    required this.title,
    required this.body,
    required this.muted,
    required this.accent,
    required this.accentBorder,
    required this.onAccent,
    required this.secondary,
    required this.headingFont,
    required this.bodyFont,
    required this.isDark,
  });

  /// Google Fonts families the app may request for slide text. Anything
  /// else falls back to Plus Jakarta Sans (avoids shipping/fetching
  /// surprises from model-invented family names).
  static const knownFonts = {
    'Plus Jakarta Sans',
    'Inter',
    'Montserrat',
    'Roboto',
    'Playfair Display',
    'Space Grotesk',
    'Lora',
    'JetBrains Mono',
  };

  static String safeFont(String family) =>
      knownFonts.contains(family.trim()) ? family.trim() : 'Plus Jakarta Sans';

  /// #rgb / #rrggbb / #aarrggbb (with or without '#'); garbage yields
  /// opaque [fallback].
  static Color parseHex(String raw, [Color fallback = const Color(0xFF808080)]) {
    var h = raw.trim().replaceAll('#', '');
    if (h.length == 3) {
      h = h.split('').map((c) => '$c$c').join();
    }
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return fallback;
    final v = int.tryParse(h, radix: 16);
    return v == null ? fallback : Color(v);
  }

  /// Lighten (amt > 0) or darken (amt < 0) by fraction 0..1.
  static Color shade(Color c, double amt) {
    double r = c.r, g = c.g, b = c.b;
    if (amt >= 0) {
      r += (1 - r) * amt;
      g += (1 - g) * amt;
      b += (1 - b) * amt;
    } else {
      r *= 1 + amt;
      g *= 1 + amt;
      b *= 1 + amt;
    }
    return Color.fromARGB(
      255,
      (r * 255).round().clamp(0, 255),
      (g * 255).round().clamp(0, 255),
      (b * 255).round().clamp(0, 255),
    );
  }

  factory SlidePalette.fromTheme(SlideDeckTheme t) {
    final bg = parseHex(t.backgroundColor, const Color(0xFF14141c));
    final dark = bg.computeLuminance() < 0.5;
    final title = parseHex(t.textColor, const Color(0xFFF2F0EA));
    final accent = parseHex(t.primaryColor, const Color(0xFFD97757));
    final secondary = parseHex(t.secondaryColor, const Color(0xFF4ADE80));
    final overlay = dark
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF000000);
    return SlidePalette(
      bg: bg,
      bgDeep: shade(bg, dark ? -0.10 : -0.05),
      card: overlay.withValues(alpha: dark ? 0.04 : 0.03),
      cardBorder: overlay.withValues(alpha: 0.08),
      title: title,
      body: title.withValues(alpha: 0.84),
      muted: title.withValues(alpha: 0.55),
      accent: accent,
      accentBorder: accent.withValues(alpha: 0.30),
      onAccent:
          accent.computeLuminance() > 0.55
              ? const Color(0xFF1A1A1A)
              : const Color(0xFFFFFFFF),
      secondary: secondary,
      headingFont: safeFont(t.fontHeading),
      bodyFont: safeFont(t.fontBody),
      isDark: dark,
    );
  }
}
