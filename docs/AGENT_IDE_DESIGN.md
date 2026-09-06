# CubicLM Agent-IDE — Technical Design (Mobile Lovable/v0)

> Goal: an AI-powered development environment INSIDE Android —
> "Tell AI → AI builds → Preview → Ask changes → Export."
> Status: design doc. Every section ends with a LOCAL / CLOUD / HYBRID
> verdict and maps to existing CubicLM code where it exists.

## 0. Ground rules (read first)

- The user never sees npm/Node/ports/Gradle. The agent handles it.
- No marketing claims: each runtime call below states what is proven,
  what is experimental, and what is impossible on-device.
- Security is load-bearing: generated code NEVER runs with app privileges.

## 1. Complete system architecture

```
┌──────────────────────────── ANDROID APP ────────────────────────────┐
│ Flutter UI: Chat · Code · Files · Preview · Logs                     │
│ Agent Orchestrator (Dart) ──► Tool Runner                            │
│   ├─ Workspace Store (Hive "projects" box + app-private files)       │
│   ├─ Local Runtimes (WebView ESM · esbuild-wasm · static server)     │
│   ├─ Cloud Gateway (signed API, job queue client, artifact fetch)    │
│   └─ AI Provider Interface (existing CloudProvider + local LLM)      │
└────────────────────────────┬────────────────────────────────────────┘
                             │ HTTPS (auth, signed URLs)
┌────────────────────────────▼────────────────────────────────────────┐
│ CLOUD (only when local cannot do it)                                 │
│ API → Job Queue → Disposable Containers (Node/Gradle/Flutter images) │
│ → Artifact store (TTL) → Preview snapshot / APK / ZIP                │
└──────────────────────────────────────────────────────────────────────┘
```

**Verdict: HYBRID** — static + ESM frameworks local; builds/APK cloud.

## 2. Android architecture

- Flutter UI (existing app) + 1 new feature module: `agent_ide/`
  (`project_model.dart`, `workspace_service.dart`, `tool_runner.dart`,
  `agent_controller.dart`, `preview_server.dart`, views).
- Project workspace: app-private files (`getApplicationDocumentsDirectory()/projects/<id>/`)
  + Hive `projects` box for metadata (name, framework, createdAt, cloudJobIds).
  Sandboxed by OS already (no access to user files without SAF picker).
- Preview: existing `InAppWebView` + a localhost static server for
  multi-file projects (relative assets resolve; single-file keeps the
  `initialData` path). DevTools-style console capture reuses the existing
  `onConsoleMessage` error banner.
- **Verdict: LOCAL** (all Android-native, no root, no Termux).

## 3. AI agent architecture

Loop (max N=6 rounds, then ask user):

```
user msg → Agent (system: repo map + tool defs + budget)
  → tool calls (JSON) → Tool Runner executes → results → Agent
  → repeat until (preview clean AND no errors) or budget out
  → summary + Preview button
```

- Tools (MCP-shaped, reuse existing `callTool` plumbing):
  `create_file, read_file, update_file, delete_file, rename_file,
  list_files, search_code, preview_project, export_project,
  install_dependency (CDN-pinned, see §5), build_project (cloud),
  get_build_logs, run_checks (static lint via esbuild-wasm transform errors
  + WebView console), stop_project`.
- Stateless per turn + persisted transcript in the project (so follow-up
  "make navbar blue" edits ONE file, never regenerates all).
- Guardrails: path jail (reject `..`/absolute), file count/size caps
  (reuse `maxFiles/maxFileChars/maxTotalChars`), timeout per tool,
  human confirm for cloud spend (build/APK buttons already explicit).
- **Verdict: LOCAL orchestration** (works with local LLM too);
  model via existing provider abstraction.

## 4. Local execution architecture

| Project kind | How it runs on-device | Net needed |
|---|---|---|
| Single HTML / Trio | Files → localhost static server → WebView (`initialFile` for entry). localStorage works on `http://127.0.0.1` origin. | First load only if CDN links used |
| React / Vue / Svelte | **ESM-CDN runtime, no npm**: `import React from "https://esm.sh/react@18"` + htm (no JSX compile) OR JSX via **esbuild-wasm** transform in-WebView. Proven pattern (StackBlitz "WebContainers-lite" style, many prod apps). | First fetch; bundling itself is local WASM |
| TypeScript | esbuild-wasm transform (no typecheck; tsc needs Node → cloud or skip with note) | Same as above |
| Tailwind | CDN play script (`https://cdn.tailwindcss.com`) — dev-grade, fine for preview; production build is cloud | Yes (CDN) |
| Next.js SSR / Express / any server JS | **Impossible locally** (needs Node server sockets + npm lifecycle) | Cloud |
| Flutter / Kotlin / Gradle APK | **Impossible locally** (SDK ~10 GB, hours, RAM) | Cloud |

**Verdict: LOCAL for static + ESM frameworks; CLOUD for SSR/builds/APK.**
Do NOT ship Termux/proot Node hacks (break on Android 12+, SELinux, no exec on scoped storage).

## 5. Runtime strategy: Node/React/Vue/Next on Android

1. **Prefer ESM-CDN** (`esm.sh`, `jsdelivr/+esm`): zero install, version-pinned
   URLs the agent writes (`install_dependency` = rewrite the import URL —
   auditable, offline-after-first-load with a cache layer later).
2. **esbuild-wasm** for JSX/TS/minify inside WebView (no server).
3. **Cloud fallback triggers**: `package.json` with non-CDN deps, Next.js
   App Router, SSR/API routes, `npm run build` required, native modules.
4. Decision is automatic per project (framework field), user sees one button.

## 6. APK strategy (Flutter/Kotlin/Java)

- Never on-device. Cloud pipeline: source ZIP → Docker image
  (`flutter stable` / `gradle+jdk17`) → `flutter build apk --split-per-abi`
  → signed? No — **unsigned + user signs** (we must not hold signing keys;
  document `apksigner` step) → artifact TTL 7d → app downloads via
  existing install-permission flow.
- Reuse: existing `REQUEST_INSTALL_PACKAGES` gate + download service.
- **Verdict: CLOUD.**

## 7. Preview architecture (one button)

- Static/Trio/ESM: `GET /preview/:projectId` on the in-app localhost
  server (shelf_static over project dir, random 127.0.0.1 port, server dies
  with the page) → WebView. Console errors surface in the existing banner
  AND feed `run_checks`.
- Cloud: job returns `previewUrl` (signed, TTL) → same WebView.
- Offline: static preview fully offline (already true today); ESM-CDN
  needs first fetch (document; add response cache in phase 2).

## 8. File management

- CRUD + rename + search (extend existing explorer; add in-file search via
  simple index — no DB needed under 5 MB/project).
- Manual editor stays (already shipped); add dirty-dot + save.
- **Verdict: LOCAL** (Hive + files, already proven).

## 9. Security / sandbox

- Local: project jail (path validation already in parser — extend to tool
  runner), WebView locked down (`allowFileAccess=false` except project
  server origin, no JS bridges into app APIs, CSP `<meta>` injected in
  preview wrapper), no secrets in context (existing SecureKeyStore rule),
  per-run timeouts (60 s static checks), file caps.
- Cloud: Firecracker/Docker per job, no creds in env (short-lived tokens),
  egress allowlist (npm/CDN/GitHub only), CPU/RAM/time quotas, artifact
  signing, 7-day TTL + wipe.
- **Verdict: LOCAL WebView sandbox + CLOUD disposable containers.**

## 10. AI provider

Already exists: `CloudProvider` interface + registry (20+ incl. OpenRouter,
custom endpoints) + local GGUF/LiteRT. Agent needs function-calling
models — route tool-capable requests to providers advertising `tools`
(OpenAI-compatible `tool_choice:auto` already wired via MCP). Local
small models do chat/edit drafts; cloud does agent loops.
**Verdict: already HYBRID.**

## 11. Tool/function design

```json
{"name":"update_file","args":{"path":"src/App.jsx","edits":[
  {"find":"<old block>","replace":"<new block>"}]}}
```
Surgical edits (find/replace blocks, not whole-file rewrites) → fewer
tokens, fewer regressions. Every tool returns `{ok, output|error,
hint}`. Budget: 6 rounds, 400 KB context cap, stop-and-ask on repeat
identical errors.

## 12. Storage

- Hive: `projects` box (meta) — files stay files (Hive isn't a FS).
- No new DB. Artifact cache: temp dir + LRU sweep (reuse existing sweepers).

## 13. Cloud API design (when built)

```
POST /v1/agent/jobs {projectZip, target:"static|node|flutter", entry}
GET  /v1/agent/jobs/:id        → status, logs tail
GET  /v1/agent/jobs/:id/logs?cursor=
GET  /v1/agent/jobs/:id/artifact.zip | .apk | previewUrl
```
Auth: per-user key (BYOK-style, like existing provider keys). Quotas per plan.

## 14–15. Stack & open-source pieces

- App: Flutter (existing), shelf_static (server), esbuild-wasm (CDN),
  Hive (store), InAppWebView (preview).
- Cloud: FastAPI/Go API, Redis/RQ or Temporal (queue), Docker +
  Firecracker/gVisor (sandbox), S3-compatible artifacts, Caddy (TLS).
- All replaceable; no proprietary lock-in except app stores.

## 16–18. Phases

- **MVP (this repo, no backend):** static/Trio + ESM React/Vue local
  preview via project server; agent file-tools over existing chat;
  error loop from WebView console; ZIP export (shipped); single-file +
  multi-file already generate. ≈ the current CubicWeb + 3-4 weeks.
- **Phase 2:** cloud build jobs (static/Node), preview URLs, npm-CDN
  audit, response cache for offline ESM, GitHub export (optional PAT).
- **Phase 3:** Flutter/APK cloud pipeline, deploy targets (static hosts),
  share-preview links, team workspaces.

## 19. Hard limitations (say plainly)

- No local npm/Node server processes on stock Android (SELinux, no exec).
- No on-device APK/Gradle builds (size/time/RAM).
- No Next.js SSR locally; no TS typecheck locally (transform only).
- ESM-CDN needs internet at least once; true-offline frameworks = static only.
- WebView ≠ Chrome DevTools (no breakpoints; console + overlay only).
- Big-model agent loops cost tokens — cap rounds, prefer small local
  model for drafts + strong cloud model for repairs.

## 20–21. Complexity & order

| Component | Complexity | Order |
|---|---|---|
| Project workspace + explorer upgrades | S | 1 |
| Localhost preview server + console loop | S | 2 |
| Agent tool runner (file tools) | M | 3 |
| ESM-CDN templates (React/Vue) | M | 4 |
| esbuild-wasm transform | M | 5 |
| Cloud build API + workers | L | 6 |
| APK pipeline | M (infra-heavy) | 7 |
| Deploy/GitHub/share links | S–M | 8 |

## 22. Example flow (prompt → APK)

1. "E-commerce site, React + Tailwind" → agent picks ESM-React template.
2. Writes 8 files via tools → preview server → WebView shows store.
3. Console: `X is not defined` → agent reads file, fixes import, re-renders. ✅
4. "Make it an app" → cloud Flutter scaffold job → APK → install prompt.

## 23. Agent/tool trace (error case)

`preview → console: "Module X missing" → search_code(X) → read package
→ update import URL (esm.sh pin) → re-preview → clean → summary.`
Max 6 rounds; identical error twice → ask user.

## 24–26. Scale, cost, offline

- Scale: stateless workers + queue; cache `node_modules` layers by lockfile
  hash; kill idle containers at 60 s.
- Cost: static = pennies (CDN); Node builds = per-minute containers;
  default free models for drafts, strong models only for repair turns;
  user BYOK first (already our model).
- Offline: static preview + edit + export + local LLM today; ESM after
  first fetch with cache (P2); everything cloud-gated fails with a clear
  "needs internet" note (existing pattern).
