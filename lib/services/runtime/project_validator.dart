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

// ── Shared source-hygiene checks (§26 corruption patterns) ──
//
// Pure content scans for SERIALIZATION corruption (never style lint):
// markdown fences or HTML entities leaked into code, unbalanced
// backticks (template literals losing them), dangling imports.
// The parser performs zero transforms, so any hit here means the
// model output itself was malformed — surfaced, never silently fixed.

/// Hygiene issues for one file. Exported so post-write integrity
/// verification reuses the exact same checks.
List<ProjectIssue> sourceHygieneIssues(String path, String content) {
  final issues = <ProjectIssue>[];
  final lower = path.toLowerCase();
  final isCode = lower.endsWith('.jsx') ||
      lower.endsWith('.js') ||
      lower.endsWith('.tsx') ||
      lower.endsWith('.ts') ||
      lower.endsWith('.css') ||
      lower.endsWith('.html') ||
      lower.endsWith('.json');
  if (!isCode || content.trim().isEmpty) return issues;
  if (content.contains('```')) {
    issues.add(ProjectIssue('markdown-fence-leak',
        '"$path" contains a markdown code fence — raw chat formatting leaked into source.',
        path: path));
  }
  if (content.contains('&lt;') ||
      content.contains('&gt;') ||
      content.contains('&amp;amp;')) {
    issues.add(ProjectIssue('html-entity-leak',
        '"$path" contains HTML entities (&lt;/&gt;) — angle brackets were escaped somewhere in transit.',
        path: path));
  }
  if (lower.endsWith('.jsx') ||
      lower.endsWith('.js') ||
      lower.endsWith('.tsx') ||
      lower.endsWith('.ts')) {
    var backticks = 0;
    var inStr = false;
    var strCh = '';
    for (var i = 0; i < content.length; i++) {
      final ch = content[i];
      if (inStr) {
        if (ch == strCh && content[i - 1] != '\\') inStr = false;
      } else if (ch == '"' || ch == "'") {
        inStr = true;
        strCh = ch;
      } else if (ch == '`') {
        backticks++;
      }
    }
    if (backticks.isOdd) {
      issues.add(ProjectIssue('unbalanced-backticks',
          '"$path" has an unbalanced backtick — a template literal may have lost its closing tick.',
          path: path, blocksPreview: false));
    }
  }
  return issues;
}

/// Run hygiene + import checks over every source file in the project.
List<ProjectIssue> checkAllSources(Map<String, String> files) {
  final issues = <ProjectIssue>[];
  final paths = files.keys.toSet();
  for (final e in files.entries) {
    issues.addAll(sourceHygieneIssues(e.key, e.value));
    final lower = e.key.toLowerCase();
    if (lower.endsWith('.jsx') ||
        lower.endsWith('.js') ||
        lower.endsWith('.tsx') ||
        lower.endsWith('.ts')) {
      for (final missing in missingRelativeImports(e.key, e.value, paths)) {
        issues.add(ProjectIssue('missing-import',
            '"${e.key}" imports "$missing", which does not exist in the project.',
            path: e.key));
      }
    }
  }
  return issues;
}

/// Relative imports (`./x`, `../y`) in [content] that resolve to no file
/// in [paths]. Bare package imports (react, …) are always skipped.
/// [paths] may be empty to skip the existence check (hygiene-only mode).
List<String> missingRelativeImports(
    String fromPath, String content, Set<String> paths) {
  if (paths.isEmpty) return [];
  final normPaths =
      paths.map((p) => p.replaceAll('\\', '/').toLowerCase()).toSet();
  final missing = <String>[];
  final re = RegExp(
      """(?:from\\s*['"]([^'"]+)['"]|require\\(\\s*['"]([^'"]+)['"]\\s*\\))""");
  for (final m in re.allMatches(content)) {
    final spec = m.group(1) ?? m.group(2) ?? '';
    if (!spec.startsWith('.')) continue; // bare package import
    final dir = fromPath.contains('/')
        ? fromPath.substring(0, fromPath.lastIndexOf('/'))
        : '';
    final segs = <String>[
      ...dir.split('/').where((s) => s.isNotEmpty),
      ...spec.split('/')
    ];
    final resolved = <String>[];
    for (final s in segs) {
      if (s == '.' || s.isEmpty) continue;
      if (s == '..') {
        if (resolved.isNotEmpty) resolved.removeLast();
      } else {
        resolved.add(s);
      }
    }
    var base = resolved.join('/').toLowerCase();
    // Strip query/hash fragments.
    base = base.split('?').first.split('#').first;
    const exts = ['', '.jsx', '.js', '.tsx', '.ts', '.json', '.css'];
    var found = normPaths.contains(base);
    if (!found) {
      for (final e in exts.skip(1)) {
        if (normPaths.contains('$base$e')) {
          found = true;
          break;
        }
      }
    }
    if (!found) {
      for (final idx in const ['/index.jsx', '/index.js']) {
        if (normPaths.contains('$base$idx')) {
          found = true;
          break;
        }
      }
    }
    if (!found && !missing.contains(spec)) missing.add(spec);
  }
  return missing;
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
    final deps = {
      ..._depNames(pkg, 'dependencies'),
      ..._depNames(pkg, 'devDependencies'),
    };
    final hasReact = deps.contains('react') || deps.contains('react-dom');
    final hasVue = deps.contains('vue');
    final hasSvelte = deps.contains('svelte');
    if ((deps.contains('react') || deps.contains('react-dom')) &&
        !(deps.contains('react') && deps.contains('react-dom'))) {
      issues.add(const ProjectIssue('missing-react-dep',
          'package.json lists react without react-dom (or vice versa) — both are required.',
          path: 'package.json'));
    } else if (!hasReact && !hasVue && !hasSvelte) {
      issues.add(const ProjectIssue('unknown-vite-flavor',
          'No react/vue/svelte dependency found — verify this Vite project has its UI framework installed.',
          path: 'package.json', blocksPreview: false));
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
    // NOTE: no raw size check here — tiny-but-valid apps exist, and
    // write-truncation is caught byte-for-byte by write-fidelity
    // verification after every generation instead.
  }
  issues.addAll(checkAllSources(files));
  return issues;
}

Set<String> _depNames(Map<String, dynamic> pkg, String section) {
  final deps = pkg[section];
  if (deps is! Map) return {};
  return deps.keys.map((k) => k.toString()).toSet();
}

// ── Next.js ──

List<ProjectIssue> _validateNext(Map<String, String> files) {
  final issues = <ProjectIssue>[];
  if (lookupFile(files, 'package.json') == null) {
    issues.add(const ProjectIssue('missing-package-json',
        'Next.js project has no package.json — `npm install` cannot run.'));
    return issues;
  }
  final pkg = readPackageJson(files);
  if (pkg.isEmpty) {
    issues.add(const ProjectIssue('bad-package-json',
        'package.json is not valid JSON.', path: 'package.json'));
  } else {
    final deps = {
      ..._depNames(pkg, 'dependencies'),
      ..._depNames(pkg, 'devDependencies'),
    };
    if (!deps.contains('next')) {
      issues.add(const ProjectIssue('missing-next-dep',
          'package.json has no "next" dependency — this is not an installable Next.js project.',
          path: 'package.json'));
    }
    if (!(deps.contains('react') && deps.contains('react-dom'))) {
      issues.add(const ProjectIssue('missing-react-dep',
          'package.json must list both react and react-dom for Next.js.',
          path: 'package.json'));
    }
  }
  final hasAppPage = lookupFile(files, 'app/page.jsx') != null ||
      lookupFile(files, 'app/page.js') != null ||
      lookupFile(files, 'app/page.tsx') != null ||
      lookupFile(files, 'app/page.ts') != null;
  final hasPagesIndex = lookupFile(files, 'pages/index.jsx') != null ||
      lookupFile(files, 'pages/index.js') != null ||
      lookupFile(files, 'pages/index.tsx') != null;
  if (!hasAppPage && !hasPagesIndex) {
    issues.add(const ProjectIssue('missing-page',
        'No app/page.* (or pages/index.*) found — Next.js has no route to render.'));
  }
  if (hasAppPage) {
    String? layoutPath;
    for (final c in const [
      'app/layout.jsx',
      'app/layout.js',
      'app/layout.tsx'
    ]) {
      if (lookupFile(files, c) != null) {
        layoutPath = c;
        break;
      }
    }
    if (layoutPath == null) {
      issues.add(const ProjectIssue('missing-layout',
          'App Router is used but app/layout.* is missing — every App Router app needs a root layout.'));
    } else {
      final layout = lookupFile(files, layoutPath)!;
      if (!layout.contains('{children}') &&
          !layout.contains('{ children }')) {
        issues.add(ProjectIssue('layout-no-children',
            'app/layout.* never renders {children} — all pages would be blank.',
            path: layoutPath,
            blocksPreview: false));
      }
    }
  }
  issues.addAll(checkAllSources(files));
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
