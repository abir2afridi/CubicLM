/// Slide deck schema, parser, and renderers (pure Dart, unit-tested).
///
/// The model is instructed to emit one fenced block:
/// ```slides
/// {"slides":[{"title":"...","points":["..."],"layout":"bullets",
///   "imagePrompt":"...","notes":"..."}]}
/// ```
///
/// Fallback: plain markdown split on `---` or `##` headings.
library;

import 'dart:convert';

/// One slide. [imageBytes] is filled post-generation (never from the model).
class Slide {
  String title;
  String subtitle;
  List<String> points;
  String
      layout; // title | bullets | image | quote | comparison | stats | timeline | summary | chart
  String imagePrompt;
  String notes;
  List<int>? imageBytes;

  String quoteAuthor;
  List<List<String>> columns;
  List<Map<String, String>> stats;

  /// Chart data: { "type": "bar|donut|line", "items": [{"label": "...", "value": "42"}] }
  Map<String, dynamic> chartData;

  /// Freehand layout mode: boxes move/scale freely on the canvas.
  /// Offsets are fractions of canvas size (0.05 = 5% right/down).
  bool freeLayout;
  double tDx;
  double tDy;
  double tS;
  double bDx;
  double bDy;
  double bS;
  double iDx;
  double iDy;
  double iS;

  Slide({
    required this.title,
    this.subtitle = '',
    List<String>? points,
    String? layout,
    String? imagePrompt,
    String? notes,
    this.imageBytes,
    this.quoteAuthor = '',
    List<List<String>>? columns,
    List<Map<String, String>>? stats,
    Map<String, dynamic>? chartData,
    this.freeLayout = false,
    this.tDx = 0,
    this.tDy = 0,
    this.tS = 1,
    this.bDx = 0,
    this.bDy = 0,
    this.bS = 1,
    this.iDx = 0,
    this.iDy = 0,
    this.iS = 1,
  })  : points = points ?? [],
        columns = columns ?? [],
        stats = stats ?? [],
        chartData = chartData ?? {},
        layout = _normLayout(layout),
        imagePrompt = imagePrompt ?? '',
        notes = notes ?? '';

  static String _normLayout(String? l) {
    final v = (l ?? '').trim().toLowerCase();
    const valid = {
      'title',
      'bullets',
      'image',
      'quote',
      'comparison',
      'stats',
      'timeline',
      'summary',
      'chart'
    };
    if (valid.contains(v)) return v;
    return 'bullets';
  }

  factory Slide.fromMap(Map m) {
    List<List<String>> cols = [];
    if (m['columns'] is List) {
      for (final c in (m['columns'] as List)) {
        if (c is List) cols.add(c.map((e) => e.toString()).toList());
      }
    }
    List<Map<String, String>> sts = [];
    if (m['stats'] is List) {
      for (final s in (m['stats'] as List)) {
        if (s is Map) {
          sts.add({
            'value': (s['value'] ?? '').toString(),
            'label': (s['label'] ?? '').toString(),
          });
        }
      }
    }
    Map<String, dynamic> chart = {};
    if (m['chartData'] is Map) {
      chart = Map<String, dynamic>.from(m['chartData'] as Map);
    }

    return Slide(
      title: (m['title'] ?? '').toString(),
      subtitle: (m['subtitle'] ?? '').toString(),
      points: (m['points'] is List)
          ? (m['points'] as List).map((e) => e.toString()).toList()
          : [],
      layout: (m['layout'] ?? '').toString(),
      imagePrompt: (m['imagePrompt'] ?? '').toString(),
      notes: (m['notes'] ?? '').toString(),
      quoteAuthor: (m['quoteAuthor'] ?? '').toString(),
      columns: cols,
      stats: sts,
      chartData: chart,
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'subtitle': subtitle,
        'points': points,
        'layout': layout,
        'imagePrompt': imagePrompt,
        'notes': notes,
        'quoteAuthor': quoteAuthor,
        'columns': columns,
        'stats': stats,
        'chartData': chartData,
      };

  bool get wantsImage => layout == 'image' || imagePrompt.trim().isNotEmpty;
}

/// Extract the fenced ```slides (or ```json holding "slides") payload.
String? extractSlidesJson(String raw) {
  // Strip <think> tags first
  var text = raw.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();

  final fence = RegExp(r'```(\w*)\n([\s\S]*?)```');
  for (final m in fence.allMatches(text)) {
    final tag = (m.group(1) ?? '').toLowerCase();
    final body = (m.group(2) ?? '').trim();
    if (tag == 'slides' || tag == 'json' || tag.isEmpty) {
      if (body.contains('"slides"') ||
          body.startsWith('[') ||
          body.startsWith('{')) {
        return body;
      }
    }
  }

  final t = text.trim();
  return t.isEmpty ? null : t;
}

/// Parse model output into slides. Never throws, never empty on valid-ish
/// input (falls back to one slide with the raw text).
List<Slide> parseSlides(String raw) {
  var text = raw.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();
  final out = <Slide>[];
  try {
    String? payload = extractSlidesJson(text);
    if (payload != null) {
      // Try partial JSON repair
      try {
        jsonDecode(payload);
      } catch (_) {
        if (payload.lastIndexOf('}') < payload.lastIndexOf(']')) {
          payload += ']}';
        } else {
          payload += '}]}';
        }
      }
      final decoded = jsonDecode(payload);
      final list = decoded is Map
          ? decoded['slides']
          : (decoded is List ? decoded : null);
      if (list is List) {
        for (final s in list.whereType<Map>()) {
          final slide = Slide.fromMap(s);
          if (slide.title.trim().isEmpty &&
              slide.points.isEmpty &&
              slide.imagePrompt.trim().isEmpty) {
            continue;
          }
          out.add(slide);
        }
      }
      if (out.isNotEmpty) return out;
    }
  } catch (_) {}
  // Markdown fallback
  return _parseMarkdownSlides(text);
}

List<Slide> _parseMarkdownSlides(String raw) {
  var text = raw.replaceAll(RegExp(r'```[\s\S]*?```'), '').trim();
  if (text.isEmpty) {
    return [Slide(title: 'Untitled', points: [])];
  }
  final chunks = text
      .split(RegExp(r'^\s*---+\s*$', multiLine: true))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  final slides = <Slide>[];
  for (final chunk in chunks) {
    String title = '';
    final points = <String>[];
    String layout = 'bullets';
    List<Map<String, String>> stats = [];
    String quoteAuthor = '';

    for (final line in chunk.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      if (title.isEmpty && (t.startsWith('#'))) {
        title = t.replaceAll(RegExp(r'^#+\s*'), '');
      } else if (t.startsWith('>')) {
        layout = 'quote';
        final quoteText = t.replaceFirst(RegExp(r'^>\s*'), '');
        if (quoteText.startsWith('-')) {
          quoteAuthor = quoteText.substring(1).trim();
        } else {
          points.add(quoteText);
        }
      } else if (t.startsWith(RegExp(r'^\d+[\.\)]\s+'))) {
        layout = 'stats';
        points.add(t);
      } else if (t.startsWith(RegExp(r'[-*•]\s+'))) {
        points.add(t.replaceFirst(RegExp(r'^[-*•]\s+'), ''));
      } else if (title.isEmpty) {
        title = t.length > 80 ? '${t.substring(0, 80)}…' : t;
      } else {
        points.add(t);
      }
    }
    if (title.isEmpty && points.isEmpty) continue;
    slides.add(Slide(
      title: title.isEmpty ? 'Untitled' : title,
      points: points,
      layout: layout,
      quoteAuthor: quoteAuthor,
      stats: stats,
    ));
  }
  if (slides.isEmpty) {
    return [
      Slide(title: 'Untitled', points: [text])
    ];
  }
  return slides;
}

/// System prompt for deck generation. [count] slides, [style] tone,
/// [audience] optional target audience (e.g. "investors", "students").
String slideSystemPrompt(
    {required int count, required String style, String audience = ''}) {
  final audienceHint =
      audience.isNotEmpty ? '\nTarget audience: $audience.' : '';
  return '''You are a world-class presentation designer who creates decks at the level of Gamma.app and Abacus.ai. Output EXACTLY one fenced block containing JSON and nothing else.
If the topic is non-English, generate ALL content in that language, but keep JSON keys in English.$audienceHint

```slides
{
  "slides": [
    {
      "title": "Welcome to the Future",
      "subtitle": "AI and You",
      "points": [],
      "layout": "title",
      "imagePrompt": "A futuristic city skyline at dawn with flying cars, neon lights, cyberpunk style",
      "notes": "Welcome the audience and set the stage."
    },
    {
      "title": "Why It Matters",
      "points": ["Automation saves 40% of manual work", "Data-driven decisions increase revenue 2.5×", "Creative AI tools reduce production time by 70%"],
      "layout": "bullets",
      "imagePrompt": "A glowing brain connected to a circuit board",
      "notes": "Focus on concrete numbers — never vague claims."
    },
    {
      "title": "Market Size & Growth",
      "layout": "chart",
      "chartData": {
        "type": "bar",
        "items": [
          {"label": "2024", "value": "12B"},
          {"label": "2025", "value": "18B"},
          {"label": "2026", "value": "27B"},
          {"label": "2027", "value": "40B"}
        ]
      },
      "notes": "Show the exponential growth trajectory."
    },
    {
      "title": "Revenue vs Cost",
      "layout": "comparison",
      "columns": [
        ["High upfront cost", "Maintenance needed", "6-month ramp-up"],
        ["Massive ROI (3× in year 1)", "Scales infinitely", "Payback in 4 months"]
      ],
      "notes": "Explain the tradeoff with specific timelines."
    },
    {
      "title": "Key Insight",
      "layout": "quote",
      "points": ["The best time to invest in AI was yesterday. The second best time is now."],
      "quoteAuthor": "Warren Buffett (adapted)",
      "notes": "Use this as a motivational pivot point."
    }
  ]
}
```

Rules — follow ALL of these:
1. Produce EXACTLY $count slides. No more, no fewer.
2. Layouts available: title, bullets, image, quote, comparison, stats, timeline, summary, chart.
3. First slide MUST be layout "title". Last slide MUST be "summary".
4. VARY layouts — use at least 4 different types across the deck. Never repeat the same layout twice in a row.
5. Use "quote" for key insights or inspirational moments (fill "quoteAuthor").
6. Use "comparison" when contrasting ideas (fill "columns" with exactly 2 lists).
7. Use "stats" when presenting 2-4 key numbers (fill "stats" with {"value": "...", "label": "..."}).
8. Use "chart" for data trends (fill "chartData" with {"type": "bar|donut|line", "items": [{"label": "...", "value": "42"}]}).
9. Use "timeline" for chronological or step-by-step content.
10. EVERY content slide MUST include "imagePrompt" (one vivid sentence for AI image generation).
11. Bullet points: max 15 words each. Use SPECIFIC numbers, percentages, and real-world data — never vague claims.
12. "notes" is a one-sentence speaker note for each slide.
13. Tone/style: $style.
14. Think like a consultant — structure ideas as Problem → Solution → Evidence → Impact.
15. Valid JSON only inside the fence. No prose outside. Do not output markdown outside the fence.''';
}

/// Single-slide regeneration user prompt.
String slideRegenPrompt({
  required String topic,
  required int index, // 1-based
  required Slide current,
  String? prevTitle,
  String? nextTitle,
}) {
  final cur = current.points.map((p) => '- $p').join('\n');
  final prevCtx = prevTitle != null ? 'Previous slide title: $prevTitle\n' : '';
  final nextCtx = nextTitle != null ? 'Next slide title: $nextTitle\n' : '';

  return '''Regenerate ONLY slide $index of the "$topic" deck. Keep the same JSON shape inside one ```slides fence.

$prevCtx$nextCtx
Current slide:
Title: ${current.title}
$cur
Layout: ${current.layout}
Image: ${current.imagePrompt}

Make it sharper, better formatted, and strictly follow the JSON schema.''';
}

/// Deck → Markdown (export + PDF source).
String deckToMarkdown(String topic, List<Slide> slides) {
  final buf = StringBuffer('# $topic\n\n');
  for (var i = 0; i < slides.length; i++) {
    final s = slides[i];
    buf.writeln('## ${i + 1}. ${s.title}\n');

    if (s.subtitle.isNotEmpty) {
      buf.writeln('**${s.subtitle}**\n');
    }

    if (s.layout == 'quote') {
      buf.writeln('> ${s.points.isNotEmpty ? s.points.join(" ") : s.title}');
      if (s.quoteAuthor.isNotEmpty) buf.writeln('> — ${s.quoteAuthor}');
      buf.writeln();
    } else if (s.layout == 'comparison' && s.columns.length >= 2) {
      buf.writeln('| Column 1 | Column 2 |');
      buf.writeln('|---|---|');
      int maxLen = s.columns[0].length > s.columns[1].length
          ? s.columns[0].length
          : s.columns[1].length;
      for (int j = 0; j < maxLen; j++) {
        String c1 = j < s.columns[0].length ? s.columns[0][j] : '';
        String c2 = j < s.columns[1].length ? s.columns[1][j] : '';
        buf.writeln('| $c1 | $c2 |');
      }
      buf.writeln();
    } else if (s.layout == 'stats' && s.stats.isNotEmpty) {
      for (var st in s.stats) {
        buf.writeln('- **${st['value']}**: ${st['label']}');
      }
      buf.writeln();
    } else if (s.layout == 'chart' && s.chartData.isNotEmpty) {
      final items = s.chartData['items'];
      final type = s.chartData['type'] ?? 'bar';
      buf.writeln('**Chart ($type):**');
      if (items is List) {
        for (final e in items) {
          if (e is Map) {
            buf.writeln('- **${e['label']}**: ${e['value']}');
          }
        }
      }
      buf.writeln();
    } else {
      for (final p in s.points) {
        buf.writeln('- $p');
      }
    }

    if (s.imagePrompt.trim().isNotEmpty) {
      buf.writeln('\n> Image: ${s.imagePrompt.trim()}');
    }
    if (s.notes.trim().isNotEmpty) {
      buf.writeln('\n_Notes: ${s.notes.trim()}_');
    }
    buf.writeln('\n---\n');
  }
  return buf.toString();
}

/// Chart slide → HTML with pure-CSS bar/donut/line visualization.
String _chartHtml(Slide s) {
  String esc(String v) => v
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  final data = s.chartData;
  if (data.isEmpty) return '';
  final chartType = (data['type'] ?? 'bar').toString();
  final items = <Map<String, String>>[];
  if (data['items'] is List) {
    for (final e in (data['items'] as List)) {
      if (e is Map) {
        items.add({
          'label': (e['label'] ?? '').toString(),
          'value': (e['value'] ?? '0').toString(),
        });
      }
    }
  }
  if (items.isEmpty) return '';
  final nums = items.map((e) {
    final raw = e['value']?.replaceAll(RegExp(r'[^0-9.\-]'), '') ?? '0';
    return double.tryParse(raw) ?? 0;
  }).toList();
  final maxVal = nums.isEmpty ? 1.0 : nums.reduce((a, b) => a > b ? a : b);

  final buf = StringBuffer('<div class="layout-chart">');
  if (chartType == 'donut') {
    final total = nums.isEmpty ? 1.0 : nums.fold(0.0, (a, b) => a + b);
    final colors = ['#d97757', '#4ade80', '#60a5fa', '#fbbf24', '#f87171', '#a78bfa'];
    double angle = -90;
    final gradientParts = <String>[];
    for (var i = 0; i < items.length && i < 6; i++) {
      final pct = total > 0 ? (nums[i] / total) * 100 : 0;
      final start = angle;
      angle += pct * 3.6;
      gradientParts.add('${colors[i % colors.length]} ${start.toStringAsFixed(1)}deg ${angle.toStringAsFixed(1)}deg');
    }
    buf.writeln('<div style="display:flex;align-items:center;gap:30px;">');
    buf.writeln('<div style="width:140px;height:140px;border-radius:50%;background:conic-gradient(${gradientParts.join(", ")});display:flex;align-items:center;justify-content:center;">');
    buf.writeln('<div style="width:80px;height:80px;border-radius:50%;background:#14141c;"></div>');
    buf.writeln('</div>');
    buf.writeln('<div style="flex:1;">');
    for (var i = 0; i < items.length && i < 6; i++) {
      buf.writeln('<div style="display:flex;align-items:center;gap:8px;margin-bottom:6px;">');
      buf.writeln('<div style="width:12px;height:12px;border-radius:3px;background:${colors[i % colors.length]};"></div>');
      buf.writeln('<span style="font-size:14px;">${esc(items[i]['label'] ?? '')} — <b>${esc(items[i]['value'] ?? '')}</b></span>');
      buf.writeln('</div>');
    }
    buf.writeln('</div></div>');
  } else if (chartType == 'line') {
    buf.writeln('<svg viewBox="0 0 400 200" style="width:100%;max-height:300px;" xmlns="http://www.w3.org/2000/svg">');
    final points = <String>[];
    for (var i = 0; i < nums.length && i < 8; i++) {
      final x = nums.length > 1 ? (i / (nums.length - 1)) * 380 + 10 : 200;
      final y = maxVal > 0 ? 180 - (nums[i] / maxVal) * 160 : 100;
      points.add('$x,$y');
      buf.writeln('<circle cx="$x" cy="$y" r="5" fill="#d97757"/>');
      buf.writeln('<text x="$x" y="${y - 10}" text-anchor="middle" fill="#d97757" font-size="11" font-weight="700">${esc(items[i]['value'] ?? '')}</text>');
      buf.writeln('<text x="$x" y="198" text-anchor="middle" fill="#b0ada6" font-size="10">${esc(items[i]['label'] ?? '')}</text>');
    }
    if (points.length > 1) {
      buf.writeln('<polyline points="${points.join(" ")}" fill="none" stroke="#d97757" stroke-width="2.5" stroke-linecap="round"/>');
      // Area fill
      buf.writeln('<polygon points="${points.first} ${points.join(" ")} ${points.last.split(",")[0]},200 ${points.first.split(",")[0]},200" fill="rgba(217,119,87,0.15)"/>');
    }
    buf.writeln('</svg>');
  } else {
    // Bar chart
    buf.writeln('<div style="display:flex;align-items:flex-end;gap:12px;height:220px;padding:20px 0;">');
    for (var i = 0; i < items.length && i < 8; i++) {
      final h = maxVal > 0 ? (nums[i] / maxVal) * 180 : 4;
      buf.writeln('<div style="flex:1;display:flex;flex-direction:column;align-items:center;justify-content:flex-end;">');
      buf.writeln('<span style="font-size:12px;font-weight:700;color:#d97757;margin-bottom:4px;">${esc(items[i]['value'] ?? '')}</span>');
      buf.writeln('<div style="width:100%;max-width:50px;height:${h.toStringAsFixed(0)}px;background:linear-gradient(180deg,#d97757,rgba(217,119,87,0.5));border-radius:6px 6px 0 0;"></div>');
      buf.writeln('<span style="font-size:11px;color:#b0ada6;margin-top:6px;text-align:center;">${esc(items[i]['label'] ?? '')}</span>');
      buf.writeln('</div>');
    }
    buf.writeln('</div>');
  }
  buf.writeln('</div>');
  return buf.toString();
}

/// Freehand-positioned slide → absolute-positioned HTML (percent based,
/// so it scales with the slide).
String _freeSlideHtml(Slide s) {
  String esc(String v) => v
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  String pct(double f) => '${(f * 100).toStringAsFixed(1)}%';
  final buf = StringBuffer(
      '<div style="position:relative;min-height:52vh;border:1px dashed #d97757;border-radius:10px;">');
  buf.write(
      '<div style="position:absolute;left:${pct(s.tDx)};top:${pct(s.tDy)};width:86%;'
      'font-size:${(30 * s.tS).toStringAsFixed(0)}px;font-weight:800;">'
      '${esc(s.title.isEmpty ? 'Untitled' : s.title)}</div>');
  if (s.points.isNotEmpty) {
    buf.write(
        '<div style="position:absolute;left:${pct(s.bDx)};top:${pct(s.bDy)};width:86%;'
        'font-size:${(17 * s.bS).toStringAsFixed(0)}px;"><ul>');
    for (final p in s.points) {
      buf.write('<li>${esc(p)}</li>');
    }
    buf.write('</ul></div>');
  }
  if (s.imagePrompt.trim().isNotEmpty || s.layout == 'image') {
    buf.write(
        '<div style="position:absolute;left:${pct(s.iDx)};top:${pct(s.iDy)};width:86%;'
        'border:2px dashed #d97757;border-radius:10px;padding:12px;text-align:center;'
        'font-size:${(14 * s.iS).toStringAsFixed(0)}px;">'
        '<b>IMAGE</b><br>${esc(s.imagePrompt.trim())}</div>');
  }
  buf.write('</div>');
  return buf.toString();
}

/// Deck → standalone styled HTML presentation (export + preview).
String deckToHtml(String topic, List<Slide> slides) {
  String esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  String img(Slide s) {
    if (s.imageBytes != null && s.imageBytes!.isNotEmpty) {
      final b64 = base64Encode(s.imageBytes!);
      return '<img src="data:image/jpeg;base64,$b64" class="slide-image" alt="${esc(s.imagePrompt)}" />';
    }
    if (s.imagePrompt.trim().isNotEmpty) {
      return '<div class="ph"><b>IMAGE</b>${esc(s.imagePrompt.trim())}</div>';
    }
    return '';
  }

  final buf = StringBuffer('''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(topic)}</title>
<style>
:root { color-scheme: light dark; --accent: #d97757; --bg: #14141c; --fg: #f2f0ea; --muted: #6a675f; }
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: 'Segoe UI', system-ui, sans-serif; background: var(--bg); color: var(--fg); overflow: hidden; }
#slides-container { position: relative; width: 100vw; height: 100vh; }
.slide { position: absolute; top: 0; left: 0; width: 100%; height: 100%; display: flex; flex-direction: column; justify-content: center; padding: 8vh 8vw; opacity: 0; transform: scale(0.95); transition: opacity 0.4s ease, transform 0.4s ease; pointer-events: none; }
.slide.active { opacity: 1; transform: scale(1); pointer-events: auto; z-index: 10; }
.kicker { color: var(--accent); font-weight: 800; letter-spacing: 3px; font-size: 13px; margin-bottom: 12px; }
h1 { font-size: clamp(32px, 6vw, 64px); line-height: 1.15; margin-bottom: 18px; }
h2 { font-size: clamp(24px, 4vw, 42px); margin-bottom: 24px; }
.subtitle { font-size: clamp(20px, 3vw, 32px); color: #c9c4bb; margin-bottom: 20px; }
ul { list-style: none; display: flex; flex-direction: column; gap: 16px; font-size: clamp(16px, 2.5vw, 24px); line-height: 1.5; }
ul li { padding-left: 30px; position: relative; }
ul li::before { content: '▸'; position: absolute; left: 0; color: var(--accent); }
.ph { margin-top: 22px; border: 2px dashed var(--accent); border-radius: 14px; padding: 28px; text-align: center; color: #c9c4bb; font-size: 14px; }
.ph b { display: block; color: var(--accent); margin-bottom: 6px; letter-spacing: 1px; font-size: 12px; }
.slide-image { max-width: 100%; max-height: 50vh; object-fit: contain; margin-top: 20px; border-radius: 12px; }
.notes { margin-top: 24px; font-size: 14px; font-style: italic; color: #9a958c; border-top: 1px solid #33334d; padding-top: 12px; }
.num { position: fixed; right: 24px; bottom: 20px; color: var(--muted); font-size: 14px; z-index: 100; transition: opacity 0.3s; }
.fullscreen .num { opacity: 0; }
#progress-bar { position: fixed; bottom: 0; left: 0; height: 4px; background: var(--accent); z-index: 100; transition: width 0.3s ease; }

/* Layout specific styles */
.layout-quote { text-align: center; }
.layout-quote h2 { font-size: clamp(28px, 5vw, 48px); font-style: italic; font-weight: 300; }
.quote-author { font-size: 20px; color: var(--accent); margin-top: 20px; font-weight: bold; }

.layout-comparison .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 40px; margin-top: 20px; }
.layout-comparison ul li::before { content: '•'; }

.layout-stats { display: flex; gap: 30px; justify-content: space-around; flex-wrap: wrap; margin-top: 30px; }
.stat-item { text-align: center; background: rgba(217,119,87,0.1); padding: 30px; border-radius: 16px; border: 1px solid rgba(217,119,87,0.3); flex: 1; min-width: 200px; }
.stat-value { font-size: clamp(40px, 6vw, 72px); font-weight: 800; color: var(--accent); line-height: 1; }
.stat-label { font-size: 18px; margin-top: 12px; color: #c9c4bb; }

.layout-timeline { position: relative; margin-top: 20px; padding-left: 40px; border-left: 4px solid var(--accent); }
.layout-timeline ul { gap: 30px; }
.layout-timeline ul li { padding-left: 20px; }
.layout-timeline ul li::before { content: ''; position: absolute; left: -26px; top: 8px; width: 16px; height: 16px; border-radius: 50%; background: var(--accent); border: 4px solid var(--bg); }

.layout-summary { background: linear-gradient(135deg, rgba(217,119,87,0.15) 0%, transparent 100%); border-radius: 20px; padding: 40px; }
.layout-summary ul li::before { content: '✓'; color: #4ade80; font-weight: bold; font-size: 20px; }

.layout-chart { display: flex; flex-direction: column; justify-content: center; height: 100%; }

@media print {
  body { overflow: auto; background: white; color: black; }
  #slides-container { height: auto; }
  .slide { position: relative; opacity: 1; transform: none; min-height: 95vh; page-break-after: always; padding: 40px; }
  .num, #progress-bar { display: none; }
  .layout-summary { background: #f0f0f0; }
  .stat-item { background: #f0f0f0; border-color: #ccc; }
}
</style>
</head>
<body>
<div id="progress-bar" style="width: 0%"></div>
<div id="slides-container">
''');

  for (var i = 0; i < slides.length; i++) {
    final s = slides[i];
    buf.writeln('<section class="slide layout-${s.layout}" id="slide-$i">');
    buf.writeln('<div class="kicker">${i + 1} / ${slides.length}</div>');

    if (s.freeLayout) {
      buf.writeln(_freeSlideHtml(s));
      buf.writeln('</section>');
      continue;
    }

    if (s.layout == 'title' && i == 0) {
      buf.writeln('<h1>${esc(s.title)}</h1>');
      if (s.subtitle.isNotEmpty) {
        buf.writeln('<div class="subtitle">${esc(s.subtitle)}</div>');
      }
    } else if (s.layout == 'quote') {
      buf.writeln('<h2>"${esc(s.title)}"</h2>');
      if (s.quoteAuthor.isNotEmpty) {
        buf.writeln('<div class="quote-author">— ${esc(s.quoteAuthor)}</div>');
      }
    } else {
      buf.writeln('<h2>${esc(s.title)}</h2>');
    }

    if (s.layout == 'comparison' && s.columns.length >= 2) {
      buf.writeln('<div class="grid">');
      for (var col in s.columns) {
        buf.writeln('<ul>');
        for (final item in col) {
          buf.writeln('<li>${esc(item)}</li>');
        }
        buf.writeln('</ul>');
      }
      buf.writeln('</div>');
    } else if (s.layout == 'stats' && s.stats.isNotEmpty) {
      buf.writeln('<div class="layout-stats">');
      for (var st in s.stats) {
        buf.writeln('<div class="stat-item">');
        buf.writeln('<div class="stat-value">${esc(st['value'] ?? '')}</div>');
        buf.writeln('<div class="stat-label">${esc(st['label'] ?? '')}</div>');
        buf.writeln('</div>');
      }
      buf.writeln('</div>');
    } else if (s.layout == 'timeline') {
      buf.writeln('<div class="layout-timeline"><ul>');
      for (final p in s.points) {
        buf.writeln('<li>${esc(p)}</li>');
      }
      buf.writeln('</ul></div>');
    } else if (s.layout == 'chart') {
      buf.writeln(_chartHtml(s));
    } else if (s.points.isNotEmpty) {
      buf.writeln('<ul>');
      for (final p in s.points) {
        buf.writeln('<li>${esc(p)}</li>');
      }
      buf.writeln('</ul>');
    }

    buf.writeln(img(s));

    if (s.notes.trim().isNotEmpty) {
      buf.writeln('<div class="notes">${esc(s.notes.trim())}</div>');
    }
    buf.writeln('</section>');
  }

  buf.writeln('''
</div>
<div class="num" id="counter">1 / ${slides.length}</div>

<script>
  let currentSlide = 0;
  const slides = document.querySelectorAll('.slide');
  const totalSlides = slides.length;
  const progressBar = document.getElementById('progress-bar');
  const counter = document.getElementById('counter');
  
  function showSlide(index) {
    if (index < 0) index = 0;
    if (index >= totalSlides) index = totalSlides - 1;
    currentSlide = index;
    
    slides.forEach((s, i) => {
      if (i === currentSlide) {
        s.classList.add('active');
      } else {
        s.classList.remove('active');
      }
    });
    
    progressBar.style.width = ((currentSlide + 1) / totalSlides * 100) + '%';
    counter.innerText = (currentSlide + 1) + ' / ' + totalSlides;
  }
  
  document.addEventListener('keydown', (e) => {
    if (e.key === 'ArrowRight' || e.key === 'Space' || e.key === 'Enter') {
      showSlide(currentSlide + 1);
    } else if (e.key === 'ArrowLeft' || e.key === 'Backspace') {
      showSlide(currentSlide - 1);
    } else if (e.key === 'f' || e.key === 'F') {
      if (!document.fullscreenElement) {
        document.documentElement.requestFullscreen().catch(err => {});
        document.body.classList.add('fullscreen');
      } else {
        document.exitFullscreen();
        document.body.classList.remove('fullscreen');
      }
    } else if (e.key === 'Escape') {
      if (document.fullscreenElement) {
        document.exitFullscreen();
        document.body.classList.remove('fullscreen');
      }
    }
  });
  
  document.addEventListener('fullscreenchange', () => {
    if (!document.fullscreenElement) {
      document.body.classList.remove('fullscreen');
    }
  });
  
  // Initialize
  showSlide(0);
</script>
</body></html>''');

  return buf.toString();
}
