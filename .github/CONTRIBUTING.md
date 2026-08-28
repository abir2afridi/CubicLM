# 🤝 Contributing to CubicLM

> Thanks for wanting to contribute to **CubicLM** (`com.cubiclm.app` v1.1.0) — a Flutter cross-platform AI chat app with local inference (`llama.cpp`, `LiteRT-LM`, `SD 1.5`) and 18 cloud providers.

Every contribution — bug fix, Skill, MCP tweak, or doc fix — is welcome. This guide is specific to **this** repository (`abir2afridi/CubicLM`).

---

## 🚀 Setup / Installation

### 📋 Prerequisites

- **Flutter** 3.3+ — `flutter --version` should show 3.38.7+ (Dart 3.10.7+). Install from https://docs.flutter.dev/get-started/install
- **Android:** Android SDK with `compileSdk 36`, `minSdk 28`, JDK **17** (Temurin 17.0.14 recommended — JDK 21/25 breaks the Kotlin 2.2.20 daemon)
- **Windows:** Visual Studio 2022 BuildTools with `Microsoft.VisualStudio.Component.VC.ATL` (provides `atlstr.h` for `flutter_secure_storage_windows`) and `Microsoft.VisualStudio.Component.VC.Tools.x86.x64`, plus `nuget.exe` on `PATH` for `flutter_inappwebview_windows`
- **Git** and a GitHub account

> ⚠️ **Path with spaces** — `D:\GitHub Project\CubicLM` breaks CMake/Firebase SDK extraction. Use the `C:\CLM` junction workaround documented in `docs/BUILD_AND_RUN.md`.

### ⌨️ Commands / Scripts

```bash
# 1. Clone
git clone https://github.com/abir2afridi/CubicLM.git
cd CubicLM

# 2. Install pub deps (reads local_plugins/ overrides for llama_flutter_android)
flutter pub get

# 3. Run (auto-picks device; specify one to force)
flutter run                          # auto
flutter run -d android               # Android — full local inference
flutter run -d windows               # Windows — cloud-only (1280×800 window_manager)
flutter run -d chrome                # Web — cloud-only (Hive IndexedDB), currently blocked by dart:ffi

# 4. Build (one-command for supported shells)
pwsh -File scripts/build-all.ps1     # Windows
bash scripts/build-all.sh            # macOS / Linux
# or individually:
flutter build apk --release          # → build/app/outputs/flutter-apk/app-release.apk (105 MB)
flutter build windows --release      # → build/windows/runner/Release/cubiclm.exe (41 MB bundle, 16 MB zip)
```

Additional commands from `analysis_options.yaml` and `pubspec.yaml`:

| Task | Command |
|------|---------|
| 🧪 Tests | `flutter test` |
| 🎨 Lint | `flutter analyze` (uses `package:flutter_lints/flutter.yaml`) |
| ✨ Format | `dart format .` |
| 🔍 Doctor | `flutter doctor -v` |

---

## 🔀 Pull Requests

### Workflow

1. **Fork** → `git checkout -b feat/your-feature` from `main`
2. Make focused, small commits (Conventional Commits style: `feat(chat): ...`, `fix(download): ...`)
3. Update `CHANGELOG.md` under `[Unreleased]` if user-facing
4. Run `flutter analyze && dart format . && flutter test` — all must pass
5. For Windows changes: verify `flutter build windows --release` still produces `cubiclm.exe` + `data/flutter_assets`
6. Push → open PR using the template (fill all sections; screenshots required for UI changes)
7. Wait for review — address comments, keep history clean (rebase if asked)

### 🎨 Code Style

- **Dart:** `flutter_lints` via `analysis_options.yaml` — `prefer_const_constructors: true`, `avoid_print: false`
- **Formatting:** `dart format .` — no manual tweaks
- **Kotlin:** `android/app/src/main/kotlin/com/cubiclm/app/ModelDownloadService.kt` — follow existing FGS / `START_STICKY` style

---

## 🐛 Bug Reporting

Use the issue forms at **Issues → New issue**:

- 🐛 Bug Report — generic bugs (choose platform: Android / Windows / Web)
- 📱 Mobile Bug Report — Android FGS / SoC / Hive / permissions
- 🔧 Build / CI Failure — Flutter / Gradle / CMake / Firebase logs
- 🔄 Regression Report — worked before, broken now (specify last working version)
- ⚡ Performance Issue — include measured `tok/s`, cold-start, RAM
- 🎨 UI / UX Issue — screenshots required; note breakpoint (360/768/1280/1920)

---

## ✨ Feature Requests

Open **✨ Feature Request** — start with the problem, then the solution. Scope by platform (`lib/` shared vs `windows/` / `android/` / `web/`). Check `CHANGELOG.md` and `docs/ARCHITECTURE.md` first.

---

## 🧪 Tests

- `flutter test` — add tests for new `lib/services/`, `lib/controllers/`, or `lib/utils/` logic where feasible
- Manual QA: `360 dp → 1920 px` responsive check (`lib/shared/theme/tokens.dart` breakpoints), `flutter analyze` clean, and release build smoke test

---

## 🔒 Security

> Do **not** open a public issue for security vulnerabilities. See [SECURITY.md](SECURITY.md) — report privately via **Security Advisories** or the email listed there. Response within 48h, critical fix within 7 days.

---

## 💬 Community

- **Discussions:** https://github.com/abir2afridi/CubicLM/discussions — questions, ideas, show & tell
- **Issues:** https://github.com/abir2afridi/CubicLM/issues — bugs and feature tracking
- **Changelog:** [CHANGELOG.md](../CHANGELOG.md) — single source, linked from **About → What's New** on all platforms

---

## 📄 License

By contributing you agree your contributions are licensed under the **MIT License** — see [LICENSE](../LICENSE).

## 👥 Maintainers

- **Abir Hasan Siam** — CodeCraftedStudio, Dhaka (@abir2afridi)

> 🙏 Thank you for making CubicLM better — every PR matters, even a one-line `docs/PLATFORM_LINKS.md` fix.
