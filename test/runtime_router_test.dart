import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/runtime/dev_url_parser.dart';
import 'package:cubiclm/services/runtime/preview_router.dart';
import 'package:cubiclm/services/runtime/project_detector.dart';
import 'package:cubiclm/services/runtime/project_validator.dart';

void main() {
  group('parseDevServerUrl', () {
    test('parses vite 5173 line', () {
      const out = '  ➜  Local:   http://localhost:5173/\n'
          '  ➜  Network: http://192.168.1.2:5173/';
      expect(parseDevServerUrl(out), 'http://localhost:5173/');
    });

    test('parses bumped port 5174 on 127.0.0.1', () {
      const out = 'Local: http://127.0.0.1:5174/app';
      expect(parseDevServerUrl(out), 'http://127.0.0.1:5174/app');
      expect(parseDevServerPort('http://127.0.0.1:5174/app'), 5174);
    });

    test('parses next.js local line', () {
      const out = '- Local:        http://localhost:3000';
      expect(parseDevServerUrl(out), 'http://localhost:3000');
    });

    test('returns null when server not ready yet', () {
      expect(parseDevServerUrl('vite v5.4.0 building…'), isNull);
    });
  });

  group('routePreview', () {
    test('static routes to staticServe', () {
      final d = routePreview(
          kind: ProjectKind.staticSite, issues: const [], nodeAvailable: false);
      expect(d.route, PreviewRoute.staticServe);
    });

    test('blocking issues route to blockedInvalid', () {
      final d = routePreview(
        kind: ProjectKind.vite,
        issues: const [
          ProjectIssue('missing-entry', 'no entry', path: 'index.html')
        ],
        nodeAvailable: true,
      );
      expect(d.route, PreviewRoute.blockedInvalid);
      expect(d.actions, contains('fix-issues'));
    });

    test('vite + node routes to dev pipeline with start action', () {
      final d = routePreview(
          kind: ProjectKind.vite, issues: const [], nodeAvailable: true);
      expect(d.route, PreviewRoute.devServerPipeline);
      expect(d.actions, contains('start-dev-server'));
    });

    test('vite without node offers recheck + cloud', () {
      final d = routePreview(
          kind: ProjectKind.vite, issues: const [], nodeAvailable: false);
      expect(d.route, PreviewRoute.devServerPipeline);
      expect(d.actions, containsAll(['recheck-runtime', 'use-cloud']));
    });
  });
}
