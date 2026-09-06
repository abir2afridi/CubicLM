/// CubicWeb Build schema, parser, prompts (pure Dart, unit-tested).
///
/// The model emits one fenced block:
/// ```files
/// {"files":[{"path":"index.html","content":"..."}]}
/// ```
/// Fallbacks: a lone ```html fence → index.html; otherwise raw text →
/// index.html. Paths are sanitized (no absolute, no `..`, caps enforced).
library;

import 'dart:convert';

/// A single project file.
class WebFile {
  String path;
  String content;

  WebFile({required this.path, required this.content});

  factory WebFile.fromMap(Map m) => WebFile(
        path: (m['path'] ?? '').toString(),
        content: (m['content'] ?? '').toString(),
      );

  Map<String, String> toMap() => {'path': path, 'content': content};
}

const int maxFiles = 30;
const int maxFileChars = 200000;
const int maxTotalChars = 5000000;

/// Clean a model-provided path. Returns '' when unusable.
String sanitizePath(String raw) {
  var p = raw.trim().replaceAll('\\', '/');
  while (p.startsWith('/')) {
    p = p.substring(1);
  }
  final parts = <String>[];
  for (final seg in p.split('/')) {
    final s = seg.trim();
    if (s.isEmpty || s == '.' || s == '..') continue;
    parts.add(s);
  }
  if (parts.isEmpty) return '';
  final joined = parts.join('/');
  if (joined.length > 160) return '';
  return joined;
}

/// Extract the fenced ```files payload (or ```json holding "files").
String? extractFilesJson(String raw) {
  final fence = RegExp(r'```(\w*)\n([\s\S]*?)```');
  for (final m in fence.allMatches(raw)) {
    final tag = (m.group(1) ?? '').toLowerCase();
    final body = (m.group(2) ?? '').trim();
    if (tag == 'files') return body;
    if ((tag == 'json' || tag.isEmpty) && body.contains('"files"')) {
      return body;
    }
  }
  final t = raw.trim();
  if (t.startsWith('{') && t.contains('"files"')) return t;
  return null;
}

/// Parse model output into files. Never throws; always ≥1 file.
List<WebFile> parseFiles(String raw) {
  final out = <WebFile>[];
  try {
    final payload = extractFilesJson(raw);
    if (payload != null) {
      final decoded = jsonDecode(payload);
      final list = decoded is Map
          ? decoded['files']
          : (decoded is List ? decoded : null);
      if (list is List) {
        var total = 0;
        for (final f in list.whereType<Map>()) {
          if (out.length >= maxFiles) break;
          final path = sanitizePath((f['path'] ?? '').toString());
          if (path.isEmpty) continue;
          var content = (f['content'] ?? '').toString();
          if (content.length > maxFileChars) {
            content = content.substring(0, maxFileChars);
          }
          if (total + content.length > maxTotalChars) break;
          total += content.length;
          out.add(WebFile(path: path, content: content));
        }
      }
      if (out.isNotEmpty) return out;
    }
  } catch (_) {}
  // Fallback: lone html fence → index.html, else raw text.
  final htmlFence =
      RegExp(r'```html\n([\s\S]*?)```', caseSensitive: false)
          .firstMatch(raw);
  if (htmlFence != null && htmlFence.group(1)!.trim().isNotEmpty) {
    return [WebFile(path: 'index.html', content: htmlFence.group(1)!.trim())];
  }
  final t = raw.trim();
  return [WebFile(path: 'index.html', content: t.isEmpty ? '' : t)];
}

/// Entry HTML for preview (root index.html preferred).
String? entryHtmlPath(List<WebFile> files) {
  for (final f in files) {
    if (f.path.toLowerCase() == 'index.html') return f.path;
  }
  for (final f in files) {
    if (f.path.toLowerCase().endsWith('.html')) return f.path;
  }
  return null;
}

/// Frameworks the builder guides (the model writes all code).
const List<String> webFrameworks = [
  'Single HTML',
  'HTML + CSS + JS',
  'React (Vite)',
  'Next.js',
  'Vue 3',
];

String _frameworkBrief(String framework) {
  switch (framework) {
    case 'HTML + CSS + JS':
      return 'multi-file site: index.html + styles.css + app.js with relative links. No build step, runs by opening index.html.';
    case 'React (Vite)':
      return 'Vite + React app: package.json (react, react-dom, vite scripts dev/build/preview), vite.config.js, index.html loading /src/main.jsx, src/main.jsx, src/App.jsx, src/index.css. npm install && npm run dev to run.';
    case 'Next.js':
      return 'Next.js App Router: package.json (next, react, react-dom, scripts dev/build/start), app/layout.jsx, app/page.jsx, app/globals.css. npm install && npm run dev to run.';
    case 'Vue 3':
      return 'Vue 3 + Vite: package.json (vue, vite, @vitejs/plugin-vue, scripts), vite.config.js, index.html loading /src/main.js, src/main.js, src/App.vue, src/style.css. npm install && npm run dev to run.';
    case 'Single HTML':
    default:
      return 'ONE self-contained index.html: all CSS in <style>, all JS in <script>, no external files except https CDN links. Runs by opening the file.';
  }
}

String webSystemPrompt({required String framework}) {
  return '''You are an expert web developer shipping complete, runnable projects. Output EXACTLY one fenced block and nothing else:

```files
{"files":[{"path":"index.html","content":"..."}]}
```

Target: $framework.
${_frameworkBrief(framework)}

Rules:
- Complete, working code — real content from the request, responsive layout. NEVER placeholders, lorem ipsum, TODO, or "... rest of code ...".
- Relative paths only; never absolute or external local files. CDN https links allowed.
- Keep every file focused; valid JSON with \\n escapes handled correctly.
- Valid JSON only inside the fence. No prose outside.''';
}

String webRegenFilePrompt({
  required String topic,
  required String framework,
  required String path,
  required String current,
  required List<String> siblings,
}) {
  return '''Regenerate ONLY the file "$path" of the "$topic" $framework project. Same JSON shape {"files":[{"path":"$path","content":"..."}]} inside one ```files fence and nothing else.

Sibling files (do not repeat them, stay compatible):
${siblings.map((s) => '- $s').join('\n')}

Current content to improve:
$current

Keep all imports/ids/classes the siblings rely on working.''';
}
