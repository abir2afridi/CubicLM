/// Generic Node.js adapter: package.json projects with no recognized
/// framework (no Vite, no Next.js, no static entry).
///
/// Minimal validation only — unknown stacks must not be force-fit into
/// Vite or Next.js rules. Only this file may change generic-Node handling.
library;

import '../project_detector.dart';
import '../project_validator.dart';
import 'framework.dart';

/// package.json without a recognized framework: generic `npm run dev`.
class NodeRuntime extends FrameworkRuntime {
  @override
  ProjectKind get kind => ProjectKind.nodeGeneric;

  @override
  String get label => 'Node.js';

  @override
  List<String> devArgs(int port) => ['run', 'dev'];

  @override
  List<ProjectIssue> validate(Map<String, String> files) {
    if (readPackageJson(files).isEmpty) {
      return const [
        ProjectIssue('bad-package-json',
            'package.json is not valid JSON.', path: 'package.json'),
      ];
    }
    return const [];
  }
}
