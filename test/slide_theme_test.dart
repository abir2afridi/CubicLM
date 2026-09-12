import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:cubiclm/controllers/slide_deck_controller.dart';
import 'package:cubiclm/utils/slide_deck.dart';
import 'package:cubiclm/utils/slide_palette.dart';

/// One-click theme presets: pure data + color math, no platform channels.
void main() {
  group('SlideThemePresets', () {
    test('ships a useful gallery with unique names', () {
      expect(SlideThemePresets.all.length, greaterThanOrEqualTo(8));
      final names = SlideThemePresets.names;
      expect(names.toSet().length, names.length);
      expect(names.first, 'Modern Terracotta');
    });

    test('every preset is renderable (valid hex + known fonts)', () {
      final hex = RegExp(r'^#[0-9a-fA-F]{6}$');
      for (final t in SlideThemePresets.all) {
        expect(hex.hasMatch(t.primaryColor), isTrue,
            reason: '${t.name} primary');
        expect(hex.hasMatch(t.secondaryColor), isTrue,
            reason: '${t.name} secondary');
        expect(hex.hasMatch(t.backgroundColor), isTrue,
            reason: '${t.name} background');
        expect(hex.hasMatch(t.textColor), isTrue,
            reason: '${t.name} text');
        expect(hex.hasMatch(t.accentColor), isTrue,
            reason: '${t.name} accent');
        expect(SlidePalette.knownFonts, contains(t.fontHeading),
            reason: '${t.name} heading font');
        expect(SlidePalette.knownFonts, contains(t.fontBody),
            reason: '${t.name} body font');
      }
    });

    test('byName is case-insensitive with default fallback', () {
      expect(SlideThemePresets.byName('paper').name, 'Paper');
      expect(SlideThemePresets.byName('  OCEAN ').name, 'Ocean');
      expect(SlideThemePresets.byName('nope').name, 'Modern Terracotta');
    });
  });

  group('SlidePalette.parseHex', () {
    test('handles #rgb, rrggbb and garbage', () {
      expect(SlidePalette.parseHex('#fff'), const Color(0xFFFFFFFF));
      expect(SlidePalette.parseHex('d97757'), const Color(0xFFD97757));
      expect(SlidePalette.parseHex('zzz'), const Color(0xFF808080));
      expect(SlidePalette.parseHex(''), const Color(0xFF808080));
    });
  });

  group('SlidePalette.fromTheme', () {
    test('detects dark vs light themes', () {
      final dark = SlidePalette.fromTheme(
          SlideThemePresets.byName('Modern Terracotta'));
      final light =
          SlidePalette.fromTheme(SlideThemePresets.byName('Paper'));
      expect(dark.isDark, isTrue);
      expect(light.isDark, isFalse);
    });

    test('onAccent contrasts with the accent', () {
      // Mono Ink accent is near-white -> dark text on it.
      final mono = SlidePalette.fromTheme(
          SlideThemePresets.byName('Mono Ink'));
      expect(mono.onAccent, const Color(0xFF1A1A1A));
      final ocean = SlidePalette.fromTheme(
          SlideThemePresets.byName('Ocean'));
      expect(ocean.onAccent, const Color(0xFFFFFFFF));
    });

    test('title/body/muted derive from theme text color', () {
      final pal = SlidePalette.fromTheme(
          SlideThemePresets.byName('Paper'));
      expect(pal.title, const Color(0xFF1C1917));
      expect(pal.body.a, lessThan(1.0));
      expect(pal.muted.a, lessThan(pal.body.a));
    });
  });

  group('SlideDeckController.applyThemePreset', () {
    late SlideDeckController c;
    setUp(() {
      Get.testMode = true;
      c = SlideDeckController();
    });
    tearDown(() => Get.delete<SlideDeckController>(force: true));

    test('switches palette without touching content fields', () {
      c.applyThemePreset('Paper');
      expect(c.theme.value.name, 'Paper');
      expect(c.theme.value.backgroundColor, '#faf7f2');
      expect(c.theme.value.fontHeading, 'Lora');
    });

    test('preserves brand-kit logo across switches', () {
      c.theme.value = SlideDeckTheme(
        name: 'x',
        primaryColor: '#000000',
        secondaryColor: '#000000',
        backgroundColor: '#000000',
        textColor: '#ffffff',
        accentColor: '#000000',
        fontHeading: 'Inter',
        fontBody: 'Inter',
        logoBytes: [1, 2, 3],
      );
      c.applyThemePreset('Ocean');
      expect(c.theme.value.name, 'Ocean');
      expect(c.theme.value.logoBytes, [1, 2, 3]);
    });

    test('unknown name falls back to default', () {
      c.applyThemePreset('does-not-exist');
      expect(c.theme.value.name, 'Modern Terracotta');
    });
  });
}
