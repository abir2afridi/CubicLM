// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Extracts plain text from document files (PDF, DOCX) so they can be
/// fed into local or cloud LLMs as context.
class DocumentExtractorService {
  /// Extract text from a file based on its extension.
  static Future<String> extractText(String path, String extension) async {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return _extractPdf(path);
      case 'docx':
        return _extractDocx(path);
      case 'txt':
      case 'md':
      case 'json':
      case 'csv':
      case 'log':
      case 'yaml':
      case 'yml':
      case 'xml':
      case 'dart':
      case 'kt':
      case 'java':
      case 'js':
      case 'ts':
      case 'py':
        final bytes = await File(path).readAsBytes();
        return utf8.decode(bytes, allowMalformed: true);
      default:
        throw UnsupportedError(
          'Document extraction not supported for .$extension files',
        );
    }
  }

  /// Extract text from a PDF file using Syncfusion PDF.
  static Future<String> _extractPdf(String path) async {
    final bytes = await File(path).readAsBytes();
    final document = PdfDocument(inputBytes: bytes);
    try {
      final extractor = PdfTextExtractor(document);
      return extractor.extractText();
    } finally {
      document.dispose();
    }
  }

  /// Extract text from a DOCX file using pure Dart (archive + xml).
  static Future<String> _extractDocx(String path) async {
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final documentFile = archive.files.firstWhere(
      (f) => f.name == 'word/document.xml',
      orElse: () => throw Exception('Invalid DOCX: word/document.xml not found'),
    );

    final xmlString = utf8.decode(documentFile.content as List<int>);
    final document = XmlDocument.parse(xmlString);

    // Preserve paragraph breaks: <w:p> elements separate paragraphs.
    final paragraphs = <String>[];
    for (final p in document.findAllElements('w:p')) {
      final pTexts = p.findAllElements('w:t').map((e) => e.value).join();
      if (pTexts.isNotEmpty) paragraphs.add(pTexts);
    }

    return paragraphs.isNotEmpty
        ? paragraphs.join('\n\n')
        : document.findAllElements('w:t').map((e) => e.value).join();
  }
}
