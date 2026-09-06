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
  });
}
