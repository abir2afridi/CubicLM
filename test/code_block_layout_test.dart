import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cubiclm/widgets/code_block.dart';

/// Regression tests for the layout cascade observed on 2026-08-22 20:47:58.
///
/// `CodeBlockBuilder` renders the code body inside a horizontally scrolling
/// `SingleChildScrollView`, which passes `maxWidth: infinity` to its child. An
/// `Expanded`/`Flexible` inside a `Row` cannot divide infinite space, so the
/// `RenderFlex` bails out of `performLayout` and stays `NEEDS-LAYOUT`. The
/// unlaid-out box then trips `hasSize` (box.dart:2251) for every ancestor up
/// the tree, fails to paint, and finally fails hit testing on tap.
void main() {
  testWidgets('multi-line code block lays out inside the horizontal scroller',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => SingleChildScrollView(
              child: MarkdownBody(
                data: '```dart\n'
                    'void main() {\n'
                    "  final greeting = 'hello';\n"
                    '  print(greeting);\n'
                    '}\n'
                    '```',
                builders: {
                  'code': CodeBlockBuilder(context),
                  'pre': CodeBlockBuilder(context),
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // Every Row rendered by the code block must have a real size. An
    // unbounded-flex failure leaves these NEEDS-LAYOUT with size MISSING.
    final rows = tester.renderObjectList<RenderBox>(find.byType(Row));
    expect(rows, isNotEmpty);
    for (final row in rows) {
      expect(row.hasSize, isTrue,
          reason: 'RenderFlex was not laid out — unbounded flex regression');
      expect(row.size.width, greaterThan(0));
    }
  });

  testWidgets('code block survives a tap (hit test needs a laid-out box)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => SingleChildScrollView(
              child: MarkdownBody(
                data: '```py\nimport os\nprint(os.getcwd())\n```',
                builders: {
                  'code': CodeBlockBuilder(context),
                  'pre': CodeBlockBuilder(context),
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // The hit-test error in the report fired on a user tap over the code body.
    // Tap by location so this exercises hit testing on the formerly-unlaid-out
    // RenderFlex itself rather than on any header chrome.
    final body = find.byType(SingleChildScrollView).last;
    await tester.tapAt(tester.getCenter(body));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('long lines scroll horizontally instead of being constrained',
      (tester) async {
    const longLine =
        'final somethingVeryLongIndeed = anotherLongIdentifier + yetAnother + '
        'andStillMore + keepGoingUntilThisIsWiderThanTheScreen;';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => SingleChildScrollView(
              child: MarkdownBody(
                data: '```dart\n$longLine\n```',
                builders: {
                  'code': CodeBlockBuilder(context),
                  'pre': CodeBlockBuilder(context),
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Intrinsic width must exceed the 800px test viewport: the point of the
    // horizontal scroller is that code is NOT wrapped or clipped to the screen.
    // Scope to the scrolling body — find.byType(Row) also matches the header,
    // which is correctly constrained to the viewport width.
    final codeRow = find.descendant(
      of: find.byType(SingleChildScrollView).last,
      matching: find.byType(Row),
    );
    final row = tester.renderObject<RenderBox>(codeRow.first);
    expect(row.size.width, greaterThan(800));
  });
}
