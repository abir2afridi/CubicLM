import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:get/get.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Claude-style prompt exports.
///
/// The prompt text is written to a `.md` file or rendered into a PDF and
/// shared through the system share sheet (Save to Files / Drive / send via
/// any app). PDF pages are rasterized with Flutter's own text engine
/// (ui.Paragraph), so every script the device fonts cover — Bangla, Arabic,
/// CJK, emoji — renders correctly without shipping/embedding font files.
class PromptExport {
  PromptExport._();

  static const double _pageWidth = 794; // A4 @ 96dpi
  static const double _margin = 48;
  static const double _scale = 2; // 2x raster for crisp text
  static const int _maxChunkChars = 1200;

  static String _stamp() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  static String _sanitize(String base) => base
      .replaceAll(RegExp(r'[^\w\-. ]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), '_');

  /// Writes the prompt as a `.md` file and opens the share sheet.
  /// Shows a snackbar instead of throwing, so icon-button callers stay lean.
  static Future<void> shareAsMarkdown(String text, {String? baseName}) async {
    try {
      final name = buildMarkdownFileName(baseName ?? 'prompt');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$name');
      await file.writeAsString(text, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/markdown')],
        subject: 'Prompt (Markdown)',
      );
    } catch (e) {
      Get.snackbar('prompt_export_failed'.tr, '$e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  /// Renders the prompt into a paginated PDF and opens the share sheet.
  /// Shows a snackbar instead of throwing, so icon-button callers stay lean.
  static Future<void> shareAsPdf(String text, {String? baseName}) async {
    try {
      final bytes = await buildPdfBytes(text);
      final name = buildPdfFileName(baseName ?? 'prompt');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Prompt (PDF)',
      );
    } catch (e) {
      Get.snackbar('prompt_export_failed'.tr, '$e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  /// Public, unit-testable filename builders (also used by the share fns).
  static String buildMarkdownFileName(String baseName) =>
      '${_sanitize(baseName)}_${_stamp()}.md';

  static String buildPdfFileName(String baseName) =>
      '${_sanitize(baseName)}_${_stamp()}.pdf';

  /// Public PDF builder (used by [shareAsPdf] and widget tests).
  static Future<Uint8List> buildPdfBytes(String rawText) =>
      _buildPdf(rawText);

  // ── PDF rendering ────────────────────────────────────────────

  static Future<Uint8List> _buildPdf(String rawText) async {
    final text = rawText.trim().isEmpty ? '(empty prompt)' : rawText;
    final document = PdfDocument();
    try {
      for (final chunk in _chunkText(text)) {
        final png = await _textChunkToPng(chunk);
        final decoded = img.decodePng(png);
        final imgW = decoded?.width.toDouble() ?? _pageWidth * _scale;
        final imgH = decoded?.height.toDouble() ?? 100;
        const pageW = 595.0; // A4 width in points
        final pageH = imgH * (pageW / imgW);
        final section = document.sections!.add();
        section.pageSettings.size = ui.Size(pageW, pageH);
        final page = section.pages.add();
        page.graphics.drawImage(
          PdfBitmap(png),
          ui.Rect.fromLTWH(0, 0, pageW, pageH),
        );
      }
      final bytes = await document.save();
      return Uint8List.fromList(bytes);
    } finally {
      document.dispose();
    }
  }

  /// Splits text into render-sized chunks at line boundaries so no single
  /// rasterized page exceeds texture limits on any device.
  static List<String> _chunkText(String text) {
    final chunks = <String>[];
    final current = StringBuffer();
    var len = 0;
    for (final line in text.split('\n')) {
      var l = line;
      while (l.length > _maxChunkChars) {
        if (current.isNotEmpty) {
          chunks.add(current.toString());
          current.clear();
          len = 0;
        }
        chunks.add(l.substring(0, _maxChunkChars));
        l = l.substring(_maxChunkChars);
      }
      if (len + l.length + 1 > _maxChunkChars && current.isNotEmpty) {
        chunks.add(current.toString());
        current.clear();
        len = 0;
      }
      current.writeln(l);
      len += l.length + 1;
    }
    if (current.isNotEmpty) chunks.add(current.toString());
    return chunks.isEmpty ? [''] : chunks;
  }

  static Future<Uint8List> _textChunkToPng(String chunk) async {
    const width = _pageWidth * _scale;
    const margin = _margin * _scale;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(fontSize: 14 * _scale, height: 1.55),
    );
    builder.pushStyle(ui.TextStyle(color: const ui.Color(0xFF1A1A1A)));
    builder.addText(chunk);
    final paragraph = builder.build();
    paragraph
        .layout(const ui.ParagraphConstraints(width: width - margin * 2));
    final canvasHeight = paragraph.height + margin * 2;

    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width, canvasHeight),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    canvas.drawParagraph(paragraph, const ui.Offset(margin, margin));
    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), canvasHeight.ceil());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    image.dispose();
    return data!.buffer.asUint8List();
  }
}