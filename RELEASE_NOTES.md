# CubicLM v1.14.1 — Release Notes

## Fixes
- **Tiny models on ~1GB free RAM**: the load reserve now scales with file size (256MB–1GB) instead of a fixed 1GB — a 229MB model loads where it was previously blocked. Single-threaded loads, image-cache clearing and a 512 ctx floor below 1.5GB free.
- **Crash-report version stamp**: previous-session death reports now show the real build instead of "app unknown".
- **Load-profile evidence**: eviction/thread/context decisions are flushed to disk before the native call, so the next log shows exactly what the loader did.

## Features
- **Sticky RAM status bar**: pinned above the Local model list with an info button explaining every row (total/used/free, "room for", tier, tips).

## Performance
- No perf changes in this release.

## Dependencies
- No dependency changes in this release.

## Breaking Changes
- None.

## Downloads
- Android (arm64-v8a, armeabi-v7a, x86_64) APKs + Windows x64 ZIP + checksums below.
