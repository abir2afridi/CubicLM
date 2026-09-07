import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/runtime/project_detector.dart';
import 'package:cubiclm/services/runtime/project_validator.dart';

const _goodVite = {
  'package.json':
      '{"name":"landing","private":true,"scripts":{"dev":"vite","build":"vite build"},"dependencies":{"react":"^18","react-dom":"^18"},"devDependencies":{"vite":"^5"}}',
  'vite.config.js': 'export default {}',
  'index.html':
      '<!doctype html><html><body><div id="root"></div><script type="module" src="/src/main.jsx"></script></body></html>',
  'src/main.jsx':
      "import React from 'react'\nimport App from './App.jsx'\nReactDOM.createRoot(document.getElementById('root')).render(<App />)",
  'src/App.jsx': 'export default function App(){ return <div><h1>Hi</h1></div> }',
  'src/index.css': 'body{}',
};

void main() {
  group('validateProject vite', () {
    test('valid vite project is clean', () {
      expect(validateProject(ProjectKind.vite, _goodVite), isEmpty);
    });

    test('missing index.html blocks', () {
      final files = Map<String, String>.from(_goodVite)
        ..remove('index.html');
      final issues = validateProject(ProjectKind.vite, files);
      expect(issues.any((i) => i.code == 'missing-entry'), isTrue);
      expect(issues.firstWhere((i) => i.code == 'missing-entry').blocksPreview,
          isTrue);
    });

    test('index.html without root div is flagged', () {
      final files = Map<String, String>.from(_goodVite)
        ..['index.html'] = '<html><body><p>no root</p></body></html>';
      final issues = validateProject(ProjectKind.vite, files);
      expect(issues.any((i) => i.code == 'entry-no-root'), isTrue);
    });

    test('main.jsx without JSX tags is flagged as corrupt', () {
      final files = Map<String, String>.from(_goodVite)
        ..['src/main.jsx'] = 'import App from App\nrender( , )';
      final issues = validateProject(ProjectKind.vite, files);
      expect(issues.any((i) => i.code == 'main-no-jsx'), isTrue);
    });

    test('bad package.json is flagged', () {
      final files = Map<String, String>.from(_goodVite)
        ..['package.json'] = '{oops';
      final issues = validateProject(ProjectKind.vite, files);
      expect(issues.any((i) => i.code == 'bad-package-json'), isTrue);
    });

    test('missing dev script is flagged', () {
      final files = Map<String, String>.from(_goodVite)
        ..['package.json'] = '{"name":"x"}';
      final issues = validateProject(ProjectKind.vite, files);
      expect(issues.any((i) => i.code == 'missing-dev-script'), isTrue);
    });
  });

  group('validateProject static/next', () {
    test('static index.html is clean', () {
      expect(
          validateProject(ProjectKind.staticSite,
              {'index.html': '<h1>hi</h1><style></style>'}),
          isEmpty);
    });

    test('empty project is unknown-blocked', () {
      final issues = validateProject(ProjectKind.unknown, {});
      expect(issues.single.code, 'unknown-stack');
    });

    test('next without page is flagged', () {
      final issues = validateProject(ProjectKind.nextjs, {
        'package.json': '{"dependencies":{"next":"14"}}',
      });
      expect(issues.any((i) => i.code == 'missing-page'), isTrue);
    });

    test('next without react deps is flagged', () {
      final issues = validateProject(ProjectKind.nextjs, {
        'package.json': '{"dependencies":{"next":"14"}}',
        'app/page.jsx': 'export default function Page(){ return <div/> }',
        'app/layout.jsx':
            'export default function L({children}){ return <html><body>{children}</body></html> }',
      });
      expect(issues.any((i) => i.code == 'missing-react-dep'), isTrue);
    });

    test('app router without layout is flagged', () {
      final issues = validateProject(ProjectKind.nextjs, {
        'package.json':
            '{"dependencies":{"next":"14","react":"18","react-dom":"18"}}',
        'app/page.jsx': 'export default function Page(){ return <div/> }',
      });
      expect(issues.any((i) => i.code == 'missing-layout'), isTrue);
    });

    test('layout without children is a non-blocking warning', () {
      final issues = validateProject(ProjectKind.nextjs, {
        'package.json':
            '{"dependencies":{"next":"14","react":"18","react-dom":"18"}}',
        'app/page.jsx': 'export default function Page(){ return <div/> }',
        'app/layout.jsx':
            'export default function L(){ return <html><body>hi</body></html> }',
      });
      final hit =
          issues.firstWhere((i) => i.code == 'layout-no-children');
      expect(hit.blocksPreview, isFalse);
    });

    test('markdown fence leak is flagged as blocking', () {
      final issues = validateProject(ProjectKind.vite, {
        ..._goodVite,
        'src/App.jsx':
            'export default function App(){ return <div/> }\n```\n',
      });
      expect(
          issues.any((i) =>
              i.code == 'markdown-fence-leak' && i.blocksPreview),
          isTrue);
    });

    test('html entity leak is flagged', () {
      final issues = validateProject(ProjectKind.vite, {
        ..._goodVite,
        'src/App.jsx':
            'export default function App(){ return &lt;div/&gt; }',
      });
      expect(issues.any((i) => i.code == 'html-entity-leak'), isTrue);
    });

    test('missing relative import is flagged', () {
      final issues = validateProject(ProjectKind.vite, {
        ..._goodVite,
        'src/App.jsx':
            "import Foo from './components/Foo.jsx'\nexport default function App(){ return <Foo/> }",
      });
      final hit = issues.firstWhere((i) => i.code == 'missing-import');
      expect(hit.path, 'src/App.jsx');
    });

    test('existing relative + bare imports are clean', () {
      expect(
          validateProject(ProjectKind.vite, _goodVite)
              .where((i) => i.code == 'missing-import'),
          isEmpty);
    });
  });
}
