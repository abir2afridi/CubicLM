import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/utils/slide_deck.dart';
import 'package:cubiclm/utils/slide_pptx.dart';

void main() {
  group('parseSlides', () {
    test('parses fenced slides JSON', () {
      const raw = '''
Here is your deck:
```slides
{"slides":[
{"title":"Intro","points":["Hello","World"],"layout":"title","imagePrompt":"","notes":""},
{"title":"Why","points":["A","B"],"layout":"image","imagePrompt":"sunrise over hills","notes":"smile"}
]}
```''';
      final slides = parseSlides(raw);
      expect(slides.length, 2);
      expect(slides[0].title, 'Intro');
      expect(slides[0].layout, 'title');
      expect(slides[1].layout, 'image');
      expect(slides[1].imagePrompt, 'sunrise over hills');
      expect(slides[1].points, ['A', 'B']);
    });

    test('skips empty slides and normalizes bad layout', () {
      const raw =
          '```slides\n{"slides":[{"title":"","points":[],"layout":"weird"},{"title":"Keep","points":["x"]}]}\n```';
      final slides = parseSlides(raw);
      expect(slides.length, 1);
      expect(slides[0].title, 'Keep');
      expect(slides[0].layout, 'bullets');
    });

    test('markdown fallback splits on rules and headings', () {
      const raw = '# Big Title\n- one\n- two\n---\n## Second\n- three\n';
      final slides = parseSlides(raw);
      expect(slides.length, 2);
      expect(slides[0].title, 'Big Title');
      expect(slides[0].points, ['one', 'two']);
      expect(slides[1].title, 'Second');
    });

    test('garbage yields a single fallback slide, never throws', () {
      final slides = parseSlides('   ');
      expect(slides.length, 1);
      expect(parseSlides('```slides\nnot json\n```').length, 1);
    });
  });

  group('renderers', () {
    final slides = [
      Slide(title: 'T', points: ['a', 'b'], imagePrompt: 'pic'),
    ];

    test('markdown contains title, points, image caption', () {
      final md = deckToMarkdown('Topic', slides);
      expect(md.contains('# Topic'), isTrue);
      expect(md.contains('- a'), isTrue);
      expect(md.contains('Image: pic'), isTrue);
    });

    test('html escapes content and marks slides', () {
      final html = deckToHtml('A<B', slides);
      expect(html.contains('A&lt;B'), isTrue);
      expect(html.contains('class="slide'), isTrue);
      expect(html.contains('class="ph"'), isTrue);
      expect(html.contains('showSlide'), isTrue);
      expect(html.contains('progress-bar'), isTrue);
    });

    test('free layout emits absolute-positioned html', () {
      final s = Slide(title: 'T', points: ['a'])
        ..freeLayout = true
        ..tDx = 0.1
        ..tDy = 0.05
        ..tS = 1.5;
      final html = deckToHtml('Topic', [s]);
      expect(html.contains('position:absolute'), isTrue);
      expect(html.contains('left:10.0%'), isTrue);
      expect(html.contains('font-size:45px'), isTrue); // 30 * 1.5
    });

    test('prompts mention count and regen shape', () {
      final sys = slideSystemPrompt(count: 5, style: 'playful');
      expect(sys.contains('5 slides'), isTrue);
      expect(sys.contains('```slides'), isTrue);
      final regen = slideRegenPrompt(topic: 'X', index: 2, current: slides[0]);
      expect(regen.contains('slide 2'), isTrue);
      expect(regen.contains('```slides'), isTrue);
    });

    test('system prompt includes audience when provided', () {
      final sys = slideSystemPrompt(
          count: 6, style: 'Professional', audience: 'investors');
      expect(sys.contains('Target audience: investors'), isTrue);
      expect(sys.contains('chart'), isTrue);
    });

    test('chart layout round-trips through fromMap/toMap', () {
      final s = Slide(
        title: 'Growth',
        layout: 'chart',
        chartData: {
          'type': 'donut',
          'items': [
            {'label': 'A', 'value': '30'},
            {'label': 'B', 'value': '70'},
          ]
        },
      );
      final map = s.toMap();
      final s2 = Slide.fromMap(map);
      expect(s2.layout, 'chart');
      expect(s2.chartData['type'], 'donut');
      expect((s2.chartData['items'] as List).length, 2);
    });

    test('supports new layouts: quote, comparison, stats, timeline, summary, chart',
        () {
      final richSlides = [
        Slide(
            title: 'Inspire',
            layout: 'quote',
            quoteAuthor: 'Einstein',
            points: ['Imagination is everything.']),
        Slide(title: 'Data', layout: 'stats', stats: [
          {'value': '99%', 'label': 'Accuracy'}
        ]),
        Slide(title: 'Compare', layout: 'comparison', columns: [
          ['Pro 1'],
          ['Con 1']
        ]),
        Slide(title: 'Steps', layout: 'timeline', points: ['Step 1', 'Step 2']),
        Slide(title: 'Wrap up', layout: 'summary', points: ['Done!']),
        Slide(title: 'Growth', layout: 'chart', chartData: {
          'type': 'bar',
          'items': [
            {'label': '2024', 'value': '12B'},
            {'label': '2025', 'value': '18B'},
          ]
        }),
      ];

      final md = deckToMarkdown('Rich Deck', richSlides);
      expect(md.contains('> Imagination is everything.'), isTrue);
      expect(md.contains('> — Einstein'), isTrue);
      expect(md.contains('**99%**: Accuracy'), isTrue);
      expect(md.contains('| Column 1 | Column 2 |'), isTrue);
      expect(md.contains('- Step 1'), isTrue);
      expect(md.contains('- Done!'), isTrue);
      expect(md.contains('**Chart (bar):**'), isTrue);
      expect(md.contains('**2024**: 12B'), isTrue);

      final html = deckToHtml('Rich Deck', richSlides);
      expect(html.contains('layout-quote'), isTrue);
      expect(html.contains('layout-stats'), isTrue);
      expect(html.contains('layout-comparison'), isTrue);
      expect(html.contains('layout-timeline'), isTrue);
      expect(html.contains('layout-summary'), isTrue);
      expect(html.contains('layout-chart'), isTrue);
    });
  });

  group('PPTX export', () {
    test('deckToPptx generates a valid zip archive with pptx structure',
        () async {
      final slides = [
        Slide(title: 'Slide 1', points: ['Point 1', 'Point 2']),
        Slide(
            title: 'Slide 2',
            layout: 'quote',
            quoteAuthor: 'Author',
            points: ['A quote']),
      ];
      final bytes = await deckToPptx('Sample Topic', slides);
      expect(bytes.isNotEmpty, isTrue);

      final archive = ZipDecoder().decodeBytes(bytes);
      final files = archive.map((f) => f.name).toSet();

      expect(files.contains('[Content_Types].xml'), isTrue);
      expect(files.contains('_rels/.rels'), isTrue);
      expect(files.contains('ppt/presentation.xml'), isTrue);
      expect(files.contains('ppt/slides/slide1.xml'), isTrue);
      expect(files.contains('ppt/slides/slide2.xml'), isTrue);
      expect(files.contains('ppt/theme/theme1.xml'), isTrue);
    });
  });
}
