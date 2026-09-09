/// Framework runtime adapters (§24 of the Next.js pipeline spec).
///
/// One adapter per framework instead of a Next-only (or Vite-only)
/// special case: detect → validate → dev-args live behind the same
/// interface so React/Vite keeps working untouched while Next.js (and
/// future frameworks) plug in beside it.
library;

import 'project_detector.dart';
import 'project_validator.dart';

/// Per-framework runtime behavior for the dev-server pipeline.
abstract class FrameworkRuntime {
  ProjectKind get kind;
  String get label;

  /// argv (after `npm`) that starts the dev server on [port], bound to
  /// loopback only. Never hardcode a single port — the manager picks a
  /// free one and parses the real URL from stdout.
  List<String> devArgs(int port);

  /// Extra validation beyond [validateProject], if any.
  List<ProjectIssue> validateExtra(Map<String, String> files) =>
      const [];
}

/// Plain HTML/CSS/JS — static localhost server, no dev process.
class StaticRuntime extends FrameworkRuntime {
  @override
  ProjectKind get kind => ProjectKind.staticSite;

  @override
  String get label => 'Static site';

  @override
  List<String> devArgs(int port) =>
      throw UnsupportedError('Static sites need no dev server.');
}

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
}

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
}

/// package.json without a recognized framework: generic `npm run dev`.
class NodeRuntime extends FrameworkRuntime {
  @override
  ProjectKind get kind => ProjectKind.nodeGeneric;

  @override
  String get label => 'Node.js';

  @override
  List<String> devArgs(int port) => ['run', 'dev'];
}

/// Adapter for a detected kind. Static/unknown have no dev process —
/// callers must check [projectNeedsNode] first.
FrameworkRuntime runtimeFor(ProjectKind kind) {
  switch (kind) {
    case ProjectKind.vite:
      return ViteRuntime();
    case ProjectKind.nextjs:
      return NextRuntime();
    case ProjectKind.nodeGeneric:
      return NodeRuntime();
    case ProjectKind.staticSite:
    case ProjectKind.unknown:
      return StaticRuntime();
  }
}
