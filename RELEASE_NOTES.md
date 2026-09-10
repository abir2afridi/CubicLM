# CubicLM v1.15.1 — Release Notes

## Fixes
- **Release-build GGUF load crash**: R8/ProGuard keep rules for the llama plugin and its Kotlin callback — release APKs no longer die instantly (SIGABRT) when loading a model. This was the reported Honor crash; debug builds were unaffected, which is why it never reproduced locally.
- **CI analyze gate**: scoped ignore for a newly-deprecated Flutter API.

## Performance
- No perf changes in this release.

## Dependencies
- No dependency changes in this release.

## Breaking Changes
- None.

## Downloads
- Android (arm64-v8a, armeabi-v7a, x86_64) APKs + Windows x64 ZIP + checksums below.
