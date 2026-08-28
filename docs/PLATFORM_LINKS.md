# Platform Links — Single Source of Truth

**File to edit:** `shared/constants/platform_links.dart` (and its mirror `lib/shared/constants/platform_links.dart` — keep them in sync; the `lib/` copy is what Flutter imports).

All three platforms' **About → Available On / What's New** sections import from this one file. You edit **one file, one time**, and every platform updates. Never hardcode URLs directly in `about_view.dart` again.

## What to fill

| Field | What it should be | Example |
|-------|-------------------|---------|
| `websiteUrl` | Your marketing / docs site root. If you have no site yet, use the GitHub repo URL. | `https://cubiclm.app` or `https://github.com/abir2afridi/CubicLM` |
| `desktopDownloadUrl` | Direct link to the Windows installer asset on your latest GitHub Release. | `https://github.com/abir2afridi/CubicLM/releases/download/v1.0.5/CubicLM-1.0.5-windows-x64.msi` (or `.exe` / `.msix`) |
| `androidDownloadUrl` | Direct link to the Android APK/AAB asset on your latest GitHub Release, or Play Store URL once published. | `https://github.com/abir2afridi/CubicLM/releases/download/v1.0.5/CubicLM-1.0.5-android.apk` |
| `changelogUrl` | Centralized changelog route. Must be a single URL that all platforms open. | `https://cubiclm.app/changelog` or `https://github.com/abir2afridi/CubicLM/blob/main/CHANGELOG.md` |

Optional: `iosDownloadUrl` if you later add iOS.

## Placeholders

The file ships with:

```dart
static const String websiteUrl = 'REPLACE_ME_WEBSITE_URL';
static const String desktopDownloadUrl = 'REPLACE_ME_EXE_DOWNLOAD_URL';
static const String androidDownloadUrl = 'REPLACE_ME_APK_DOWNLOAD_URL';
static const String changelogUrl = 'REPLACE_ME_WEBSITE_URL/changelog';
```

- The app **compiles and renders correctly** with these. The About screen detects `REPLACE_ME` and shows *“Configure in platform_links.dart”* plus a snackbar that tells the user exactly which file to edit — it never shows a broken link.
- **Do not invent URLs.** Only fill these after you have actually published a release or site.

## How About uses them

- **Web** (`kIsWeb`): shows Desktop + Android + Changelog — *no* Website link (already on it).
- **Windows Desktop** (`TargetPlatform.windows`): shows Website + Android + Changelog — *no* Desktop self-link.
- **Android** (`TargetPlatform.android`): shows Website + Desktop + Changelog — *no* Android self-link.
- All use `launchUrl(..., LaunchMode.externalApplication)` per §5.5.4: Web → `_blank`, Desktop → OS default browser, Android → Browser tab (with back button, not trapped in WebView).

## Versioning (§5.5.5)

`About` also shows `platformLabel • vX.Y.Z` where `vX.Y.Z` comes from `SettingsController.appVersion` (which reads `package_info_plus` → `pubspec.yaml` `version: 1.0.5+5`). The `+5` build number maps to Android `versionCode` and Windows `msix_version` — keep them in sync via `pubspec.yaml` as the single source.

## Checklist after you fill

- [ ] `flutter analyze` still passes
- [ ] About on each platform shows the *other* two platforms (never itself)
- [ ] Tapping a link opens **outside** the app (browser / external app), not inside the app's WebView
- [ ] `CHANGELOG.md` latest entry's version matches `pubspec.yaml` `version`
