<!-- markdownlint-disable-file md033 md041 -->
<p align="center">
  <img src="assets/icons/CubicLM.png" alt="CubicLM" width="128" />
</p>

# CubicLM

[![Release](https://img.shields.io/github/v/release/abir2afridi/CubicLM?label=release)](https://github.com/abir2afridi/CubicLM/releases/tag/v1.4.0)
[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20Windows-blue)](https://github.com/abir2afridi/CubicLM/releases/tag/v1.4.0)
[![Website](https://img.shields.io/badge/website-cubiclm.vercel.app-FF4D00)](https://cubiclm.vercel.app)

> 📱⚡ A cross-platform AI chat application with local on-device inference and multi-provider cloud AI support. Runs LLMs directly on your Android device via GPU-accelerated llama.cpp 🦙 and Google's LiteRT-LM runtime ⚡, with an optional built-in OpenAI-compatible API server 🔌.

## 📥 Download — v1.4.0

| Platform | File | Size | Download |
|---|---|---:|---|
| Android (arm64) | `cubiclm-v1.4.0-arm64-v8a.apk` | 60 MB | [GitHub Release](https://github.com/abir2afridi/CubicLM/releases/download/v1.4.0/cubiclm-v1.4.0-arm64-v8a.apk) |
| Android (arm32) | `cubiclm-v1.4.0-armeabi-v7a.apk` | 15 MB | [GitHub Release](https://github.com/abir2afridi/CubicLM/releases/download/v1.4.0/cubiclm-v1.4.0-armeabi-v7a.apk) |
| Android (x86_64) | `cubiclm-v1.4.0-x86_64.apk` | 26 MB | [GitHub Release](https://github.com/abir2afridi/CubicLM/releases/download/v1.4.0/cubiclm-v1.4.0-x86_64.apk) |
| Windows (x64) | `cubiclm-v1.4.0-windows-x64.zip` | 16 MB | [GitHub Release](https://github.com/abir2afridi/CubicLM/releases/download/v1.4.0/cubiclm-v1.4.0-windows-x64.zip) — unzip & run `cubiclm.exe` (WebView2 required) |
| Checksums | `checksums.sha256` | — | [GitHub Release](https://github.com/abir2afridi/CubicLM/releases/download/v1.4.0/checksums.sha256) |

> **Website:** [cubiclm.vercel.app](https://cubiclm.vercel.app) — landing + direct APK / Windows downloads
> **Full notes:** [CHANGELOG.md](CHANGELOG.md) · [Release page](https://github.com/abir2afridi/CubicLM/releases/tag/v1.4.0)
> Web (`dart:ffi`) is tracked for the next release — Android + Windows are the supported targets for `v1.4.0`.

## ✨ Features

### 🧠 Local AI Inference

- **LLM inference** via llama.cpp (GGUF models) with GPU acceleration (Vulkan / OpenCL)
- **LiteRT-LM inference** via Google's LiteRT-LM runtime (.litertlm models)
- **Stable Diffusion 1.5** on-device image generation (safetensors)
- **Vision models** — Qwen2-VL-2B, Gemma 4 E2B/E4B for image understanding
- **Streaming token generation** with real-time tokens-per-second display
- **GPU crash recovery** — automatic CPU fallback if GPU backend fails
- **Device-tier auto-configuration** — adjusts context size and max tokens based on detected RAM
- **Real hardware identification** — reads `ro.soc.*` system properties to show the actual processor (Snapdragon 8 Gen 2, Dimensity 9000, Google Tensor G3…) and probes Vulkan for the GPU renderer name (Adreno, Mali…) instead of a generic "Unknown" label; SoC-aware quantization recommendations follow from the detected family

### 🎛️ Inference Parameters (Nodes › Config)

- **🪄 Auto Tune (default ON)** — one switch that keeps limits optimal:
  - Context window and output budget are set to the highest the device's RAM can safely run (tier-based)
  - Cloud requests are sent **without an output cap**, so large models write full detailed answers instead of stopping mid-response
  - An inline **(i) info dialog** explains exactly what it does
- **Manual mode** — flip Auto off for direct control with extended ranges:
  - Context window ladder from 1K up to **1M tokens** (LiteRT capped to 4K by hardware)
  - Output token ladder from 256 up to **128K tokens**
  - Orange warnings appear past the device's recommended limit but values stay selectable
- **Inference temperature** — applied on every generation, local and cloud
- **Context window changes** auto-reload the resident model after the slider settles
- **RAM guard (new)** — `DeviceInfoService.canAllocateContextSize()` (`fileBytes + KV~2.5KB×context` vs 80% available RAM); `SettingsController.setContextSize` clamps to `maxSafeContextSize` with snackbar, `ModelController._confirmModelLoadSafety` includes KV estimate before showing *Restart recommended*
- **Sampling steps** and **synthesis resolution** for image generation (Auto mode scales by available RAM)
- **Compute backend toggle** (CPU / Vulkan / OpenCL) for image generation with automatic model reload

### 🚀 Startup, Onboarding & Splash

- **Warm native splash** — `launch_background` is `#F8F4ED` (same as `Dt.canvas`), no white flash on cold start; `NormalTheme` matches
- **Animated CubicLM** — 44–48sp PlusJakartaSans w900, shimmer `LinearGradient` isolated in `RepaintBoundary` + `760ms` fade-in/out, `1380ms` dwell → onboarding/home — no jank after `runApp()` was moved to critical path
- **First-run onboarding (new)** — `onboarding_view.dart` 3-page `PageView`: *Private by Default* (shield) → *Or Use Any Cloud* (20+ providers) → *Pick Your First Model* (recommended chip) with dots + `Skip/Next/Start Chatting` (Hive `onboarding_done_v1`, i18n `onboarding_*` EN+BN, fallback for 13 langs)
- **Deferred heavy init** — `NotificationHistory/Skill/MCP/DeviceInfo/CrashReporting/ImageNotifications` start `2200ms` after `runApp()` (after splash), plus `Hive` per-box `3s` timeout with `_MemoryBox` fallback — native `launch_background` never hangs
- **Auto-load last model** — `App Settings → STARTUP` switch (`AppConstants.keyAutoLoadLastModel`). **ON**: after chat UI is idle (splash gone + `DeviceInfo` ready + `1200ms`), checks `isModelLoaded` resident, `90s` crash-loop guard, `80%` RAM guard, then `loadModel().timeout(90s)` off the UI frame. **OFF** (default): shows `Resume Session?` dialog after `520ms`. Prevents `mmap 2-7GB` during splash which previously froze 2nd open

### 🌐 Web Access (independent chat)

The chat page can fetch live web content on its own — no external services or API keys:

- Toggle the 🌐 button in the input bar; when on, any `https://…` links in your message are downloaded automatically
- Pages are stripped to clean readable text (scripts/styles removed, entities decoded) and injected into the model's context — works for **both local and cloud models**
- Up to 3 links per message, ~9K characters per page, 15s timeout per fetch
- **Visible sources** — every successful fetch is shown below the assistant’s answer as tappable chips with **favicon** (Google S2) + domain + page title; failed fetches are not shown but logged. No more “is web search working?” — you see exactly which sites were used, like ChatGPT/Claude, and can tap to open them. Great for “summarize this article”, “what changed on this docs page”, or grounding answers in real data

### ☁️ Cloud AI Providers

- **OpenRouter** (multi-provider gateway — hundreds of models, free tier)
- **Hugging Face** (Inference Providers router — dozens of upstream vendors)
- **xKiro** (smart-routing gateway, free tier, all vendors)
- **TokenRouter** (unified hub — 100+ vendor models)
- **OpenAI** (GPT-5.2, GPT-4o, etc.)
- **Anthropic** (Claude Sonnet 4)
- **Google Gemini** (Gemini 2.5 Flash)
- **DeepSeek** (deepseek-v4-flash)
- **Z.AI** (GLM-5.3 series + free GLM Flash models)
- **Groq** (ultra-fast LPU inference — Llama, Qwen, DeepSeek)
- **Mistral AI** (Large, Codestral, Pixtral)
- **Together AI** (Llama, DeepSeek, Qwen turbo)
- **xAI Grok** (Grok-4, Grok-3, vision)
- **Perplexity** (Sonar — web-grounded answers)
- **Cerebras** (fastest inference — Llama, Qwen, GPT-OSS)
- **Fireworks AI** (production open-model hosting)
- **Cohere** (Command-A, Command-R, Aya)
- **NVIDIA NIM** (Llama 3.1, etc.)
- **Stability AI** (SD3.5 Flash cloud image generation)
- **Custom OpenAI-compatible** endpoints with multiple profile support

All providers share a unified plugin architecture (`lib/services/cloud/providers/`) — each provider implements the `CloudProvider` interface and registers in `CloudProviderRegistry`. Model lists auto-fetch from each provider's API on key save/refresh (with catalog fallback for providers without a `/models` endpoint), with FREE model tagging and filtering where supported. With **Auto Tune** enabled, cloud requests carry no output-token cap — models with 128K+ output budgets answer at full length.

#### 🏷️ Auto-Detected Company Filter

For aggregator providers that host multiple companies' models under `vendor/model` IDs (OpenRouter, Hugging Face, xKiro, TokenRouter, NVIDIA NIM, Together AI, Fireworks…), a company filter chip row appears automatically above the model list. Chips are **derived from the fetched model IDs themselves** — when a vendor releases new models or a brand-new company appears on the aggregator, its filter chip shows up on the next refresh with zero app changes. Known vendor names/icons are prettified automatically; unknown ones fall back to capitalized IDs.

### 🧩 Skills — Offline Instruction Extensions

Skills are **offline, static prompt-injection blocks** (markdown) that teach the model how to handle a class of tasks. No network, no SDK — just text appended to the system prompt. Works identically for local (llama.cpp/LiteRT-LM) and cloud models.

- **Data model** (`lib/models/skill_model.dart`): `id/name/description/author/version/content/enabled/isBuiltIn/source/createdAt`; plain text; file fallback for >100 KB
- **Registry** (`lib/services/skills/skill_registry_service.dart`): Hive `skillsBox` with `installBuiltIns()` (idempotent), `importFromMarkdown`, `enable/disable/delete/getEnabled/getAll`; 5 bundled starters in `assets/skills/` seeded on first run
- **Injection** (`lib/services/skills/skill_injector.dart`): `buildInjectedContext()` / `buildForSkills()` concatenate skills as `### Skill: {name}` blocks, stably ordered. **Intelligent per-prompt activation** — `selectRelevantSkills(prompt, max 2)` scores enabled skills by keywords, Bangla-script detection, code-block presence, etc. (threshold 0.6) and only those are injected via `SettingsController.effectiveSystemPromptForPrompt(model, prompt)` → read by `ChatController` for every generation. The assistant bubble then shows **“Skills used”** chips (check + name, e.g., *Code Reviewer*) — exactly like ChatGPT/Claude’s skill indicator — so you see which skill was judged relevant for that prompt; if none match, no injection and no chip
- **Starter skills** (real content, not placeholders):
  - *Bangla-English Translator* — bilingual Banglish handling
  - *Code Reviewer* — Flutter/Dart/Python/JS senior review
  - *On-Device Efficient Prompting* — concise, structured for 2K–8K contexts
  - *Study Helper — ELI12* — analogy + quiz format
  - *Creative Writer* — stories/poems/scripts
- **UI** — dedicated **Explore → Skills** tab (4-way toggle: Local / Online / Skills / MCP) plus the same card in **Nodes › Config → SKILLS** (next to Global System Prompt) for quick access: grouped card with count, **Import → From file** (file_picker), **Browse Anthropic skills** (`anthropics/skills` via GitHub REST + raw fetch, cached 6h, rate-limit safe), **From URL** (any raw markdown URL, size/type checked, preview-before-enable). GitHub browse is a flat list (no search/categories) with per-item Import; URL import shows preview (frontmatter-parsed name/description) before save. All imports converge on `importFromMarkdown`.

### 🔌 Custom MCP Server — Single Remote Connection (no marketplace)

A power-user setting in **Nodes › Config** to connect one user-provided **remote** MCP server (Streamable HTTP / SSE). No stdio, no marketplace, no multi-server, no OAuth UI — intentionally minimal.

- **SDK** — `dart_mcp ^0.5.2` (labs.dart.dev) + `mcp_client` fallback checked; only remote transport is exposed. Hand-rolled JSON-RPC is avoided where the SDK fits; Flutter ergonomics fallback is HTTP/SSE via `dio`.
- **Connection** (`lib/services/mcp/mcp_connection.dart`): `connect()` (initialize → notifications/initialized → tools/list), `listTools()`, `callTool(name, args)` (size-capped, untrusted), `disconnect()`, `statusStream` (disconnected/connecting/connected/error) with typed errors (auth/timeout/unreachable). Session ID via `mcp-session-id` header, SSE data-frame parsing, bearer auth from secure storage.
- **Config** (`lib/services/mcp/mcp_config.dart`): single `McpConfig` (name/url/transport/bearer/enabled), transport auto-inferred from URL, Hive `mcpBox` single record.
- **Registry** (`lib/services/mcp/mcp_registry_service.dart`): Hive + `flutter_secure_storage` (Keystore/Keychain) for token (never in Hive/plaintext), `saveConfig/testConnection/enable/disable/remove`, status/tools observables, `WidgetsBindingObserver` to disconnect on background and reconnect on resume.
- **LLM wiring**: `CloudProvider.supportsMcpTools` + `buildRequestBody(mcpTools)` adds `tools`/`tool_choice: auto` for OpenAI-compatible providers; `OpenAICompatibleProvider.sendMessage/streamMessage` detects `tool_calls`, calls `McpRegistryService.callTool`, round-trips `tool` result via second request, then returns final answer (streaming buffers tool deltas and re-emits final answer chunked). Local models skip tools (no reliable structured output) but still benefit from Skills. Offline/unreachable still advertises tools; failed `callTool` surfaces as error tool-result.
- **UI** — dedicated **Explore → MCP** tab and the same form in **Nodes › Config → CUSTOM MCP SERVER** (`_McpSection` + `explore_skills_mcp_tabs.dart`): single form (name, URL, bearer token with eye toggle, transport auto), Save / Test / Enable-Disable (with pre-enable tool preview dialog) / Remove, live status dot + banner, and exposed-tools list (name + description) before enabling. Stored token never enters LLM context. Explore’s 4-way toggle (Local / Online / Skills / MCP) keeps everything discoverable in one place.

### 🔌 Built-in OpenAI-Compatible API Server

- Expose local models as an OpenAI-compatible API on port 8080
- Optional API key authentication
- Use local models from any OpenAI-compatible client on your network

### 🧩 Additional

- **Navigation:** Chat · Explore · Nodes · App Settings
  - **Explore** now has a 4-way toggle — **Local** (on-device models) / **Online** (cloud providers) / **Skills** (offline prompt extensions) / **MCP** (custom remote server) — so models, skills, and MCP are discoverable in one hub
  - **Nodes** page has two tabs — **Node** (local API server) and **Config** (diagnostics, hardware capabilities, inference mode, system prompt, Skills, Custom MCP Server, local model & imaging parameters)
  - **App Settings** is its own destination — theme mode, typography scale, **Thinking Orbs** (custom animation per context: chatting / image generation / analyzing — each set to **Random** or any of the 9 states with live preview), **Language** (15 languages including Bangla, Hindi, Arabic, Chinese, Spanish, French, Japanese, Korean, Portuguese, German, Turkish, Indonesian, Russian, Urdu — instant switch, Hive-persisted), **Startup → Auto-load last model**, and app info (tap to open **About** page with feature highlights, tech stack, and GitHub link)
- Multi-session chat with history (Hive persistence) and a **full-text searchable** sidebar drawer (`HiveService.searchMessages` scans `content`) with swipe-to-delete, long-press Export/Delete, and header Export (`share_plus` Markdown)
- **Message actions** — copy, **share**, regenerate, branch into a new chat, and edit with full revision history (step back and forth between edited versions)
- **Code blocks** with syntax highlighting, one-tap copy, and export/share
- **Thinking Orbs** — 3D particle sphere animation (9 states: Working, Searching, Solving, Listening, Connecting, Weaving, Composing, Breathing, Shaping) with grayscale ink, size-aware speeds, and phase-continuous hard cuts; shown during chat responses, thought analysis, and image synthesis — each context configurable to **Random** shuffle or a fixed state via **App Settings › Thinking Orbs** (live orb previews in the picker)
- **Empty state** — `assets/icons/CubicLM.png` 64×64 + animated `CubicLM` shimmer (same engine as splash) above suggestions — never a blank screen
- **Header & composer sync** — `chat_view.dart:302,1185` both `Obx` on `InferenceService.loadedModelName` / `LocalImageService.loadedModelName` + `SettingsController` mode; composer pill `Flexible` + `14` char truncate prevents `RenderFlex overflow 4.4/12px` on 360dp
- **Notification history** — 🔔 bell in chat header with unread badge; slide-in page grouped by Today/Yesterday/weekday with relative timestamps (Just now / 5m ago / 2h ago), swipe-to-delete, mark-all-read & clear-all; every model switch (local / cloud / back-to-local) auto-logs with timestamp and shows as a top spring-animated toast (`AppSnackbar.showTop` `lib/utils/app_snackbar.dart:29`), Hive-persisted, max 100. `LogView` copy now also uses top toast, not bottom
- **Chat enrichments** — assistant bubbles show **Sources** chips (favicon + domain + title, tap to open) when web search was used, and **Skills used** chips (check + skill name) when a prompt matched enabled skills — so you instantly see *whether* web fetch worked and *which* skill was activated, just like ChatGPT/Claude
- Attachments from camera, gallery, or files (PDF/text extraction)
- Image sharing and export
- Dark/light theme with adjustable font scale
- **Background model download** with foreground service — downloads keep running when the app is closed or swiped away; notification with Pause/Cancel actions; HTTP Range resume picks up at the exact byte offset after pause or app restart (START_STICKY). **Resume race + atomicity fixed (new)** — `download_service:68` atomic `.tmp→rename` for `paused_downloads.json`, `download_native:427` `validateDownloadedFile()` (GGUF `GGUF` / litertlm `LITERTLM` / safetensors `{` + 1% size), `reconcileActiveDownloads` prefers native and cleans stale completed before restore, `model_controller:199` async header check for imported files
- Firebase Crashlytics integration
- Background service and boot persistence
- In-app model download with byte-exact pause / resume / cancel, plus file import

### 🖥️ Universal Multi-Platform — One Codebase, Three Shells

> **Web ⇄ Windows Desktop ⇄ Android** — same `lib/` product, not three forks. Per `docs/multiplatfrom.md` (AUDIT→PLAN→BUILD).

- **Android (primary, full)** — `android/` Gradle 8.14 + `ModelDownloadService.kt` (FGS, Range, `START_STICKY`), native storage, background service & boot persistence
- **Web (Flutter Web)** — `web/` static shell (`index.html`, `manifest.json`), Hive IndexedDB, `dart:io` stubs (`download_web.dart`, `inference_stub.dart`); `flutter build web` → `build/web`
- **Windows Desktop (Flutter Windows, not Tauri per §8.5)** — `windows/` CMake runner, `window_manager 0.4.3` (`400×700` min, `1280×800` default, centered, `CubicLM` title, `waitUntilReadyToShow`), native file dialogs via `file_picker`, `flutter build windows` → `build/windows/runner/Release/cubiclm.exe`
- **Why Flutter Windows, not Tauri?** Existing `shared` is Dart (`lib/`), not TS — Tauri would require rewriting `lib/` in TS/Svelte or bridging Dart→Rust; `flutter create --platforms=windows` reuses 100% of `lib/` for free (lower total cost, §8.5 justification)
- **Single source of truth** — `shared/constants/platform_links.dart` + `lib/shared/constants/platform_links.dart` (now set to `https://cubiclm.vercel.app` + GitHub Releases). `About → AVAILABLE ON` links to the *other two* platforms + centralized `CHANGELOG.md`, never to itself, via `launchUrl(externalApplication)` (Web `_blank`, Desktop OS browser, Android Browser tab) — see `docs/PLATFORM_LINKS.md`
- **Responsive, not forked** — `lib/shared/theme/tokens.dart` (`Breakpoints.phone 360/tablet 600/laptop 900/desktop 1280/wide 1920`, `Spacing`, `TypographyTokens`) + `Dt` tokens; `HomeView._isWide 800` (sidebar vs bottom nav), `Flexible` pill `14` chars, `Expanded` header — verified `360/768/1280/1920` + manual resize `400×700` → `1920` per §5.3 (no `MobileHomePage` vs `DesktopHomePage` fork)
- **Platform differences documented** — `docs/PLATFORM_DIFFERENCES.md` (local inference cloud-only on Web/Windows until `local_plugins/llama_flutter_windows` ported), `docs/ARCHITECTURE.md`, `docs/BUILD_AND_RUN.md`, `scripts/build-all.ps1` / `.sh`
- **Windows local inference (intentional gap §8.3):** `local_plugins` are Android FFI only → `supportsLocalInference=false` on `TargetPlatform.windows`, shows cloud banner; roadmap is `local_plugins/llama_flutter_windows` (`llama.dll`)

#### 🔄 In-Chat Model Switcher

Opened from the chat header — mirrors the Explore page's layout:

- **Local tab**: search box over downloaded models; LiteRT / GGUF / "In memory" badges; live load progress
- **Cloud tab**: every configured provider gets a collapsible section styled like the Explore provider cards — count badges, FREE badge + filter chip, per-provider search, auto-detected company filter chips, and a scrollable boxed model list. A global search box above matches models across **all providers at once** (results show the owning provider); picking a result switches the active provider automatically
- Deactivating the active cloud provider switches inference back to local mode and **auto-loads the last downloaded model**

### 🩺 System Diagnostics (Nodes › Config › System Logs)

- **Health dashboard** — auto-detects 10 crash patterns: model file missing, context overflow, model load failure, GPU error, cloud API error, out of memory, generation hang, stale multi-model slot, import failure, Firebase init; `RenderFlex overflow` is logged as `ERROR [System]` but correctly shows **No crash patterns** (layout, not model)
- **Category filters** — System, Model, Cloud, Chat, Server, Image
- **Full-text search** across log messages and details
- **Level filters** — ALL, ERROR, WARNING, INFO, DEBUG
- **Log persistence** — logs survive app restarts (saved to JSON, max 500 entries)
- **Export** — copies full diagnostic report (health summary + all logs) to clipboard (top toast)
- **Crash pattern details** — occurrence count, last-seen timestamp, and fix suggestion for each detected issue

## 🤖 Supported Models

### ⚡ LiteRT-LM (on-device)

| Model | Size | Description |
| ----- | ---- | ----------- |
| Qwen3-0.6B | 586 MB | Smallest chat model for low-RAM phones |
| Qwen2.5-1.5B Instruct | 1.49 GB | Balanced int8 quantized chat model |
| DeepSeek-R1-Distill-Qwen-1.5B | 1.71 GB | Reasoning-focused model |
| Gemma 4 E2B Instruct | 2.46 GB | Google Gemma vision + chat |
| Gemma 4 E4B Instruct | 3.40 GB | Highest quality LiteRT option |

### 🐫 GGUF (llama.cpp)

| Model | Size | Description |
| ----- | ---- | ----------- |
| Kimi Moonlight 16B-A3B (Q3_K_S) | 7.1 GB | MoE, 3B active params |
| Qwen2.5-3B Instruct (Q4_K_M) | 2.1 GB | Best mobile speed/quality |
| Qwen2-VL-2B (Q4_K_M) | 1.5 GB | Vision-capable |
| Phi-3.5 Mini (Q4_K_M) | 2.2 GB | Microsoft reasoning model |
| Gemma 2 2B (Q4_K_M) | 1.71 GB | Google lightweight chat |
| Llama-3.2-3B Uncensored | 2.1 GB | Unrestricted assistant |
| Llama-3.2-1B Instruct | 0.8 GB | Ultra-lightweight |
| + uncensored/abliterated variants | — | Dolphin, SmolLM2, Gemma abliterated |

### 🎨 Image Generation (Stable Diffusion 1.5)

| Model | Size | Description |
| ----- | ---- | ----------- |
| DreamShaper 8 LCM | 2.0 GB | Fast 4-step generation |
| CyberRealistic V8 FP16 | 2.0 GB | Photorealistic, uncensored |
| Realistic Vision V5.1 FP16 | 2.0 GB | Popular portrait/scene model |
| AbsoluteReality 1.8.1 | 2.0 GB | General-purpose photorealistic |
| AnyLoRA | 2.0 GB | Anime / stylized |

## 🛠️ Tech Stack

- **Framework:** Flutter 3.x
- **Language:** Dart, Kotlin, C++ (native plugins)
- **State Management:** GetX
- **Localization:** 15 languages — EN, BN, HI, AR, ZH, ES, FR, JA, KO, PT, DE, TR, ID, RU, UR (GetX Translations, Hive-persisted) — **90+ keys** (`nav_*`, `chat_*`, `model_*`, `nodes_*`, `about_*`, `settings_*`, `onboarding_*`) with `fallbackLocale EN`; App Settings + bottom nav + all 5 views now reactive via `'.tr'`
- **Local Storage:** Hive
- **Networking:** dio, http
- **Local Inference:** llama_flutter_android, flutter_litert_lm, sd_flutter_android (custom plugins)
- **Cloud:** Firebase Core, Firebase Messaging, Firebase Crashlytics
- **Other:** google_fonts, flutter_markdown, image_picker, share_plus, permission_handler, speech_to_text, lucide_icons, url_launcher, file_picker, flutter_secure_storage, dart_mcp, window_manager

## 📂 Project Structure

```text
lib/
├── main.dart                    # App entry point — window_manager on Windows + critical path (Hive 5s + Settings) before runApp(), heavy services 2200ms after first frame, _MemoryBox fallback
├── core/
│   ├── colors.dart              # App color palette (warm Claude-inspired)
│   ├── constants.dart           # Settings keys (incl. autoLoadLastModel, keyLanguage, keyOnboardingDone), model catalog, API endpoints
│   ├── routes.dart              # Route definitions
│   ├── theme.dart               # Light/dark theme with warm accent palette
│   ├── design_tokens.dart       # Claude APK-measured warm palette (canvas #F8F4ED, pill, accent, hairline)
│   ├── languages.dart           # 15 supported languages (code, name, nativeName, flag, Locale)
│   └── app_translations.dart    # GetX Translations — ~160 keys × 15 languages (settings, chat, navigation, common, onboarding)
├── models/
│   ├── ai_model.dart            # AI model data class
│   ├── chat_message.dart        # Chat message model (with revision history + webSources + usedSkills)
│   ├── chat_session.dart        # Chat session model
│   ├── web_source.dart          # Web source (url/domain/favicon/title/success)
│   ├── task_model.dart          # Automated task model
│   ├── notification_entry.dart  # Model-switch history entry (title/message/type/timestamp/read)
│   └── skill_model.dart         # Skill (name/description/content/enabled/isBuiltIn/source)
├── controllers/
│   ├── chat_controller.dart     # Chat logic, streaming, per-prompt skill/web-source tracking (webSources + usedSkills persisted)
│   ├── cloud_model_controller.dart  # Cloud model selection
│   ├── home_controller.dart     # Tab navigation, model resume (520ms delay, async file check, 90s crash guard, 80% RAM guard, chat-idle defer)
│   ├── model_controller.dart    # Model download/import management
│   ├── server_controller.dart   # Local API server
│   ├── settings_controller.dart # App settings + locale (15 langs), baseSystemPromptForModel / effectiveSystemPromptForPrompt (selective skills) + autoLoadLastModel
│   └── task_controller.dart     # Automated task execution
├── services/
│   ├── cloud_service.dart       # Multi-provider cloud API (delegates to providers)
│   ├── cloud/                   # Cloud provider plugin architecture
│   │   ├── cloud_provider.dart          # Abstract CloudProvider interface
│   │   ├── cloud_provider_registry.dart # Provider registry (ID → instance)
│   │   └── providers/                   # One file per provider
│   │       ├── openai_compatible_provider.dart  # Shared OpenAI-format base
│   │       ├── openai_provider.dart
│   │       ├── anthropic_provider.dart          # Native Messages API
│   │       ├── google_provider.dart             # Native Gemini API
│   │       ├── deepseek_provider.dart
│   │       ├── zai_provider.dart                # GLM catalog models
│   │       ├── groq_provider.dart
│   │       ├── mistral_provider.dart
│   │       ├── together_provider.dart
│   │       ├── xai_provider.dart
│   │       ├── perplexity_provider.dart
│   │       ├── cerebras_provider.dart
│   │       ├── fireworks_provider.dart
│   │       ├── cohere_provider.dart
│   │       ├── huggingface_provider.dart        # HF Inference Providers router
│   │       ├── xkiro_provider.dart              # Smart-routing gateway
│   │       ├── tokenrouter_provider.dart        # Unified vendor hub
│   │       ├── kimi_provider.dart
│   │       ├── nvidia_provider.dart
│   │       ├── openrouter_provider.dart         # FREE tag parsing
│   │       ├── stability_provider.dart          # Image generation
│   │       └── custom_provider.dart             # User-defined endpoint
│   ├── inference_service.dart   # Cross-platform inference orchestrator
│   ├── inference_android.dart   # Android llama.cpp / LiteRT engine bridge
│   ├── openai_server_service.dart   # Built-in OpenAI-compatible server
│   ├── download_native.dart         # Resumable streaming downloader (HTTP Range) + native bridges
├── download_web.dart            # Web stubs
├── download_service.dart        # Download orchestrator (native FGS + Dart fallback, stale-paused cleanup + isModelDownloaded guard)
│   ├── hive_service.dart        # Local persistence (7 boxes, per-box 3s timeout, _MemoryBox fallback, isFallback flag) + `searchMessages()` full-text
│   ├── notification_history_service.dart # Model-switch history (Hive, max 100, unread count)
│   ├── skills/
│   │   ├── skill_registry_service.dart # Hive skillsBox, import, enable/disable, file fallback
│   │   ├── skill_injector.dart         # Concatenates skills + intelligent per-prompt selection (max 2, threshold 0.6, Bangla/code/creative heuristics)
│   │   ├── github_skill_source.dart    # anthropics/skills REST + raw fetch, cached 6h
│   │   └── url_skill_source.dart       # Any URL markdown fetch with size/type guard
│   ├── mcp/
│   │   ├── mcp_config.dart             # Single McpConfig (url/transport/bearer/enabled)
│   │   ├── mcp_connection.dart         # HTTP/SSE JSON-RPC: connect/listTools/callTool
│   │   └── mcp_registry_service.dart   # Hive + secure storage, status stream, lifecycle
│   ├── device_info_service.dart # RAM/tier + SoC/GPU detection
│   ├── web_fetch_service.dart   # URL fetching → clean text + WebSource (domain/favicon/title) via augmentWithSources
│   ├── execution_service.dart   # Task execution engine
│   ├── document_extractor_service.dart  # PDF/text extraction
│   ├── local_image_service.dart # Stable Diffusion inference
│   ├── sd_isolate_processor.dart    # SD processing in isolates
│   ├── image_generation_notification_service.dart  # Image gen notifications
│   ├── app_log_service.dart     # App logging with categories, search, crash pattern detection
│   └── crash_reporting_service.dart  # Firebase Crashlytics
├── views/
│   ├── splash_view.dart         # 1380ms shimmer + 760ms fade-out → onboarding/home (checks `onboarding_done_v1`)
│   ├── onboarding_view.dart     # 3-page PageView (Private/Cloud/Model) + dots + Hive persist, i18n
│   ├── home_view.dart           # Main navigation scaffold (Stateful, one-shot checkResumeModel in initState)
│   ├── chat_view.dart           # Chat interface (drawer + _AnimatedAppName 64px icon + header/composer Obx sync, Flexible pill 14-char)
│   ├── model_view.dart          # Model Hub — 4-way toggle (Local / Online / Skills / MCP)
│   ├── explore_skills_mcp_tabs.dart # Explore Skills + MCP tabs (shared with Nodes Config)
│   ├── server_view.dart         # Nodes page — Node tab (API server) + Config tab
│   ├── settings_view.dart       # Config sections (embedded in Nodes › Config) — now also hosts Skills + MCP form
│   ├── app_settings_view.dart   # App Settings — theme, typography, Thinking Orbs picker, Language (15 langs), Startup auto-load switch, app info
│   ├── language_picker_view.dart # Full-page language picker — flag + nativeName, instant apply + top toast, Apple-style grouped list
│   ├── about_view.dart          # About page — feature highlights, tech stack, GitHub
│   ├── notification_history_view.dart # 🔔 History page (grouped by day, swipe-to-delete, mark read/clear)
│   ├── log_view.dart            # System diagnostics viewer (health dashboard, search, categories, top-toast copy)
│   └── task_view.dart           # Automated tasks
├── widgets/
│   ├── chat_bubble.dart         # Message bubble (inline actions + revisions + Skills used + Sources chips with favicon)
│   ├── code_block.dart          # Syntax-highlighted code blocks (copy/export)
│   ├── model_switcher_sheet.dart    # Quick model switcher
│   ├── attachment_preview.dart  # File/image attachment preview
│   ├── image_viewer.dart        # Full-screen image viewer
│   ├── thought_disclosure.dart  # Reasoning/thought tag expansion with ThinkingOrb
│   ├── thinking_orb.dart        # 3D particle sphere animation (9 states, size-aware speeds, orbStateFromName helper, crisp shimmer)
│   └── typing_indicator.dart    # Typing animation
├── ffi/
│   └── sd_ffi_bindings.dart     # FFI bindings for SD native lib
└── utils/
    ├── app_snackbar.dart        # Top spring-animated toast (model switch, cloud, local, logs-copied)
    └── thought_parser.dart      # <thought> tag parser
├── shared/                      # re-export of root shared/ for Flutter imports
│   ├── constants/platform_links.dart
│   └── theme/tokens.dart        # breakpoints 360/600/900/1280/1920 + spacing

shared/                          # root single source (for future Tauri/Next.js shells)
├── constants/platform_links.dart
└── theme/tokens.dart

windows/                         # Flutter Windows shell (runner/*.cpp, CMake, app_icon.ico, updater_config.json)
├── runner/
├── CMakeLists.txt
└── updater_config.json          # auto-update scaffolding (disabled, REPLACE_ME)

web/                             # Flutter Web shell
├── index.html
└── manifest.json

scripts/
├── build-all.ps1
└── build-all.sh                 # one-command Android+Web+Windows

local_plugins/
├── llama_flutter_android/       # llama.cpp Flutter plugin (GGUF inference)
├── flutter_litert_lm/          # Google LiteRT-LM Flutter plugin
└── sd_flutter_android/         # Stable Diffusion Flutter plugin

android/
├── app/src/main/kotlin/com/cubiclm/app/
│   ├── MainActivity.kt          # Flutter engine + channel wiring
│   └── ModelDownloadService.kt  # Foreground service: Range resume, notification, START_STICKY
└── res/values+drawable/launch_background.xml # Warm #F8F4ED (was white) — seamless native→Flutter

assets/
└── skills/                  # 5 bundled starters (bn_en_translator, code_reviewer, efficient_prompting, study_helper, creative_writer)

docs/
├── ARCHITECTURE.md          # one product, three shells — shared vs platform
├── PLATFORM_DIFFERENCES.md  # Android full vs Web/Windows cloud-only + responsive checklist
├── BUILD_AND_RUN.md         # clean clone → Android/Web/Windows + junctions for spaces
├── PLATFORM_LINKS.md        # single-file link editing
└── ../CHANGELOG.md          # single source (About → What's New on all platforms)

```

## 📋 Requirements

- **Flutter** 3.3.0+
- **Android SDK** (minSdk 28 / Android 9+)
- **Java 17**
- For release builds: a keystore configured at `android/key.properties` (see `android/key.properties.example`)

## 🚀 Getting Started

```bash
# Clone the repository
git clone https://github.com/abir2afridi/CubicLM.git
cd CubicLM

# Install dependencies
flutter pub get

# Run on a connected device
flutter run                 # auto-picks Android/Windows/Web device from `flutter devices`
flutter run -d android      # Android — full local inference
flutter run -d chrome       # Web — cloud-only (Hive IndexedDB), responsive reflow
flutter run -d windows      # Windows — 1280×800 window_manager, cloud-only until llama.dll ported
```

### 📦 Release Build

1. Copy `android/key.properties.example` to `android/key.properties`
2. Fill in your keystore credentials and path
3. Build each shell:

```bash
flutter build apk --release        # → build/app/outputs/flutter-apk/app-release.apk
flutter build windows              # → build/windows/runner/Release/cubiclm.exe (41 MB bundle; zip: 16 MB)
flutter build web                  # → build/web — currently blocked by dart:ffi (see CHANGELOG Known Limitations)
# or one command for supported shells:
pwsh -File scripts/build-all.ps1   # /  bash scripts/build-all.sh
```

> **Windows build prerequisites (v1.2.0):** `nuget.exe` on `PATH` (`flutter_inappwebview_windows`), ATL headers (`Microsoft.VisualStudio.Component.VC.ATL` via Visual Studio Installer), short build path if your checkout contains spaces (e.g. `C:\CLM` junction), and `CL=/D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` for MSVC 14.51 — see [`windows/CMakeLists.txt:1,35,47`](windows/CMakeLists.txt) and [`docs/BUILD_AND_RUN.md`](docs/BUILD_AND_RUN.md).

Or set `CUBICLM_ALLOW_DEBUG_RELEASE_SIGNING=true` to skip keystore validation during development.

## ⚙️ Configuration

### 🔑 Cloud API Keys

Tap **Add API Key** on any provider card in the **Explore** tab — the key is verified and the live model list loads automatically on save. Refresh any time with the ↻ button on a provider card.

### 💾 Local Models

Download models from the **Explore** tab (with pause / resume / cancel support) or import `.gguf` / `.litertlm` / `.safetensors` files via the file picker. Models are stored in app-private storage. Loading is guarded — missing or corrupted files are detected before reaching the native engine, and stale download pointers are cleaned up automatically.

### 🌐 Local API Server

Open the **Nodes** tab › **Node** and flip the switch. Once running, point any OpenAI-compatible client at `http://<device-ip>:8080` to use your local models programmatically.

### 🧩 Skills

Manage in **Nodes › Config → SKILLS** (next to Global System Prompt) — enable/disable built-ins, **Import → From file** (.md), **Browse Anthropic skills** (flat list from `anthropics/skills`, cached, rate-limit safe), **From URL** (any raw markdown link, size/type checked). Every import shows a preview before saving; skills are pure text injection, never executable. Nothing about installed skills is sent to any Abir/Anthropic server.

### 🔌 Custom MCP Server

Configure in **Nodes › Config → CUSTOM MCP SERVER** — single remote HTTP/SSE URL, optional bearer token (secure storage), transport auto-detected. **Save / Test Connection / Enable-Disable (with tool-preview dialog) / Remove** with live status (disconnected/connecting/connected/error). When enabled, its tools are added to OpenAI-compatible cloud requests (`tools`/`tool_choice: auto`); tool results are round-tripped via `chat_controller` and capped. If offline, tools are still advertised and failed calls return an error `tool_result` — never silently omitted. Local models don’t use live tools (Skills still apply).

### ⚙️ Engine & App Configuration

- **Nodes › Config** — diagnostics, hardware capabilities, inference mode, Auto Tune (context/output limits), global system prompt, Skills, Custom MCP Server, local model & imaging parameters
- **App Settings** (bottom navigation) — theme, typography scale, Thinking Orbs (Random or fixed state per context), **Language** (15 languages with instant switch), Startup auto-load, app info
- **Web Access** toggle — in the chat input bar; reads links from your message into the model's context

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.
