# CubicWeb System Logs

## Production-Grade System Diagnostics & App Compatibility Layer for CubicLM

Repository:
https://github.com/abir2afridi/CubicLM

You are working on CubicLM, an AI-powered application development environment that can generate code, modify projects, use a terminal, run projects, and preview websites/apps.

I want to add a new core feature called:

# CubicWeb System Logs

This must NOT be implemented as just a visual error-log page.

CubicWeb System Logs must become a centralized **System Diagnostics + Runtime Failure + App Compatibility observability layer** for CubicLM.

The main problem this feature must solve is:

> AI can often detect and fix source-code errors by itself, but some failures are NOT source-code problems. The generated code may be completely valid, yet CubicLM may be unable to execute, build, preview, or interact with that application because of Android, WebView, runtime, process, filesystem, architecture, permission, dependency, or other platform/environment limitations.

When this happens, AI should NOT keep modifying valid code endlessly.

Instead, CubicLM must understand:

"This is not a code problem. The current execution environment cannot perform this operation."

That failure must be captured by CubicWeb System Logs, explained clearly to the user, provided to the AI as structured diagnostic context, and routed to an appropriate fallback when possible.

---

# 1. UNDERSTAND THE CORE PROBLEM BEFORE IMPLEMENTING

CubicLM has three fundamentally different layers of failure.

## LAYER 1 — USER / GENERATED CODE ERROR

The generated project itself is wrong.

Examples:

* JSX syntax error
* TypeScript error
* JavaScript exception
* incorrect import
* missing component
* invalid API usage
* incorrect variable
* broken React logic
* invalid Next.js code
* malformed package.json
* dependency version conflict
* application-level runtime exception

These should normally go through the existing AI debugging/fixing workflow.

Example:

```text
TypeError:
Cannot read properties of undefined
```

AI may inspect the code, identify the problem, modify the source, and retry.

This is a CODE ERROR.

It should NOT automatically become a CubicWeb compatibility error.

---

# 2. LAYER 2 — RUNTIME / EXECUTION ENVIRONMENT ERROR

The source code may be valid, but CubicLM cannot execute something because a required runtime/tool/process is unavailable.

Examples:

* Node.js unavailable
* npm unavailable
* Python unavailable
* Git unavailable
* shell unavailable
* executable not found
* executable cannot start
* PTY unavailable
* process creation failed
* local development server cannot start
* required runtime version unavailable
* runtime architecture mismatch
* port cannot be bound
* process terminated by environment
* native executable cannot execute

Example:

The AI creates a valid Next.js project.

The project contains:

```text
package.json
app/
components/
next.config.js
```

The code is valid.

CubicLM executes:

```bash
npm run dev
```

But Android does not have a compatible Node.js runtime.

This is NOT a Next.js source-code error.

It is a:

RUNTIME / COMPATIBILITY ERROR.

The AI must NOT start changing the user's Next.js files just because the command failed.

CubicWeb should report:

```text
CW-RUNTIME-001
Node.js Runtime Unavailable

The project requires Node.js to run its development server, but
Node.js is not currently available in this execution environment.

AI code changes are unlikely to resolve this issue.
```

---

# 3. LAYER 3 — PLATFORM / APP COMPATIBILITY ERROR

The required runtime may exist, but the application still cannot perform an operation because the host environment is different from a normal desktop/browser/server environment.

This is especially important because CubicLM runs on Android.

Examples:

* Android sandbox restriction
* WebView limitation
* unavailable browser capability
* unavailable native API
* restricted filesystem access
* permission denied
* unsupported architecture
* native library unavailable
* desktop Linux binary cannot execute on Android
* glibc-based binary incompatible with Android/Bionic
* restricted process behavior
* localhost/network restriction
* WebSocket limitation
* service worker limitation
* browser API unavailable
* file:// restrictions
* mixed-content restriction
* unsupported system feature
* insufficient device resources

These are PLATFORM / APP COMPATIBILITY failures.

The user should be told:

> "Your code may be valid, but this operation cannot be performed by the current CubicLM/Android environment."

---

# 4. THE MOST IMPORTANT BEHAVIOR

The system must NEVER blindly assume:

"Command failed → code is broken."

Instead:

```text
Operation
    ↓
Execution Attempt
    ↓
Raw Result
    ↓
Error Classification
    ↓
Determine Root Cause
    ↓
┌─────────────────────────────┐
│                             │
│ Code Error?                 │
│ Runtime Error?              │
│ Platform Compatibility?    │
│ Dependency Error?           │
│ Permission Error?           │
│ Resource Error?             │
└─────────────────────────────┘
    ↓
Appropriate Handler
```

If the problem is source code:

→ AI debugging loop

If the problem is runtime:

→ CubicWeb System Logs

If the problem is platform compatibility:

→ CubicWeb System Logs

If a fallback exists:

→ fallback

If no fallback exists:

→ clearly explain the limitation

---

# 5. DO NOT LET AI ENTER AN INFINITE FIX LOOP

This is one of the primary reasons for this feature.

Example:

AI generates valid Next.js project.

CubicLM tries:

```bash
npm run dev
```

Node.js unavailable.

Bad behavior:

```text
AI modifies package.json
AI modifies next.config.js
AI modifies app/page.jsx
AI modifies package.json again
AI tries npm again
AI modifies code again
...
```

This is wrong.

Correct behavior:

```text
npm run dev
       ↓
Node unavailable
       ↓
CW-RUNTIME-001
       ↓
AI receives:
aiCanFix = false
       ↓
Stop unnecessary source modifications
       ↓
Show System Log
       ↓
Attempt Cloud Runtime if available
```

The AI must understand:

> "There is no source-code modification that can make an unavailable runtime magically exist."

---

# 6. CENTRAL CUBICWEB LOGGER

Create a centralized logging architecture.

Conceptually:

```text
CubicWebLogger
```

Every CubicLM system component capable of producing platform/runtime failures should be able to report structured events to it.

Components should include:

* AI Agent
* Project Manager
* Workspace
* File System
* Terminal
* Process Executor
* Runtime Manager
* Preview
* WebView
* Dev Server Manager
* Dependency Manager
* Native Layer
* Network Layer
* Cloud Runtime
* Android Platform Layer

Do NOT make each UI component implement its own error classification.

The low-level system layer should generate structured diagnostics.

---

# 7. STRUCTURED LOG EVENT

Create a strongly typed event model appropriate for the existing CubicLM architecture.

Conceptually:

```text
SystemLogEvent

id
timestamp
traceId
severity
category
component
errorCode
title
message
technicalDetails
operation
platform
runtime
projectId
projectPath
command
exitCode
recoverable
aiCanFix
fallbackAvailable
fallbackUsed
occurrenceCount
metadata
```

Do not blindly copy this exact structure if the repository uses another architecture.

Adapt it properly.

---

# 8. ERROR CLASSIFICATION

Create a real classifier.

At minimum:

```text
CODE
RUNTIME
PLATFORM
COMPATIBILITY
DEPENDENCY
PERMISSION
FILESYSTEM
NETWORK
WEBVIEW
PROCESS
NATIVE
RESOURCE
PREVIEW
CLOUD
SECURITY
UNKNOWN
```

The classifier must be evidence-based.

Do NOT classify every non-zero exit code as a compatibility issue.

For example:

```text
npm install
```

fails because a package version does not exist.

That is likely a dependency problem.

But:

```text
execve failed
```

because the binary cannot execute on the Android architecture is a runtime/platform compatibility problem.

---

# 9. ERROR CODE REGISTRY

Create stable CubicWeb error codes.

Examples:

```text
CW-RUNTIME-001
Node.js runtime unavailable

CW-RUNTIME-002
Python runtime unavailable

CW-RUNTIME-003
Unsupported runtime architecture

CW-RUNTIME-004
Required executable unavailable

CW-PREVIEW-001
Development server failed to start

CW-PREVIEW-002
Localhost server unavailable

CW-PREVIEW-003
Framework requires unavailable runtime

CW-TERMINAL-001
Process execution failed

CW-TERMINAL-002
PTY unavailable

CW-TERMINAL-003
Command unavailable

CW-WEBVIEW-001
WebView capability unavailable

CW-WEBVIEW-002
WebView navigation failed

CW-WEBVIEW-003
Required browser API unavailable

CW-FS-001
Filesystem operation denied

CW-PERM-001
Required permission unavailable

CW-NATIVE-001
Native binary incompatible

CW-NATIVE-002
Native dependency unavailable

CW-NET-001
Network operation failed

CW-RESOURCE-001
Insufficient device resources

CW-CLOUD-001
Cloud fallback unavailable
```

Create an extensible registry rather than hardcoding only these examples.

---

# 10. RUNTIME CAPABILITY DETECTION

CubicLM must know what the current environment can actually do.

Create or integrate with a runtime capability layer.

Detect actual availability of:

* Node.js
* npm
* Python
* pip
* Git
* shell
* required executables
* architecture
* executable permissions
* filesystem capabilities
* network capabilities
* WebView capabilities
* process capabilities
* native library capabilities

Conceptually:

```text
RuntimeCapabilities

node
npm
python
pip
git
shell
architecture
os
webview
filesystem
network
process
native
```

Use the actual project's architecture and platform APIs.

Do not fake capability detection.

---

# 11. IMPORTANT ANDROID REQUIREMENT

CubicLM runs on Android.

Do NOT treat Android as ordinary desktop Linux.

Do NOT assume:

* arbitrary Linux binaries will execute
* glibc binaries will work
* desktop Linux CLI programs are automatically compatible
* every shell exists
* every filesystem path is writable
* every process model behaves like desktop Linux
* every port behaves like a desktop environment
* every browser API exists in Android WebView
* native libraries built for desktop Linux can execute on Android
* a tool being "available" in PATH means it is actually usable

The system must detect actual compatibility.

Where necessary, distinguish:

```text
Android
ARM64
Android/Bionic
WebView
CubicLM Runtime
Cloud Runtime
```

from:

```text
Desktop Linux
Desktop Chrome
Windows
macOS
```

---

# 12. TERMINAL INTEGRATION

CubicLM already has a Terminal.

Integrate CubicWeb System Logs into the REAL terminal/process execution pipeline.

Capture:

* command
* arguments
* start time
* end time
* exit code
* stdout
* stderr
* process start failure
* executable-not-found
* permission failure
* architecture failure
* signal termination
* timeout
* PTY failure
* process crash

But preserve classification.

Example:

```text
Command:
npm run dev

Exit:
failed

Reason:
Node.js executable unavailable

Classification:
RUNTIME / COMPATIBILITY

Error:
CW-RUNTIME-001
```

Do not classify:

```text
npm run build
```

failing because of a genuine application syntax error as a platform compatibility issue.

---

# 13. PREVIEW INTEGRATION

Integrate directly with CubicLM Preview.

Preview must understand:

* static HTML
* CSS
* JavaScript
* React
* Vite
* Vue
* Next.js
* other framework projects

When Preview cannot execute something:

DO NOT simply display a generic:

```text
Nothing browser-runnable at this path.
```

Instead:

1. Determine why.
2. Generate a structured CubicWeb System Log.
3. Show a user-friendly explanation.
4. Tell whether the problem is code, runtime, dependency, WebView, or platform.
5. Tell whether local execution is possible.
6. Tell whether cloud fallback is possible.

---

# 14. NEXT.JS EXAMPLE

Suppose the AI generates:

```text
package.json
next.config.js
app/layout.jsx
app/page.jsx
```

The source is valid.

CubicLM attempts:

```bash
npm install
npm run dev
```

But Node.js is unavailable.

System should produce:

```text
ERROR

CW-PREVIEW-003

Framework requires unavailable runtime

Framework:
Next.js

Required runtime:
Node.js

Detected:
Unavailable

Platform:
Android

AI can fix source code:
No

Cloud fallback:
Available
```

Preview should then show:

```text
This Next.js project requires a Node.js runtime.

The project itself may be valid, but Node.js is unavailable
in the current CubicLM environment.

You can:
[Use Cloud Runtime]
[Retry]
[View System Logs]
```

---

# 15. WEBVIEW COMPATIBILITY

CubicLM uses an embedded WebView.

Create compatibility diagnostics for:

* unsupported browser APIs
* navigation failures
* localhost issues
* WebSocket failures
* service-worker limitations
* file:// limitations
* mixed-content restrictions
* JavaScript execution failures
* unsupported browser capabilities
* origin restrictions

But do NOT classify every JavaScript error as a WebView compatibility issue.

Only classify it as platform/WebView compatibility when there is evidence that the environment is responsible.

---

# 16. AI AGENT DIAGNOSTIC CONTEXT

This is critical.

The AI agent must be able to receive structured system diagnostics.

Example:

```text
{
  errorCode: "CW-RUNTIME-001",
  category: "RUNTIME",
  component: "PREVIEW",
  rootCause: "NODE_RUNTIME_UNAVAILABLE",
  aiCanFix: false,
  fallbackAvailable: true,
  recommendedAction: "USE_CLOUD_RUNTIME"
}
```

The AI should understand:

```text
This is an environment problem.
Do not repeatedly modify source code.
```

The AI may explain the problem to the user, but must not pretend it can fix a platform limitation through code changes.

---

# 17. AI + SYSTEM LOG INTERACTION

The AI should have access to recent relevant CubicWeb logs.

For example:

```text
User:
"Why isn't my website opening?"

AI context:

Recent CubicWeb System Log:

CW-RUNTIME-001
Node.js unavailable
Project:
portfolio-site
Operation:
npm run dev
AI can fix:
false
Cloud fallback:
true
```

AI can then answer:

```text
Your project files were generated successfully.
The problem is that this device currently lacks the Node.js
runtime required to run the Next.js development server.
```

This is much better than making the AI inspect and rewrite the project repeatedly.

---

# 18. CLOUD FALLBACK

If CubicLM has a cloud execution system:

Use:

```text
LOCAL EXECUTION
       ↓
FAILURE
       ↓
CUBICWEB CLASSIFICATION
       ↓
COMPATIBILITY ISSUE?
       ↓
YES
       ↓
CLOUD AVAILABLE?
       ↓
YES → CLOUD RUNTIME
NO  → USER EXPLANATION
```

Do not silently replace the local failure.

Record both:

```text
Local:
CW-RUNTIME-001

Fallback:
Cloud Runtime started successfully
```

If cloud execution fails:

```text
CW-CLOUD-002
Cloud Runtime execution failed
```

The original local failure must remain visible.

---

# 19. SYSTEM LOG UI

Create a dedicated screen/panel:

# CubicWeb System Logs

It should feel like a professional developer diagnostics console.

Example:

```text
CubicWeb System Logs

[All] [Errors] [Warnings] [Info] [Debug]

────────────────────────────────────

🔴 ERROR
CW-RUNTIME-001

Node.js runtime unavailable

Preview • Runtime
12:42:18 PM

The current environment does not provide
a compatible Node.js runtime required by
this Next.js project.

[View Details]

────────────────────────────────────

🟠 WARNING
CW-WEBVIEW-003

Browser capability unavailable

Preview • WebView
12:43:02 PM

────────────────────────────────────

🔵 INFO
CW-CLOUD-001

Cloud Runtime fallback started

Preview • Cloud
12:43:09 PM
```

---

# 20. LOG DETAILS

Clicking a log should reveal:

```text
Title
Error Code
Severity
Category
Component
Timestamp
Trace ID
Project
Operation
Command
Platform
Runtime
Root Cause
Human Explanation
Technical Details
Exit Code
AI Can Fix?
Fallback Available?
Fallback Used?
Occurrences
```

Technical details should be collapsible.

Do not overwhelm normal users.

---

# 21. FILTERING

Support:

Severity:

```text
All
Errors
Warnings
Info
Debug
```

Category:

```text
All
Runtime
Compatibility
Preview
Terminal
WebView
Network
Filesystem
Native
Cloud
Permission
Resource
```

Search by:

* error code
* message
* project
* component
* command
* trace ID

---

# 22. ACTIONS

Each applicable log may provide:

```text
Copy Error
Copy Details
Retry
View Project
Open Terminal
Open Preview
Use Cloud Runtime
Clear
```

Only show actions that actually make sense for that event.

Do not show fake buttons.

---

# 23. TRACE / CORRELATION ID

Every significant operation should have a trace ID.

Example:

```text
TRACE:
CW-7F29A1
```

A single user operation may generate:

```text
AI Agent
    ↓
File Creation
    ↓
npm install
    ↓
npm run dev
    ↓
Runtime Failure
    ↓
Preview Failure
```

All related logs should share the same trace ID.

This allows CubicLM to reconstruct:

"What exactly happened during this operation?"

---

# 24. LOG DEDUPLICATION

Do not flood the UI.

If:

```text
CW-RUNTIME-001
```

occurs 30 times because Preview keeps retrying:

Group it.

Display:

```text
Node.js runtime unavailable

Occurred 30 times

First:
12:40 PM

Last:
12:45 PM
```

The raw occurrence count should be preserved.

---

# 25. PERSISTENCE

Logs must survive normal navigation and UI re-rendering.

Use the most appropriate existing persistence mechanism.

Avoid unlimited storage.

Implement retention limits.

Old logs should be automatically removed according to a reasonable policy.

Provide:

```text
Clear Logs
```

Do not allow logs to consume significant device storage.

---

# 26. SECURITY / SECRET REDACTION

System logs must never leak sensitive information.

Redact:

* API keys
* access tokens
* passwords
* cookies
* authorization headers
* private environment variables
* secrets
* private credentials

Example:

```text
OPENAI_API_KEY=sk-xxxxxxxx
```

becomes:

```text
OPENAI_API_KEY=[REDACTED]
```

Never dump the complete environment.

Never dump Authorization headers.

Never store unnecessary request bodies.

Apply redaction before persistence AND before UI display.

---

# 27. SEPARATE USER LOGS FROM CUBICWEB SYSTEM LOGS

This distinction is mandatory.

A website's own:

```text
console.error(...)
```

is a USER APPLICATION LOG.

It is not automatically a CubicWeb System Log.

Similarly:

```text
HTTP 404
```

inside the user's website is not automatically a CubicWeb compatibility failure.

CubicWeb System Logs are specifically for:

```text
CubicLM
Runtime
Platform
Execution
Preview
Terminal
WebView
Native
Environment
Fallback
```

---

# 28. DO NOT CREATE FALSE POSITIVES

The logging system must be conservative.

Do not report compatibility errors for:

* normal application errors
* expected HTTP failures
* user website console logs
* ordinary compiler errors
* normal npm warnings
* intentionally failed commands
* invalid user input

Use actual evidence from:

* exit codes
* stderr
* system exceptions
* runtime detection
* platform APIs
* process execution result
* WebView APIs
* capability detection
* architecture information

---

# 29. THREE-WAY CLASSIFICATION MODEL

The final architecture should make this distinction explicit:

```text
┌─────────────────────────────┐
│       USER CODE             │
│                             │
│ React / JS / TS / Next.js   │
│ Syntax / Logic / API errors │
└──────────────┬──────────────┘
               │
               ▼
        AI DEBUGGER
```

and:

```text
┌─────────────────────────────┐
│        RUNTIME              │
│                             │
│ Node / Python / Process     │
│ Shell / PTY / Dev Server    │
└──────────────┬──────────────┘
               │
               ▼
       CUBICWEB SYSTEM LOGS
```

and:

```text
┌─────────────────────────────┐
│ PLATFORM / COMPATIBILITY    │
│                             │
│ Android / WebView / Native  │
│ Permission / Architecture   │
│ Filesystem / Resources      │
└──────────────┬──────────────┘
               │
               ▼
       CUBICWEB SYSTEM LOGS
```

---

# 30. OBSERVABILITY PIPELINE

Implement the complete pipeline:

```text
USER ACTION
    ↓
CUBICLM OPERATION
    ↓
EXECUTION
    ↓
RAW RESULT
    ↓
ERROR CLASSIFIER
    ↓
ROOT-CAUSE ANALYSIS
    ↓
┌─────────────┬──────────────┬───────────────┐
│ CODE ERROR  │ RUNTIME ERROR │ PLATFORM ERROR│
└─────────────┴──────────────┴───────────────┘
       ↓              ↓               ↓
   AI DEBUGGER   CUBICWEB LOGS   CUBICWEB LOGS
                      ↓               ↓
                 FALLBACK / RECOVERY
                      ↓
                     UI
                      ↓
                AI DIAGNOSTIC CONTEXT
```

This architecture is the heart of the feature.

---

# 31. RELATIONSHIP WITH EXISTING AI CODING WORKFLOW

Do NOT replace the existing AI coding/debugging system.

Instead:

```text
AI Coding System
       │
       ├── Code problem
       │      ↓
       │   AI fixes code
       │
       └── Environment problem
              ↓
         CubicWeb Logs
              ↓
       fallback / explanation
```

CubicWeb System Logs should complement the AI coding agent, not compete with it.

---

# 32. REAL-WORLD EXAMPLES THE SYSTEM MUST HANDLE

### Example A — Syntax Error

```text
JSX element has no corresponding closing tag.
```

Classification:

```text
CODE ERROR
```

AI should fix it.

No compatibility log required.

---

### Example B — Next.js Without Node

```text
npm run dev

Node executable not found.
```

Classification:

```text
RUNTIME / COMPATIBILITY
CW-RUNTIME-001
```

AI should NOT modify source code.

---

### Example C — Android Native Binary

```text
Exec format error
```

Classification:

```text
NATIVE / PLATFORM
CW-NATIVE-001
```

---

### Example D — WebView Capability

```text
Required browser capability unavailable.
```

Classification:

```text
WEBVIEW / COMPATIBILITY
CW-WEBVIEW-003
```

---

### Example E — Permission

```text
Permission denied
```

If caused by Android sandbox restrictions:

```text
PERMISSION / PLATFORM
CW-PERM-001
```

---

### Example F — Dependency

```text
npm ERR! package version not found
```

Classification:

```text
DEPENDENCY
```

AI may fix package configuration.

---

### Example G — Resource

```text
Process killed because device resources are insufficient.
```

Classification:

```text
RESOURCE
CW-RESOURCE-001
```

AI should not endlessly rewrite source code.

---

# 33. TESTING REQUIREMENTS

Create automated tests.

## Classification

Test:

* syntax error
* runtime exception
* missing executable
* Node unavailable
* Python unavailable
* dependency failure
* permission failure
* architecture mismatch
* WebView limitation
* filesystem restriction
* network failure
* resource failure

Verify each is classified correctly.

---

# 34. TERMINAL TESTS

Test:

* valid command
* command not found
* permission denied
* process crash
* timeout
* non-zero exit code
* unavailable executable
* architecture mismatch
* PTY failure

Verify normal command failures are not incorrectly classified as platform compatibility errors.

---

# 35. PREVIEW TESTS

Test:

* static HTML
* React
* Vite
* Vue
* Next.js
* localhost server
* missing runtime
* failed dev server
* WebView navigation
* WebSocket
* cloud fallback

---

# 36. SECURITY TESTS

Verify:

```text
API key → REDACTED
Authorization → REDACTED
Password → REDACTED
Cookie → REDACTED
Environment variables → NOT EXPOSED
```

Test both:

```text
UI logs
Persistent logs
AI diagnostic context
```

---

# 37. REGRESSION REQUIREMENTS

Do not break:

* AI chat
* AI coding agent
* workspace
* file system
* project generation
* terminal
* Preview
* React
* Vite
* Next.js
* WebView
* Android
* cloud APIs
* existing runtime functionality

Do not rewrite unrelated components.

---

# 38. IMPLEMENTATION STRATEGY

Before coding:

1. Inspect the repository.
2. Map the current architecture.
3. Identify existing logging/error infrastructure.
4. Identify process execution.
5. Identify Preview execution.
6. Identify WebView bridge.
7. Identify runtime detection.
8. Identify cloud fallback.
9. Identify AI debugging loop.
10. Identify where errors are currently swallowed or converted into generic messages.

Then implement the smallest architecture that can provide the complete behavior.

Do not create duplicate infrastructure if suitable infrastructure already exists.

---

# 39. IMPORTANT: FIX ROOT CAUSES, NOT JUST UI

If the current CubicLM architecture swallows a runtime error and only returns:

```text
Preview unavailable
```

do not merely modify the UI to display a prettier message.

Trace backward and make the underlying runtime layer produce structured error information.

The UI must consume real diagnostics.

No fake logs.

No hardcoded simulated errors.

---

# 40. FINAL ACCEPTANCE FLOW

The feature is NOT complete unless this complete flow works:

```text
USER
 ↓
"Build a Next.js website"
 ↓
AI generates project
 ↓
Files written to workspace
 ↓
CubicLM attempts npm install
 ↓
CubicLM attempts npm run dev
 ↓
Node.js unavailable
 ↓
REAL runtime failure detected
 ↓
REAL error classification
 ↓
CW-RUNTIME-001 generated
 ↓
CubicWeb System Logs receives event
 ↓
User sees useful diagnostic
 ↓
AI receives structured diagnostic
 ↓
AI understands:
"This is not a source-code problem."
 ↓
AI stops unnecessary code modifications
 ↓
Cloud fallback detected
 ↓
Cloud runtime started
 ↓
Preview connects to runtime
 ↓
Successful recovery logged
```

---

# 41. SUCCESSFUL RECOVERY MUST ALSO BE LOGGED

System Logs are not only for failures.

Example:

```text
🔵 INFO

Cloud Runtime started successfully

Trace:
CW-7F29A1

Previous issue:
CW-RUNTIME-001

Recovery:
Cloud execution

Status:
Recovered
```

This gives the user a complete story:

```text
What failed?
Why did it fail?
What did CubicLM do?
Did AI need to modify code?
Was fallback available?
Did fallback work?
```

---

# 42. FINAL PRODUCT VISION

CubicWeb System Logs should effectively become CubicLM's:

**"System-level truth layer."**

The AI decides:

```text
How should the code be written?
```

CubicWeb determines:

```text
Can this environment actually execute it?
```

The user should never be forced to guess whether:

```text
"My code is broken"
```

or:

```text
"CubicLM cannot execute this code in the current environment."
```

The system must make that distinction automatically.

---

# 43. FINAL DELIVERABLE

After implementation, provide a detailed report containing:

1. Files changed
2. New files created
3. Existing architecture reused
4. CubicWeb Logger architecture
5. Error classification architecture
6. Error-code registry
7. Runtime capability detection
8. Terminal integration
9. Preview integration
10. WebView integration
11. AI agent integration
12. Cloud fallback integration
13. Trace/correlation system
14. Deduplication
15. Persistence
16. Security/redaction
17. UI implementation
18. Tests added
19. Tests passed
20. Known limitations

Most importantly, explicitly demonstrate that the system can distinguish:

```text
CODE ERROR
```

from:

```text
RUNTIME ERROR
```

from:

```text
PLATFORM / APP COMPATIBILITY ERROR
```

and that these three paths behave differently.

DO NOT claim the feature is complete unless the actual end-to-end behavior has been implemented and tested.

The goal is NOT:

"Show errors in a log screen."

The goal is:

# Detect → Classify → Explain → Log → Inform AI → Recover/Fallback

That is what CubicWeb System Logs must implement.
