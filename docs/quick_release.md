# Quick Release — CubicLM

One-page checklist for cutting a release (`vX.Y.Z`). Source of truth for
version: `pubspec.yaml`. In-app links use `/releases/latest` (no code change
needed); only the website + README hardcode versions.

## 0. Toolchain (Windows host, paths with spaces)

```powershell
# Junctions (create once):
#   mklink /J C:\Android\Sdk "<sdk>" ; mklink /J C:\JDK17 "<jdk17>"
#   mklink /J C:\CLM "D:\GitHub Project\CubicLM"
$env:FLUTTER_ROOT = "C:\src\flutter"
$env:PATH = "C:\src\flutter\bin;$env:PATH"
$env:JAVA_HOME = "C:\JDK17"
$env:ANDROID_SDK_ROOT = "C:\Android\Sdk"
```

## 1. Prep (code)

1. `flutter analyze` — 0 issues.
2. Bump `pubspec.yaml` `version: X.Y.Z+N` (semver: feat → minor, fix → patch).
3. `CHANGELOG.md` — new `## [X.Y.Z+N] - YYYY-MM-DD` section (Added/Changed/Fixed).
4. `website/index.html` — download URLs `vX.Y.Z`, size labels, new changelog
   tab (active) + detail panel; demote previous tab/panel.
5. `README.md` — badge links, download table (file names, sizes, URLs).
6. Commit everything. The release keystore (`cubiclm-release-key.jks`) and
   `android/key.properties` are gitignored — verify with
   `git check-ignore` before committing.

## 2. Sign (Android)

```powershell
# android/key.properties (NEVER commit):
#   storeFile=<abs path>/cubiclm-release-key.jks
#   storePassword=...
#   keyAlias=...
#   keyPassword=...
```

Without it, `--release` fails fast (unless
`CUBICLM_ALLOW_DEBUG_RELEASE_SIGNING=true`, which is for size measurement
only — never publish those APKs).

## 3. Build artifacts

```powershell
# Android splits (from C:\CLM):
flutter build apk --release --split-per-abi
# → build/app/outputs/flutter-apk/app-<abi>-release.apk
# Rename on upload: cubiclm-vX.Y.Z-<abi>.apk

# Windows:
flutter build windows --release
Compress-Archive -Path build/windows/x64/runner/Release/* `
  -DestinationPath cubiclm-vX.Y.Z-windows-x64.zip -Force

# Checksums (repo root):
#   certutil -hashfile <file> SHA256  (collect into checksums.sha256)
```

Fill measured sizes back into README + website labels.

## 4. Publish

```powershell
git tag vX.Y.Z; git push origin main vX.Y.Z
gh release create vX.Y.Z --title "vX.Y.Z" --notes-file CHANGELOG.md `
  cubiclm-vX.Y.Z-arm64-v8a.apk cubiclm-vX.Y.Z-armeabi-v7a.apk `
  cubiclm-vX.Y.Z-x86_64.apk cubiclm-vX.Y.Z-windows-x64.zip checksums.sha256
```

## 5. Verify

- [ ] `https://github.com/abir2afridi/CubicLM/releases/tag/vX.Y.Z` — 5 assets.
- [ ] In-app update check offers the new version (Android downloads APK).
- [ ] Website download buttons 200 (push to main redeploys Vercel).
- [ ] About → What's New opens the new CHANGELOG section.
