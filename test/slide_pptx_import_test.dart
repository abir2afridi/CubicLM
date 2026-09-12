import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/utils/slide_deck.dart';
import 'package:cubiclm/utils/slide_pptx.dart';

/// PPTX import: structural parse, pure logic + in-memory zips.
void main() {
  List<int> makePptx(Map<String, String> files) {
    final archive = Archive();
    files.forEach((name, body) {
      final bytes = utf8.encode(body);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    });
    return ZipEncoder().encode(archive);
  }

  const slide1 = '''<?xml version="1.0" encoding="UTF-8"?>
<p:sld xmlns:p="x" xmlns:a="y"><p:cSld><p:spTree>
<w><a:t>Intro &amp; Vision</a:t></w>
<w><a:t>First point</a:t></w>
<w><a:t>Second point</a:t></w>
</p:spTree></p:cSld></p:sld>''';

  const slide2 = '''<?xml version="1.0" encoding="UTF-8"?>
<p:sld xmlns:p="x" xmlns:a="y"><p:cSld><p:spTree>
<w><a:t>Thanks</a:t></w>
</p:spTree></p:cSld></p:sld>''';

  const notes2 = '''<?xml version="1.0" encoding="UTF-8"?>
<p:notes xmlns:p="x" xmlns:a="y"><a:t>Say thanks slowly.</a:t></p:notes>''';

  group('parsePptx', () {
    test('recovers titles, points and notes in order', () {
      final bytes = makePptx({
        'ppt/slides/slide1.xml': slide1,
        'ppt/slides/slide2.xml': slide2,
        'ppt/notesSlides/notesSlide2.xml': notes2,
      });
      final slides = parsePptx(bytes);
      expect(slides.length, 2);
      expect(slides[0].title, 'Intro & Vision');
      expect(slides[0].points, ['First point', 'Second point']);
      expect(slides[0].layout, 'bullets');
      expect(slides[0].speakerNotes, isEmpty);
      expect(slides[1].title, 'Thanks');
      expect(slides[1].layout, 'title');
      expect(slides[1].speakerNotes, 'Say thanks slowly.');
    });

    test('sorts slides numerically, not lexically', () {
      final bytes = makePptx({
        'ppt/slides/slide10.xml': slide2,
        'ppt/slides/slide2.xml': slide1,
      });
      final slides = parsePptx(bytes);
      expect(slides.length, 2);
      expect(slides[0].title, 'Intro & Vision');
      expect(slides[1].title, 'Thanks');
    });

    test('rejects non-zip and slide-less zips', () {
      expect(parsePptx([1, 2, 3, 4]), isEmpty);
      expect(parsePptx(utf8.encode('hello')), isEmpty);
      expect(makePptx({'doc.txt': 'hi'}).isNotEmpty, isTrue);
      expect(parsePptx(makePptx({'doc.txt': 'hi'})), isEmpty);
    });
  });

  group('pptx round-trip', () {
    test('export then import recovers slide titles', () async {
      final deck = [
        Slide(title: 'Alpha', points: ['a', 'b']),
        Slide(title: 'Beta', points: []),
      ];
      final bytes = await deckToPptx('Roundtrip', deck);
      final back = parsePptx(bytes);
      expect(back.length, deck.length);
      expect(back.map((s) => s.title).toList(), ['Alpha', 'Beta']);
    });
  });
}
