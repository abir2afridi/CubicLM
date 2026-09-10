/// Per-framework runtime contract for the CubicWeb dev-server pipeline.
///
/// One adapter per runtime kind (see `frameworks/`): detect → validate →
/// dev-args live behind this single interface so a fix for one framework
/// (e.g. Next.js) cannot touch another framework's (e.g. Vite) code path.
/// Shared, framework-agnostic source-hygiene checks stay in
/// `project_validator.dart` on purpose — duplicating them per framework
/// would let the copies diverge and reintroduce the corruption class
/// described in docs/web_builder_nextjs.md §3 (source is opaque data).
library;

import '../project_detector.dart';
import '../project_validator.dart';

/// Per-framework runtime behavior for the dev-server pipeline.
abstract class FrameworkRuntime {
  ProjectKind get kind;
  String get label;

  /// argv (after `npm`) that starts the dev server on [port], bound to
  /// loopback only. Never hardcode a single port — the manager picks a
  /// free one and parses the real URL from stdout.
  List<String> devArgs(int port);

  /// Structural validation for this framework's project shape.
  /// Empty list = clean. Never throws.
  List<ProjectIssue> validate(Map<String, String> files);
}

/// Dependency names of one package.json section (`dependencies` /
/// `devDependencies`). Shared by the Node-based framework validators.
Set<String> depNames(Map<String, dynamic> pkg, String section) {
  final deps = pkg[section];
  if (deps is! Map) return {};
  return deps.keys.map((k) => k.toString()).toSet();
}
