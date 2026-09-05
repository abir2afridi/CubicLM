// Shared single source of truth for cross-platform links.
// See docs/PLATFORM_LINKS.md for how to fill these.
// Do NOT hardcode URLs in individual About screens — import from here.
//
// Placeholders are intentional — the app compiles and renders correctly
// with them. Replace them with real URLs after you publish releases.
//
// For Dart/Flutter, this is a Dart file. For a future JS web build,
// generate or mirror this as shared/constants/platformLinks.ts.

class PlatformLinks {
  PlatformLinks._();

  /// Main website / marketing page.
  static const String websiteUrl = 'https://cubiclm.vercel.app/';

  /// Direct download for Windows desktop installer (.exe / .msi).
  static const String desktopDownloadUrl = 'https://github.com/abir2afridi/CubicLM/releases/latest';

  /// Direct download for Android APK / AAB.
  static const String androidDownloadUrl = 'https://github.com/abir2afridi/CubicLM/releases/latest';

  /// Centralized changelog — single source of truth.
  static const String changelogUrl =
      'https://github.com/abir2afridi/CubicLM/blob/main/CHANGELOG.md';

  /// Website changelog section (user-facing Feature Highlights target).
  static const String websiteChangelogUrl =
      'https://cubiclm.vercel.app/#changelog';

  /// New-issue page (Update page → ⋮ → More → Feedback).
  static const String issuesUrl =
      'https://github.com/abir2afridi/CubicLM/issues/new';

  /// Optional: iOS / other platforms (if you add them later)
  static const String iosDownloadUrl = '';
}
