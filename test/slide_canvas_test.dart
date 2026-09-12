import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/utils/slide_deck.dart';
import 'package:cubiclm/utils/slide_palette.dart';
import 'package:cubiclm/views/slides/slide_canvas.dart';
import 'package:cubiclm/views/slides/slide_present_view.dart';

/// Shared renderer: every layout (both themes, both modes) must build
/// without throwing. Pure widget pumps — no controllers, no platform.
void main() {
  Slide base(String layout) => Slide(
        title: 'Title $layout',
        subtitle: 'Subtitle',
        points: const ['Alpha: 1', 'Beta: 2', 'Gamma: 3'],
        layout: layout,
        imagePrompt: 'a mountain',
        notes: 'note',
        quoteAuthor: 'Author',
        columns: const [
          ['a1', 'a2'],
          ['b1', 'b2']
        ],
        stats: const [
          {'value': '99%', 'label': 'done'}
        ],
        chartData: {
          'type': 'bar',
          'items': [
            {'label': 'A', 'value': '10'},
            {'label': 'B', 'value': '20'},
          ]
        },
        diagram: 'A --> B',
        speakerNotes: 'Say it slowly.',
      );

  Future<void> pumpCanvas(
    WidgetTester tester,
    Slide slide,
    SlidePalette pal, {
    bool interactive = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SlideCanvas(
            slide: slide,
            index: 0,
            pal: pal,
            interactive: interactive,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  for (final themeName in ['Modern Terracotta', 'Paper']) {
    group('SlideCanvas [$themeName]', () {
      late SlidePalette pal;
      setUpAll(() {
        pal = SlidePalette.fromTheme(
            SlideThemePresets.byName(themeName));
      });

      for (final layout in [
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
      ]) {
        testWidgets('layout $layout builds', (tester) async {
          await pumpCanvas(tester, base(layout), pal);
          // Quote layout leads with the first point, not the title.
          expect(
            find.textContaining(
                layout == 'quote' ? 'Alpha' : 'Title'),
            findsWidgets,
          );
        });
      }

      testWidgets('freeLayout builds in both modes', (tester) async {
        final s = base('bullets')..freeLayout = true;
        await pumpCanvas(tester, s, pal, interactive: true);
        await pumpCanvas(tester, s, pal, interactive: false);
      });

      testWidgets('donut + line charts build', (tester) async {
        for (final type in ['donut', 'line']) {
          final s = base('chart');
          s.chartData = {
            'type': type,
            'items': [
              {'label': 'A', 'value': '10'},
              {'label': 'B', 'value': '20'},
            ]
          };
          await pumpCanvas(tester, s, pal);
        }
      });
    });
  }

  group('SlidePresentView.stepIndex', () {
    test('clamps at both ends', () {
      expect(SlidePresentView.stepIndex(0, 5, -1), 0);
      expect(SlidePresentView.stepIndex(4, 5, 1), 4);
      expect(SlidePresentView.stepIndex(2, 5, 1), 3);
      expect(SlidePresentView.stepIndex(2, 5, -1), 1);
      expect(SlidePresentView.stepIndex(0, 0, 1), 0);
    });
  });
}
