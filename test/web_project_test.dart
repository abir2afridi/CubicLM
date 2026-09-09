import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/utils/web_project.dart';

void main() {
  group('parseFiles', () {
    test('parses fenced files JSON', () {
      const raw = '''
```files
{"files":[
{"path":"index.html","content":"<h1>Hi</h1>"},
{"path":"styles.css","content":"h1{color:red}"}
]}
```''';
      final files = parseFiles(raw);
      expect(files.length, 2);
      expect(files[0].path, 'index.html');
      expect(files[1].content, 'h1{color:red}');
    });

    test('sanitizes evil paths and caps counts', () {
      final many = List.generate(
          40, (i) => '{"path":"f$i.html","content":"x"}').join(',');
      final files = parseFiles('```files\n{"files":[$many]}\n```');
      expect(files.length, maxFiles);
      expect(files.any((f) => f.path.contains('..')), isFalse);
      final evil = parseFiles(
          '```files\n{"files":[{"path":"../../etc/passwd","content":"x"},{"path":"ok.html","content":"y"}]}\n```');
      expect(evil.length, 2);
      expect(evil.any((f) => f.path.contains('..')), isFalse);
      expect(evil.any((f) => f.path == 'etc/passwd'), isTrue);
    });

    test('html fence fallback becomes index.html', () {
      final files =
          parseFiles('Sure:\n```html\n<h1>Yo</h1>\n```\nDone.');
      expect(files.length, 1);
      expect(files.first.path, 'index.html');
      expect(files.first.content.contains('<h1>Yo</h1>'), isTrue);
    });

    test('garbage never throws and yields one file', () {
      expect(parseFiles('   ').length, 1);
    });

    test('entryHtmlPath prefers root index', () {
      final files = [
        WebFile(path: 'css/a.css', content: ''),
        WebFile(path: 'about.html', content: ''),
        WebFile(path: 'index.html', content: ''),
      ];
      expect(entryHtmlPath(files), 'index.html');
      expect(entryHtmlPath([files[0]]), isNull);
    });
  });

  group('prompts', () {
    test('system prompt names framework + fence', () {
      final sys = webSystemPrompt(framework: 'React (Vite)');
      expect(sys.contains('React (Vite)'), isTrue);
      expect(sys.contains('```files'), isTrue);
      expect(sys.contains('lorem ipsum'), isTrue);
    });

    test('browser-run frameworks forbid bare specifiers + TS', () {
      final vue = webSystemPrompt(framework: 'Vue 3');
      expect(vue.contains('import map'), isTrue);
      expect(vue.contains('esm.sh'), isTrue);
      final single = webSystemPrompt(framework: 'Single HTML');
      expect(single.contains('PLAIN JAVASCRIPT'), isTrue);
    });

    test('frameworkNeedsNode splits static vs node frameworks', () {
      expect(frameworkNeedsNode('Single HTML'), isFalse);
      expect(frameworkNeedsNode('HTML + CSS + JS'), isFalse);
      expect(frameworkNeedsNode('React (Vite)'), isTrue);
      expect(frameworkNeedsNode('Next.js'), isTrue);
      expect(frameworkNeedsNode('Vue 3'), isTrue);
      expect(frameworkNeedsNode('Nuxt'), isTrue);
    });
  });

  group('parsePartialFiles', () {
    test('no fence yields nothing (never raw-text garbage)', () {
      expect(parsePartialFiles('hello world'), isEmpty);
      expect(parsePartialFiles('```html\n<h1>Hi</h1>\n```'), isEmpty);
      expect(parsePartialFiles(''), isEmpty);
    });

    test('closed entries parse with complete=true', () {
      const raw = '```files\n{"files":[{"path":"index.html","content":"<h1>Hi</h1>"},{"path":"a.css","content":"h1{color:red}"}]}';
      final out = parsePartialFiles(raw);
      expect(out.length, 2);
      expect(out[0].path, 'index.html');
      expect(out[0].content, '<h1>Hi</h1>');
      expect(out[0].complete, isTrue);
    });

    test('truncated content yields one partial entry', () {
      const raw = '```files\n{"files":[{"path":"index.html","content":"<h1>Hi<';
      final out = parsePartialFiles(raw);
      expect(out.length, 1);
      expect(out[0].path, 'index.html');
      expect(out[0].content, '<h1>Hi<');
      expect(out[0].complete, isFalse);
    });

    test('complete file plus trailing partial sibling', () {
      const raw = '```files\n{"files":[{"path":"a.html","content":"<b>x</b>"},{"path":"b.css","content":"h1{color:';
      final out = parsePartialFiles(raw);
      expect(out.length, 2);
      expect(out[0].complete, isTrue);
      expect(out[1].path, 'b.css');
      expect(out[1].content, 'h1{color:');
      expect(out[1].complete, isFalse);
    });

    test('escaped sequences unescape progressively', () {
      const raw = '```files\n{"files":[{"path":"a.html","content":"<p>line1\\nline2';
      final out = parsePartialFiles(raw);
      expect(out.single.content, '<p>line1\nline2');
    });

    test('cut escape at tail is trimmed, not fatal', () {
      const raw = '```files\n{"files":[{"path":"a.html","content":"abc\\u12';
      final out = parsePartialFiles(raw);
      expect(out.single.path, 'a.html');
      expect(out.single.content, 'abc');
    });
  });

  // §26 corruption patterns: the parser performs ZERO transforms, so a
  // realistic Next.js payload must survive byte-for-byte.
  group('parseFiles preserves source exactly', () {
    String roundTrip(String path, String content) {
      final payload = jsonEncode({
        'files': [
          {'path': path, 'content': content}
        ]
      });
      final out = parseFiles('```files\n$payload\n```');
      expect(out.length, 1);
      expect(out.single.path, path);
      return out.single.content;
    }

    test('layout with {children} stays intact', () {
      const src = "import './globals.css';\n\nexport default function RootLayout({ children }) {\n  return (\n    <html lang=\"en\">\n      <body>{children}</body>\n    </html>\n  );\n}\n";
      expect(roundTrip('app/layout.jsx', src), src);
    });

    test('fragments, components and anchors survive', () {
      const src = "export default function Page() {\n  return (\n    <>\n      <Navigation />\n      <Hero />\n      <a href=\"#contact\">Get In Touch</a>\n    </>\n  );\n}\n";
      expect(roundTrip('app/page.jsx', src), src);
    });

    test('template literals keep backticks and \${}', () {
      const src = "const id = `g-\${a.slice(1)}-\${b.slice(1)}`;\nconst q = \"it's \" + 'a \"test\"';\n";
      expect(roundTrip('app/components/X.jsx', src), src);
    });

    test('client directives, hooks and imports survive', () {
      const src = "'use client';\n\nimport { useEffect, useState } from 'react';\nimport Navigation from './components/Navigation';\n\nexport default function Navigation() {\n  const [open, setOpen] = useState(false);\n  useEffect(() => {\n    const onScroll = () => setScrolled(window.scrollY > 20);\n    window.addEventListener('scroll', onScroll);\n    return () => window.removeEventListener('scroll', onScroll);\n  }, []);\n  return null;\n}\n";
      expect(roundTrip('app/components/Navigation.jsx', src), src);
    });

    test('css braces, vars and media queries survive', () {
      const src = ":root {\n  --bg: #0a0a0f;\n}\n@media (max-width: 768px) {\n  .nav-links {\n    transform: translateX(100%);\n  }\n}\n";
      expect(roundTrip('app/globals.css', src), src);
    });
  });

  group('parseFiles truncation callback (§13)', () {
    test('oversize file is cut and reported', () {
      final big = 'x' * (maxFileChars + 100);
      final payload = jsonEncode({
        'files': [
          {'path': 'big.js', 'content': big},
        ]
      });
      final cut = <String>[];
      final out = parseFiles('```files\n$payload\n```',
          onTruncated: cut.add);
      expect(out.single.content.length, maxFileChars);
      expect(cut, ['big.js']);
    });

    test('nothing reported when everything fits', () {
      final cut = <String>[];
      final out = parseFiles(
          '```files\n${jsonEncode({
                'files': [
                  {'path': 'a.js', 'content': 'hi'}
                ]
              })}\n```',
          onTruncated: cut.add);
      expect(out.length, 1);
      expect(cut, isEmpty);
    });
  });

  group('parsePartialFiles streaming (§9)', () {
    test('incremental chunks converge to the final parse', () {
      const src =
          "export default function Page() {\n  const id = `g-\${a}`;\n  return <><a href=\"#c\">x</a></>;\n}\n";
      final payload =
          '```files\n${jsonEncode({
                'files': [
                  {'path': 'app/page.jsx', 'content': src}
                ]
              })}\n```';
      List<PartialWebFile> last = const [];
      for (var i = 10; i <= payload.length; i += 37) {
        last = parsePartialFiles(payload.substring(0, i));
      }
      final complete =
          last.where((f) => f.complete).toList();
      expect(complete.length, 1);
      expect(complete.single.content, src);
      // Final closed buffer matches one-shot parseFiles exactly.
      final once = parseFiles(payload);
      expect(once.single.content, complete.single.content);
    });
  });
}
