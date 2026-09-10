/// Structural validation for CubicWeb Builder projects (pure Dart).
///
/// Runs BEFORE preview so malformed AI output surfaces as actionable
/// diagnostics instead of a blank WebView. Never throws.
library;

import 'framework_runtime.dart';
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
///
/// Delegates to the per-framework adapter in `frameworks/` — each
/// framework's structural rules live in its own file so they cannot
/// interfere with each other. Framework-agnostic source-hygiene checks
/// ([checkAllSources]) stay shared here on purpose.
List<ProjectIssue> validateProject(
    ProjectKind kind, Map<String, String> files) {
  // Unknown stack is a detection-level outcome, not a framework:
  // no adapter owns it, so it keeps its dedicated blocking issue.
  if (kind == ProjectKind.unknown) {
    return const [
      ProjectIssue('unknown-stack',
          'No recognizable entry file (index.html or package.json). Add an index.html or describe the stack.'),
    ];
  }
  return runtimeFor(kind).validate(files);
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
