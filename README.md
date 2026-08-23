<p align="center">
  <img src="assets/icons/CubicLM.png" alt="CubicLM" width="128" />
</p>

# CubicLM

A cross-platform AI chat application with local on-device inference and multi-provider cloud AI support. Runs LLMs directly on your Android device via GPU-accelerated llama.cpp and Google's LiteRT-LM runtime, with an optional built-in OpenAI-compatible API server.

## Features

### Local AI Inference
- **LLM inference** via llama.cpp (GGUF models) with GPU acceleration (Vulkan / OpenCL)
- **LiteRT-LM inference** via Google's LiteRT-LM runtime (.litertlm models)
- **Stable Diffusion 1.5** on-device image generation (safetensors)
- **Vision models** — Qwen2-VL-2B, Gemma 4 E2B/E4B for image understanding
- **Streaming token generation** with real-time tokens-per-second display
- **GPU crash recovery** — automatic CPU fallback if GPU backend fails
- **Device-tier auto-configuration** — adjusts context size and max tokens based on detected RAM

### Inference Parameters (live-tunable from Settings)
- **Inference temperature** and **output token limit** — applied on every generation, local and cloud
- **Context window size** — auto-reloads the resident model after the slider settles
- **Sampling steps** and **synthesis resolution** for image generation (Auto mode scales by available RAM)
- **Compute backend toggle** (CPU / Vulkan / OpenCL) for image generation with automatic model reload
- Safety rails warn when values exceed the device's recommended limits

### Cloud AI Providers
- **OpenAI** (GPT-5.2, GPT-4o, etc.)
- **Anthropic** (Claude Sonnet 4)
- **Google Gemini** (Gemini 2.5 Flash)
- **Kimi / Moonshot AI** (kimi-k2.6)
- **NVIDIA NIM** (Llama 3.1, etc.)
- **OpenRouter** (multi-provider gateway)
- **DeepSeek** (deepseek-v4-flash)
- **Stability AI** (SD3.5 Flash cloud image generation)
- **Custom OpenAI-compatible** endpoints with multiple profile support

### Built-in OpenAI-Compatible API Server
- Expose local models as an OpenAI-compatible API on port 8080
- Optional API key authentication
- Use local models from any OpenAI-compatible client on your network

### Additional
- Multi-session chat with history (Hive persistence) and a searchable sidebar drawer with swipe-to-delete
- **Message actions** — copy, regenerate, branch into a new chat, and edit with full revision history (step back and forth between edited versions)
- **Code blocks** with syntax highlighting, one-tap copy, and export/share
- Attachments from camera, gallery, or files (PDF/text extraction)
- Image sharing and export
- Dark/light theme with adjustable font scale
- Firebase Crashlytics integration
- Background service and boot persistence
- In-app model download with pause / resume / cancel, plus file import

## Supported Models

### LiteRT-LM (on-device)
| Model | Size | Description |
|-------|------|-------------|
| Qwen3-0.6B | 586 MB | Smallest chat model for low-RAM phones |
| Qwen2.5-1.5B Instruct | 1.49 GB | Balanced int8 quantized chat model |
| DeepSeek-R1-Distill-Qwen-1.5B | 1.71 GB | Reasoning-focused model |
| Gemma 4 E2B Instruct | 2.46 GB | Google Gemma vision + chat |
| Gemma 4 E4B Instruct | 3.40 GB | Highest quality LiteRT option |

### GGUF (llama.cpp)
| Model | Size | Description |
|-------|------|-------------|
| Kimi Moonlight 16B-A3B (Q3_K_S) | 7.1 GB | MoE, 3B active params |
| Qwen2.5-3B Instruct (Q4_K_M) | 2.1 GB | Best mobile speed/quality |
| Qwen2-VL-2B (Q4_K_M) | 1.5 GB | Vision-capable |
| Phi-3.5 Mini (Q4_K_M) | 2.2 GB | Microsoft reasoning model |
| Gemma 2 2B (Q4_K_M) | 1.71 GB | Google lightweight chat |
| Llama-3.2-3B Uncensored | 2.1 GB | Unrestricted assistant |
| Llama-3.2-1B Instruct | 0.8 GB | Ultra-lightweight |
| + uncensored/abliterated variants | — | Dolphin, SmolLM2, Gemma abliterated |

### Image Generation (Stable Diffusion 1.5)
| Model | Size | Description |
|-------|------|-------------|
| DreamShaper 8 LCM | 2.0 GB | Fast 4-step generation |
| CyberRealistic V8 FP16 | 2.0 GB | Photorealistic, uncensored |
| Realistic Vision V5.1 FP16 | 2.0 GB | Popular portrait/scene model |
| AbsoluteReality 1.8.1 | 2.0 GB | General-purpose photorealistic |
| AnyLoRA | 2.0 GB | Anime / stylized |

## Tech Stack

- **Framework:** Flutter 3.x
- **Language:** Dart, Kotlin, C++ (native plugins)
- **State Management:** GetX
- **Local Storage:** Hive
- **Networking:** dio, http
- **Local Inference:** llama_flutter_android, flutter_litert_lm, sd_flutter_android (custom plugins)
- **Cloud:** Firebase Core, Firebase Messaging, Firebase Crashlytics
- **Other:** google_fonts, flutter_markdown, image_picker, share_plus, permission_handler, speech_to_text

## Project Structure

```
lib/
├── main.dart                    # App entry point
├── core/
│   ├── colors.dart              # App color palette
│   ├── constants.dart           # Settings keys, model catalog, API endpoints
│   ├── routes.dart              # Route definitions
│   └── theme.dart               # Light/dark theme
├── models/
│   ├── ai_model.dart            # AI model data class
│   ├── chat_message.dart        # Chat message model (with revision history)
│   ├── chat_session.dart        # Chat session model
│   └── task_model.dart          # Automated task model
├── controllers/
│   ├── chat_controller.dart     # Chat logic and streaming
│   ├── cloud_model_controller.dart  # Cloud model selection
│   ├── home_controller.dart     # Tab navigation, model resume
│   ├── model_controller.dart    # Model download/import management
│   ├── server_controller.dart   # Local API server
│   ├── settings_controller.dart # App settings
│   └── task_controller.dart     # Automated task execution
├── services/
│   ├── cloud_service.dart       # Multi-provider cloud API
│   ├── inference_service.dart   # Cross-platform inference orchestrator
│   ├── inference_android.dart   # Android llama.cpp / LiteRT engine bridge
│   ├── openai_server_service.dart   # Built-in OpenAI-compatible server
│   ├── download_service.dart    # Model download manager (pause/resume/cancel)
│   ├── hive_service.dart        # Local persistence
│   ├── device_info_service.dart # RAM/tier detection
│   ├── execution_service.dart   # Task execution engine
│   ├── document_extractor_service.dart  # PDF/text extraction
│   ├── local_image_service.dart # Stable Diffusion inference
│   ├── sd_isolate_processor.dart    # SD processing in isolates
│   ├── image_generation_notification_service.dart  # Image gen notifications
│   ├── app_log_service.dart     # App logging
│   └── crash_reporting_service.dart  # Firebase Crashlytics
├── views/
│   ├── home_view.dart           # Main navigation scaffold
│   ├── chat_view.dart           # Chat interface with sidebar drawer
│   ├── model_view.dart          # Model browser/manager
│   ├── server_view.dart         # Local API server UI
│   ├── settings_view.dart       # Settings panel
│   ├── log_view.dart            # App logs viewer
│   └── task_view.dart           # Automated tasks
├── widgets/
│   ├── chat_bubble.dart         # Message bubble with inline actions + revisions
│   ├── code_block.dart          # Syntax-highlighted code blocks (copy/export)
│   ├── model_switcher_sheet.dart    # Quick model switcher
│   ├── attachment_preview.dart  # File/image attachment preview
│   ├── image_viewer.dart        # Full-screen image viewer
│   ├── thought_disclosure.dart  # Reasoning/thought tag expansion
│   └── typing_indicator.dart    # Typing animation
├── ffi/
│   └── sd_ffi_bindings.dart     # FFI bindings for SD native lib
└── utils/
    └── thought_parser.dart      # <thought> tag parser

local_plugins/
├── llama_flutter_android/       # llama.cpp Flutter plugin (GGUF inference)
├── flutter_litert_lm/          # Google LiteRT-LM Flutter plugin
└── sd_flutter_android/         # Stable Diffusion Flutter plugin
```

## Requirements

- **Flutter** 3.3.0+
- **Android SDK** (minSdk 28 / Android 9+)
- **Java 17**
- For release builds: a keystore configured at `android/key.properties` (see `android/key.properties.example`)

## Getting Started

```bash
# Clone the repository
git clone https://github.com/your-username/CubicLM.git
cd CubicLM

# Install dependencies
flutter pub get

# Run on a connected device
flutter run
```

### Release Build

1. Copy `android/key.properties.example` to `android/key.properties`
2. Fill in your keystore credentials and path
3. Build the release APK:

```bash
flutter build apk --release
```

Or set `CUBICLM_ALLOW_DEBUG_RELEASE_SIGNING=true` to skip keystore validation during development.

## Configuration

### Cloud API Keys

Configure cloud providers in **Settings** > **Cloud Provider**, or tap **Add API Key** directly on any provider card in the Models tab — the key is verified and the live model list loads on save.

### Local Models

Download models from the **Models** tab (with pause / resume / cancel support) or import `.gguf` / `.litertlm` / `.safetensors` files via the file picker. Models are stored in app-private storage. Loading is guarded — missing or corrupted files are detected before reaching the native engine, and stale download pointers are cleaned up automatically.

### Local API Server

Start the built-in server from the **Server** tab. Once running, point any OpenAI-compatible client at `http://<device-ip>:8080` to use your local models programmatically.

## License

MIT License. See [LICENSE](LICENSE) for details.
