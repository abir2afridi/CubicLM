/// Static-site adapter: Single HTML and HTML + CSS + JS projects.
///
/// No Node, no dev process — preview serves the directory directly.
/// Only this file may change static validation; Node-framework edits
/// must not touch it.
library;

import '../project_detector.dart';
import '../project_validator.dart';
import 'framework.dart';

/// Plain HTML/CSS/JS — static localhost server, no dev process.
class StaticRuntime extends FrameworkRuntime {
  @override
  ProjectKind get kind => ProjectKind.staticSite;

  @override
  String get label => 'Static site';

  @override
  List<String> devArgs(int port) =>
      throw UnsupportedError('Static sites need no dev server.');

  @override
  List<ProjectIssue> validate(Map<String, String> files) {
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
}
