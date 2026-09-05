# Platform Differences — Intentional, Documented

Per `docs/multiplatfrom.md` §8.3: if a feature is genuinely infeasible on a target, state exactly why and the closest real alternative — do not silently drop it.

## Summary

| Feature | Android (primary, full) | Web (Flutter Web) | Windows Desktop (Flutter Windows) |
|---------|------------------------|-------------------|-----------------------------------|
| **Local LLM (llama.cpp GGUF)** | ✅ Full — `llama_flutter_android`, GPU Vulkan/OpenCL, resident pool, instant switch | ❌ Cloud-only — `dart:io` unavailable, `inference_stub` returns `supportsLocalInference=false`; `File`/`mmap` not possible in browser sandbox | ❌ Cloud-only (for now) — `local_plugins` are Android FFI only; Windows runner has no `llama.dll` yet. Stub returns `Cloud mode` banner. **Roadmap:** add `local_plugins/llama_flutter_windows` |
| **LiteRT-LM (.litertlm)** | ✅ Full — `flutter_litert_lm` | ❌ Cloud-only | ❌ Cloud-only (same reason) |
| **Stable Diffusion 1.5** | ✅ Full — `sd_flutter_android` (safetensors) | ❌ Cloud Stability fallback | ❌ Cloud Stability fallback |
| **Image understanding (Qwen2-VL, Gemma vision)** | ✅ Via GGUF vision | ❌ Cloud vision models (Gemini, GPT-4o, Claude) | ❌ Same as Web |
| **Model download (foreground service, Range resume, START_STICKY)** | ✅ `ModelDownloadService.kt` + `download_native.dart` (Range, `.part`, notification Pause/Cancel) | ⚠️ Browser download — `download_web.dart` stub (direct `AnchorElement` download, no resume, no FGS; `file_picker` save) | ⚠️ Dart fallback — `download_native.dart` `streamDownload` via `HttpClient` (Range, `.part`, but no FGS; Windows service not needed as app stays running) |
| **Storage** | Hive on app-private files (`path_provider`) + `_MemoryBox` fallback | Hive on IndexedDB (same Dart API, different backend) + `_MemoryBox` | Hive on app-private files (same as Android) |
| **Secure storage (MCP bearer)** | `flutter_secure_storage` → Android Keystore | `flutter_secure_storage` → Web `localStorage` (not secure, documented) | `flutter_secure_storage` → Windows Credential Locker |
| **File picker / share** | `file_picker` (Storage Access), `share_plus`, `gal`, `image_picker` (native) | `file_picker` (browser `<input>`), `share_plus` (Web Share API, degrades to download) | `file_picker` (native `GetOpenFileName`), `share_plus` (Windows share) |
| **Notifications** | `flutter_local_notifications` (channels, foreground service notification) | `Web Notifications API` (permission-gated, `flutter_local_notifications` web stub) | `flutter_local_notifications` Windows stub (toast via `win_toast` if added later) |
| **Window chrome** | System status bar (`setPreferredOrientations`, `SystemUiOverlayStyle` per theme) | Browser chrome (no control) | `window_manager`: `400×700` min, `1280×800` default, centered, `CubicLM` title, `normal` titleBar, `show()/focus()` after `waitUntilReadyToShow` |
| **Menu bar / shortcuts** | Bottom nav + drawer | Browser menu (none) | No visual MenuBar (custom chrome design) — desktop keyboard shortcuts in `home_view.dart`: `Ctrl+N` new chat, `Ctrl+F` history search, `Ctrl+,` settings, `Ctrl+1..4` switch tabs |
| **Back navigation** | System back → in-app stack (GetX), not app-exit unless at root | Browser back → GetX stack | `window_manager.setPreventClose(true)` + `onWindowClose` in `main.dart` LockGate state — quits immediately when idle, confirms when a reply is generating or models are downloading |
| **Auto-update** | Play Store / GitHub Releases APK | Web deploy (Vercel/Netlify) — instant | Scaffolding: `windows/updater_config.json` placeholder + doc step “generate your own MSIX signing cert + `msix` pubspec entry”; not auto-enabled (needs signing) |
| **Installer** | `.apk` / `.aab` via `flutter build apk --release --flavor gplay` + `android/key.properties`; `fdroid` flavor (`com.cubiclm.app.fdroid`) for F-Droid source builds | `flutter build web` → static `build/web` deploy (**fixed 2026-09-05**: stub parity — shared `soc_family.dart`, engine + download stubs; flutter_tts web lints are warnings only) | `flutter build windows` → `build/windows/runner/Release/cubiclm.exe` + `windows/installer/cubiclm.iss` (Inno Setup, unsigned — no prod keystore committed per §8.6) |
| **Push / boot persistence** | `flutter_background_service` + `BootReceiver` (`RECEIVE_BOOT_COMPLETED`) | No boot (browser) | No boot (desktop) |
| **Speech-to-text** | `speech_to_text` (Android `RECORD_AUDIO` permission, contextual) | `speech_to_text` Web Speech API (permission-gated) | `speech_to_text_windows` registered — mic button hides automatically when the engine reports unavailable, with a snackbar on failed start |
| **Deep links** | `queries` `PROCESS_TEXT`, `url_launcher` external | `url_launcher` `target="_blank"` + route `/chat/:id` shareable | `url_launcher` `externalApplication` (OS default browser) |
| **Responsive** | Phone-first: `Get.width <800` → bottom nav, `≥800` → sidebar (84dp) + `IndexedStack`; `Flexible` pill `14` char, header `20` char, `Expanded` status row — verified `360/768/1280/1920` per §5.3 | Same Flutter responsive: browser resize reflows identical code; `window_manager` resize also reflows (not fixed canvas) | Same as Web — `windows/runner` window is user-resizable, same `800` breakpoint reflows; `pointer: fine` vs `coarse` hit sizing via `Dt.pillHeight` + `MediaQuery` |

## Why Local Inference Is Cloud-Only on Web/Windows (for now)

- `local_plugins/llama_flutter_android` contains `android/src/main/cpp` + `llama.cpp` built for `arm64-v8a`/`armeabi-v7a` only. No `windows/*.dll` or `wasm` build exists. Shipping a stub that returns `supportsLocalInference=false` and shows a banner (“Local models require Android — use Cloud on this platform”) is the honest closest alternative per §8.3.
- The business logic (`lib/services/inference_service.dart`) is already decoupled — conditional import (`inference_android.dart`, stub only on web) + `supportsLocalInference => Platform.isAndroid || Platform.isIOS` — so adding a Windows native lib later is a single `local_plugins/llama_flutter_windows` + `pubspec` change, no `shared/` duplication.

## Responsive Verification (per §5.3 item 8)

- [x] `~360px` (phone / Android smallest) — no horizontal scroll, no `RenderFlex overflow` (fixed `4.4/12px`), tap targets `≥48dp` (`AppCircleButton 40dp` + padding)
- [x] `~768px` (tablet / narrow desktop) — `800` breakpoint flips bottom nav → sidebar, `IndexedStack` preserves state
- [x] `~1280px` (laptop) — default `window_manager` size, `1280×800`, sidebar + chat `Expanded` + ModelHub grid `2-col`
- [x] `~1920px` (wide desktop) — `maxWidth` + `center` constraints prevent over-stretch; `Dt.rSheet 17`, `Dt.hPadding 14` scale with `rem`
- [x] Desktop window manually resized `400×700` min → `1920` max — reflow verified, not fixed canvas
- [x] Typography `clamp(0.8, 1.4)` `fontScale` + `Dt.text*` tokens — no truncation at extremes
