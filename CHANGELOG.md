# Changelog

All notable changes to CubicLM are documented here. This is the **single source of truth** per `docs/multiplatfrom.md` §5.5.3 — Desktop and Android `About → What's New` links open this file's rendered route (or its GitHub URL), they do not keep separate copies.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0+8] - 2026-09-03

### Added
- **Biometric App Lock** - `local_auth` gate (Android biometrics + Windows Hello) on launch and background-resume, with lock screen, enrollment detection, and device-PIN fallback.
- **Chat backup & restore** - export every session/message to JSON (Android share sheet, Windows save dialog), validated merge-import, plus **session pinning** (pinned chats float to top).
- **In-app APK update** - GitHub Releases check with download progress and one-tap install on Android; Windows links out to the desktop build.
- **Save models to Downloads** - Model Hub can save GGUF/LiteRT files to the system Downloads folder (Android DownloadManager bridge, desktop stream-then-move with auto-rename).
- **Desktop shortcuts & close guard** - `Ctrl+N` new chat, `Ctrl+F` history search, `Ctrl+,` settings, `Ctrl+1..4` tabs; window close confirms while generating/downloading.
- **Read-aloud (TTS)** - per-bubble text-to-speech with App Settings toggle, locale-matched voices.
- **Gallery history** - SD1.5 generations persist (capped at 200, oldest evicted with files).
- **3-page onboarding** - private/cloud/model setup flow with recommended-model deep link to Explore.
- **Full i18n** - 243 keys x 15 languages, 100% coverage with instant switch.
- **Log viewer + notification history + web-fetch source pills** - in-app diagnostics, past notifications, URL-augmented answers with Sources chips.

### Changed
- **Streaming performance** - chat list no longer rebuilds per token (scoped `Obx` + `RepaintBoundary`), token flush `40ms` to `150ms`, `cacheWidth` thumbnails, one-time base64 decode in composer.
- **Boot recovery** - `BootReceiver` no longer launches the UI (blocked since Android 10); resumes interrupted model downloads via the foreground service only.
- **Windows device info** - real RAM via `device_info_plus` (was fake 4 GB mistuning context sizes); processor label.
- **Manifest hardening** - backup rules wired (`dataExtractionRules`), predictive back, per-app language config (15 locales).
- **Deps** - removed dead `firebase_messaging`, `speech_to_text` 7.4.0.

### Fixed
- **Backup restore always reporting invalid** - picked bytes were stringified (`"[123, ...]"`) instead of UTF-8 decoded.
- **Windows image-attach crash** - gallery pick routes through FilePicker (no `image_picker_windows` registered); camera shows guidance instead of `MissingPluginException`.
- **App Lock first-launch race** - gate awaits biometric detection instead of fail-opening; nothing-enrolled honesty in settings.
- **Mic dead button** - hidden when STT unavailable, snackbar on failed start.
- **Windows build (STT plugin)** - vendored `speech_to_text_windows` 1.0.1 under `local_plugins/` fixing upstream `pluginClass` + missing public header (fatal C1083/C3861).
- **Stale channel name** - `com.aichat.ai_chat/model_import` renamed to `com.cubiclm.app/model_import` on all 4 ends.
- **New chats jumping above pinned sessions** until reload.

## [1.2.0+7] - 2026-08-28

### Added
- **Multi-language support** — 15 languages (EN, BN, HI, AR, ZH, ES, FR, JA, KO, PT, DE, TR, ID, RU, UR) with instant-switch Apple-style picker in App Settings. GetX translations, ~70 keys × 15 languages.
- **GitHub community infrastructure** — issue forms (15 types), PR template, CONTRIBUTING, CODE_OF_CONDUCT, SECURITY, SUPPORT, auto-label workflows, Dependabot, FUNDING.yml, 51 synced labels.

### Fixed
- **Android build stability** — Gradle JVM heap reduced from 8 GB to 3 GB (`-Xmx3072m`) to prevent Kotlin daemon incremental cache OOM/corruption on 16 GB machines. Stale caches cleaned.

## [1.1.0+6] - 2026-08-28

### Added
- **Windows Desktop (production)** — Signed `cubiclm.exe` bundle (`41.1 MB` / `16.22 MB` zip) ships alongside Android APK. Same `lib/` codebase, no separate fork.

### Fixed
- **Windows build** — `CMAKE_POLICY_VERSION_MINIMUM 3.5` for Firebase C++ SDK (CMake 3.5 compat removed in 4.x), `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` for `flutter_inappwebview_windows` / MSVC 14.51 STL1011, `native_assets` install guard (`if(EXISTS)`), and missing ATL headers (`Microsoft.VisualStudio.Component.VC.ATL`).

### Known Limitations
- **Web** — `dart:ffi` (`sd_ffi_bindings.dart`) not yet web-compatible; `flutter build web` fails. Tracked for next release. Android + Windows are the supported targets for `v1.1.0`.

## [1.0.5+5] - 2026-08-28

### Added
- **Windows Desktop** — Flutter Windows shell via `flutter create --platforms=windows` + `window_manager` (`400×700` min, `1280×800` default, centered, `CubicLM` title). Single codebase (`lib/`) ships to Android, Web, and Windows.
- **Shared platform links** — `shared/constants/platformLinks.dart` + `lib/shared/constants/platformLinks.dart` (re-export) with `REPLACE_ME_*` placeholders; all `About` screens import from here (§5.4.1).
- **Cross-platform About** — per §5.5.2: Web links to Desktop+Android+changelog, Desktop links to Website+Android+changelog, Android links to Website+Desktop+changelog; never to itself. Shows `platformLabel • version` from `PlatformLinks` + `SettingsController.appVersion` (§5.5.5).
- **Startup auto-load** — `App Settings → STARTUP → Auto-load last model` (`keyAutoLoadLastModel`), deferred until chat UI idle (splash gone + `DeviceInfo` ready + `1200ms`), with `90s` crash-loop guard, `80%` RAM guard, `90s` load timeout, and resident-model check.

### Changed
- **Warm native splash** — `android/res/values/colors.xml` + `drawable*/launch_background.xml` now `#F8F4ED` (`Dt.canvas`) instead of white — seamless native→Flutter transition.
- **Smooth splash exit** — `splash_view.dart` `RepaintBoundary` isolation + `760ms` fade-in/out, `1380ms` dwell before `Get.offAllNamed(home)`; deferred heavy services now `2200ms` after `runApp()` (was `900ms`), never janks shimmer.
- **Header & composer sync** — both `Obx` on `InferenceService.loadedModelName` / `LocalImageService.loadedModelName`; composer pill `Flexible` + `14` char truncate fixes `RenderFlex overflow 4.4/12px` on 360dp.
- **Download resume** — `download_service.dart` stale `paused_downloads.json` cleanup via `isModelDownloaded` + `ModelController.refreshDownloaded()` fixes “completed but still shows downloading”.
- **Log copy toast** — `log_view.dart` `Get.snackbar BOTTOM` → `AppSnackbar.showTop` (spring, `copyCheck`).

### Fixed
- `HiveService` per-box `3s` timeout + `_MemoryBox` fallback (was `Future.wait` on 7 boxes, one corrupt killed all).
- `ChatController` → `HiveService` defensive `isOpen` + `on HiveError` (was `Box has already been closed` flood).
- `InferenceService` growable `residentTextModels` (was `FixedLengthListMixin` on `clear()`).
- `SkillRegistryService` missing `try` brace.

## [1.0.4] - 2026-08-21

### Added
- Skills + MCP 4-way toggle in Explore, GitHub/URL skill import, MCP remote HTTP/SSE, notification history, web source favicon chips, ThinkingOrbs per-context picker.

### Fixed
- Model switcher free filter, serial numbers, header model row non-tappable, sticky Explore toggle.

## [1.0.0] - 2026-08-01

- Initial Android release — local llama.cpp/LiteRT-LM + cloud providers + OpenAI-compatible server.
