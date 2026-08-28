#!/usr/bin/env bash
# Build all three shells — per docs/multiplatfrom.md §6
set -e
echo "== CubicLM — build-all =="

export JAVA_HOME="C:\JDK17"
export PATH="$JAVA_HOME/bin:$PATH"

echo "[1/3] Android APK (debug)..."
flutter build apk --debug

echo "[2/3] Web (static)..."
flutter build web

echo "[3/3] Windows (exe)..."
flutter build windows

echo "All builds succeeded:"
echo "  Android:  build/app/outputs/flutter-apk/app-debug.apk"
echo "  Web:      build/web"
echo "  Windows:  build/windows/runner/Release/cubiclm.exe"
echo "About links: edit shared/constants/platform_links.dart (see docs/PLATFORM_LINKS.md)"
