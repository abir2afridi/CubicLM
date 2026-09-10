# CubicLM v1.13.0 — Release Notes

## Features
- **Streaming upgrades**: granular thought/answer streaming, prompt templates, multi-select messages, live context-window bars for local and cloud.
- **Asset browser + vision stabilization**: browse assets in-app, hardened image-input handling.
- **Projects, artifacts & RAG**: project management, artifact versions, better retrieval in chat.
- **Builder configuration**: guided agent-builder setup and project initialization.

## Fixes
- **GGUF load validation**: truncated/corrupt files are caught before native load (tensor-table validation + correct header offset).
- **Chat crash guards**: artifact null-guard, sidebar init crash fixed.
- **Preview layout**: resize-handle overflow and preview parent-data crash fixed.
- **Vision error UX**: image sent to a non-vision model now shows a helpful message instead of a raw error.
- **Build pins**: Gradle JVM pinned to Temurin 17, `dynamic_color` pinned to 1.8.1.

## Performance
- No perf changes in this release.

## Dependencies
- `dynamic_color` pinned to 1.8.1 (1.9.0 breaks the Gradle build).

## Breaking Changes
- None.

## Downloads
- Android (arm64-v8a, armeabi-v7a, x86_64) APKs + Windows x64 ZIP + checksums below.
