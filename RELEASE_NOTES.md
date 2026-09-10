# CubicLM v1.14.0 — Release Notes

## Features
- **Standalone Toolkit page**: Battle Arena and Slide Maker moved out of Model Hub into their own bottom-navigation tab.
- **Combined build-setup switcher**: Framework, Component Library and Design System as tabs in one sheet, with a single summary chip in the composer.

## Fixes
- **Low-RAM GGUF loads**: pool eviction below 3GB free, thread clamps, one reduced retry and a 512 ctx floor — small models now load on 4GB phones.
- **Model Hub GetX warning**: removed the empty observer left over from the Toolkit move.

## Performance
- No perf changes in this release.

## Dependencies
- No dependency changes in this release.

## Breaking Changes
- None — bottom-nav order is now Chat · Explore · Toolkit · Nodes · Settings (desktop Ctrl+1..5 updated).

## Downloads
- Android (arm64-v8a, armeabi-v7a, x86_64) APKs + Windows x64 ZIP + checksums below.
