# CubicLM v1.9.0

**CubicWeb Builder goes pro: live streaming builds, real runtimes, system diagnostics.**

The biggest CubicLM release yet — the website builder now streams files live like v0, runs real dev servers, manages terminal CLIs, and tells code errors apart from environment failures.

## What's New

- **Live streaming builds** — files appear as the AI writes; preview reloads live
- **Real local runtime** — project detection, validation, dev servers, real shell
- **Terminal CLI manager** — one-tap installs (Claude Code, OpenCode, Cline, Kilo)
- **CubicWeb System Logs** — CW-* diagnostics, no more infinite AI fix-loops
- **Next.js pipeline** — integrity gates, build check, crash recovery
- **Cloud model tools** — import from /models, test-all with online dots, auto-sync
- **Builder extras** — plan mode, undo history, templates, deploy, diff view, mobile/tablet/desktop preview

## Downloads

| Platform | File |
|---|---|
| Android (arm64) | `cubiclm-v1.9.0-arm64-v8a.apk` |
| Android (arm32) | `cubiclm-v1.9.0-armeabi-v7a.apk` |
| Android (x86_64) | `cubiclm-v1.9.0-x86_64.apk` |
| Windows (x64) | `cubiclm-v1.9.0-windows-x64.zip` |

## Known Limitations

- On-device Node.js is not bundled: framework previews need a desktop or exported ZIP (the app says so explicitly instead of failing silently).
- No cloud execution backend yet — "Use Cloud" explains instead of pretending.
