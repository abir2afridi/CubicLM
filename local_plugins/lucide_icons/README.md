# Vendored `lucide_icons` 0.257.0

Upstream (`pub.dev/packages/lucide_icons`) is frozen at 0.257.0 and its
`LucideIconData extends IconData` no longer compiles on newer Flutter,
where `IconData` is a `final` class (CI builds on latest stable).

Fix applied here (mechanical, zero icon changes):
- All 1191 `const LucideIconData(0x…)` constants rewritten as plain
  `const IconData(0x…, fontFamily: 'Lucide', fontPackage: 'lucide_icons')`,
  which compiles on every Flutter SDK (old and new).
- `src/icon_data.dart` (the subclass) removed.
- Package name kept as `lucide_icons` so `fontPackage` resolution and
  all existing `import 'package:lucide_icons/lucide_icons.dart'` lines
  keep working untouched.

Wired via `dependency_overrides` in the root `pubspec.yaml`
(same pattern as the other vendored plugins in `local_plugins/`).
Original LICENSE preserved in this folder.
