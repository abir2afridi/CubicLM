# Changelog

All notable changes to CubicLM are documented here. This is the **single source of truth** per `docs/multiplatfrom.md` §5.5.3 — Desktop and Android `About → What's New` links open this file's rendered route (or its GitHub URL), they do not keep separate copies.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.5.0+10] - 2026-09-05

### Added
- **Chat context memory guard** - history rebuilt from storage with token-budget trim (local ~60% ctx, cloud 48k chars); oversized turns middle-truncated, current + previous turn always kept; UI fallback when storage is empty; per-send `Chat context: N turns…` proof line in System Logs.
- **Prompt templates** - 6 built-ins (explain/fix/summarize/ELI12/translate/mail) + custom add/delete, one-tap insert from the composer.
- **Multi-select messages** - long-press or header toggle → bulk copy/share/delete with a selection bar.
- **Per-chat model pin** - switcher-sheet toggle remembers the active local/cloud model for one chat (📌 pill), auto-applied on open.
- **Side-by-side compare** - one-shot challenger (cloud or downloaded local) answers the same prompt; primary setup restored in `finally`.
- **Cloud usage estimates** - per-provider in/out tokens + calls (chars/4) in Explore → Online, with reset.
- **MCP tool approval** - Deny / Allow once / Always-allow gate (fail-closed) + Explore toggle.
- **Auto backup** - silent JSON every N days (last 3 kept) in App Settings → DATA.
- **Lock options** - re-lock timeout (immediate/1/5/15 min) + biometric-only mode.
- **Hidden chats** - stronger hide than archive (out of drawer AND search) with show/hide toggle.
- **Local API hardening** - 120 POSTs/min/IP rate limit (429), in-memory request ring surfaced in capabilities, honest 400 for `/v1/embeddings`.
- **Claude-style prompt View/Code** - every AI answer gets a View ↔ raw toggle; Code mode copies/exports the exact visible text (.md + PDF via share sheet).
- **Chat header overflow menu** - Find / Export / Select moved into a ⋮ menu with icons (cleaner 360dp header).

### Fixed
- **HTML preview localStorage crash** - preview now loads with `https://localhost/` origin + DOM storage enabled (`SecurityError` gone for games with saves/high-scores).
- **Code-block header overflow** - 39px right overflow on narrow screens; buttons go icon-only under 320dp.
- **Provider 429 wall** - rate-limit errors now show a short remedy bubble (wait/retry ETA, BYOK hint); full JSON stays in System Logs.
- **Log spam** - 60 per-vendor `Auto-detected provider` rows collapsed to one summary line.
- **Assistant Copy included think tags** - copy/export now uses the visible answer text.

## [1.4.0+9] - 2026-09-04

### Added
- **Find in chat** - in-conversation search with match counter, prev/next jump, and deep search across older pages.
- **Per-chat persona** - extra instructions per conversation (empty = global prompt), editable from the chat menu.
- **Archive chats** - hide from history with a show/hide toggle; survives backup/restore.
- **Encrypted backups** - optional AES-256-CBC passphrase encryption plus optional image inclusion (was plaintext, imageless).
- **Multi-MCP servers** - connect several servers at once with per-server tokens, merged tools, and collision-safe routing.
- **Image controls** - negative prompt, guidance (CFG) slider, and fixed/random seed in Settings.
- **Hands-free voice mode** - listen → auto-send → speak reply → listen loop with headset toggle.
- **Tasks export ADB scripts** - planner output becomes a runnable `.sh` via share sheet (on-device shell exec is impossible for stock apps).
- **OTA model catalog** - `assets/catalog/models.json` fetched with validation, cache, and bundled fallback (`dart run tool/gen_catalog.dart` to regenerate).

### Changed
- **Updater picks the right APK** - ABI-matched split asset instead of first `.apk`; install-permission gate with settings deep-link.
- **Local server secure by default** - auto-generated API key enforced on first start (LAN bind kept).
- **Mic + STT** - runtime microphone permission flow; recognition follows the app language (was hardcoded `en_US`).
- **Streaming performance** - memoized markdown stylesheets/builders, chat pagination (100/page with load-more), sidebar search on isolate, image preload, PDF/DOCX/PNG/base64 on workers.
- **History hygiene** - 500-session cap (unpinned eviction), paused-download TTL, crash-orphan `.part` sweep, gallery existence cache.
- **MCP settings** - card is now a multi-server summary linking to Explore manager.
- **Deps** - removed dead `flutter_inappwebview` (+ orphan WebGPU asset), `speech_to_text` 7.4 migration.
- **Windows build** - vendored `speech_to_text_windows` fix (upstream registration bug).
- **Desktop parity** - App Lock screenshot blackout (`FLAG_SECURE`), real Windows RAM detection, close guard, shortcuts, save dialogs.

### Fixed
- **Backup restore always invalid** (bytes stringified), **pin-sort jump**, **Windows image-attach crash**, **lock race/enrollment**, **mic dead button**.
- **New-chat/revision/branch/export flows** made pagination-safe (context from storage, full-history branch, window-edge guards).

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
