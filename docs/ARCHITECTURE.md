# CubicLM — Architecture

> Single coherent product, three shells — not three codebases. Per `docs/multiplatfrom.md` §4–§6.

## 1. Platform Map

```
CubicLM/
├── lib/                      # ← shared product (Dart) — business logic + UI
│   ├── main.dart             # critical path: Hive 5s + Settings before runApp(); heavy services 2200ms after first frame
│   ├── core/                 # constants, routes, theme, colors, design_tokens
│   ├── models/               # ai_model, chat_message (webSources+usedSkills), chat_session, web_source, skill_model
│   ├── controllers/          # GetX: chat, cloud_model, home (idle-deferred auto-load), model, server, settings
│   ├── services/             # hive (_MemoryBox fallback), inference (llama/LiteRT), download (FGS+Range), device_info, cloud/providers/*, skills, mcp, web_fetch
│   ├── views/                # splash (RepaintBoundary shimmer+fade), home (Stateful one-shot checkResume), chat (Obx header/composer sync), model (4-way), about (platform-aware)
│   ├── widgets/              # chat_bubble (Sources+Skills chips), thinking_orb (9 states), model_switcher_sheet, app_snackbar (top spring), etc.
│   ├── utils/                # app_snackbar, thought_parser
│   └── shared/               # ← re-export of root shared/ for Flutter imports
│       └── constants/platformLinks.dart  # single source for website/desktop/apk/changelog URLs
├── shared/                   # ← root single source (JS/TS mirror for future non-Flutter shells)
│   ├── constants/platformLinks.dart   # Dart source — also mirrored as .ts if a Next.js shell is added
│   └── theme/tokens.dart     # (planned) spacing + breakpoint tokens consumed by lib/theme/design_tokens.dart
├── android/                  # Flutter Android shell: Gradle 8.14, minSdk 28, ModelDownloadService.kt (FGS, Range, START_STICKY), MainActivity channel
├── windows/                  # Flutter Windows shell (generated via `flutter create --platforms=windows`): runner/*.cpp, CMakeLists, app_icon.ico
├── web/                      # Flutter Web shell: index.html, manifest.json, web/icons
├── ios/                      # Flutter iOS shell (present, not primary)
├── local_plugins/            # llama_flutter_android, flutter_litert_lm, sd_flutter_android (Android-only FFI)
├── assets/skills/            # 5 bundled skills (bn_en_translator, code_reviewer, efficient_prompting, study_helper, creative_writer)
└── docs/                     # ARCHITECTURE, PLATFORM_DIFFERENCES, BUILD_AND_RUN, PLATFORM_LINKS
```

**Why this shape (§6):** Restructuring `lib/` into `shared/` would have broken the working Android build. We kept `lib/` as the de-facto shared layer (Flutter's `lib` *is* shared across its platform shells) and added `shared/` at root as the *contract* for any future non-Flutter shell (e.g., Tauri/Next.js would consume `shared/constants/platformLinks.ts` generated from the Dart source). No business logic is duplicated.

## 2. Shared vs Platform-Specific

| Category | Location | Shared? | Notes |
|----------|----------|---------|-------|
| API/network, cloud providers | `lib/services/cloud/` | **Yes** — all 18 providers + registry | Thin adapter per provider, same for Web/Android/Windows |
| Auth/token | `lib/services/mcp/mcp_registry_service` + `flutter_secure_storage` | **Yes** | Token in secure storage (Android Keystore / Windows Credential Locker / Web IndexedDB via hive), never in `shared/` plaintext |
| Validation, core algorithms | `lib/services/skills/skill_injector`, `lib/utils/thought_parser` | **Yes** | Pure Dart, no `dart:io` at import time |
| Constants, types, theme | `lib/core/constants`, `lib/models`, `lib/theme/design_tokens` | **Yes** | `shared/theme/tokens.dart` will hold spacing/breakpoint tokens per §5.3 |
| i18n | strings inline + skills | **Yes** (future: `shared/locales/`) | Bangla detection in `skill_injector` |
| Theme tokens | `lib/theme/design_tokens.dart` + `shared/theme/` | **Yes** | `canvas #F8F4ED`, `accent #D97757`, etc. consumed by all shells |
| Storage | `lib/services/hive_service.dart` | **Yes** with platform adapter | `hive_flutter` on Android/Windows, `hive` IndexedDB on Web; `_MemoryBox` fallback on corruption |
| File picker/share | `file_picker`, `share_plus`, `gal`, `image_picker` | **Yes** via plugin abstraction | Plugins internally use native dialogs (Android Storage Access, Windows `GetOpenFileName`, Web `<input>`) — no `dart:io` direct |
| Window chrome | `windows/runner/*`, `lib/main.dart: window_manager` | **No** — Windows only | `window_manager` gated by `!kIsWeb && defaultTargetPlatform==windows` |
| Foreground service | `android/app/.../ModelDownloadService.kt` | **No** — Android only | `START_STICKY`, `Range` resume, notification Pause/Cancel |
| LiteRT / llama native | `local_plugins/*` | **No** — Android only | Windows is cloud-only until Windows llama build is ported (§8.5 justified) |

**Rule enforced (§8.2):** No second copy of `shared/` logic exists. If Windows needs `download_service` differently, it will get a thin adapter, not a fork.

## 3. Key Flows

### 3.1 Startup (critical path never blocks native splash)

```
WidgetsFlutterBinding.ensureInitialized()
→ window_manager (Windows only, 400×700 min, 1280×800 default, centered)
→ AppLogService (Get.put)
→ Hive.initFlutter() 3-4s timeout → HiveService per-box 3s + _MemoryBox fallback
→ SettingsController (theme, fontScale, autoLoadLastModel) — required before runApp
→ CloudModelController, InferenceService, CloudService, DownloadService, LocalImageService, ServerController, ModelController (sync, cheap)
→ runApp(CubicLMApp)  ← native launch_background removed here (warm #F8F4ED, no white flash)
→ addPostFrameCallback: setThemeMode
→ 2200ms delayed: _initDeferredServices (NotificationHistory, SkillRegistry, McpRegistry, DeviceInfo, CrashReporting, ImageNotifications)
→ HomeView initState → 520ms → checkResumeModel → async file check (400ms) → RAM/crash guards → 1200ms idle → loadModel defer
```

### 3.2 Chat (per-prompt skill + web)

```
ChatController.sendMessage()
→ SkillInjector.selectRelevantSkills(prompt, max2, threshold 0.6, Bangla/code heuristics)
→ WebFetchService.augmentWithSources(prompt) → {augmentedText, sources[url/domain/favicon/title/success]}
→ InferenceService.generate() or CloudService.sendMessage() with systemPromptForThisTurn
→ persist ChatMessage{webSources, usedSkills} → ChatBubble renders Sources chips (favicon) + Skills used chips
```

### 3.3 Download (resume)

```
ModelController.downloadModel → DownloadService.downloadModel → startNativeStreamDownload (FGS) or streamDownload (Range)
→ platform Native → MethodChannel importProgress → activeDownloads[filename] (Rx) → ModelView Obx card
→ reconcileActiveDownloads() on resume merges native streams + paused_downloads.json + isModelDownloaded cleanup
```

## 4. Decisions & Tradeoffs (§10)

- **Flutter Windows, not Tauri** (§8.5): Existing `shared/` is Dart, not TS. Porting to Tauri would require rewriting `lib/` in TS/Svelte or bridging Dart→Rust — larger cost than `flutter create --platforms=windows` which reuses 100% of `lib/` for free. Justified per §8.5 lower-total-cost path.
- **window_manager, not manual Win32**: Fleet-tested, handles `waitUntilReadyToShow` correctly, no custom `flutter_window.cpp` edits needed beyond defaults.
- **Decouple first, then scaffold** (§4): `lib/services/hive_service.dart` was refactored to per-box timeout + `_MemoryBox` *before* scaffolding Windows, verified Android still builds — prevents diverging bug fixes.
- **No `shared/` forced restructure** (§6): `lib/` stays canonical; `shared/` at root is the *contract* for future non-Flutter shells, not a breaking move.

## 5. What Was Not Built & Why

- **Linux/macOS shells**: Not requested (§1 lists Web, Windows, Android). `flutter create` could add them in one command when needed — same pattern as Windows.
- **Windows local inference**: `local_plugins` are Android-only FFI. Windows build is **cloud-only** (local toggle shows “Not available on this platform” via `supportsLocalInference==false` stub) — intentional per §8.3, avoids shipping a broken native lib. Roadmap: port `llama.cpp` Windows build to `local_plugins/llama_flutter_windows` and flip the flag.
