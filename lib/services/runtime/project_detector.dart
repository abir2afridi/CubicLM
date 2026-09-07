/// Project-kind detection for CubicWeb Builder projects (pure Dart).
///
/// Detection is content-based, never extension-only: package.json
/// dependencies/scripts plus framework config files decide the kind.
/// `files` maps project-relative path → file content.
library;

import 'dart:convert';

/// Kinds the preview/terminal pipeline knows how to route.
enum ProjectKind {
  /// Plain HTML/CSS/JS — served directly by the static localhost server.
  staticSite,

  /// Vite project (React/Vue/Svelte/Vanilla) — needs Node + `npm run dev`.
  vite,

  /// Next.js project — needs Node + `npm run dev`.
  nextjs,

  /// Has package.json but no recognized framework — needs Node.
  nodeGeneric,

  /// Nothing recognizable (empty project, unknown stack).
  unknown,
}

/// Human label for UI status lines.
String projectKindLabel(ProjectKind kind) {
  switch (kind) {
    case ProjectKind.staticSite:
      return 'Static site';
    case ProjectKind.vite:
      return 'Vite project';
    case ProjectKind.nextjs:
      return 'Next.js';
    case ProjectKind.nodeGeneric:
      return 'Node.js project';
    case ProjectKind.unknown:
      return 'Unknown project';
  }
}

/// True when the kind needs a JS runtime (Node) instead of static serving.
bool projectNeedsNode(ProjectKind kind) =>
    kind == ProjectKind.vite ||
    kind == ProjectKind.nextjs ||
    kind == ProjectKind.nodeGeneric;

/// Lower-cased file lookup that tolerates `./` prefixes.
String? lookupFile(Map<String, String> files, String name) {
  final want = name.toLowerCase();
  for (final e in files.entries) {
    var p = e.key.replaceAll('\\', '/').toLowerCase();
    while (p.startsWith('./') || p.startsWith('/')) {
      p = p.startsWith('./') ? p.substring(2) : p.substring(1);
    }
    if (p == want) return e.value;
  }
  return null;
}

/// Best-effort package.json decode. Returns {} when missing/invalid.
Map<String, dynamic> readPackageJson(Map<String, String> files) {
  final raw = lookupFile(files, 'package.json');
  if (raw == null) return {};
  try {
    final v = jsonDecode(raw);
    if (v is Map) return Map<String, dynamic>.from(v);
  } catch (_) {}
  return {};
}

bool _hasDep(Map<String, dynamic> pkg, String name) {
  for (final section in const ['dependencies', 'devDependencies']) {
    final deps = pkg[section];
    if (deps is Map && deps.containsKey(name)) return true;
  }
  return false;
}

bool _hasAnyFile(Map<String, String> files, List<String> names) {
  for (final n in names) {
    if (lookupFile(files, n) != null) return true;
  }
  return false;
}

/// Detect the project kind from file names + package.json content.
ProjectKind detectProject(Map<String, String> files) {
  if (files.isEmpty) return ProjectKind.unknown;
  final pkg = readPackageJson(files);
  final hasPkg = lookupFile(files, 'package.json') != null;

  String scriptsText() {
    final s = pkg['scripts'];
    if (s is! Map) return '';
    return s.values.map((v) => v.toString().toLowerCase()).join(' ');
  }

  // Next.js wins over Vite when both markers exist (next depends on react).
  if (_hasDep(pkg, 'next') ||
      scriptsText().contains('next dev') ||
      scriptsText().contains('next start') ||
      _hasAnyFile(files, const [
        'next.config.js',
        'next.config.mjs',
        'next.config.ts',
        'app/layout.jsx',
        'app/layout.tsx',
        'app/page.jsx',
        'app/page.tsx',
      ])) {
    return ProjectKind.nextjs;
  }

  final scripts = scriptsText();
  final runsVite = RegExp(r'(^|\s|;)vite(\s|$)').hasMatch(scripts) ||
      scripts.contains('vite build') ||
      scripts.contains('vite dev') ||
      scripts.contains('vite preview');
  if (_hasDep(pkg, 'vite') ||
      runsVite ||
      _hasDep(pkg, '@vitejs/plugin-react') ||
      _hasDep(pkg, '@vitejs/plugin-vue') ||
      _hasDep(pkg, '@sveltejs/vite-plugin-svelte') ||
      _hasAnyFile(files, const [
        'vite.config.js',
        'vite.config.ts',
        'vite.config.mjs',
      ])) {
    return ProjectKind.vite;
  }

  if (hasPkg) return ProjectKind.nodeGeneric;

  // Static: any HTML entry, or loose css/js assets.
  if (_hasAnyFile(files, const ['index.html'])) {
    return ProjectKind.staticSite;
  }
  for (final e in files.keys) {
    final p = e.replaceAll('\\', '/').toLowerCase();
    if (p.endsWith('.html') || p.endsWith('.css') || p.endsWith('.js')) {
      return ProjectKind.staticSite;
    }
  }
  return ProjectKind.unknown;
}
