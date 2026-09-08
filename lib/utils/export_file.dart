import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'web_download.dart';

/// Direct file export — saves bytes straight to the device with a system
/// Save dialog (Storage Access Framework on Android, NSSavePanel-style
/// picker on desktop, browser download on web).
///
/// Unlike `share_plus`, this never opens the share sheet, so exports work
/// even when no other app can receive the file.
class ExportFile {
  ExportFile._();

  /// Saves [bytes] as [fileName]. Returns the saved path (or file name on
  /// web), or null when the user cancels / the platform cannot save.
  static Future<String?> saveBytes({
    required Uint8List bytes,
    required String fileName,
    String? dialogTitle,
    String? mimeType,
  }) async {
    if (kIsWeb) {
      try {
        if (await downloadWebFile(
            bytes, fileName, mimeType ?? 'application/octet-stream')) {
          return fileName;
        }
      } catch (_) {}
      return null;
    }
    final ext =
        fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    try {
      return await FilePicker.saveFile(
        dialogTitle: dialogTitle ?? 'Save $fileName',
        fileName: fileName,
        type: ext.isEmpty ? FileType.any : FileType.custom,
        allowedExtensions: ext.isEmpty ? null : [ext],
        bytes: bytes,
      );
    } catch (_) {
      return null;
    }
  }

  /// Text twin of [saveBytes].
  static Future<String?> saveText({
    required String text,
    required String fileName,
    String? dialogTitle,
    String? mimeType,
  }) =>
      saveBytes(
        bytes: Uint8List.fromList(utf8.encode(text)),
        fileName: fileName,
        dialogTitle: dialogTitle,
        mimeType: mimeType,
      );
}
