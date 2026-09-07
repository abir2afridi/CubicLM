import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/runtime/project_detector.dart';

void main() {
  group('detectProject', () {
    test('empty project is unknown', () {
      expect(detectProject({}), ProjectKind.unknown);
    });

    test('single index.html is static', () {
      expect(detectProject({'index.html': '<h1>hi</h1>'}),
          ProjectKind.staticSite);
    });

    test('multi-file html/css/js is static', () {
      expect(
          detectProject({
            'index.html': '<html></html>',
            'styles.css': 'h1{}',
            'app.js': 'console.log(1)',
          }),
          ProjectKind.staticSite);
    });

    test('vite config + react deps is vite', () {
      expect(
          detectProject({
            'package.json':
                '{"dependencies":{"react":"^18","react-dom":"^18"},"devDependencies":{"vite":"^5"}}',
            'vite.config.js': 'export default {}',
            'index.html': '<div id="root"></div>',
            'src/main.jsx': 'x',
          }),
          ProjectKind.vite);
    });

    test('vite dep alone (no config file) is vite', () {
      expect(
          detectProject({
            'package.json': '{"devDependencies":{"vite":"^5"}}',
          }),
          ProjectKind.vite);
    });

    test('next dep wins over react', () {
      expect(
          detectProject({
            'package.json':
                '{"dependencies":{"next":"14","react":"18","react-dom":"18"}}',
            'app/page.jsx': 'x',
          }),
          ProjectKind.nextjs);
    });

    test('plain package.json is nodeGeneric', () {
      expect(detectProject({'package.json': '{"name":"tool"}'}),
          ProjectKind.nodeGeneric);
    });

    test('lookup is case-insensitive for App.jsx vs app.jsx', () {
      expect(lookupFile({'src/App.jsx': 'x'}, 'src/app.jsx'), 'x');
    });

    test('invalid package.json does not crash detection', () {
      expect(detectProject({'package.json': 'not json {{{'}),
          ProjectKind.nodeGeneric);
    });
  });

  group('projectNeedsNode', () {
    test('static does not need node, vite does', () {
      expect(projectNeedsNode(ProjectKind.staticSite), isFalse);
      expect(projectNeedsNode(ProjectKind.vite), isTrue);
      expect(projectNeedsNode(ProjectKind.nextjs), isTrue);
      expect(projectNeedsNode(ProjectKind.unknown), isFalse);
    });
  });
}
