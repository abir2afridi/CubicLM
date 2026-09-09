# CubicLM v1.12.0 — Release Notes

## Features
- **Intelligent code editing**: ghost-text autocomplete, inline AI edits, visual diff review, @mentions, floating prompt overlays.
- **Studio preview**: browser header, resizable viewport, element hover/select bridge, version timeline, auto-scroll.
- **Agent upgrades**: auto npm install, console buffering, binary writes, @mention file/symbol picking, new Knowledge/Responsive/Component views.

## Fixes
- **Silent model-load death fixed**: missing foreground-service declaration added, native errors now surface instead of killing the app, and a kill-proof breadcrumb reports the exact death step on next launch.
- **Engine isolation**: GGUF and LiteRT run in separate engines — no cross-engine regressions, errors name the engine.

## Performance
- No perf changes in this release.

## Dependencies
- No dependency changes in this release.

## Breaking Changes
- None.

## Downloads
- Android (arm64-v8a, armeabi-v7a, x86_64) APKs + Windows x64 ZIP + checksums below.
