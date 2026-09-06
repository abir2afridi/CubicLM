import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/agent_workspace.dart';

void main() {
  group('AgentWorkspaceService.sanitize', () {
    test('keeps normal relative paths', () {
      expect(AgentWorkspaceService.sanitize('src/App.jsx'),
          'src/App.jsx');
      expect(AgentWorkspaceService.sanitize('index.html'),
          'index.html');
    });

    test('strips absolute roots, dots and traversal', () {
      expect(AgentWorkspaceService.sanitize('/etc/passwd'),
          'etc/passwd');
      expect(AgentWorkspaceService.sanitize('../../a.html'), 'a.html');
      expect(
          AgentWorkspaceService.sanitize('src/./x.js'), 'src/x.js');
      expect(AgentWorkspaceService.sanitize('a\\b\\c.css'),
          'a/b/c.css');
    });

    test('rejects empty and overlong paths', () {
      expect(AgentWorkspaceService.sanitize('   '), '');
      expect(AgentWorkspaceService.sanitize('..'), '');
      expect(AgentWorkspaceService.sanitize('a' * 200), '');
    });
  });
}
