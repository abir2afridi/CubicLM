# Build & Run — One Product, Three Shells

## Prerequisites

- **Flutter 3.3.0+** (`flutter --version`)
- **Java 17** (`JAVA_HOME=C:\JDK17` on Windows) — Gradle 8.14, AGP 8.11.1, Kotlin 2.2.20, minSdk 28
- **Android SDK** (via Android Studio or `C:\Android\Sdk` junction for paths with spaces)
- **Windows** (for `flutter build windows`): Visual Studio 2022 with “Desktop development with C++” + Windows 10 SDK
- No `src-tauri`, `electron`, or `capacitor.config` needed — this repo is **Flutter-native** per §8.5

## Clean Clone → First Run

```bash
git clone https://github.com/abir2afridi/CubicLM.git
cd CubicLM

# If your Windows username or project path contains spaces, create junctions once:
#   mklink /J C:\Android\Sdk "C:\Users\HP 840G5-i7\AppData\Local\Android\Sdk"
#   mklink /J C:\JDK17 "C:\Program Files\Eclipse Adoptium\jdk-17..."
#   mklink /J C:\CubicLM "D:\GitHub Project\CubicLM"

flutter pub get

# ── Android (primary, full features) ──
# Wireless ADB if needed:
#   adb pair <ip>:<port> ; adb connect <ip>:<port>
$env:JAVA_HOME="C:\JDK17"; $env:Path="$env:JAVA_HOME\bin;$env:Path"
flutter run -d android          # or specific device id from `flutter devices`
flutter build apk --debug
# push without cable (wireless ADB sleeps):
#   adb push build/app/outputs/flutter-apk/app-debug.apk /data/local/tmp/app.apk
#   adb shell pm install -r /data/local/tmp/app.apk

# ── Web (Flutter Web, reuses same lib/) ──
flutter config --enable-web
flutter run -d chrome           # hot-reload in browser
flutter build web               # → build/web (static, deploy to Vercel/Netlify)

# ── Windows Desktop (Flutter Windows) ──
flutter config --enable-windows-desktop
flutter create --platforms=windows .   # already done, generates windows/ if missing
flutter run -d windows          # default 1280×800, min 400×700, centered
flutter build windows           # → build/windows/runner/Release/cubiclm.exe

# All shells share `lib/` — no separate `web/` or `desktop/` codebase.
```

## Project Type & Metadata

- `lib/main.dart` is the single entry — `!kIsWeb && defaultTargetPlatform==TargetPlatform.windows` gates `window_manager`.
- `.metadata` tracks `platforms: [root, android, windows, web, ios]` after `flutter create`.
- `pubspec.yaml` `version: 1.0.5+5` is the single source for `About → vX.Y.Z` (via `package_info_plus` → `SettingsController.appVersion`).

## Windows Specifics

- **Window config** — `lib/main.dart` `windowManager.ensureInitialized()` → `WindowOptions(minimumSize 400×700, size 1280×800, center, title CubicLM)` → `waitUntilReadyToShow → show/focus`. Edit there for min size / titleBar.
- **Menu & shortcuts** — `lib/views/home_view.dart` Windows branch: `MenuBar` (File: New Chat `Ctrl+N`, Edit: Search `Ctrl+F`, View: Toggle theme, Help: About) via `CallbackShortcuts` + `SingleActivator`. Fallback to no menu on Android/Web (not needed).
- **File dialogs** — `file_picker` already uses native Windows `GetOpenFileName` — no code change.
- **Installer** — `flutter build windows` gives `cubiclm.exe`. For `.msi`/`.msix` installer:
  ```bash
  dart pub add msix
  flutter pub run msix:create
  # edits pubspec `msix_config:` (publisher, identityName) — use debug cert only, never commit prod cert per §8.6
  # → build/windows/runner/Release/msix/CubicLM.msix
  ```
  Or Inno Setup: `flutter build windows` + `iscc windows/installer.iss`.

- **Local inference on Windows** — currently **cloud-only** (stub). `local_plugins` are Android FFI only; `InferenceService.supportsLocalInference` returns false on `TargetPlatform.windows`. Roadmap: add `local_plugins/llama_flutter_windows` (compile `llama.cpp` to `llama.dll`) and flip the flag.

## Web Specifics

- `flutter run -d chrome` serves `web/index.html` + `canvaskit`/`skwasm`.
- `hive_flutter` on Web uses IndexedDB (same Dart API).
- `dart:io` (`File`, `Platform`) is not available — `device_info_service`, `download_service` already have `if (kIsWeb)` stubs (`download_web.dart`, `inference_stub.dart`). Do not add new `dart:io` imports without a `kIsWeb` guard.
- Deploy `build/web` to any static host; `shared/constants/platformLinks.dart` `websiteUrl` should point here.

## Android Specifics

- `android/app/src/main/kotlin/com/cubiclm/app/ModelDownloadService.kt` is the foreground service (Range, notification, `START_STICKY`).
- `android/app/src/main/AndroidManifest.xml` `FOREGROUND_SERVICE_DATA_SYNC`, `RECEIVE_BOOT_COMPLETED`, `BootReceiver` already configured.
- Signing: `android/key.properties.example` → `android/key.properties` (never commit real keystore per §8.6).

## Scripts

- `scripts/build-all.sh` / `scripts/build-all.ps1` (if present) — runs `flutter build apk --release` + `flutter build web` + `flutter build windows` sequentially. If missing, run the three commands above manually.

## Troubleshooting (paths with spaces)

- `HP 840G5-i7` username and `D:\GitHub Project\CubicLM` both contain spaces → NDK/CMake fails. Use junctions `C:\Android\Sdk`, `C:\JDK17`, `C:\CubicLM` and set `JAVA_HOME`, `ANDROID_SDK_ROOT` accordingly (see top).

## Definition of Done Check (run before PR)

```bash
flutter analyze --no-pub   # 0 issues
flutter test               # if tests exist
flutter build apk --debug
flutter build web
flutter build windows      # on Windows host
# Manual: resize Windows window 400→1920, check no overflow; Android 360dp, no bottom overflow
# About on each platform shows the other two + changelog, never itself
```
