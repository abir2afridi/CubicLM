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
  static const String websiteUrl = 'REPLACE_ME_WEBSITE_URL';

  /// Direct download for Windows desktop installer (.exe / .msi).
  /// Example: https://github.com/your-org/CubicLM/releases/download/v1.0.5/CubicLM-1.0.5-windows-x64.msi
  static const String desktopDownloadUrl = 'REPLACE_ME_EXE_DOWNLOAD_URL';

  /// Direct download for Android APK / AAB.
  /// Example: https://github.com/your-org/CubicLM/releases/download/v1.0.5/CubicLM-1.0.5-android.apk
  static const String androidDownloadUrl = 'REPLACE_ME_APK_DOWNLOAD_URL';

  /// Centralized changelog — single source of truth.
  /// All platforms' "What's New" buttons open this.
  /// Example: https://your-website.com/changelog  (or https://github.com/your-org/CubicLM/blob/main/CHANGELOG.md)
  static const String changelogUrl = 'REPLACE_ME_WEBSITE_URL/changelog';

  /// Optional: iOS / other platforms (if you add them later)
  static const String iosDownloadUrl = 'REPLACE_ME_IPA_DOWNLOAD_URL';
}
