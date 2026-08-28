# Changelog

All notable changes to CubicLM are documented here. This is the **single source of truth** per `docs/multiplatfrom.md` §5.5.3 — Desktop and Android `About → What's New` links open this file's rendered route (or its GitHub URL), they do not keep separate copies.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
