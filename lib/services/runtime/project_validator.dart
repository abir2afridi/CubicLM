/// Structural validation for CubicWeb Builder projects (pure Dart).
///
/// Runs BEFORE preview so malformed AI output surfaces as actionable
/// diagnostics instead of a blank WebView. Never throws.
library;

import 'project_detector.dart';

/// A single structural problem found in the generated project.
class ProjectIssue {
  /// Machine key, e.g. 'missing-entry', 'bad-package-json'.
  final String code;

  /// Human sentence for UI + AI repair prompts.
  final String message;

  /// Related file path, if any.
  final String? path;

  /// True when preview cannot meaningfully run until this is fixed.
  final bool blocksPreview;

  const ProjectIssue(this.code, this.message, {this.path, this.blocksPreview = true});
}

/// Validate [files] for [kind]. Returns issues (empty = clean).
List<ProjectIssue> validateProject(
    ProjectKind kind, Map<String, String> files) {
  switch (kind) {
    case ProjectKind.staticSite:
      return _validateStatic(files);
    case ProjectKind.vite:
      return _validateVite(files);
    case ProjectKind.nextjs:
      return _validateNext(files);
    case ProjectKind.nodeGeneric:
      return _validateNodeGeneric(files);
    case ProjectKind.unknown:
      return const [
        ProjectIssue('unknown-stack',
            'No recognizable entry file (index.html or package.json). Add an index.html or describe the stack.'),
      ];
  }
}

// ── Static ──

List<ProjectIssue> _validateStatic(Map<String, String> files) {
  final issues = <ProjectIssue>[];
  final entry = lookupFile(files, 'index.html');
  if (entry == null) {
    // Loose .html pages can still preview via direct file open.
    final hasHtml = files.keys.any(
        (k) => k.replaceAll('\\', '/').toLowerCase().endsWith('.html'));
    if (!hasHtml) {
      issues.add(const ProjectIssue('missing-entry',
          'No index.html found. The preview needs an HTML entry file.'));
    }
    return issues;
  }
  if (entry.trim().isEmpty) {
    issues.add(const ProjectIssue(
        'empty-entry', 'index.html is empty.', path: 'index.html'));
  }
  return issues;
}

// ── Vite ──

List<ProjectIssue> _validateVite(Map<String, String> files) {
  final issues = <ProjectIssue>[];

  final pkgRaw = lookupFile(files, 'package.json');
  if (pkgRaw == null) {
    issues.add(const ProjectIssue('missing-package-json',
        'Vite project has no package.json — `npm install` cannot run.'));
    return issues;
  }
  final pkg = readPackageJson(files);
  if (pkg.isEmpty) {
    issues.add(const ProjectIssue('bad-package-json',
        'package.json is not valid JSON. Fix the syntax so npm can read it.',
        path: 'package.json'));
  } else {
    final scripts = pkg['scripts'];
    final hasDev = scripts is Map && scripts['dev'] != null;
    if (!hasDev) {
      issues.add(const ProjectIssue('missing-dev-script',
          'package.json has no "dev" script — `npm run dev` cannot start.',
          path: 'package.json'));
    }
  }

  final indexHtml = lookupFile(files, 'index.html');
  if (indexHtml == null) {
    issues.add(const ProjectIssue(
        'missing-entry', 'Vite project has no index.html entry.'));
  } else {
    if (!RegExp(r'<div[^>]*id=["\x27]?root["\x27]?', caseSensitive: false)
        .hasMatch(indexHtml)) {
      issues.add(const ProjectIssue('entry-no-root',
          'index.html has no <div id="root"> mount point — React has nowhere to render.',
          path: 'index.html'));
    }
    if (!RegExp(r'<script[^>]*src=["\x27]?/src/main\.jsx?["\x27]?',
            caseSensitive: false)
        .hasMatch(indexHtml)) {
      issues.add(const ProjectIssue('entry-no-main-script',
          'index.html does not load /src/main.jsx — the app entry is never executed.',
          path: 'index.html'));
    }
  }

  final main =
      lookupFile(files, 'src/main.jsx') ?? lookupFile(files, 'src/main.js');
  if (main == null) {
    issues.add(const ProjectIssue('missing-main',
        'src/main.jsx is missing — nothing mounts the React app.'));
  } else {
    if (!main.contains('createRoot') && !main.contains('render')) {
      issues.add(const ProjectIssue('main-no-mount',
          'src/main.jsx never mounts (no createRoot/render call).',
          path: 'src/main.jsx',
          blocksPreview: false));
    }
    if (!main.contains('<')) {
      issues.add(const ProjectIssue('main-no-jsx',
          'src/main.jsx contains no JSX tags — the file may be truncated or corrupted.',
          path: 'src/main.jsx'));
    }
  }

  final app =
      lookupFile(files, 'src/app.jsx') ?? lookupFile(files, 'src/app.js');
  if (app == null) {
    issues.add(const ProjectIssue('missing-app',
        'src/App.jsx is missing — the root component does not exist.'));
  } else {
    if (app.trim().isEmpty) {
      issues.add(const ProjectIssue(
          'empty-app', 'src/App.jsx is empty.', path: 'src/App.jsx'));
    } else if (!app.contains('<') && !app.contains('return')) {
      issues.add(const ProjectIssue('app-no-component',
          'src/App.jsx has no component output — it may be truncated.',
          path: 'src/App.jsx'));
    }
  }
  return issues;
}

// ── Next.js ──

List<ProjectIssue> _validateNext(Map<String, String> files) {
  final issues = <ProjectIssue>[];
  if (lookupFile(files, 'package.json') == null) {
    issues.add(const ProjectIssue('missing-package-json',
        'Next.js project has no package.json — `npm install` cannot run.'));
    return issues;
  }
  if (readPackageJson(files).isEmpty) {
    issues.add(const ProjectIssue('bad-package-json',
        'package.json is not valid JSON.', path: 'package.json'));
  }
  final hasPage = lookupFile(files, 'app/page.jsx') != null ||
      lookupFile(files, 'app/page.tsx') != null ||
      lookupFile(files, 'pages/index.jsx') != null ||
      lookupFile(files, 'pages/index.js') != null;
  if (!hasPage) {
    issues.add(const ProjectIssue('missing-page',
        'No app/page.jsx (or pages/index) found — Next.js has no route to render.'));
  }
  return issues;
}

// ── Generic Node ──

List<ProjectIssue> _validateNodeGeneric(Map<String, String> files) {
  if (readPackageJson(files).isEmpty) {
    return const [
      ProjectIssue('bad-package-json',
          'package.json is not valid JSON.', path: 'package.json'),
    ];
  }
  return const [];
}
