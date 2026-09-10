/// Next.js adapter: App Router and Pages Router projects (JS/JSX/TS/TSX).
///
/// Owns Next.js validation end to end — per docs/web_builder_nextjs.md
/// §19 the source pipeline treats file content as opaque text, and this
/// file is the ONLY place Next-specific structural rules live, so React
/// (Vite) changes cannot corrupt Next.js handling or vice versa.
library;

import '../project_detector.dart';
import '../project_validator.dart';
import 'framework.dart';

/// Next.js: `npm run dev -- -H 127.0.0.1 -p <port>`.
class NextRuntime extends FrameworkRuntime {
  @override
  ProjectKind get kind => ProjectKind.nextjs;

  @override
  String get label => 'Next.js';

  @override
  List<String> devArgs(int port) => [
        'run',
        'dev',
        '--',
        '-H',
        '127.0.0.1',
        '-p',
        '$port',
      ];

  @override
  List<ProjectIssue> validate(Map<String, String> files) {
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
        ...depNames(pkg, 'dependencies'),
        ...depNames(pkg, 'devDependencies'),
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
}
