// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

/// Save bytes via an anchor download (Web Share file support is spotty).
Future<bool> downloadWebFile(
  List<int> bytes,
  String filename,
  String mime,
) async {
  try {
    final blob = html.Blob([bytes], mime);
    final url = html.Url.createObjectUrlFromBlob(blob);
    try {
      html.AnchorElement(href: url)
        ..download = filename
        ..click();
    } finally {
      html.Url.revokeObjectUrl(url);
    }
    return true;
  } catch (_) {
    return false;
  }
}
