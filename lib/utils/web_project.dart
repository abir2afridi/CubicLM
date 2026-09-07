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

/// One file mid-stream: [content] may be a prefix of the final text.
/// [complete] is true only when the closing quote was actually seen.
class PartialWebFile {
  final String path;
  final String content;
  final bool complete;

  const PartialWebFile(this.path, this.content, {this.complete = false});
}

/// Incrementally parse a streaming ```files fence into files-so-far.
///
/// Unlike [parseFiles] this NEVER falls back to raw-text-as-index.html:
/// a buffer without a ```files fence yields [] (no garbage mid-stream).
/// Closed entries come first (in order), then at most one trailing
/// partial entry whose content is JSON-unescaped on a best-effort basis
/// (a cut escape sequence at the tail is trimmed and retried).
List<PartialWebFile> parsePartialFiles(String raw) {
  final out = <PartialWebFile>[];
  final fenceAt = raw.indexOf('```files');
  if (fenceAt < 0) return out;
  var body = raw.substring(fenceAt + '```files'.length);
  // Drop a closing fence if the stream already finished it.
  final closeAt = body.lastIndexOf('```');
  if (closeAt >= 0) body = body.substring(0, closeAt);
  if (body.trim().isEmpty) return out;

  // Fast path: the whole payload already decodes.
  final trimmed = body.trim();
  if (trimmed.startsWith('{')) {
    try {
      final decoded = jsonDecode(trimmed);
      final list = decoded is Map ? decoded['files'] : null;
      if (list is List) {
        for (final f in list.whereType<Map>()) {
          if (out.length >= maxFiles) break;
          final path = sanitizePath((f['path'] ?? '').toString());
          if (path.isEmpty) continue;
          var content = (f['content'] ?? '').toString();
          if (content.length > maxFileChars) {
            content = content.substring(0, maxFileChars);
          }
          out.add(PartialWebFile(path, content, complete: true));
        }
        if (out.isNotEmpty) return out;
      }
    } catch (_) {
      // Truncated JSON — fall through to the incremental scan.
    }
  }

  // Incremental scan: closed "path","content" pairs first.
  final closedRe = RegExp(
      r'"path"\s*:\s*"((?:[^"\\]|\\.)*)"\s*,\s*"content"\s*:\s*"((?:[^"\\]|\\.)*)"');
  final closedSpans = <int>[];
  for (final m in closedRe.allMatches(body)) {
    if (out.length >= maxFiles) break;
    final path = sanitizePath(_unescapeJsonString(m.group(1) ?? ''));
    if (path.isEmpty) continue;
    var content = _unescapeJsonString(m.group(2) ?? '');
    if (content.length > maxFileChars) {
      content = content.substring(0, maxFileChars);
    }
    out.add(PartialWebFile(path, content, complete: true));
    closedSpans.add(m.start);
    closedSpans.add(m.end);
  }

  // Trailing partial entry: "path":"P","content":"<unfinished…>
  final openRe = RegExp(r'"path"\s*:\s*"((?:[^"\\]|\\.)*)"\s*,\s*"content"\s*:\s*"');
  for (final m in openRe.allMatches(body)) {
    // Skip ones already consumed as closed entries.
    var consumed = false;
    for (var i = 0; i < closedSpans.length; i += 2) {
      if (m.start >= closedSpans[i] && m.start < closedSpans[i + 1]) {
        consumed = true;
        break;
      }
    }
    if (consumed || out.length >= maxFiles) continue;
    final path = sanitizePath(_unescapeJsonString(m.group(1) ?? ''));
    if (path.isEmpty) continue;
    var tail = body.substring(m.end);
    // Cut at the next entry start so a partial never swallows siblings.
    final nextPath = RegExp(r'"path"\s*:').firstMatch(tail);
    if (nextPath != null) tail = tail.substring(0, nextPath.start);
    var content = _unescapeJsonString(tail);
    if (content.length > maxFileChars) {
      content = content.substring(0, maxFileChars);
    }
    out.add(PartialWebFile(path, content));
  }
  return out;
}

/// Best-effort JSON string unescape. A trailing cut escape (e.g. `\u12`)
/// is trimmed and retried; total failure returns the raw text.
String _unescapeJsonString(String s) {
  var candidate = s;
  for (var attempt = 0; attempt < 10; attempt++) {
    try {
      final v = jsonDecode('"$candidate"');
      if (v is String) return v;
      return s;
    } catch (_) {
      if (candidate.isEmpty) return '';
      candidate = candidate.substring(0, candidate.length - 1);
    }
  }
  return s;
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
  const esmRule =
      'BROWSER-RUNNABLE MODULES (critical): never use bare specifiers like '
      '"vue", "react" or relative paths missing ./ or ../ — browsers throw '
      '"Failed to resolve module specifier". Either import from a full '
      'https://esm.sh/... URL, or add an import map in index.html mapping '
      'bare names to esm.sh URLs.';
  const plainJsRule =
      'PLAIN JAVASCRIPT ONLY for browser-run targets: never emit .ts/.tsx '
      'files or TypeScript syntax (types, interfaces, enums) — browsers '
      'cannot execute them and fail silently.';
  switch (framework) {
    case 'HTML + CSS + JS':
      return 'multi-file site: index.html + styles.css + app.js with relative links. No build step, runs by opening index.html. '
          '$plainJsRule';
    case 'React (Vite)':
      return 'Two legal shapes, pick ONE and be consistent: (A) browser-run: '
          'single index.html + htm + esm.sh React (no JSX, no build). (B) '
          'Vite project for npm users: package.json (react, react-dom, vite, '
          'scripts dev/build), vite.config.js, index.html with '
          '<div id="root"></div> + <script type="module" src="/src/main.jsx">, '
          'src/main.jsx that createRoots and renders <App/>, src/App.jsx '
          'returning real JSX (never empty, never truncated — every tag '
          'closed). Shape B previews via the app\'s Node dev-server '
          'pipeline when a runtime is available. $esmRule';
    case 'Next.js':
      return 'Next.js App Router: package.json (next, react, react-dom, scripts dev/build/start), app/layout.jsx, app/page.jsx, app/globals.css. '
          'PLAIN JAVASCRIPT (.jsx), never TypeScript. '
          'Every file complete and syntactically valid — previews via the '
          'app\'s Node dev-server pipeline when a runtime is available. $esmRule';
    case 'Vue 3':
      return 'Two legal shapes, pick ONE: (A) browser-run: index.html with '
          'an import map {"imports":{"vue":"https://esm.sh/vue@3"}} + '
          'inline module script using Vue.createApp (no SFC, no build). '
          '(B) Vite SFC project for npm users. $esmRule $plainJsRule';
    case 'Single HTML':
    default:
      return 'ONE self-contained index.html: all CSS in <style>, all JS in <script>, no external files except https CDN links. Runs by opening the file. '
          '$plainJsRule';
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
