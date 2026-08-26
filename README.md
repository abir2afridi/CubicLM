<!-- markdownlint-disable-file md033 md041 -->
<p align="center">
  <img src="assets/icons/CubicLM.png" alt="CubicLM" width="128" />
</p>

# CubicLM

> 📱⚡ A cross-platform AI chat application with local on-device inference and multi-provider cloud AI support. Runs LLMs directly on your Android device via GPU-accelerated llama.cpp 🦙 and Google's LiteRT-LM runtime ⚡, with an optional built-in OpenAI-compatible API server 🔌.

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
- **Sampling steps** and **synthesis resolution** for image generation (Auto mode scales by available RAM)
- **Compute backend toggle** (CPU / Vulkan / OpenCL) for image generation with automatic model reload

### 🌐 Web Access (independent chat)

The chat page can fetch live web content on its own — no external services or API keys:

- Toggle the 🌐 button in the input bar; when on, any `https://…` links in your message are downloaded automatically
- Pages are stripped to clean readable text (scripts/styles removed, entities decoded) and injected into the model's context — works for **both local and cloud models**
- Up to 3 links per message, ~9K characters per page, 15s timeout per fetch
- Great for "summarize this article", "what changed on this docs page", or grounding answers in real data

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

### 🔌 Built-in OpenAI-Compatible API Server

- Expose local models as an OpenAI-compatible API on port 8080
- Optional API key authentication
- Use local models from any OpenAI-compatible client on your network

### 🧩 Additional

- **Navigation:** Chat · Explore · Nodes · App Settings
  - **Nodes** page has two tabs — **Node** (local API server) and **Config** (diagnostics, hardware capabilities, inference mode, system prompt, local model & imaging parameters)
  - **App Settings** is its own destination — theme mode, typography scale, **Thinking Orbs** (custom animation per context: chatting / image generation / analyzing — each set to **Random** or any of the 9 states with live preview), and app info (tap to open **About** page with feature highlights, tech stack, and GitHub link)
- Multi-session chat with history (Hive persistence) and a searchable sidebar drawer with swipe-to-delete
- **Message actions** — copy, regenerate, branch into a new chat, and edit with full revision history (step back and forth between edited versions)
- **Code blocks** with syntax highlighting, one-tap copy, and export/share
- **Thinking Orbs** — 3D particle sphere animation (9 states: Working, Searching, Solving, Listening, Connecting, Weaving, Composing, Breathing, Shaping) with grayscale ink, size-aware speeds, and phase-continuous hard cuts; shown during chat responses, thought analysis, and image synthesis — each context configurable to **Random** shuffle or a fixed state via **App Settings › Thinking Orbs** (live orb previews in the picker)
- **Notification history** — 🔔 bell in chat header with unread badge; slide-in page grouped by Today/Yesterday/weekday with relative timestamps (Just now / 5m ago / 2h ago), swipe-to-delete, mark-all-read & clear-all; every model switch (local / cloud / back-to-local) auto-logs with timestamp and shows as a top spring-animated toast (Hive-persisted, max 100)
- Attachments from camera, gallery, or files (PDF/text extraction)
- Image sharing and export
- Dark/light theme with adjustable font scale
- **Background model download** with foreground service — downloads keep running when the app is closed or swiped away; notification with Pause/Cancel actions; HTTP Range resume picks up at the exact byte offset after pause or app restart (START_STICKY)
- Firebase Crashlytics integration
- Background service and boot persistence
- In-app model download with byte-exact pause / resume / cancel, plus file import

#### 🔄 In-Chat Model Switcher

Opened from the chat header — mirrors the Explore page's layout:

- **Local tab**: search box over downloaded models; LiteRT / GGUF / "In memory" badges; live load progress
- **Cloud tab**: every configured provider gets a collapsible section styled like the Explore provider cards — count badges, FREE badge + filter chip, per-provider search, auto-detected company filter chips, and a scrollable boxed model list. A global search box above matches models across **all providers at once** (results show the owning provider); picking a result switches the active provider automatically
- Deactivating the active cloud provider switches inference back to local mode and **auto-loads the last downloaded model**

### 🩺 System Diagnostics (Nodes › Config › System Logs)

- **Health dashboard** — auto-detects 10 crash patterns: model file missing, context overflow, model load failure, GPU error, cloud API error, out of memory, generation hang, stale multi-model slot, import failure, Firebase init
- **Category filters** — System, Model, Cloud, Chat, Server, Image
- **Full-text search** across log messages and details
- **Level filters** — ALL, ERROR, WARNING, INFO, DEBUG
- **Log persistence** — logs survive app restarts (saved to JSON, max 500 entries)
- **Export** — copies full diagnostic report (health summary + all logs) to clipboard
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
- **Local Storage:** Hive
- **Networking:** dio, http
- **Local Inference:** llama_flutter_android, flutter_litert_lm, sd_flutter_android (custom plugins)
- **Cloud:** Firebase Core, Firebase Messaging, Firebase Crashlytics
- **Other:** google_fonts, flutter_markdown, image_picker, share_plus, permission_handler, speech_to_text, lucide_icons, url_launcher

## 📂 Project Structure

```text
lib/
├── main.dart                    # App entry point
├── core/
│   ├── colors.dart              # App color palette (warm Claude-inspired)
│   ├── constants.dart           # Settings keys, model catalog, API endpoints
│   ├── routes.dart              # Route definitions
│   ├── theme.dart               # Light/dark theme with warm accent palette
│   └── design_tokens.dart       # Claude APK-measured warm palette (canvas, pill, accent, hairline)
├── models/
│   ├── ai_model.dart            # AI model data class
│   ├── chat_message.dart        # Chat message model (with revision history)
│   ├── chat_session.dart        # Chat session model
│   ├── task_model.dart          # Automated task model
│   └── notification_entry.dart  # Model-switch history entry (title/message/type/timestamp/read)
├── controllers/
│   ├── chat_controller.dart     # Chat logic and streaming
│   ├── cloud_model_controller.dart  # Cloud model selection
│   ├── home_controller.dart     # Tab navigation, model resume
│   ├── model_controller.dart    # Model download/import management
│   ├── server_controller.dart   # Local API server
│   ├── settings_controller.dart # App settings
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
├── download_service.dart        # Download orchestrator (native FGS + Dart fallback)
│   ├── hive_service.dart        # Local persistence (now also notifications box)
│   ├── notification_history_service.dart # Model-switch history (Hive, max 100, unread count)
│   ├── device_info_service.dart # RAM/tier + SoC/GPU detection
│   ├── web_fetch_service.dart   # URL fetching → clean text for chat context
│   ├── execution_service.dart   # Task execution engine
│   ├── document_extractor_service.dart  # PDF/text extraction
│   ├── local_image_service.dart # Stable Diffusion inference
│   ├── sd_isolate_processor.dart    # SD processing in isolates
│   ├── image_generation_notification_service.dart  # Image gen notifications
│   ├── app_log_service.dart     # App logging with categories, search, crash pattern detection
│   └── crash_reporting_service.dart  # Firebase Crashlytics
├── views/
│   ├── home_view.dart           # Main navigation scaffold (Chat · Explore · Nodes · App Settings)
│   ├── chat_view.dart           # Chat interface with sidebar drawer
│   ├── model_view.dart          # Model browser/manager (Explore page)
│   ├── server_view.dart         # Nodes page — Node tab (API server) + Config tab
│   ├── settings_view.dart       # Config sections (embedded in Nodes › Config)
│   ├── app_settings_view.dart   # App Settings — theme, typography scale, Thinking Orbs picker, app info
│   ├── about_view.dart          # About page — feature highlights, tech stack, GitHub
│   ├── notification_history_view.dart # 🔔 History page (grouped by day, swipe-to-delete, mark read/clear)
│   ├── log_view.dart            # System diagnostics viewer (health dashboard, search, categories)
│   └── task_view.dart           # Automated tasks
├── widgets/
│   ├── chat_bubble.dart         # Message bubble with inline actions + revisions
│   ├── code_block.dart          # Syntax-highlighted code blocks (copy/export)
│   ├── model_switcher_sheet.dart    # Quick model switcher
│   ├── attachment_preview.dart  # File/image attachment preview
│   ├── image_viewer.dart        # Full-screen image viewer
│   ├── thought_disclosure.dart  # Reasoning/thought tag expansion with ThinkingOrb
│   ├── thinking_orb.dart        # 3D particle sphere animation (9 states, size-aware speeds, orbStateFromName helper)
│   └── typing_indicator.dart    # Typing animation
├── ffi/
│   └── sd_ffi_bindings.dart     # FFI bindings for SD native lib
└── utils/
    ├── app_snackbar.dart        # Top spring-animated toast (model switch, cloud, local)
    └── thought_parser.dart      # <thought> tag parser

local_plugins/
├── llama_flutter_android/       # llama.cpp Flutter plugin (GGUF inference)
├── flutter_litert_lm/          # Google LiteRT-LM Flutter plugin
└── sd_flutter_android/         # Stable Diffusion Flutter plugin

android/
├── app/src/main/kotlin/com/cubiclm/app/
│   ├── MainActivity.kt          # Flutter engine + channel wiring
│   └── ModelDownloadService.kt  # Foreground service: Range resume, notification, START_STICKY
```

## 📋 Requirements

- **Flutter** 3.3.0+
- **Android SDK** (minSdk 28 / Android 9+)
- **Java 17**
- For release builds: a keystore configured at `android/key.properties` (see `android/key.properties.example`)

## 🚀 Getting Started

```bash
# Clone the repository
git clone https://github.com/your-username/CubicLM.git
cd CubicLM

# Install dependencies
flutter pub get

# Run on a connected device
flutter run
```

### 📦 Release Build

1. Copy `android/key.properties.example` to `android/key.properties`
2. Fill in your keystore credentials and path
3. Build the release APK:

```bash
flutter build apk --release
```

Or set `CUBICLM_ALLOW_DEBUG_RELEASE_SIGNING=true` to skip keystore validation during development.

## ⚙️ Configuration

### 🔑 Cloud API Keys

Tap **Add API Key** on any provider card in the **Explore** tab — the key is verified and the live model list loads automatically on save. Refresh any time with the ↻ button on a provider card.

### 💾 Local Models

Download models from the **Explore** tab (with pause / resume / cancel support) or import `.gguf` / `.litertlm` / `.safetensors` files via the file picker. Models are stored in app-private storage. Loading is guarded — missing or corrupted files are detected before reaching the native engine, and stale download pointers are cleaned up automatically.

### 🌐 Local API Server

Open the **Nodes** tab › **Node** and flip the switch. Once running, point any OpenAI-compatible client at `http://<device-ip>:8080` to use your local models programmatically.

### ⚙️ Engine & App Configuration

- **Nodes › Config** — diagnostics, hardware capabilities, inference mode, Auto Tune (context/output limits), global system prompt, local model parameters, imaging parameters
- **App Settings** (bottom navigation) — theme, typography scale, Thinking Orbs (Random or fixed state per context), app info
- **Web Access** toggle — in the chat input bar; reads links from your message into the model's context

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.
