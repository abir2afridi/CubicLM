/// Framework runtime registry (§24 of the Next.js pipeline spec).
///
/// One adapter per framework (see `frameworks/`) instead of Next-only or
/// Vite-only special cases: detect → validate → dev-args live behind the
/// [FrameworkRuntime] interface so React/Vite keeps working untouched
/// while Next.js (and future frameworks) plug in beside it.
///
/// Public surface is unchanged: import this file for [FrameworkRuntime]
/// and [runtimeFor].
library;

import 'frameworks/framework.dart';
import 'frameworks/nextjs.dart';
import 'frameworks/node_generic.dart';
import 'frameworks/static_site.dart';
import 'frameworks/vite.dart';
import 'project_detector.dart';

export 'frameworks/framework.dart';

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
