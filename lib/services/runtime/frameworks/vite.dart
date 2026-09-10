/// Vite adapter: React (Vite), Vue 3, Svelte and vanilla Vite projects.
///
/// Vue 3 rides this adapter on purpose — detection maps
/// `@vitejs/plugin-vue` to [ProjectKind.vite], and the flavor checks
/// below keep React/Vue/Svelte validation in this one file. Only this
/// file may change Vite validation or dev args.
library;

import '../project_detector.dart';
import '../project_validator.dart';
import 'framework.dart';

/// Vite (React/Vue/Svelte/Vanilla): `npm run dev -- --host … --port …`.
class ViteRuntime extends FrameworkRuntime {
  @override
  ProjectKind get kind => ProjectKind.vite;

  @override
  String get label => 'Vite';

  @override
  List<String> devArgs(int port) => [
        'run',
        'dev',
        '--',
        '--host',
        '127.0.0.1',
        '--port',
        '$port',
        '--strictPort',
        '--cors',
      ];

  @override
  List<ProjectIssue> validate(Map<String, String> files) {
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
        ...depNames(pkg, 'dependencies'),
        ...depNames(pkg, 'devDependencies'),
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
}
