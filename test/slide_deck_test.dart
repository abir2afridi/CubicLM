import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/utils/slide_deck.dart';

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
      expect(html.contains('<section class="slide">'), isTrue);
      expect(html.contains('class="ph"'), isTrue);
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
      expect(sys.contains('exactly 5 slides'), isTrue);
      expect(sys.contains('```slides'), isTrue);
      final regen = slideRegenPrompt(
          topic: 'X', index: 2, current: slides[0]);
      expect(regen.contains('slide 2'), isTrue);
      expect(regen.contains('```slides'), isTrue);
    });
  });
}
