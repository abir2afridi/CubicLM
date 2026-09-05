# Build all three shells from one repo — per docs/multiplatfrom.md §6
# Usage:  pwsh -File scripts/build-all.ps1  (or ./scripts/build-all.sh on bash)
# Requires: Flutter 3.3+, Java 17, Android SDK, Visual Studio 2022 (for Windows)

$ErrorActionPreference = "Stop"

Write-Host "== CubicLM — build-all ==" -ForegroundColor Cyan

$env:JAVA_HOME = "C:\JDK17"
$env:Path = "$env:JAVA_HOME\bin;$env:Path"

Write-Host "`n[1/3] Android APK (debug, gplay flavor)..." -ForegroundColor Yellow
flutter build apk --debug --flavor gplay
if ($LASTEXITCODE -ne 0) { throw "Android build failed" }

Write-Host "`n[2/3] Web (static)..." -ForegroundColor Yellow
flutter build web
if ($LASTEXITCODE -ne 0) { throw "Web build failed" }

Write-Host "`n[3/3] Windows (exe)..." -ForegroundColor Yellow
flutter build windows
if ($LASTEXITCODE -ne 0) { throw "Windows build failed" }

Write-Host "`nAll builds succeeded:" -ForegroundColor Green
Write-Host "  Android:  build/app/outputs/flutter-apk/app-gplay-debug.apk"
Write-Host "  Web:      build/web"
Write-Host "  Windows:  build/windows/runner/Release/cubiclm.exe"
Write-Host "`nAbout links: edit shared/constants/platform_links.dart (see docs/PLATFORM_LINKS.md)"
