#!/usr/bin/env bash
# 🏷️ CubicLM — GitHub Label Setup Script
# Run from the repository root: bash .github/create-labels.sh
# Requires: GitHub CLI (gh) — https://cli.github.com

set -e

echo "🏷️  Creating labels for CubicLM (abir2afridi/CubicLM)..."
echo "────────────────────────────────────────────────────────"

# 🔴 Type Labels
gh label create "bug"              --color "d73a4a" --description "🐛 Something isn't working" --force
gh label create "feature-request"  --color "a2eeef" --description "✨ New feature or request" --force
gh label create "documentation"    --color "0075ca" --description "📝 Improvements or additions to docs" --force
gh label create "question"         --color "d876e3" --description "💬 Further information is requested" --force
gh label create "security"         --color "e4e669" --description "🔒 Security vulnerability or concern" --force
gh label create "performance"      --color "f9d0c4" --description "⚡ Performance improvement or regression" --force
gh label create "ui"               --color "bfd4f2" --description "🎨 UI or visual change" --force
gh label create "accessibility"    --color "7057ff" --description "♿ Accessibility concern" --force
gh label create "regression"       --color "d73a4a" --description "🔄 Previously working feature is now broken" --force
gh label create "refactor"         --color "e4e669" --description "♻️ Code improvement without behavior change" --force

# 🟡 Status Labels
gh label create "needs-triage"        --color "ededed" --description "🔍 Awaiting review and categorization" --force
gh label create "needs-reproduction"  --color "fef2c0" --description "🔁 Cannot reproduce — more info needed" --force
gh label create "needs-info"          --color "fef2c0" --description "💬 Waiting for more information from reporter" --force
gh label create "confirmed"           --color "0e8a16" --description "✅ Issue confirmed and reproducible" --force
gh label create "in-progress"         --color "fbca04" --description "🔄 Currently being worked on" --force
gh label create "blocked"             --color "e4e669" --description "🚧 Blocked by another issue or PR" --force
gh label create "wont-fix"            --color "ffffff" --description "🚫 This will not be addressed" --force
gh label create "duplicate"           --color "cfd3d7" --description "🔁 This issue already exists" --force
gh label create "stale"               --color "c5def5" --description "💤 No recent activity" --force
gh label create "invalid"             --color "e4e669" --description "❌ Not a valid issue" --force

# 🔵 Priority Labels
gh label create "priority: critical" --color "b60205" --description "🚨 Must fix immediately — app is broken" --force
gh label create "priority: high"     --color "d93f0b" --description "🔴 High impact — fix in next release" --force
gh label create "priority: medium"   --color "fbca04" --description "🟡 Medium impact — schedule soon" --force
gh label create "priority: low"      --color "0e8a16" --description "🟢 Low impact — fix when convenient" --force

# 🟢 Contributor Labels
gh label create "good first issue" --color "7057ff" --description "👋 Good for newcomers — well-scoped and documented" --force
gh label create "help wanted"      --color "008672" --description "🙋 Extra attention is needed — community help welcome" --force
gh label create "hacktoberfest"    --color "ff6d00" --description "🎃 Open for Hacktoberfest contributions" --force

# ⚪ Area Labels (CubicLM-specific)
gh label create "area: frontend"     --color "bfd4f2" --description "🖥️ Frontend / UI code (lib/views, lib/widgets)" --force
gh label create "area: mobile"       --color "d4c5f9" --description "📱 Mobile-specific — Android FGS, SoC, Hive, minSdk 28" --force
gh label create "area: desktop"      --color "d4c5f9" --description "🖥️ Desktop — Flutter Windows, window_manager, CMake, ATL" --force
gh label create "area: api"          --color "fef2c0" --description "🔌 API — local OpenAI server (8080) + cloud providers" --force
gh label create "area: ai"           --color "fef2c0" --description "🧠 AI — llama.cpp / LiteRT-LM / SD 1.5 / FFI" --force
gh label create "area: build"        --color "fef2c0" --description "🔧 Build system — Flutter, Gradle 8.14, CMake, Firebase" --force
gh label create "area: ci-cd"        --color "ededed" --description "⚙️ CI/CD pipelines and automation" --force
gh label create "area: docs"         --color "0075ca" --description "📖 Documentation" --force
gh label create "area: tests"        --color "c2e0c6" --description "🧪 Tests — flutter test, flutter analyze" --force
gh label create "area: i18n"         --color "f9d0c4" --description "🌍 i18n — bn_en_translator, localization" --force
gh label create "area: a11y"         --color "7057ff" --description "♿ Accessibility" --force
gh label create "area: performance"  --color "f9d0c4" --description "⚡ Performance — tok/s, cold start, bundle size" --force
gh label create "area: security"     --color "e4e669" --description "🔒 Security — secure storage, MCP bearer, key handling" --force
gh label create "api"                --color "fef2c0" --description "🔌 API design or implementation" --force
gh label create "mobile"             --color "d4c5f9" --description "📱 Mobile-specific code" --force
gh label create "build"              --color "fef2c0" --description "🔧 Build system and tooling" --force
gh label create "integration"        --color "a2eeef" --description "🔗 New provider / MCP / skill integration" --force
gh label create "i18n"               --color "f9d0c4" --description "🌍 Internationalization" --force
gh label create "dependencies"       --color "ededed" --description "📦 Dependency updates" --force

# 📏 PR Size Labels
gh label create "size: xs" --color "3cbf00" --description "📏 XS: 1–10 lines changed" --force
gh label create "size: s"  --color "5d9801" --description "📏 S: 11–50 lines changed" --force
gh label create "size: m"  --color "fef2c0" --description "📏 M: 51–200 lines changed" --force
gh label create "size: l"  --color "f9d0c4" --description "📏 L: 201–500 lines changed" --force
gh label create "size: xl" --color "d73a4a" --description "📏 XL: 500+ lines changed" --force

echo "✅ Done! All labels synced for abir2afridi/CubicLM"
