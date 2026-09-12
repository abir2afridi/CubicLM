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
  /// List of icon names matching point indices.
  List<String>? icons;
  String
      layout; // title | bullets | image | quote | comparison | stats | timeline | summary | chart | diagram
  String imagePrompt;
  String notes;
  List<int>? imageBytes;
  String? imageUrl;
  List<int>? audioBytes;
  String? backgroundUrl;

  /// List of interactive widgets: {"type": "poll|form", "data": {...}}
  List<Map<String, dynamic>> widgets;

  String quoteAuthor;
  List<List<String>> columns;
  List<Map<String, String>> stats;

  /// Chart data: { "type": "bar|donut|line", "items": [{"label": "...", "value": "42"}] }
  Map<String, dynamic> chartData;

  /// Diagram data: Mermaid syntax string.
  String? diagram;

  /// Citations for the data in the slide.
  List<Citation> citations;

  /// Speaker notes for the presenter.
  String speakerNotes;

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
    this.icons,
    String? layout,
    String? imagePrompt,
    String? notes,
    this.imageBytes,
    this.imageUrl,
    this.backgroundUrl,
    this.audioBytes,
    List<Map<String, dynamic>>? widgets,
    this.quoteAuthor = '',
    List<List<String>>? columns,
    List<Map<String, String>>? stats,
    Map<String, dynamic>? chartData,
    this.diagram,
    List<Citation>? citations,
    this.speakerNotes = '',
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
        citations = citations ?? [],
        widgets = widgets ?? [],
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
      'chart',
      'diagram',
      'cards',
      'gallery'
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

    List<Citation> cits = [];
    if (m['citations'] is List) {
      for (final c in (m['citations'] as List)) {
        if (c is Map) cits.add(Citation.fromMap(c));
      }
    }

    return Slide(
      title: (m['title'] ?? '').toString(),
      subtitle: (m['subtitle'] ?? '').toString(),
      points: (m['points'] is List)
          ? (m['points'] as List).map((e) => e.toString()).toList()
          : [],
      icons: (m['icons'] is List)
          ? (m['icons'] as List).map((e) => e.toString()).toList()
          : null,
      layout: (m['layout'] ?? '').toString(),
      imagePrompt: (m['imagePrompt'] ?? '').toString(),
      notes: (m['notes'] ?? '').toString(),
      quoteAuthor: (m['quoteAuthor'] ?? '').toString(),
      columns: cols,
      stats: sts,
      chartData: chart,
      diagram: (m['diagram'] ?? '').toString(),
      citations: cits,
      speakerNotes: (m['speakerNotes'] ?? '').toString(),
      imageUrl: m['imageUrl']?.toString(),
      backgroundUrl: m['backgroundUrl']?.toString(),
      widgets: (m['widgets'] is List)
          ? (m['widgets'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : [],
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'subtitle': subtitle,
        'points': points,
        'icons': icons,
        'layout': layout,
        'imagePrompt': imagePrompt,
        'notes': notes,
        'quoteAuthor': quoteAuthor,
        'columns': columns,
        'stats': stats,
        'chartData': chartData,
        'diagram': diagram,
        'citations': citations.map((e) => e.toMap()).toList(),
        'speakerNotes': speakerNotes,
        'imageUrl': imageUrl,
        'backgroundUrl': backgroundUrl,
        'widgets': widgets,
      };

  bool get wantsImage => layout == 'image' || layout == 'gallery' || imagePrompt.trim().isNotEmpty || (imageUrl != null && imageUrl!.isNotEmpty);
}

class Citation {
  final String source;
  final String? url;

  Citation({required this.source, this.url});

  factory Citation.fromMap(Map m) => Citation(
        source: (m['source'] ?? '').toString(),
        url: m['url']?.toString(),
      );

  Map<String, dynamic> toMap() => {
        'source': source,
        'url': url,
      };
}

class SlideOutline {
  String title;
  String description;
  String layout;
  List<String> keyPoints;

  SlideOutline({
    required this.title,
    this.description = '',
    this.layout = 'bullets',
    List<String>? keyPoints,
  }) : keyPoints = keyPoints ?? [];

  factory SlideOutline.fromMap(Map m) => SlideOutline(
        title: (m['title'] ?? '').toString(),
        description: (m['description'] ?? '').toString(),
        layout: (m['layout'] ?? 'bullets').toString(),
        keyPoints: (m['keyPoints'] is List)
            ? (m['keyPoints'] as List).map((e) => e.toString()).toList()
            : [],
      );

  Map<String, dynamic> toMap() => {
        'title': title,
        'description': description,
        'layout': layout,
        'keyPoints': keyPoints,
      };
}

class SlideDeckTheme {
  final String name;
  final String primaryColor;
  final String secondaryColor;
  final String backgroundColor;
  final String textColor;
  final String accentColor;
  final String fontHeading;
  final String fontBody;
  final List<int>? logoBytes;

  SlideDeckTheme({
    required this.name,
    required this.primaryColor,
    required this.secondaryColor,
    required this.backgroundColor,
    required this.textColor,
    required this.accentColor,
    required this.fontHeading,
    required this.fontBody,
    this.logoBytes,
  });

  factory SlideDeckTheme.fromMap(Map m) => SlideDeckTheme(
        name: (m['name'] ?? 'Modern').toString(),
        primaryColor: (m['primaryColor'] ?? '#d97757').toString(),
        secondaryColor: (m['secondaryColor'] ?? '#4ade80').toString(),
        backgroundColor: (m['backgroundColor'] ?? '#14141c').toString(),
        textColor: (m['textColor'] ?? '#f2f0ea').toString(),
        accentColor: (m['accentColor'] ?? '#d97757').toString(),
        fontHeading: (m['fontHeading'] ?? 'Plus Jakarta Sans').toString(),
        fontBody: (m['fontBody'] ?? 'Plus Jakarta Sans').toString(),
        logoBytes: m['logoBytes'] is List ? List<int>.from(m['logoBytes'] as List) : null,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'primaryColor': primaryColor,
        'secondaryColor': secondaryColor,
        'backgroundColor': backgroundColor,
        'textColor': textColor,
        'accentColor': accentColor,
        'fontHeading': fontHeading,
        'fontBody': fontBody,
        'logoBytes': logoBytes,
      };
}

/// Curated one-click themes. Applied instantly (no AI regen) via
/// [SlideDeckController.applyThemePreset] — content untouched, only the
/// palette + fonts change. First entry is the default deck theme.
class SlideThemePresets {
  SlideThemePresets._();

  static final List<SlideDeckTheme> all = [
    SlideDeckTheme(
      name: 'Modern Terracotta',
      primaryColor: '#d97757',
      secondaryColor: '#4ade80',
      backgroundColor: '#14141c',
      textColor: '#f2f0ea',
      accentColor: '#d97757',
      fontHeading: 'Plus Jakarta Sans',
      fontBody: 'Plus Jakarta Sans',
    ),
    SlideDeckTheme(
      name: 'Forest',
      primaryColor: '#4ade80',
      secondaryColor: '#d97757',
      backgroundColor: '#0f1a14',
      textColor: '#eef5ee',
      accentColor: '#4ade80',
      fontHeading: 'Plus Jakarta Sans',
      fontBody: 'Plus Jakarta Sans',
    ),
    SlideDeckTheme(
      name: 'Ocean',
      primaryColor: '#60a5fa',
      secondaryColor: '#4ade80',
      backgroundColor: '#0e1626',
      textColor: '#eaf2fd',
      accentColor: '#60a5fa',
      fontHeading: 'Space Grotesk',
      fontBody: 'Inter',
    ),
    SlideDeckTheme(
      name: 'Royal',
      primaryColor: '#a78bfa',
      secondaryColor: '#f0abfc',
      backgroundColor: '#171226',
      textColor: '#f1ecfd',
      accentColor: '#a78bfa',
      fontHeading: 'Montserrat',
      fontBody: 'Inter',
    ),
    SlideDeckTheme(
      name: 'Midnight Gold',
      primaryColor: '#eab308',
      secondaryColor: '#f97316',
      backgroundColor: '#12100a',
      textColor: '#faf5e9',
      accentColor: '#eab308',
      fontHeading: 'Playfair Display',
      fontBody: 'Inter',
    ),
    SlideDeckTheme(
      name: 'Paper',
      primaryColor: '#c2410c',
      secondaryColor: '#0d9488',
      backgroundColor: '#faf7f2',
      textColor: '#1c1917',
      accentColor: '#c2410c',
      fontHeading: 'Lora',
      fontBody: 'Inter',
    ),
    SlideDeckTheme(
      name: 'Mint',
      primaryColor: '#059669',
      secondaryColor: '#0ea5e9',
      backgroundColor: '#f0fdf4',
      textColor: '#052e16',
      accentColor: '#059669',
      fontHeading: 'Montserrat',
      fontBody: 'Inter',
    ),
    SlideDeckTheme(
      name: 'Sunset',
      primaryColor: '#fb7185',
      secondaryColor: '#fbbf24',
      backgroundColor: '#1c0f14',
      textColor: '#fbe9e7',
      accentColor: '#fb7185',
      fontHeading: 'Space Grotesk',
      fontBody: 'Inter',
    ),
    SlideDeckTheme(
      name: 'Mono Ink',
      primaryColor: '#e5e5e5',
      secondaryColor: '#a3a3a3',
      backgroundColor: '#0a0a0a',
      textColor: '#e5e5e5',
      accentColor: '#e5e5e5',
      fontHeading: 'JetBrains Mono',
      fontBody: 'JetBrains Mono',
    ),
    SlideDeckTheme(
      name: 'Lavender',
      primaryColor: '#7c3aed',
      secondaryColor: '#db2777',
      backgroundColor: '#f5f3ff',
      textColor: '#2e1065',
      accentColor: '#7c3aed',
      fontHeading: 'Montserrat',
      fontBody: 'Inter',
    ),
  ];

  static List<String> get names => [for (final t in all) t.name];

  /// Case-insensitive lookup; falls back to the default (first) preset.
  static SlideDeckTheme byName(String name) {
    final q = name.trim().toLowerCase();
    for (final t in all) {
      if (t.name.toLowerCase() == q) return t;
    }
    return all.first;
  }
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
List<Slide> parseSlides(String raw, {SlideDeckTheme? outTheme}) {
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
      if (decoded is Map && decoded['theme'] is Map && outTheme != null) {
        // Potentially update theme if needed, but here we just note it
      }
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
List<SlideOutline> parseOutline(String raw) {
  var text = raw.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();
  final out = <SlideOutline>[];
  try {
    String? payload = extractSlidesJson(text);
    if (payload != null) {
      final decoded = jsonDecode(payload);
      final list = decoded is Map
          ? decoded['outline']
          : (decoded is List ? decoded : null);
      if (list is List) {
        for (final s in list.whereType<Map>()) {
          out.add(SlideOutline.fromMap(s));
        }
      }
    }
  } catch (_) {}
  return out;
}

String outlineSystemPrompt({required int count, required String topic}) {
  return '''You are a presentation architect. Create a $count-slide outline for a deck about: $topic.
Output EXACTLY one fenced block containing JSON and nothing else.

```slides
{
  "outline": [
    {
      "title": "Introduction to Quantum Computing",
      "description": "Hook the audience and define the scope.",
      "layout": "title",
      "keyPoints": ["What is a qubit?", "Why traditional computers fail"]
    },
    {
      "title": "Quantum Superposition",
      "description": "Explain the core concept using a coin analogy.",
      "layout": "bullets",
      "keyPoints": ["Being in two states at once", "Measurement collapses state"]
    }
  ]
}
```''';
}

String slideSystemPrompt(
    {required int count,
    required String style,
    String audience = '',
    String visualStyle = 'Professional'}) {
  final audienceHint =
      audience.isNotEmpty ? '\nTarget audience: $audience.' : '';
  return '''You are a world-class presentation designer who creates decks at the level of Gamma.app and Abacus.ai. Output EXACTLY one fenced block containing JSON and nothing else.
If the topic is non-English, generate ALL content in that language, but keep JSON keys in English.$audienceHint
Visual style for all images: $visualStyle.

```slides
{
  "theme": {
    "name": "Modern Terracotta",
    "primaryColor": "#d97757",
    "backgroundColor": "#14141c",
    "textColor": "#f2f0ea"
  },
  "slides": [
    {
      "title": "Welcome to the Future",
      "subtitle": "AI and You",
      "points": [],
      "layout": "title",
      "imagePrompt": "A futuristic city skyline at dawn with flying cars, neon lights, cyberpunk style",
      "notes": "Welcome the audience and set the stage.",
      "speakerNotes": "Start by introducing the goal of this session. Use an energetic tone."
    },
    {
      "title": "Why It Matters",
      "points": ["Automation saves 40% of manual work", "Data-driven decisions increase revenue 2.5×", "Creative AI tools reduce production time by 70%"],
      "icons": ["zap", "bar-chart", "palette"],
      "layout": "bullets",
      "imagePrompt": "A glowing brain connected to a circuit board",
      "notes": "Focus on concrete numbers — never vague claims.",
      "citations": [{"source": "Gartner 2024 AI Report", "url": "https://gartner.com/ai"}]
    },
...
```

Rules — follow ALL of these:
1. Produce EXACTLY $count slides. No more, no fewer.
2. Layouts available: title, bullets, image, quote, comparison, stats, timeline, summary, chart, diagram.
3. First slide MUST be layout "title". Last slide MUST be "summary".
4. VARY layouts — use at least 4 different types across the deck. Never repeat the same layout twice in a row.
5. Use "diagram" for logical flows, architecture, or cycles using Mermaid syntax.
6. Use "icons" for bullet points (Lucide icon names like: zap, check, star, bar-chart, users, palette).
7. EVERY content slide MUST include "imagePrompt" following the style: $visualStyle.
8. Bullet points: max 15 words each. Use SPECIFIC numbers, percentages, and real-world data.
9. "notes" is a short summary; "speakerNotes" is the actual script for the presenter.
10. Add "citations" whenever providing specific data or quotes.
11. Think like a consultant — structure ideas as Problem → Solution → Evidence → Impact.
12. Valid JSON only inside the fence. No prose outside.''';
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
      buf.writeln('<div class="bar-item" data-label="${esc(items[i]['label'] ?? '')}" data-value="${esc(items[i]['value'] ?? '')}" style="display:flex;align-items:center;gap:8px;margin-bottom:6px;">');
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
      buf.writeln('<circle class="bar-item" data-label="${esc(items[i]['label'] ?? '')}" data-value="${esc(items[i]['value'] ?? '')}" cx="$x" cy="$y" r="5" fill="#d97757"/>');
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
      buf.writeln('<div class="bar-item" data-label="${esc(items[i]['label'] ?? '')}" data-value="${esc(items[i]['value'] ?? '')}" style="flex:1;display:flex;flex-direction:column;align-items:center;justify-content:flex-end;">');
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
String deckToHtml(String topic, List<Slide> slides, {SlideDeckTheme? theme}) {
  String esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  final primary = theme?.primaryColor ?? '#d97757';
  final bg = theme?.backgroundColor ?? '#14141c';
  final fg = theme?.textColor ?? '#f2f0ea';

  String getIconSvg(String name) {
    switch (name.toLowerCase()) {
      case 'zap': return '<path d="M13 2L3 14h9l-1 8 10-12h-9l1-8z"/>';
      case 'check': return '<path d="M20 6L9 17l-5-5"/>';
      case 'star': return '<path d="m12 2 3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z"/>';
      case 'bar-chart': return '<path d="M12 20V10"/><path d="M18 20V4"/><path d="M6 20v-4"/>';
      case 'users': return '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>';
      case 'palette': return '<circle cx="13.5" cy="6.5" r=".5"/><circle cx="17.5" cy="10.5" r=".5"/><circle cx="8.5" cy="7.5" r=".5"/><circle cx="6.5" cy="12.5" r=".5"/><path d="M12 2C6.5 2 2 6.5 2 12s4.5 10 10 10c.92 0 1.7-.39 2.3-1.01l1.7-1.74a1.8 1.8 0 0 1 2.5-2.5l1.7 1.74c.6.61 1.4 1 2.3 1 5.5 0 10-4.5 10-10S17.5 2 12 2z"/>';
      default: return '<path d="m9 18 6-6-6-6"/>';
    }
  }

  String img(Slide s) {
    String style = 'view-transition-name: slide-img-${slides.indexOf(s)};';
    if (s.backgroundUrl != null && s.backgroundUrl!.isNotEmpty) {
      style += 'position:absolute;top:0;left:0;width:100%;height:100%;object-fit:cover;z-index:-1;opacity:0.4;';
    }
    if (s.imageBytes != null && s.imageBytes!.isNotEmpty) {
      final b64 = base64Encode(s.imageBytes!);
      return '<img src="data:image/jpeg;base64,$b64" class="slide-image" alt="${esc(s.imagePrompt)}" style="$style" />';
    }
    if (s.imageUrl != null && s.imageUrl!.isNotEmpty) {
      return '<img src="${s.imageUrl}" class="slide-image" alt="${esc(s.imagePrompt)}" style="$style" />';
    }
    if (s.imagePrompt.trim().isNotEmpty) {
      return '<div class="ph"><b>IMAGE</b>${esc(s.imagePrompt.trim())}</div>';
    }
    return '';
  }

  String renderAudio(Slide s) {
    if (s.audioBytes != null && s.audioBytes!.isNotEmpty) {
      final b64 = base64Encode(s.audioBytes!);
      return '<div class="audio-control"><audio controls><source src="data:audio/mp3;base64,$b64" type="audio/mp3"></audio></div>';
    }
    return '';
  }

  String renderWidgets(Slide s) {
    if (s.widgets.isEmpty) return '';
    final buf = StringBuffer('<div class="widgets-area">');
    for (final w in s.widgets) {
      final type = w['type'];
      if (type == 'poll') {
        buf.writeln('<div class="widget poll">');
        buf.writeln('<h4>${esc(w['question'] ?? 'Poll')}</h4>');
        final options = w['options'] as List?;
        if (options != null) {
          for (final opt in options) {
            buf.writeln('<button onclick="alert(\'Vote cast!\')">${esc(opt.toString())}</button>');
          }
        }
        buf.writeln('</div>');
      } else if (type == 'form') {
        buf.writeln('<div class="widget form">');
        buf.writeln('<h4>${esc(w['title'] ?? 'Contact Form')}</h4>');
        buf.writeln('<input type="text" placeholder="Your Name" />');
        buf.writeln('<input type="email" placeholder="Email" />');
        buf.writeln('<textarea placeholder="Message"></textarea>');
        buf.writeln('<button onclick="alert(\'Submitted!\')">Send</button>');
        buf.writeln('</div>');
      }
    }
    buf.writeln('</div>');
    return buf.toString();
  }

  String logoHtml = '';
  if (theme?.logoBytes != null && theme!.logoBytes!.isNotEmpty) {
    final b64 = base64Encode(theme.logoBytes!);
    logoHtml = '<img src="data:image/png;base64,$b64" class="brand-logo" alt="Logo" />';
  }

  final buf = StringBuffer('''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(topic)}</title>
<style>
:root { color-scheme: light dark; --accent: $primary; --bg: $bg; --fg: $fg; --muted: #6a675f; --heading-font: "${theme?.fontHeading ?? 'Segoe UI'}"; --body-font: "${theme?.fontBody ?? 'Segoe UI'}"; }
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: var(--body-font), system-ui, sans-serif; background: var(--bg); color: var(--fg); overflow: hidden; }
#slides-container { position: relative; width: 100vw; height: 100vh; }
.slide { position: absolute; top: 0; left: 0; width: 100%; height: 100%; display: flex; flex-direction: column; justify-content: center; padding: 8vh 8vw; opacity: 0; transform: scale(0.95); transition: opacity 0.4s ease, transform 0.4s ease; pointer-events: none; }
.slide.active { opacity: 1; transform: scale(1); pointer-events: auto; z-index: 10; }
.brand-logo { position: fixed; top: 24px; right: 24px; max-height: 40px; opacity: 0.8; z-index: 20; }
.kicker { color: var(--accent); font-weight: 800; letter-spacing: 3px; font-size: 13px; margin-bottom: 12px; }
h1 { font-family: var(--heading-font); font-size: clamp(32px, 6vw, 64px); line-height: 1.15; margin-bottom: 18px; view-transition-name: slide-title; }
h2 { font-family: var(--heading-font); font-size: clamp(24px, 4vw, 42px); margin-bottom: 24px; view-transition-name: slide-h2; }
.subtitle { font-size: clamp(20px, 3vw, 32px); color: #c9c4bb; margin-bottom: 20px; }
ul { list-style: none; display: flex; flex-direction: column; gap: 16px; font-size: clamp(16px, 2.5vw, 24px); line-height: 1.5; }
ul li { padding-left: 36px; position: relative; }
ul li::before { content: '▸'; position: absolute; left: 0; color: var(--accent); }
.icon-li { display: flex; align-items: flex-start; gap: 12px; }
.icon-li svg { width: 24px; height: 24px; fill: none; stroke: var(--accent); stroke-width: 2; stroke-linecap: round; stroke-linejoin: round; flex-shrink: 0; margin-top: 4px; }

.ph { margin-top: 22px; border: 2px dashed var(--accent); border-radius: 14px; padding: 28px; text-align: center; color: #c9c4bb; font-size: 14px; }
.ph b { display: block; color: var(--accent); margin-bottom: 6px; letter-spacing: 1px; font-size: 12px; }
.slide-image { max-width: 100%; max-height: 50vh; object-fit: contain; margin-top: 20px; border-radius: 12px; transition: transform 0.3s; }
.slide-image:hover { transform: scale(1.02); }

/* Glassmorphism */
.glass { background: rgba(255, 255, 255, 0.05); backdrop-filter: blur(10px); border: 1px solid rgba(255, 255, 255, 0.1); border-radius: 16px; padding: 24px; }

/* Cards & Gallery */
.layout-cards .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; margin-top: 20px; }
.card { @extend .glass; }
.layout-gallery .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-top: 20px; }
.gallery-item { border-radius: 12px; overflow: hidden; height: 200px; }
.gallery-item img { width: 100%; height: 100%; object-fit: cover; }

/* Chart Interactivity */
.bar-item { transition: filter 0.2s, transform 0.2s; cursor: pointer; }
.bar-item:hover { filter: brightness(1.2); transform: scaleX(1.05); }
.donut-segment { transition: stroke-width 0.2s; cursor: pointer; }
.donut-segment:hover { stroke-width: 18; }
.chart-tooltip { position: absolute; background: rgba(0,0,0,0.8); color: white; padding: 4px 8px; border-radius: 4px; font-size: 12px; display: none; pointer-events: none; z-index: 100; }

/* Audio & Widgets */
.audio-control { margin-top: 15px; }
.audio-control audio { width: 100%; height: 32px; filter: grayscale(1) invert(1); }
.widgets-area { margin-top: 20px; display: flex; flex-direction: column; gap: 15px; }
.widget { background: rgba(255,255,255,0.05); padding: 15px; border-radius: 12px; border: 1px solid rgba(255,255,255,0.1); }
.widget h4 { margin-bottom: 10px; color: var(--accent); }
.poll button { display: block; width: 100%; padding: 8px; margin-bottom: 5px; background: rgba(217,119,87,0.2); border: 1px solid var(--accent); color: white; border-radius: 6px; cursor: pointer; }
.form input, .form textarea { display: block; width: 100%; padding: 8px; margin-bottom: 8px; background: rgba(0,0,0,0.2); border: 1px solid #333; color: white; border-radius: 6px; }
.form button { background: var(--accent); color: white; border: none; padding: 10px 20px; border-radius: 6px; cursor: pointer; }

/* Sidebar Navigation */
#sidebar { position: fixed; top: 0; left: -260px; width: 260px; height: 100vh; background: rgba(20,20,28,0.95); border-right: 1px solid #333; z-index: 2000; transition: left 0.3s ease; overflow-y: auto; padding: 20px; }
#sidebar.open { left: 0; }
.nav-item { padding: 12px; border-radius: 8px; cursor: pointer; font-size: 14px; margin-bottom: 8px; transition: background 0.2s; }
.nav-item:hover { background: rgba(217,119,87,0.1); }
.nav-item.active { background: var(--accent); color: white; }
#nav-toggle { position: fixed; bottom: 20px; left: 24px; width: 40px; height: 40px; background: var(--accent); border-radius: 50%; display: flex; align-items: center; justify-content: center; cursor: pointer; z-index: 2001; box-shadow: 0 4px 12px rgba(0,0,0,0.3); }

/* Presenter Mode */
#presenter-view { position: fixed; top: 0; left: 0; width: 100vw; height: 100vh; background: #000; z-index: 1000; display: none; grid-template-columns: 2fr 1fr; grid-template-rows: 2fr 1fr; gap: 10px; padding: 10px; }
#presenter-view.active { display: grid; }
.pv-box { background: #1a1a24; border-radius: 8px; border: 1px solid #333; overflow: hidden; position: relative; }
.pv-header { background: #2a2a35; padding: 8px 12px; font-size: 12px; font-weight: bold; color: var(--accent); border-bottom: 1px solid #333; display: flex; justify-content: space-between; }
.pv-content { padding: 15px; overflow-y: auto; height: calc(100% - 35px); }
.pv-current { grid-row: 1 / 2; grid-column: 1 / 2; }
.pv-next { grid-row: 2 / 3; grid-column: 1 / 2; }
.pv-notes { grid-row: 1 / 3; grid-column: 2 / 3; font-size: 18px; line-height: 1.6; color: #eee; }
.pv-timer { font-family: monospace; font-size: 24px; color: #fff; }

.num { position: fixed; right: 24px; bottom: 20px; color: var(--muted); font-size: 14px; z-index: 100; transition: opacity 0.3s; }
.fullscreen .num { opacity: 0; }
#progress-bar { position: fixed; bottom: 0; left: 0; height: 4px; background: var(--accent); z-index: 100; transition: width 0.3s ease; }

@media print {
  body { overflow: auto; background: white; color: black; }
  #slides-container { height: auto; }
  .slide { position: relative; opacity: 1; transform: none; min-height: 95vh; page-break-after: always; padding: 40px; }
  .num, #progress-bar { display: none; }
}
</style>
</head>
<body>
<div id="progress-bar" style="width: 0%"></div>
$logoHtml
<div id="nav-toggle">☰</div>
<div id="sidebar">
  <h3 style="margin-bottom:20px;color:var(--accent);">Navigation</h3>
  <div id="nav-list"></div>
</div>
<div id="chart-tooltip" class="chart-tooltip"></div>
<div id="slides-container">
''');

  for (var i = 0; i < slides.length; i++) {
    final s = slides[i];
    buf.writeln('<section class="slide layout-${s.layout}" id="slide-$i">');
    buf.writeln('<div class="kicker">${i + 1} / ${slides.length}</div>');

    if (s.freeLayout) {
      buf.writeln(_freeSlideHtml(s));
      if (s.notes.trim().isNotEmpty) {
        buf.writeln('<div class="notes">${esc(s.notes.trim())}</div>');
      }
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
    } else if (s.layout == 'cards') {
      buf.writeln('<div class="grid">');
      for (final p in s.points) {
        buf.writeln('<div class="card">${esc(p)}</div>');
      }
      buf.writeln('</div>');
    } else if (s.layout == 'gallery') {
      buf.writeln('<div class="grid">');
      for (var j = 0; j < s.points.length; j++) {
        buf.writeln('<div class="gallery-item">${img(s)}</div>');
      }
      buf.writeln('</div>');
    } else if (s.layout == 'chart') {
      buf.writeln(_chartHtml(s));
    } else if (s.points.isNotEmpty) {
      buf.writeln('<ul>');
      for (var j = 0; j < s.points.length; j++) {
        final p = s.points[j];
        if (s.icons != null && j < s.icons!.length) {
          buf.writeln('<li class="icon-li"><svg viewBox="0 0 24 24">${getIconSvg(s.icons![j])}</svg><span>${esc(p)}</span></li>');
        } else {
          buf.writeln('<li>${esc(p)}</li>');
        }
      }
      buf.writeln('</ul>');
    }

    buf.writeln(img(s));
    buf.writeln(renderAudio(s));
    buf.writeln(renderWidgets(s));

    if (s.notes.trim().isNotEmpty) {
      buf.writeln('<div class="notes">${esc(s.notes.trim())}</div>');
    }
    buf.writeln('</section>');
  }

  // Pre-generate notes for Presenter Mode
  final notesJson = jsonEncode(slides.map((s) => s.speakerNotes.isNotEmpty ? s.speakerNotes : s.notes).toList());

  buf.writeln('''
</div>
<div class="num" id="counter">1 / ${slides.length}</div>

<div id="presenter-view">
  <div class="pv-box pv-current">
    <div class="pv-header">CURRENT SLIDE <span id="pv-num">1</span></div>
    <div class="pv-content" id="pv-current-content"></div>
  </div>
  <div class="pv-box pv-next">
    <div class="pv-header">NEXT SLIDE</div>
    <div class="pv-content" id="pv-next-content"></div>
  </div>
  <div class="pv-box pv-notes">
    <div class="pv-header">SPEAKER NOTES <span class="pv-timer" id="timer">00:00</span></div>
    <div class="pv-content" id="pv-notes-content"></div>
  </div>
</div>

<script>
  let currentSlide = 0;
  const slides = document.querySelectorAll('.slide');
  const totalSlides = slides.length;
  const progressBar = document.getElementById('progress-bar');
  const counter = document.getElementById('counter');
  const speakerNotes = $notesJson;
  const tooltip = document.getElementById('chart-tooltip');
  
  let startTime = Date.now();
  setInterval(() => {
    const elapsed = Math.floor((Date.now() - startTime) / 1000);
    const m = Math.floor(elapsed / 60).toString().padStart(2, '0');
    const s = (elapsed % 60).toString().padStart(2, '0');
    document.getElementById('timer').innerText = m + ':' + s;
  }, 1000);

  function updateUI() {
    slides.forEach((s, i) => {
      s.classList.toggle('active', i === currentSlide);
    });
    
    progressBar.style.width = ((currentSlide + 1) / totalSlides * 100) + '%';
    counter.innerText = (currentSlide + 1) + ' / ' + totalSlides;
    
    // Auto-narrate if enabled
    if (window.isNarrating) {
      speak(speakerNotes[currentSlide]);
    }

    // Update Sidebar
    document.querySelectorAll('.nav-item').forEach((it, i) => {
      it.classList.toggle('active', i === currentSlide);
    });

    // Update Presenter View
    const pv = document.getElementById('presenter-view');
    if (pv.classList.contains('active')) {
      document.getElementById('pv-num').innerText = (currentSlide + 1);
      document.getElementById('pv-current-content').innerHTML = slides[currentSlide].innerHTML;
      document.getElementById('pv-notes-content').innerText = speakerNotes[currentSlide] || "No notes for this slide.";
      
      const nextIdx = currentSlide + 1;
      if (nextIdx < totalSlides) {
        document.getElementById('pv-next-content').innerHTML = slides[nextIdx].innerHTML;
      } else {
        document.getElementById('pv-next-content').innerHTML = "<h3>End of presentation</h3>";
      }
    }
  }

  // Narration Engine
  window.isNarrating = false;
  const synth = window.speechSynthesis;
  function speak(text) {
    synth.cancel();
    if (!text) return;
    const utter = new SpeechSynthesisUtterance(text);
    utter.rate = 0.9;
    if (window.isVideoMode) {
      utter.onend = () => {
        if (currentSlide < totalSlides - 1) {
          window.videoTimer = setTimeout(() => showSlide(currentSlide + 1), 1000);
        } else {
          window.isVideoMode = false;
        }
      };
    }
    synth.speak(utter);
  }

  function autoAdvance() {
    speak(speakerNotes[currentSlide]);
  }

  // Build Navigation Sidebar
  const navList = document.getElementById('nav-list');
  slides.forEach((s, i) => {
    const title = s.querySelector('h1, h2')?.innerText || ('Slide ' + (i + 1));
    const item = document.createElement('div');
    item.className = 'nav-item';
    item.innerText = (i + 1) + '. ' + title;
    item.onclick = () => {
      showSlide(i);
      document.getElementById('sidebar').classList.remove('open');
    };
    navList.appendChild(item);
  });

  document.getElementById('nav-toggle').onclick = () => {
    document.getElementById('sidebar').classList.toggle('open');
  };

  function showSlide(index) {
    if (index < 0) index = 0;
    if (index >= totalSlides) index = totalSlides - 1;
    if (index === currentSlide) return;

    if (document.startViewTransition) {
      document.startViewTransition(() => {
        currentSlide = index;
        updateUI();
      });
    } else {
      currentSlide = index;
      updateUI();
    }
  }
  
  // Chart tooltips
  document.addEventListener('mouseover', (e) => {
    const target = e.target.closest('.bar-item, .donut-segment');
    if (target) {
      const val = target.getAttribute('data-value');
      const label = target.getAttribute('data-label');
      if (val) {
        tooltip.innerText = (label ? label + ': ' : '') + val;
        tooltip.style.display = 'block';
        tooltip.style.left = (e.pageX + 10) + 'px';
        tooltip.style.top = (e.pageY + 10) + 'px';
      }
    }
  });
  document.addEventListener('mouseout', (e) => {
    tooltip.style.display = 'none';
  });
  document.addEventListener('mousemove', (e) => {
    if (tooltip.style.display === 'block') {
      tooltip.style.left = (e.pageX + 10) + 'px';
      tooltip.style.top = (e.pageY + 10) + 'px';
    }
  });

  document.addEventListener('keydown', (e) => {
    const key = e.key.toLowerCase();
    if (key === 'arrowright' || key === ' ' || key === 'enter') {
      showSlide(currentSlide + 1);
    } else if (key === 'arrowleft' || key === 'backspace') {
      showSlide(currentSlide - 1);
    } else if (key === 'f') {
      if (!document.fullscreenElement) {
        document.documentElement.requestFullscreen().catch(() => {});
        document.body.classList.add('fullscreen');
      } else {
        document.exitFullscreen();
        document.body.classList.remove('fullscreen');
      }
    } else if (key === 'p') {
      const pv = document.getElementById('presenter-view');
      pv.classList.toggle('active');
      if (pv.classList.contains('active')) {
        showSlide(currentSlide);
      }
    } else if (key === 'n') {
      window.isNarrating = !window.isNarrating;
      if (window.isNarrating) speak(speakerNotes[currentSlide]);
      else synth.cancel();
    } else if (key === 'v') {
      // Toggle "Video Mode" - auto advance slides
      window.isVideoMode = !window.isVideoMode;
      if (window.isVideoMode) {
        window.isNarrating = true;
        autoAdvance();
      } else {
        clearTimeout(window.videoTimer);
      }
    } else if (key === 'escape') {
      if (document.fullscreenElement) document.exitFullscreen();
      document.getElementById('presenter-view').classList.remove('active');
      document.getElementById('sidebar').classList.remove('open');
    }
  });

  // Touch / swipe support
  let touchStartX = 0;
  document.addEventListener('touchstart', (e) => touchStartX = e.touches[0].clientX, { passive: true });
  document.addEventListener('touchend', (e) => {
    const dx = e.changedTouches[0].clientX - touchStartX;
    if (Math.abs(dx) > 50) {
      if (dx < 0) showSlide(currentSlide + 1);
      else showSlide(currentSlide - 1);
    }
  }, { passive: true });
  
  showSlide(0);
</script>
</body></html>''');

  return buf.toString();
}
