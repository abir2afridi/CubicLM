You are working on **CubicLM**, an existing cross-platform AI coding/client application.

Repository:
https://github.com/abir2afridi/CubicLM

Your task is NOT to create a mock terminal, fake Node support, or a static HTML preview workaround.

You must inspect the existing CubicLM architecture and implement a **real, production-oriented Android local development runtime** so that AI-generated projects can actually execute on Android whenever technically possible.

The goal is to make CubicLM behave more like a combination of:

* AI coding agent
* real terminal
* local development environment
* project/workspace manager
* localhost development server
* browser preview
* cloud fallback runtime

Do not destroy existing functionality. Reuse existing architecture/components whenever possible.

---

# 1. FIRST: FULL REPOSITORY AUDIT

Before modifying code, inspect the repository carefully.

Identify:

* Android architecture
* Flutter/native Android boundaries
* current Terminal implementation
* current Preview implementation
* project/workspace/file-system implementation
* AI coding agent
* command execution code
* process management
* WebView implementation
* networking layer
* existing cloud/runtime functionality
* build system
* Gradle configuration
* AndroidManifest
* native Android code
* C++ components
* JNI/FFI bridges
* existing llama.cpp/local AI runtime
* any existing shell/process abstractions
* existing dependency/runtime management

Do not assume that the current Terminal is a real terminal.

Trace the actual execution path:

AI → command → process → stdout/stderr → terminal UI

and:

Project → runtime → server → port → Preview WebView

Document the current architecture internally before changing it.

---

# 2. CORE PROBLEM

CubicLM currently has a Preview behavior where React/Vite projects may be treated as if they were static HTML projects.

For example, a project may contain:

package.json

```json
{
  "name": "landing-page",
  "private": true,
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "react": "^18.3.1",
    "react-dom": "^18.3.1"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "^4.3.1",
    "vite": "^5.4.0"
  }
}
```

and:

```text
vite.config.js
src/
  main.jsx
  App.jsx
```

This is NOT a static HTML project.

It requires:

Node.js
↓
npm
↓
node_modules
↓
Vite
↓
development server
↓
localhost
↓
WebView

Do not solve this by simply opening `index.html` directly.

---

# 3. VERY IMPORTANT: ANDROID IS NOT DESKTOP LINUX

Do not implement the naive assumption:

"Just execute node/npm like Linux."

Android has its own:

* application sandbox
* process model
* filesystem restrictions
* Bionic libc
* ABI/architecture requirements
* SELinux restrictions
* scoped/storage limitations
* background execution restrictions
* lifecycle behavior

Therefore, design an Android-compatible runtime architecture.

Do NOT promise that every arbitrary Linux CLI binary will work.

Instead, create a runtime abstraction that supports tools that are actually compatible with Android.

---

# 4. IMPLEMENT A MANAGED LOCAL RUNTIME

Create a proper runtime management layer.

Conceptually:

```text
CubicLM
   │
   └── RuntimeManager
          │
          ├── NodeRuntime
          ├── PythonRuntime (future/optional)
          ├── GitRuntime
          ├── ShellRuntime
          └── CloudRuntime
```

The exact class/module names should follow the existing CubicLM architecture.

The runtime manager must be able to answer:

```text
Is Node available?
Which Node version?
Which npm version?
Is the architecture compatible?
Where is Node installed?
Where is npm?
Which environment variables are required?
Which runtimes are currently running?
```

---

# 5. NODE.JS ON ANDROID

The most important requirement:

CubicLM must NOT assume that the Android OS already contains a usable Node.js installation.

Implement a **managed Node runtime strategy**.

Preferred order:

### Strategy A — Bundled/managed Android-compatible Node runtime

If technically and legally appropriate for the project:

* provide or package an Android-compatible Node runtime
* support ARM64 devices
* use app-private storage
* expose node/npm through CubicLM's runtime PATH
* verify executable availability before use
* verify architecture
* verify version
* avoid requiring root
* avoid requiring Termux to be installed

The runtime should live in an app-managed location rather than requiring the user to manually configure the Android system.

Example conceptual structure:

```text
CubicLM/
  runtime/
    node/
      bin/
        node
        npm
        npx
      ...
```

Do not hardcode this exact structure if the existing project architecture requires another structure.

---

# 6. IF EMBEDDING NODE DIRECTLY IS NOT PRACTICAL

Do NOT fake it.

Implement a runtime provider abstraction:

```text
LocalRuntimeProvider
CloudRuntimeProvider
```

The local provider attempts Android-compatible execution.

If a project requires a runtime that cannot safely or reliably execute locally, use the cloud provider.

For example:

```text
React/Vite
   ↓
Local Node available?
   ├── YES → local execution
   └── NO → cloud runtime
```

The user should never receive the misleading message:

"Nothing browser-runnable"

when the actual reason is:

"Node runtime is unavailable."

Instead, provide a useful runtime status.

Example:

```text
React/Vite project detected.

Node.js runtime is not currently available on this device.

[Install/Enable Local Runtime]
[Run in Cloud]
[Cancel]
```

---

# 7. REAL TERMINAL

Upgrade the existing Terminal from a visual command box into an actual process execution system.

It must support:

* real shell/process execution
* stdin
* stdout
* stderr
* exit codes
* process lifecycle
* Ctrl+C / SIGINT equivalent where Android permits
* process termination
* process restart
* working directory
* environment variables
* PATH
* HOME
* project workspace
* terminal resize
* long-running processes
* background processes where safe
* streaming output
* command history
* multiple terminal sessions if architecture allows

The UI should be connected to actual processes.

Do NOT simulate output.

For example:

```bash
node --version
npm --version
pwd
ls
git --version
npm install
npm run dev
```

must produce actual process output.

---

# 8. PTY / SHELL ARCHITECTURE

If the current terminal requires a pseudo-terminal, implement an appropriate PTY/process layer for Android.

Do not assume Android provides a normal desktop terminal environment.

If a full PTY is not required for a particular process, use direct process execution where appropriate.

The architecture should distinguish:

```text
Interactive shell
Non-interactive command
Long-running server
Background process
One-shot task
```

Do not force everything through one implementation.

---

# 9. SHARED WORKSPACE

This is critical.

The following components must use the SAME project workspace:

```text
AI Coding Agent
       │
       ├── reads files
       ├── edits files
       └── creates files
              │
              ▼
        Project Workspace
              │
              ├── Terminal
              │
              ├── npm install
              │
              ├── npm run dev
              │
              └── Preview
```

If the AI creates:

```text
package.json
vite.config.js
index.html
src/App.jsx
src/main.jsx
```

the Terminal must see exactly those files.

If Terminal runs:

```bash
npm install
```

the resulting:

```text
node_modules/
```

must be visible to the same project.

If Terminal starts:

```bash
npm run dev
```

Preview must access that exact server.

Do NOT create separate isolated copies of the workspace unless explicitly required.

---

# 10. PROJECT DETECTION

Create a reliable project detector.

At minimum detect:

### Static

```text
HTML
CSS
JavaScript
```

### Vite

```text
React + Vite
Vue + Vite
Svelte + Vite
Vanilla Vite
```

### React

Check:

* package.json
* react dependency
* react-dom
* Vite dependency
* scripts
* vite.config.*
* source files

### Next.js

Detect:

```text
next
next.config.*
```

### Node

Detect:

```text
package.json
```

### Other frameworks

Design this so additional frameworks can be added later.

Do not classify a project only by file extension.

---

# 11. REACT/VITE EXECUTION PIPELINE

For a React/Vite project:

```text
AI generates project
        ↓
Validate files
        ↓
Detect React/Vite
        ↓
Check Node runtime
        ↓
Check npm
        ↓
Check package.json
        ↓
Check node_modules
        ↓
npm install if necessary
        ↓
npm run dev
        ↓
capture stdout/stderr
        ↓
detect localhost port
        ↓
health-check server
        ↓
open Preview
```

This pipeline must be implemented for real.

---

# 12. NEVER HARD-CODE ONLY PORT 5173

Vite commonly uses 5173, but it may select another port.

Therefore:

DO NOT assume:

```text
localhost:5173
```

always.

Start the server and inspect its output.

Detect URLs such as:

```text
Local: http://localhost:5173/
```

or:

```text
Local: http://127.0.0.1:5174/
```

Then extract the actual port.

Also support port conflict handling.

Example:

```text
5173 occupied
↓
Vite selects 5174
↓
CubicLM detects 5174
↓
Preview opens 5174
```

---

# 13. VITE HOST CONFIGURATION

Do not blindly expose the development server to the entire network.

Prefer an appropriate local-only configuration such as:

```bash
npm run dev -- --host 127.0.0.1
```

or the safest equivalent supported by the Android/WebView architecture.

Only expose broader interfaces if explicitly required and safely controlled.

---

# 14. LONG-RUNNING DEV SERVER

This is essential.

When:

```bash
npm run dev
```

starts, the process must remain alive.

Do NOT execute it as a one-shot command that is immediately killed after stdout is returned.

Create a process/session manager.

Conceptually:

```text
DevServerManager
    │
    ├── start()
    ├── stop()
    ├── restart()
    ├── status()
    ├── getPort()
    ├── getUrl()
    └── logs()
```

When Preview is closed, decide whether the server remains alive according to the existing UX.

When the project changes, support HMR/reload where possible.

If a server is already running for the same project:

```text
reuse existing server
```

instead of launching duplicates.

---

# 15. PREVIEW WEBVIEW

Preview must load the actual running development server.

For example:

```text
http://127.0.0.1:5173
```

NOT:

```text
file:///project/index.html
```

for React/Vite projects.

The Preview layer should understand:

```text
StaticProject
DevServerProject
CloudPreview
```

For static projects:

```text
files → WebView
```

For Vite:

```text
files
 ↓
Vite server
 ↓
localhost URL
 ↓
WebView
```

For cloud:

```text
cloud container
 ↓
public/secure preview URL
 ↓
WebView
```

---

# 16. VERIFY REACT SOURCE BEFORE PREVIEW

Before starting the preview, validate the generated project.

For a basic Vite React project, verify:

### package.json

Contains appropriate:

```text
react
react-dom
vite
```

and a dev script.

### index.html

Must contain something conceptually equivalent to:

```html
<div id="root"></div>
<script type="module" src="/src/main.jsx"></script>
```

### src/main.jsx

Must actually mount the React application.

Conceptually:

```jsx
import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App.jsx'

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
)
```

### App.jsx

Must return actual React elements/components.

Do not assume the generated source is valid.

---

# 17. JSX / FILE GENERATION CORRUPTION

Investigate whether CubicLM's AI generation/file-writing pipeline can corrupt JSX.

Do NOT assume that malformed JSX is an Android runtime problem.

Inspect:

* AI response parser
* JSON extraction
* markdown extraction
* code fence parsing
* streaming response assembly
* escaping
* Unicode handling
* newline handling
* file-write logic
* partial response handling
* retry logic
* tool-call/file-edit parser
* atomic file writes

A generated file must not be truncated halfway through JSX.

For example, if AI intends:

```jsx
return (
  <div>
    <Navbar />
    <Hero />
    <Features />
  </div>
)
```

the actual file on disk must contain valid JSX.

Implement validation where practical.

---

# 18. BUILD VALIDATION

Before showing a complex React/Vite preview, optionally run:

```bash
npm run build
```

if the project supports it.

If build fails:

DO NOT simply show a blank Preview.

Display a useful diagnostic:

```text
Build failed

src/App.jsx:23
Unexpected token

[Open Terminal]
[View Error]
[Ask AI to Fix]
```

The AI coding agent should be able to consume the build error and fix the project.

---

# 19. ERROR STATES

Do not collapse all failures into:

"Nothing browser-runnable."

Create specific error states.

At minimum:

### Node missing

```text
Node.js runtime unavailable.
```

### npm missing

```text
npm is unavailable.
```

### Dependency installation failed

```text
npm install failed.
```

### Build failed

```text
Project build failed.
```

### Dev server crashed

```text
Development server stopped unexpectedly.
```

### Port conflict

```text
Development server port unavailable.
```

### Preview connection failed

```text
Preview server is running but cannot be reached.
```

### Unsupported local runtime

```text
This project requires a runtime that is not supported locally on Android.
```

Then offer Cloud Runtime when available.

---

# 20. CLOUD FALLBACK

Implement the architecture so heavy or unsupported projects can run remotely.

Conceptually:

```text
RuntimeRouter
       │
       ├── Local Android Runtime
       │
       └── Cloud Runtime
```

Decision example:

```text
Can run locally?
      │
   YES ──→ Local
      │
     NO
      ↓
Cloud
```

The cloud environment should be disposable and isolated.

It should support:

* Node
* npm
* project files
* dependency installation
* development server
* preview URL

Do not give arbitrary AI-generated code unrestricted access to a production server.

Use appropriate isolation/resource limits.

---

# 21. SECURITY

This is a major requirement.

AI-generated commands can be dangerous.

Do not give arbitrary project code unrestricted access to:

* private user files
* Android system directories
* credentials
* application secrets
* unrelated app data
* sensitive OS resources

Where technically feasible, restrict execution to the project workspace.

Example:

```text
/project
```

should be the default working directory.

Implement environment filtering.

Avoid exposing unnecessary environment variables.

For cloud execution:

* isolated container
* CPU limit
* memory limit
* storage limit
* process limit
* network policy
* timeout
* automatic cleanup

Never hardcode secrets into the project or runtime.

---

# 22. RUNTIME INSTALLATION UX

If Node is not installed, do not silently fail.

Provide a clear flow:

```text
React/Vite project detected

Local Node.js runtime is required.

[Install Local Runtime]
[Use Cloud Runtime]
```

During installation:

```text
Downloading runtime...
Verifying runtime...
Installing...
Testing node...
Testing npm...
Ready
```

Then:

```text
Node vXX
npm vXX
```

The exact versions should be chosen based on compatibility and project requirements.

Do not claim a runtime works until actually executing:

```bash
node --version
npm --version
```

successfully.

---

# 23. ARCHITECTURE COMPATIBILITY

Android devices can use different ABIs.

At minimum consider:

```text
arm64-v8a
armeabi-v7a
x86_64
```

Do not ship an incompatible binary and then report a generic process error.

Detect the current device ABI and runtime compatibility.

If a runtime cannot execute locally:

```text
Local runtime unsupported on this device
```

then use cloud fallback where available.

---

# 24. STORAGE

npm projects can become large.

Manage:

* node_modules
* npm cache
* runtime files
* build artifacts
* temporary files

Provide project/runtime storage information where useful.

Avoid unnecessary duplicate dependency installations.

Where safe, allow dependency caching.

---

# 25. OFFLINE MODE

CubicLM is intended to be local-first.

Therefore distinguish:

### Runtime installed + dependencies cached

A project may run offline.

### Runtime installed + dependencies missing

`npm install` requires network access.

### No runtime

Use cloud if network is available.

Do not claim that React/Vite can install dependencies offline if packages are not cached.

---

# 26. TERMINAL + AI AGENT INTEGRATION

The AI coding agent should be able to execute commands through the same terminal/runtime system.

Example:

AI:

```text
I created the React project.
```

Then it can execute:

```bash
npm install
npm run build
```

and inspect the output.

If build fails:

```text
AI reads error
↓
edits file
↓
build again
↓
success
↓
start dev server
↓
Preview
```

This should become an actual iterative coding loop.

---

# 27. WEBSITE BUILDER WORKFLOW

The intended CubicLM workflow is:

```text
User:
"Build me a modern SaaS landing page"

        ↓

AI Coding Agent
        ↓
Creates project files
        ↓
package.json
vite.config.js
src/*
        ↓
Project Validator
        ↓
Runtime Manager
        ↓
Node
        ↓
npm install
        ↓
npm run dev
        ↓
localhost
        ↓
Preview
```

The user should not need to manually copy the project to a PC just to see a React application.

---

# 28. TERMINAL COMMAND EXAMPLES

After implementation, these should be tested where supported:

```bash
node --version
npm --version
pwd
ls
cd <project>
npm install
npm run build
npm run dev
```

For a simple project:

```bash
node -e "console.log('hello from CubicLM')"
```

should execute successfully if supported by the runtime.

Do not fake these results.

---

# 29. TEST PROJECT

Create/use a minimal test project:

```text
react-vite-test/
├── package.json
├── vite.config.js
├── index.html
└── src/
    ├── main.jsx
    └── App.jsx
```

App.jsx:

```jsx
export default function App() {
  return (
    <div>
      <h1>CubicLM React Runtime Test</h1>
      <p>React is running successfully.</p>
    </div>
  )
}
```

main.jsx:

```jsx
import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App.jsx'

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
)
```

Success means:

```text
npm install
        ↓
npm run dev
        ↓
localhost detected
        ↓
WebView opens
        ↓
"CubicLM React Runtime Test"
```

is visibly rendered.

---

# 30. HMR TEST

After Preview is running:

Modify:

```jsx
<h1>CubicLM React Runtime Test</h1>
```

to:

```jsx
<h1>CubicLM Live React Preview</h1>
```

Verify the Preview updates without requiring a complete app restart whenever Vite HMR supports it.

---

# 31. STATIC PROJECT MUST STILL WORK

Do not break existing static preview.

For:

```text
index.html
style.css
script.js
```

there should still be a lightweight direct preview path.

Architecture:

```text
Static
 → direct WebView

React/Vite
 → Node
 → Vite
 → localhost
 → WebView

Unsupported/heavy
 → Cloud runtime
 → preview URL
 → WebView
```

---

# 32. DO NOT USE THESE BAD SOLUTIONS

Do NOT:

* fake terminal output
* fake Node.js
* convert React into static HTML
* remove React to make Preview work
* hardcode one localhost port
* open React project's index.html directly
* silently fall back to static rendering
* assume Node exists on Android
* require root
* require Termux unless explicitly designed as an optional provider
* execute arbitrary commands with unrestricted device access
* kill the dev server immediately after starting it
* create separate workspaces for AI and Terminal
* hide actual errors behind "Nothing browser-runnable"

---

# 33. OPTIONAL TERMUX PROVIDER

If useful, design the runtime abstraction so Termux can be an optional external runtime provider.

However:

CubicLM must not depend on Termux being installed for the primary experience unless there is a strong technical reason.

The primary goal is a self-contained CubicLM experience.

---

# 34. PERFORMANCE

Optimize for Android devices.

Avoid:

* unnecessarily starting multiple Node processes
* reinstalling dependencies every preview
* copying entire projects repeatedly
* excessive polling
* excessive log buffering
* memory leaks from long-running servers
* keeping dead processes alive

Use:

* streaming logs
* process reuse
* dependency caching
* lifecycle-aware cleanup
* port tracking
* project-based server sessions

---

# 35. ANDROID LIFECYCLE

Handle:

* app backgrounding
* app foregrounding
* activity recreation
* process death
* device rotation where relevant
* Preview reopening
* terminal session restoration where possible

Do not assume a server will survive Android process termination.

Persist enough metadata to recover gracefully.

---

# 36. OBSERVABILITY / DEBUGGING

Add useful internal logs around:

```text
Runtime detection
Runtime installation
Node execution
npm execution
Project detection
Dependency installation
Build
Dev server startup
Port detection
Preview connection
Process termination
```

Logs should make it possible to determine exactly where the pipeline failed.

Avoid leaking secrets into logs.

---

# 37. UI STATUS

The user should be able to understand what CubicLM is doing.

Example:

```text
Detecting project...
✓ React + Vite detected

Checking runtime...
✓ Node.js available

Checking dependencies...
✓ node_modules found

Starting development server...
✓ Vite running on localhost:5173

Opening Preview...
✓ Connected
```

For failures:

```text
Detecting project...
✓ React + Vite detected

Checking runtime...
✗ Node.js unavailable

[Install Local Runtime]
[Use Cloud Runtime]
```

---

# 38. DO NOT OVERWRITE EXISTING ARCHITECTURE BLINDLY

Before creating new modules:

Search for existing equivalents.

If CubicLM already has:

* ProcessManager
* TerminalService
* PreviewManager
* RuntimeManager
* WorkspaceManager
* WebViewManager

extend them rather than creating duplicate systems.

Follow existing naming conventions and architecture.

---

# 39. IMPLEMENTATION QUALITY

Write production-quality code.

Requirements:

* proper error handling
* null safety where applicable
* lifecycle management
* cancellation
* resource cleanup
* process cleanup
* concurrency protection
* no blocking UI thread
* secure filesystem handling
* secure command execution
* testable abstractions

Do not implement everything in one giant class.

Separate:

```text
Runtime
Process
Terminal
Project Detection
Dev Server
Preview
Cloud Runtime
```

appropriately.

---

# 40. IMPORTANT: ACTUALLY RUN TESTS

Do not stop after writing code.

Build the Android project.

Run relevant unit/integration tests.

If possible, test on Android emulator/device.

Test:

1. Static HTML preview
2. React/Vite detection
3. Node detection
4. npm detection
5. npm install
6. npm run build
7. npm run dev
8. dynamic port detection
9. Preview WebView
10. HMR
11. terminal commands
12. process termination
13. Node missing state
14. dependency failure
15. build failure
16. server crash
17. port conflict
18. cloud fallback

If something cannot be tested because the environment lacks an Android device/runtime, explicitly state that.

Do not claim success without evidence.

---

# 41. IMPORTANT DIAGNOSTIC REQUIREMENT

If the existing React preview is failing, first determine which of these is actually happening:

### Case A

React/Vite project is being incorrectly classified as static.

### Case B

React source files are malformed/corrupted.

### Case C

Node/npm is unavailable.

### Case D

npm install fails.

### Case E

Vite never starts.

### Case F

Vite starts but CubicLM does not detect the port.

### Case G

Vite is running but WebView opens the wrong URL.

### Case H

WebView cannot access localhost.

### Case I

Android kills the development server.

### Case J

Cloud fallback is missing.

Fix the actual root cause instead of applying a superficial UI patch.

---

# 42. FINAL ACCEPTANCE CRITERIA

The implementation is successful only if:

### Terminal

A real process can execute:

```bash
node --version
npm --version
```

when the managed runtime is available.

### Workspace

AI-created files are immediately visible to Terminal.

### React

A React/Vite project is correctly detected.

### Dependencies

npm can install dependencies using the managed runtime when network access is available.

### Dev server

`npm run dev` creates a persistent development server.

### Port

CubicLM detects the actual dynamic localhost port.

### Preview

Preview opens the real Vite server URL, not the filesystem HTML.

### HMR

Changes can update the running app when supported.

### Errors

Runtime/build/npm/server errors are clearly reported.

### Security

Project execution is appropriately isolated from unrelated user/system data.

### Android

The solution respects Android's runtime, ABI, filesystem, and lifecycle constraints.

### Fallback

Unsupported local workloads can use Cloud Runtime when available.

---

# 43. FINAL REPORT

After implementation, provide a concise engineering report containing:

1. Root cause of the original Preview problem
2. Existing architecture discovered
3. Files/modules changed
4. Android runtime strategy
5. How Node/npm are executed
6. How Terminal works
7. How React/Vite projects are detected
8. How npm install works
9. How dev servers are managed
10. How ports are detected
11. How Preview connects
12. How HMR works
13. Security model
14. Cloud fallback behavior
15. Tests actually performed
16. Tests that could not be performed
17. Known limitations
18. Any additional Android-specific requirements

Most importantly:

**Do not merely make the Preview UI say that React is supported.**

Make the underlying execution pipeline actually work.

The final system should conceptually behave like:

```text
                CUBICLM
                   │
        ┌──────────┴──────────┐
        │                     │
   AI CODING AGENT         TERMINAL
        │                     │
        └──────────┬──────────┘
                   │
             SHARED WORKSPACE
                   │
            PROJECT DETECTOR
                   │
             RUNTIME ROUTER
              /           \
             /             \
     LOCAL ANDROID       CLOUD
       RUNTIME           RUNTIME
          │                 │
        Node              Node
          │                 │
        npm               npm
          │                 │
       Vite/Next/etc.   Vite/Next/etc.
          │                 │
       localhost        Preview URL
          │                 │
          └────────┬────────┘
                   │
                PREVIEW
                WEBVIEW
```

Build this as a real execution architecture, not a mock.

If the repository's current architecture makes one part technically impossible, do not hide it. Explain the limitation and implement the strongest practical architecture with a clean abstraction/fallback path.
