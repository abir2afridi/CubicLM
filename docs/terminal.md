You are working on the existing **CubicLM** repository:

https://github.com/abir2afridi/CubicLM

CubicLM is a mobile-first AI development application, primarily targeting Android.

Your task is to transform the existing Terminal into a **real developer terminal + mobile-friendly CLI manager**.

The final experience should feel like:

> **A lightweight developer environment inside CubicLM — not a fake terminal and not a desktop terminal awkwardly squeezed into a mobile UI.**

The user must be able to:

* run real commands
* install supported developer CLIs
* see all installed CLIs
* launch them
* uninstall them
* update/repair them
* see their versions/status
* install CLIs without manually typing complicated commands
* still use normal terminal commands when they want
* launch CLIs directly inside the current project
* share the same workspace with CubicLM's AI coding agent
* run Node/npm-based projects
* start development servers
* preview projects

---

# 1. FIRST — INSPECT THE EXISTING PROJECT

Before modifying anything, inspect the existing CubicLM architecture.

Find:

* Terminal UI
* terminal backend
* process execution
* shell/PTY implementation
* workspace manager
* project/file manager
* AI coding agent
* command execution tools
* Preview system
* Android native code
* Flutter/native bridge if applicable
* JNI/FFI
* runtime management
* Gradle
* AndroidManifest
* storage
* settings/preferences
* existing installation/download mechanisms

Reuse existing architecture whenever possible.

Do not create duplicate services if CubicLM already has an equivalent.

---

# 2. CORE PRODUCT VISION

The Terminal should have TWO complementary experiences:

```text
┌──────────────────────────────────────┐
│ Terminal                             │
├──────────────────────────────────────┤
│ Installed CLI Tools                  │
│                                      │
│ ✓ Claude Code        Ready     ›     │
│ ✓ OpenCode           Ready     ›     │
│ ✓ Kilo              Ready     ›     │
│                                      │
│ + Install CLI                        │
├──────────────────────────────────────┤
│ Terminal Session                     │
│                                      │
│ $ npm run dev                        │
│                                      │
│ $ _                                  │
└──────────────────────────────────────┘
```

The top section is a **mobile-friendly CLI manager**.

The bottom section is a **real terminal**.

Both must use the same backend/runtime system.

---

# 3. MOBILE-FIRST PRINCIPLE

Do NOT simply copy a desktop terminal UI onto Android.

The user should not have to type:

```bash
npm install -g some-long-package-name
```

just to install a supported CLI.

Instead provide:

```text
Install CLI
     ↓
Select CLI
     ↓
Install
     ↓
Verify
     ↓
Ready
```

Prefer one-tap or minimum-interaction installation.

The terminal command should still be available for advanced users.

---

# 4. INSTALLED CLI SECTION

The Terminal must contain a persistent:

## Installed CLI Tools

section.

Example:

```text
Installed CLI Tools

┌────────────────────────────────┐
│ ◉ Claude Code                  │
│   vX.X.X                       │
│   Ready                        │
│                    [Open] [⋮] │
├────────────────────────────────┤
│ ◉ OpenCode                     │
│   vX.X.X                       │
│   Ready                        │
│                    [Open] [⋮] │
├────────────────────────────────┤
│ ◉ Kilo                         │
│   vX.X.X                       │
│   Ready                        │
│                    [Open] [⋮] │
└────────────────────────────────┘

+ Install CLI
```

The exact UI should match CubicLM's existing design language.

---

# 5. CLI CARD ACTIONS

Every installed CLI should provide mobile-friendly actions.

At minimum:

```text
Open
Verify
Update
Repair
Uninstall
```

Do not put too many buttons directly on the card.

Use a bottom sheet/menu for secondary actions.

Example:

```text
Claude Code

Version X.X.X
Status: Ready

[Open]

More
──────────────
Verify Installation
Update
Repair
Uninstall
```

This keeps the mobile UI clean.

---

# 6. UNINSTALL MUST BE EASY

The user explicitly needs an uninstall option.

Implement:

```text
CLI → ⋮ → Uninstall
```

Ask for confirmation:

```text
Uninstall Claude Code?

This removes the CLI and its managed installation files.

Your project files will NOT be deleted.

[Cancel] [Uninstall]
```

After successful removal:

```text
✓ Claude Code removed
```

Remove the CLI from the installed list immediately.

Do NOT delete:

* project files
* user source code
* unrelated CLIs
* unrelated runtimes

---

# 7. ONE-TAP CLI INSTALLATION

Create an:

```text
+ Install CLI
```

experience.

Instead of requiring terminal commands, show a catalog.

Example:

```text
Install CLI

AI Coding

Claude Code
AI coding agent
Runtime: Node.js
[Install]

OpenCode
AI coding agent
Runtime: ...
[Install]

Kilo
AI coding agent
Runtime: ...
[Install]

Cline
AI coding agent
Runtime: ...
[Install]
```

The installation should be handled by CubicLM.

The user should NOT need to manually type the installation command.

---

# 8. INSTALLATION FLOW

When the user taps Install:

```text
Claude Code

Preparing installation...

✓ Checking device
✓ Checking architecture
✓ Checking required runtime
↓ Preparing Node.js
↓ Installing package
↓ Verifying executable
✓ Installation complete
✓ Version detected

[Open Claude Code]
[Done]
```

Only show progress corresponding to actual operations.

Never fake progress.

---

# 9. SMART DEPENDENCY INSTALLATION

The user should not have to understand runtime dependencies.

For example:

```text
Claude Code
     ↓
Requires Node.js
     ↓
Is Node installed?
   ├── YES
   │    ↓
   │   Install CLI
   │
   └── NO
        ↓
   Automatically prepare Node
        ↓
   Install CLI
```

If a CLI requires another runtime, CubicLM should handle it automatically where technically possible.

If user intervention is required, explain it clearly.

---

# 10. "NO MANUAL HASSLE" RULE

For supported CLIs, the preferred experience is:

```text
Tap Install
      ↓
CubicLM handles runtime
      ↓
CubicLM handles package installation
      ↓
CubicLM verifies executable
      ↓
CLI appears in Installed CLI Tools
```

The user should not need to:

* open a separate app
* manually configure PATH
* manually create directories
* manually download binaries
* manually configure npm global paths
* manually type complicated installation commands

unless technically unavoidable.

---

# 11. TERMINAL COMMAND INSTALLATION

The normal terminal must ALSO work.

For example, if a user types:

```bash
npm install ...
```

or another supported installation command:

```bash
...
```

and a CLI becomes available, CubicLM should detect it where practical.

After the command completes:

```text
CLI detected: Claude Code
Version: X.X.X

Add to Installed CLI Tools?

[Add] [Ignore]
```

Or automatically register it if the installation clearly matches a known CLI manifest and security rules permit it.

This means CLI management works both ways:

```text
GUI Install
      ↕
Real Terminal
```

---

# 12. CLI REGISTRY

Create a persistent registry.

Conceptually:

```text
CLIRegistry

installed:
  - id
  - name
  - command
  - version
  - runtime
  - install provider
  - install path
  - package identifier
  - status
  - installed timestamp
  - last verified timestamp
```

Do not use the registry alone to determine whether a CLI actually exists.

The executable must be verified.

---

# 13. LIVE VERIFICATION

When CubicLM starts, it should quickly verify installed CLIs where practical.

Example:

```text
Claude Code
✓ Ready
```

If the binary is missing:

```text
Claude Code
⚠ Installation missing
[Repair]
```

If runtime is missing:

```text
Claude Code
⚠ Node.js unavailable
[Fix]
```

If authentication is needed:

```text
Claude Code
⚠ Authentication required
[Open]
```

Do not falsely show "Ready."

---

# 14. CLI STATUS MODEL

Implement clear states such as:

```text
NOT_INSTALLED
INSTALLING
INSTALLED
VERIFYING
READY
RUNTIME_MISSING
BINARY_MISSING
AUTH_REQUIRED
UPDATE_AVAILABLE
BROKEN
UNINSTALLING
ERROR
```

Use whatever enum/state architecture fits the existing project.

---

# 15. CLI MANIFEST SYSTEM

Do not hardcode installation logic into the UI.

Create a manifest/provider architecture.

Conceptually:

```text
CLI Manifest
│
├── id
├── displayName
├── description
├── command
├── versionCommand
├── runtimeRequirements
├── installProvider
├── packageIdentifier
├── launchConfiguration
├── authentication
├── platformSupport
└── capabilities
```

The exact fields should follow the actual implementation.

This allows new CLIs to be added later without rewriting the Terminal.

---

# 16. INSTALL PROVIDERS

Do not assume every CLI uses npm.

Support an abstraction such as:

```text
InstallProvider
│
├── NpmProvider
├── BinaryProvider
├── ArchiveProvider
├── GitProvider
├── ManagedRuntimeProvider
└── CloudProvider
```

Only implement providers actually needed.

The architecture must be extensible.

---

# 17. OFFICIAL INSTALLATION REQUIREMENTS

Before adding installation definitions for:

* Claude Code
* OpenCode
* Kilo
* Cline

verify their current official installation instructions.

Verify:

* official package/binary
* installation mechanism
* supported platforms
* Node requirement
* architecture
* authentication
* version command
* launch command

Do NOT invent package names.

Do NOT assume all of them can run natively on Android.

If one is not Android-compatible, do not fake local support.

Use:

```text
Cloud Runtime
```

or another legitimate compatible provider if available.

---

# 18. ANDROID RUNTIME

Android does not provide a normal desktop Linux environment.

Do not assume:

```text
/usr/bin/node
/usr/local/bin/npm
```

or glibc-based Linux binaries.

Use an Android-compatible managed runtime.

Conceptually:

```text
RuntimeManager
│
├── NodeRuntime
├── ShellRuntime
├── GitRuntime
├── PythonRuntime
└── CloudRuntime
```

Use app-private storage.

Do not require root.

Do not require Termux for the primary experience.

---

# 19. NODE.JS RUNTIME

For Node-based CLIs and React/Vite projects:

```text
Node Runtime
    ↓
npm
    ↓
CLI
```

CubicLM should manage:

* Node executable
* npm
* npx
* PATH
* HOME
* npm cache
* package location
* runtime version
* architecture

Node must actually execute.

Verify:

```bash
node --version
npm --version
npx --version
```

before marking the runtime ready.

---

# 20. MANAGED GLOBAL CLI DIRECTORY

Do not install global npm packages into Android system locations.

Use an app-managed location.

Conceptually:

```text
CubicLM/
  runtimes/
    node/
  cli/
    bin/
    packages/
    cache/
```

The actual implementation may use Android's internal app storage.

Expose the appropriate executable directories through the process environment.

---

# 21. CLI DEPENDENCY GRAPH

A CLI may depend on:

```text
Node
Python
Git
Other runtime
```

Represent this relationship.

Example:

```text
Claude Code
   ↓
Node Runtime
```

Before installation:

```text
Required runtime:
Node.js

Status:
✓ Available
```

or:

```text
Required runtime:
Node.js

Status:
Not installed

[Prepare Runtime]
```

Prefer automatically preparing dependencies.

---

# 22. CLI LAUNCH

When user taps:

```text
Claude Code → Open
```

launch the actual executable.

Do not open a fake AI chat interface.

Conceptually:

```text
Installed CLI
      ↓
Resolve executable
      ↓
Create process
      ↓
Attach PTY/terminal
      ↓
Interactive CLI
```

The CLI must run inside the real terminal.

---

# 23. LAUNCH INSIDE CURRENT PROJECT

If the user currently has:

```text
my-project
```

open, then:

```text
Open Claude Code
```

should launch it inside:

```text
my-project
```

as its working directory.

Same for:

* OpenCode
* Kilo
* Cline
* other supported coding CLIs

---

# 24. CLI QUICK LAUNCH

Make installed CLIs extremely easy to launch on mobile.

For example:

```text
Installed CLI Tools

✓ Claude Code          [Open]
✓ OpenCode             [Open]
✓ Kilo                 [Open]
```

One tap should launch the CLI.

No need to type:

```bash
claude
```

manually.

However, the command must remain available:

```bash
claude
```

for advanced users.

---

# 25. COMMAND PALETTE / QUICK ACTION

If appropriate for the existing CubicLM UI, add a mobile-friendly command/action sheet:

```text
Quick Actions

Run Command
Install CLI
Open Claude Code
Open OpenCode
Open Kilo
Open Cline
Start Dev Server
Stop Dev Server
```

This can significantly reduce typing on mobile.

Keep it optional and unobtrusive.

---

# 26. SEARCH INSTALLED CLIs

If the number of CLIs grows, provide search.

Example:

```text
Search CLI...

Claude Code
OpenCode
Kilo
Cline
```

Do not create unnecessary complexity for a small list.

---

# 27. CLI DETAILS SCREEN

Tapping a CLI should optionally open a detail screen/bottom sheet:

```text
Claude Code

Version
X.X.X

Status
Ready

Runtime
Node.js

Location
Managed by CubicLM

Installed
September 7, 2026

Actions

[Open]
[Verify]
[Update]
[Repair]
[Uninstall]
```

Do not expose sensitive filesystem paths unnecessarily.

---

# 28. REAL TERMINAL

The bottom terminal must remain a real terminal.

Support:

```text
pwd
ls
cd
echo
node
npm
npx
git
```

and installed CLI commands.

The output must come from actual processes.

Never fake output.

---

# 29. INTERACTIVE TERMINAL

Support:

* stdin
* stdout
* stderr
* PTY where required
* ANSI
* terminal resize
* Ctrl+C
* interactive prompts
* process termination

AI coding CLIs must be able to interact with the terminal.

---

# 30. MULTIPLE TERMINAL SESSIONS

Support multiple sessions where practical:

```text
Terminal 1
Claude Code

Terminal 2
npm run dev

Terminal 3
git status
```

A running dev server must not prevent another terminal from being opened.

---

# 31. PROCESS MANAGER

Implement/reuse a ProcessManager.

It should track:

```text
process
command
working directory
runtime
session
status
start time
```

and where possible:

```text
PID
port
```

Support:

```text
start
attach
input
terminate
kill
restart
status
```

---

# 32. SHARED WORKSPACE

This is mandatory.

All of these must use the same project:

```text
CubicLM AI Agent
Terminal
Claude Code
OpenCode
Kilo
Cline
npm
Vite
Preview
```

Architecture:

```text
              PROJECT WORKSPACE
                     │
       ┌─────────────┼─────────────┐
       │             │             │
       ▼             ▼             ▼
   AI Agent      Terminal        CLI
       │             │             │
       └─────────────┼─────────────┘
                     │
                 Same Files
```

No duplicated project copies.

---

# 33. AI AGENT SHOULD KNOW INSTALLED CLIs

Expose installed CLI information to CubicLM's AI agent.

Example:

```text
Available local CLIs:

Claude Code — Ready
OpenCode — Ready
Kilo — Ready
```

The AI can use this information when planning tasks.

But respect CubicLM's existing permission/confirmation model before allowing external tools to execute destructive commands.

---

# 34. TERMINAL INSTALL DETECTION

If the user manually installs a supported CLI from Terminal, CubicLM should detect it where possible.

Example:

```bash
npm install ...
```

After successful installation:

```text
✓ New CLI detected

Claude Code
Version X.X.X

Add to Installed CLI Tools?

[Add] [Ignore]
```

This prevents the registry from becoming disconnected from the actual terminal environment.

---

# 35. UPDATE DETECTION

For supported providers:

```text
Installed
Version X.X.X

Update available
Version Y.Y.Y

[Update]
```

Do not silently update.

Allow the user to control updates.

---

# 36. REPAIR

If:

```text
Claude Code
⚠ Broken
```

provide:

```text
[Repair]
```

Repair should:

1. verify runtime
2. verify package
3. reinstall if needed
4. verify executable
5. refresh version
6. update registry
7. return to Ready if successful

---

# 37. STORAGE MANAGEMENT

CLI installations and npm packages can consume substantial storage.

Add a lightweight storage indicator if practical:

```text
CLI Runtime Storage
342 MB
```

Potentially provide:

```text
Clear Cache
```

but NEVER delete required runtime/package files without confirmation.

Distinguish:

```text
Runtime
Installed CLI
Package cache
Temporary files
```

---

# 38. NETWORK STATUS

Before downloading a CLI:

```text
Checking network...
```

If offline:

```text
You're offline.

This CLI is not cached and requires an internet connection.

[Retry]
```

Do not report it as a broken CLI.

---

# 39. OFFLINE SUPPORT

If the runtime and required packages are already cached:

```text
Offline
↓
Launch installed CLI
```

should work where the CLI itself does not require network authentication/API access.

Do not promise offline operation for tools that inherently require cloud APIs.

---

# 40. AUTHENTICATION

Some AI CLIs require login/API credentials.

Use secure Android storage where appropriate.

Do NOT store credentials in:

```text
package.json
CLI registry
project files
plain text logs
```

If the CLI provides an interactive login flow, let the actual CLI handle it through the terminal.

---

# 41. SECRET PROTECTION

Never intentionally log:

* API keys
* access tokens
* passwords
* authorization headers
* private credentials

Filter sensitive environment variables where practical.

Do not send terminal credentials to cloud runtime.

---

# 42. SECURITY

AI coding CLIs can execute arbitrary commands.

The default working directory should be the selected project workspace.

Where technically feasible, prevent access to unrelated private user data.

Do not expose:

* Android system data
* other application data
* unrelated private files
* secure storage
* credentials

to project processes unnecessarily.

---

# 43. CLOUD FALLBACK

If a CLI cannot run locally on Android:

```text
Claude Code
⚠ Not supported locally

[Run in Cloud]
```

Do NOT pretend it is locally installed.

Cloud execution should receive only the selected project/workspace.

Use an isolated environment with appropriate:

* CPU limits
* memory limits
* storage limits
* process limits
* network policy
* timeout
* cleanup

---

# 44. MOBILE INSTALLATION UX

The most important UX principle:

### Beginner

```text
Install CLI
→ Tap Install
→ Done
```

### Intermediate

```text
Install CLI
→ See progress
→ See runtime/dependency status
```

### Advanced

```text
Terminal
→ manually run commands
```

All three should work.

---

# 45. SMART ERROR MESSAGES

Never show:

```text
Command failed.
```

when more useful information exists.

Instead:

```text
Claude Code could not start.

Reason:
Node.js runtime is unavailable.

[Install Node Runtime]
[Use Cloud]
```

or:

```text
Installation failed.

npm returned exit code 1.

<relevant error>

[Retry]
[Open Terminal]
```

---

# 46. NO FAKE SUCCESS

Absolute requirement:

Never display:

```text
✓ Installed
✓ Ready
✓ Running
✓ Updated
```

unless the underlying operation actually succeeded.

Never fake:

```text
node --version
npm --version
claude --version
```

Never simulate CLI output.

---

# 47. ANDROID LIFECYCLE

Handle:

* app background
* foreground
* activity recreation
* process death
* terminal reopening
* CLI registry persistence
* running server cleanup/recovery

Do not assume Android will keep arbitrary processes alive forever.

Implement safe recovery.

---

# 48. RESOURCE MANAGEMENT

Track long-running processes.

Prevent accidental accumulation of:

```text
node
npm
vite
claude
opencode
kilo
cline
```

processes.

Allow the user to terminate processes.

When a project is closed, provide appropriate cleanup behavior.

---

# 49. CLI INSTALLATION SECURITY

Only install software from trusted/verified sources defined by the CLI manifest/provider.

Do not allow arbitrary package installation through the GUI without clearly showing what is being installed.

For third-party CLI manifests, maintain enough metadata to identify:

```text
source
provider
package
version
integrity/checksum where applicable
```

Do not execute downloaded binaries before verification where feasible.

---

# 50. COMMAND VS GUI

The GUI is a convenience layer.

The real terminal remains the underlying power tool.

For example:

```text
GUI:
[Install Claude Code]
```

should conceptually perform the same real operation that an experienced user would otherwise perform manually.

The GUI must NOT be a fake shortcut.

---

# 51. TERMINAL COMMAND AUTOCOMPLETE

If practical, add command suggestions for installed CLIs.

Example:

```text
$ cla
```

suggest:

```text
claude
```

If user types:

```text
$ op
```

suggest:

```text
opencode
```

This is especially useful on mobile keyboards.

Do not make autocomplete intrusive.

---

# 52. RECENT COMMANDS

Persist a lightweight command history.

Example:

```text
Recent

npm install
npm run dev
git status
claude
```

Allow tapping a command to reuse it.

Do not store sensitive commands indefinitely.

---

# 53. COPY / SHARE / LOG ACTIONS

Terminal output should support:

* copy
* select
* clear
* share where appropriate

For errors, allow:

```text
Copy Error
```

so users can send it to the AI agent.

---

# 54. "ASK AI TO FIX" INTEGRATION

When a command/build/CLI operation fails:

```text
npm run build

✗ Build failed

[Copy]
[Ask AI to Fix]
```

When the user chooses Ask AI:

Send the relevant error context to the CubicLM AI agent.

The AI should know:

* project path
* command
* error
* relevant files

but avoid sending secrets.

---

# 55. DEVELOPMENT SERVER INTEGRATION

The same Terminal system must support:

```bash
npm run dev
```

and other long-running development commands.

For React/Vite:

```text
Node
 ↓
npm
 ↓
Vite
 ↓
localhost
 ↓
Preview WebView
```

Do not open the project's `index.html` directly when it requires Vite.

---

# 56. DYNAMIC PORT DETECTION

Never hardcode only:

```text
5173
```

Read actual server output and detect:

```text
localhost:5173
localhost:5174
127.0.0.1:5175
```

Then send the actual URL to Preview.

---

# 57. CLI + PROJECT + PREVIEW

Target workflow:

```text
User:
"Build a modern React dashboard"

AI Agent
   ↓
creates files
   ↓
shared workspace
   ↓
Claude Code/OpenCode/etc.
   ↓
npm install
   ↓
npm run dev
   ↓
CubicLM detects port
   ↓
Preview
```

This should work without the user manually moving files between systems.

---

# 58. CLI CATALOG UX

The catalog should not feel like an app store.

Keep it developer-focused.

Example:

```text
Install CLI

AI Coding
────────────

Claude Code
AI coding agent
Node.js
[Install]

OpenCode
Open-source coding agent
[Install]

Kilo
AI coding agent
[Install]

Cline
AI coding agent
[Install]

────────────────

Development

Git
Node.js
Python
...
```

Only show tools that can realistically be supported.

---

# 59. INSTALLATION QUEUE

If the user installs multiple tools:

```text
Claude Code
OpenCode
Kilo
```

avoid running many heavy installations simultaneously.

Use a small installation queue:

```text
Installing 1 of 3

Claude Code
██████████░░ 80%
```

Then continue.

Allow cancellation.

---

# 60. CANCEL INSTALLATION

If installation is in progress:

```text
Installing OpenCode...

[Cancel]
```

Cancellation must actually stop the relevant process/download where possible.

Clean temporary files.

Do not leave the registry claiming the CLI is installed.

---

# 61. FIRST-RUN EXPERIENCE

When Terminal is opened for the first time:

```text
Welcome to CubicLM Terminal

You can:
• Run commands
• Install developer CLIs
• Launch AI coding agents
• Run development servers
• Preview projects

[Install a CLI]
[Open Terminal]
```

Keep it concise.

Do not force onboarding every time.

---

# 62. IMPLEMENTATION ORDER

Implement in this order:

### Phase 1

Real process engine.

### Phase 2

Runtime Manager.

### Phase 3

Node/npm managed runtime.

### Phase 4

CLI manifest architecture.

### Phase 5

CLI installation providers.

### Phase 6

Persistent CLI registry.

### Phase 7

Installed CLI UI.

### Phase 8

One-tap install.

### Phase 9

Open/verify/update/repair/uninstall.

### Phase 10

Interactive CLI/PTY integration.

### Phase 11

Shared workspace.

### Phase 12

AI Agent integration.

### Phase 13

Vite/dev-server integration.

### Phase 14

Preview integration.

### Phase 15

Cloud fallback.

### Phase 16

Security/lifecycle/performance hardening.

---

# 63. DO NOT MAKE THESE MISTAKES

Do NOT:

* build only a terminal-looking UI
* fake CLI installation
* fake version numbers
* assume Android has Node
* assume Android has npm
* assume desktop Linux binaries work
* require root
* require Termux for primary functionality
* hardcode one package manager
* hardcode one port
* launch CLIs outside the selected workspace
* create duplicate project copies
* silently install software
* silently update software
* delete project files during uninstall
* expose API keys
* hide errors
* claim Android compatibility without testing
* treat unsupported CLIs as successfully installed

---

# 64. TEST MATRIX

Test:

### Terminal

```text
pwd
ls
echo
node --version
npm --version
```

### CLI Manager

```text
Install
Verify
Open
Update
Repair
Uninstall
Persistence
```

### CLI Registry

```text
Install → appears
Restart app → still appears
Uninstall → disappears
Binary removed externally → Broken/Missing
```

### Interactive

```text
CLI launch
stdin
stdout
stderr
Ctrl+C
ANSI
```

### Workspace

```text
AI creates file
CLI reads file
CLI modifies file
Terminal sees file
File manager sees change
```

### React/Vite

```text
npm install
npm run build
npm run dev
port detection
Preview
HMR
```

### Android

```text
ARM64
storage restrictions
background/foreground
process cleanup
network unavailable
runtime unavailable
```

Do not claim tests passed unless actually executed.

---

# 65. FINAL ACCEPTANCE TEST

A successful implementation should allow this exact experience:

```text
Open CubicLM
      ↓
Open Terminal
      ↓
See:

Installed CLI Tools
──────────────────────
✓ Claude Code
✓ OpenCode
✓ Kilo
──────────────────────
+ Install CLI
```

User taps:

```text
+ Install CLI
```

Selects:

```text
Claude Code
```

Taps:

```text
Install
```

CubicLM automatically:

```text
Checks Android compatibility
        ↓
Checks Node runtime
        ↓
Prepares Node if necessary
        ↓
Installs CLI
        ↓
Verifies executable
        ↓
Runs version command
        ↓
Registers CLI
```

Then:

```text
Installed CLI Tools

✓ Claude Code
  vX.X.X
  Ready

[Open]
```

User taps Open:

```text
Claude Code starts
inside the current project
```

User can interact with the real CLI.

Then the user can return to Terminal and run:

```bash
npm install
npm run dev
```

CubicLM starts the real development server.

Preview detects the actual localhost port.

The Preview opens the real application.

---

# 66. FINAL ARCHITECTURE

The final system should conceptually look like:

```text
                         CUBICLM
                            │
            ┌───────────────┼────────────────┐
            │               │                │
            ▼               ▼                ▼
        AI AGENT         TERMINAL         PREVIEW
            │               │
            │               ▼
            │         Process Manager
            │               │
            │         Runtime Manager
            │               │
            │      ┌────────┼─────────┐
            │      │        │         │
            │      ▼        ▼         ▼
            │     Node    Python     Git
            │      │
            │      ▼
            │     npm
            │      │
            │      ▼
            │   CLI Manager
            │      │
            │      ├── Claude Code
            │      ├── OpenCode
            │      ├── Kilo
            │      ├── Cline
            │      └── Future CLIs
            │
            └───────────────┐
                            ▼
                     SHARED WORKSPACE
                            │
                  ┌─────────┴─────────┐
                  │                   │
                  ▼                   ▼
              Dev Server          CLI Tools
                  │
                  ▼
              localhost
                  │
                  ▼
               Preview
```

---

# 67. FINAL ENGINEERING REPORT

After implementation, provide:

1. Existing terminal architecture
2. Root problems discovered
3. Files/modules changed
4. Process execution architecture
5. Android runtime strategy
6. Node/npm strategy
7. CLI manifest architecture
8. CLI providers implemented
9. Supported CLIs
10. Exact installation mechanisms
11. Persistent registry implementation
12. Installed CLI UI
13. One-tap installation flow
14. Uninstall flow
15. Update/repair flow
16. Version verification
17. Interactive CLI implementation
18. Shared workspace integration
19. AI integration
20. Security model
21. Storage/cache strategy
22. Android lifecycle strategy
23. Cloud fallback
24. Tests actually performed
25. Tests that could not be performed
26. Known limitations

The most important requirement:

**Build a real system underneath the mobile-friendly UI.**

The user should experience:

> **Tap Install → CLI is actually installed → CLI appears in Installed CLI Tools → Tap Open → real CLI starts inside the current project.**

And advanced users should still be able to use:

> **Terminal → real commands → real processes → real runtimes.**

Do not sacrifice the real terminal architecture merely to make the UI look convenient.
