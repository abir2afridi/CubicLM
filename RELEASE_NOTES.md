# CubicLM v1.2.0

**15 languages. One tap to switch.**

CubicLM now speaks your language — literally. Switch between English, বাংলা, हिन्दी, العربية, 中文, Español, Français, 日本語, 한국어, Português, Deutsch, Türkçe, Bahasa Indonesia, Русский, and اردو instantly from App Settings. No restart needed.

## What's New

- **Language Picker** — Apple-style full-page selector with native script labels and country flags. Instant apply, top toast confirmation.
- **Community Infrastructure** — 15 issue templates, CONTRIBUTING guide, CODE_OF_CONDUCT, SECURITY policy, auto-labeling, Dependabot.
- **Build Fix** — Android Kotlin daemon no longer crashes from memory pressure during incremental builds.

## Downloads

| Platform | File |
|---|---|
| Android (arm64) | `cubiclm-v1.2.0-arm64-v8a.apk` |
| Android (arm32) | `cubiclm-v1.2.0-armeabi-v7a.apk` |
| Android (x86_64) | `cubiclm-v1.2.0-x86_64.apk` |
| Windows (x64) | `cubiclm-v1.2.0-windows-x64.zip` |

## Known Limitations

- Web build blocked by `dart:ffi` (`sd_ffi_bindings.dart`). Android + Windows are supported.
