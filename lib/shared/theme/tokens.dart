// Shared design tokens — single source for spacing, typography, and breakpoints
// per docs/multiplatfrom.md §5.3 and §5.5. The Flutter app imports via
// `lib/shared/theme/tokens.dart` (re-export) or directly if the build
// tool supports root `shared/` imports. A future Next.js web shell would
// import the mirrored `shared/theme/tokens.ts` generated from this file.

class Breakpoints {
  Breakpoints._();
  // Mobile-first min-width breakpoints (§5.3.3)
  static const double phone = 360;   // ~360–480
  static const double tablet = 600;  // ~600–900
  static const double laptop = 900;  // ~900–1280
  static const double desktop = 1280; // ~1280+
  static const double wide = 1920;   // ultrawide

  // Flutter breakpoint used by HomeView._isWide (sidebar vs bottom nav)
  static const double isWide = 800;
}

class Spacing {
  Spacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 14; // Dt.hPadding
  static const double lg = 20;
  static const double xl = 32;
}

class TypographyTokens {
  TypographyTokens._();
  // Relative scale — use clamp() on web, fontScale * base on Flutter
  static const double base = 14;
  static const double scaleMin = 0.8;
  static const double scaleMax = 1.4;
  // CSS example for web mirror: clamp(1rem, 2vw + 0.5rem, 1.5rem)
}
