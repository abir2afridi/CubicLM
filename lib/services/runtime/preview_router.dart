/// Preview routing decisions (pure Dart, unit-tested).
///
/// Decides HOW a project should be previewed — static file server,
/// dev-server pipeline, or a specific blocked state — so the UI never
/// collapses every failure into one generic message.
library;

import 'project_detector.dart';
import 'project_validator.dart';

/// How the preview layer should handle the current project.
enum PreviewRoute {
  /// Serve the project dir with the static localhost server (as today).
  staticServe,

  /// Framework project: keep the static fallback AND offer/attempt the
  /// Node dev-server pipeline. Never silently pretend static == running.
  devServerPipeline,

  /// Structural problems block any meaningful preview until fixed.
  blockedInvalid,
}

/// Decision + human-readable reason + suggested actions.
class PreviewDecision {
  final PreviewRoute route;

  /// Short status line for the preview pane, e.g. 'Vite project — needs Node'.
  final String statusLine;

  /// Action keys the UI understands: 'start-dev-server', 'recheck-runtime',
  /// 'use-cloud', 'fix-issues', 'open-terminal'.
  final List<String> actions;

  const PreviewDecision(this.route, this.statusLine,
      [this.actions = const []]);
}

/// Route a project to its preview strategy.
///
/// [nodeAvailable] comes from the runtime manager probe (never assumed).
PreviewDecision routePreview({
  required ProjectKind kind,
  required List<ProjectIssue> issues,
  required bool nodeAvailable,
}) {
  final blocking = issues.where((i) => i.blocksPreview).toList();
  if (blocking.isNotEmpty) {
    return PreviewDecision(
      PreviewRoute.blockedInvalid,
      '${blocking.length} problem${blocking.length == 1 ? '' : 's'} block preview — fix them or ask AI to fix.',
      const ['fix-issues', 'open-terminal'],
    );
  }
  switch (kind) {
    case ProjectKind.staticSite:
    case ProjectKind.unknown:
      return const PreviewDecision(
          PreviewRoute.staticServe, 'Static preview');
    case ProjectKind.vite:
    case ProjectKind.nextjs:
    case ProjectKind.nodeGeneric:
      if (nodeAvailable) {
        return const PreviewDecision(
          PreviewRoute.devServerPipeline,
          'Node available — dev server can run',
          ['start-dev-server', 'open-terminal'],
        );
      }
      return const PreviewDecision(
        PreviewRoute.devServerPipeline,
        'Framework project needs Node.js — runtime unavailable on this device',
        ['recheck-runtime', 'use-cloud', 'open-terminal'],
      );
  }
}
