# 🔒 Security Policy for CubicLM

> **Do not report security vulnerabilities via public issues.** Use the private channels below.

CubicLM (`abir2afridi/CubicLM`, `com.cubiclm.app` v1.1.0) stores API keys via `flutter_secure_storage` (Android Keystore / Keychain), handles model downloads via `ModelDownloadService.kt` (FGS, HTTP Range), and round-trips MCP tool calls — so we take security seriously.

## 🛡️ Supported Versions

| Version | Supported |
|---------|-----------|
| `1.1.0+6` (latest) | ✅ Yes — actively patched |
| `1.0.5+5` | ⚠️ Security fixes only until next minor |
| `< 1.0.5` | ❌ No |

We recommend always running the latest APK or Windows zip from [Releases](https://github.com/abir2afridi/CubicLM/releases).

## 📬 Reporting a Vulnerability

### 🛡️ GitHub Security Advisories (Preferred)

[Report privately →](https://github.com/abir2afridi/CubicLM/security/advisories/new)

Only maintainers can see your report until a fix is released. Fastest path.

### 📧 Email

If you prefer email, contact the maintainer listed in [`CODEOWNERS`](CODEOWNERS) / commit history. Include **"CubicLM Security"** in the subject. You may encrypt with PGP if available.

**Include in your report:**

- CubicLM version and platform (Android / Windows / Web)
- Affected component (`lib/services/cloud/`, `lib/services/mcp/`, `android/`, `windows/`, `lib/ffi/`)
- Steps to reproduce (without exploiting beyond proof-of-concept)
- Impact assessment (data exposure, privilege, denial of service)
- Any suggested mitigation

## ⏱️ Response Time

- **Acknowledgement:** within **48 hours**
- **Triage / severity assignment:** within **72 hours**
- **Critical fix target:** within **7 days** (patch release + advisory)
- **Public disclosure:** coordinated after a fix is available; reporter is credited unless they prefer anonymity

## 🔍 Scope

In scope:

- Authentication / API key handling (`flutter_secure_storage`, MCP bearer tokens, `cloud_service.dart`)
- Download and storage (`download_service.dart`, `ModelDownloadService.kt`, Hive boxes, `android/key.properties` handling)
- Local OpenAI-compatible server (`openai_server_service.dart`, port 8080)
- Native FFI (`lib/ffi/sd_ffi_bindings.dart`, `local_plugins/`)
- Windows bundle and Android APK signing

Out of scope (but we still welcome heads-ups):

- Upstream provider APIs (OpenRouter, Hugging Face, etc.)
- Denial-of-service requiring physical device access
- Issues in `flutter`, `Gradle`, `CMake`, or `Firebase C++ SDK` themselves — report upstream and link us

## 🙏 Safe Harbor

We consider research conducted in good faith, with responsible disclosure and no data exfiltration beyond what is needed to demonstrate the issue, to be authorized. Thank you for helping keep CubicLM users safe.

---

> 💡 **Tip:** Rotate any exposed API keys immediately in **Explore → Online** provider cards and revoke the compromised token at the provider dashboard.
