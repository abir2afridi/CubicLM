// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class DocumentChunk {
  final String text;
  final int pageNumber;
  final String source;

  DocumentChunk({
    required this.text,
    required this.pageNumber,
    required this.source,
  });

  Map<String, dynamic> toMap() => {
        'text': text,
        'pageNumber': pageNumber,
        'source': source,
      };
}

/// Extracts plain text from document files (PDF, DOCX) so they can be
/// fed into local or cloud LLMs as context.
class DocumentExtractorService {
  /// Extract text from a file based on its extension.
  static Future<String> extractText(String path, String extension) async {
    return _extractTextInternal(path, extension);
  }

  static Future<List<DocumentChunk>> extractChunks(
      String path, String extension, {int chunkSize = 1000}) async {
    final fullText = await _extractTextInternal(path, extension);
    final fileName = path.split('/').last;
    
    final chunks = <DocumentChunk>[];
    for (var i = 0; i < fullText.length; i += chunkSize) {
      final end = (i + chunkSize < fullText.length) ? i + chunkSize : fullText.length;
      chunks.add(DocumentChunk(
        text: fullText.substring(i, end),
        pageNumber: (i / 2000).floor() + 1,
        source: fileName,
      ));
    }
    return chunks;
  }

  static Future<String> _extractTextInternal(String path, String extension) async {
    switch (extension.toLowerCase()) {
      case 'zip':
        final chunks = await extractZip(path);
        return chunks.map((c) => '--- ${c.source} ---\n${c.text}').join('\n\n');
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

  static Future<String> _extractPdf(String path) async {
    final bytes = await File(path).readAsBytes();
    return compute(_extractPdfBytes, bytes);
  }

  static Future<String> _extractDocx(String path) async {
    final bytes = await File(path).readAsBytes();
    return compute(_extractDocxBytes, bytes);
  }

  static Future<List<DocumentChunk>> extractZip(String path) async {
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final chunks = <DocumentChunk>[];

    final allowedExtensions = {
      'txt', 'md', 'json', 'csv', 'log', 'yaml', 'yml', 'xml',
      'dart', 'kt', 'java', 'js', 'ts', 'py', 'c', 'cpp', 'h', 'hpp', 'go', 'rs', 'rb', 'php'
    };

    for (final file in archive) {
      if (file.isFile) {
        final name = file.name;
        final ext = name.split('.').last.toLowerCase();
        if (allowedExtensions.contains(ext)) {
          final content = utf8.decode(file.content as List<int>, allowMalformed: true);
          if (content.trim().isNotEmpty) {
            chunks.add(DocumentChunk(
              text: content,
              pageNumber: 0,
              source: name,
            ));
          }
        }
      }
    }
    return chunks;
  }
}

String _extractPdfBytes(Uint8List bytes) {
  final document = PdfDocument(inputBytes: bytes);
  try {
    return PdfTextExtractor(document).extractText();
  } finally {
    document.dispose();
  }
}

String _extractDocxBytes(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);

  final documentFile = archive.files.firstWhere(
    (f) => f.name == 'word/document.xml',
    orElse: () => throw Exception('Invalid DOCX: word/document.xml not found'),
  );

  final xmlString = utf8.decode(documentFile.content as List<int>);
  final document = XmlDocument.parse(xmlString);

  final paragraphs = <String>[];
  for (final p in document.findAllElements('w:p')) {
    final pTexts = p.findAllElements('w:t').map((e) => e.value).join();
    if (pTexts.isNotEmpty) paragraphs.add(pTexts);
  }

  return paragraphs.isNotEmpty
      ? paragraphs.join('\n\n')
      : document.findAllElements('w:t').map((e) => e.value).join();
}
