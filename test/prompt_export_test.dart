import 'package:flutter_test/flutter_test.dart';
import 'package:cubiclm/utils/prompt_export.dart';

/// Unit tests for Claude-style prompt exports (no platform channels).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('markdown filename is sanitized, stamped and suffixed', () {
    final name = PromptExport.buildMarkdownFileName('my prompt!');
    expect(name.endsWith('.md'), isTrue);
    expect(name.startsWith('my_prompt_'), isTrue);
    expect(name.contains(' '), isFalse);
    expect(name.contains('!'), isFalse);
  });

  test('pdf filename is sanitized, stamped and suffixed', () {
    final name = PromptExport.buildPdfFileName('game idea?');
    expect(name.endsWith('.pdf'), isTrue);
    expect(name.startsWith('game_idea_'), isTrue);
  });

  test('pdf bytes build for short text', () async {
    final bytes = await PromptExport.buildPdfBytes('Hello world');
    expect(bytes.isNotEmpty, isTrue);
    // PDF magic header: %PDF
    expect(bytes.length > 4, isTrue);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('pdf bytes build for Bangla text (font-independent raster)', () async {
    const bangla = 'আমি বাংলায় গান গাই।\nপরের লাইন এখানে।';
    final bytes = await PromptExport.buildPdfBytes(bangla);
    expect(bytes.isNotEmpty, isTrue);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('long text produces a bigger pdf than short text', () async {
    final short = await PromptExport.buildPdfBytes('Hi');
    final longText = List.filled(60, 'This is a repeated line for pagination.').join('\n');
    final long = await PromptExport.buildPdfBytes(longText);
    expect(long.length > short.length, isTrue);
  });

  test('empty text still builds a valid pdf', () async {
    final bytes = await PromptExport.buildPdfBytes('   ');
    expect(bytes.isNotEmpty, isTrue);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
