import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/constants.dart';
import '../services/hive_service.dart';
import 'web_download.dart';

/// Direct file export — saves bytes straight to the device with a system
/// Save dialog (Storage Access Framework on Android, NSSavePanel-style
/// picker on desktop, browser download on web).
///
/// Unlike `share_plus`, this never opens the share sheet, so exports work
/// even when no other app can receive the file.
class ExportFile {
  ExportFile._();

  static const _androidChannel =
      MethodChannel('com.cubiclm.app/model_import');

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

  /// Sanitized export subfolder name (user setting or 'CubicLM').
  /// Pure logic — safe to unit test.
  static String appSubfolder() {
    try {
      final raw = Get.isRegistered<HiveService>()
          ? (Get.find<HiveService>()
                  .getSetting<String>(AppConstants.keyExportSubfolder) ??
              '')
          : '';
      final clean = sanitizeExportSubfolder(raw);
      return clean.isEmpty ? AppConstants.defaultExportSubfolder : clean;
    } catch (_) {
      return AppConstants.defaultExportSubfolder;
    }
  }

  /// Keep only filesystem-safe chars for the subfolder name.
  /// Pure logic — safe to unit test.
  static String sanitizeExportSubfolder(String s) {
    var clean = s.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean == '.' || clean == '..') return '';
    if (clean.length > 32) clean = clean.substring(0, 32).trim();
    return clean;
  }

  /// Short display label for Settings, e.g. 'Download/CubicLM'.
  static String exportLocationLabel() {
    if (kIsWeb) return 'Browser downloads';
    try {
      if (Platform.isAndroid) {
        final treeName = Get.isRegistered<HiveService>()
            ? (Get.find<HiveService>()
                    .getSetting<String>(AppConstants.keyExportTreeName) ??
                '')
            : '';
        if (treeName.isNotEmpty) return '$treeName (custom)';
        return 'Download/${appSubfolder()}';
      }
      if (!Platform.isIOS) {
        final custom = Get.isRegistered<HiveService>()
            ? (Get.find<HiveService>()
                    .getSetting<String>(AppConstants.keyExportCustomDir) ??
                '')
            : '';
        if (custom.isNotEmpty) return custom;
        return 'Documents/${appSubfolder()}';
      }
    } catch (_) {}
    return appSubfolder();
  }

  /// Opens the system folder picker (Android file manager) for the export
  /// destination. Returns {'uri', 'name'} or null when cancelled.
  /// Caller persists via SettingsController.setExportTree.
  static Future<Map<String, String>?> pickExportFolder() async {
    if (kIsWeb) return null;
    try {
      if (!Platform.isAndroid) return null;
      final res = await _androidChannel
          .invokeMapMethod<String, dynamic>('pickExportFolder');
      if (res == null) return null;
      final uri = res['uri']?.toString() ?? '';
      final name = res['name']?.toString() ?? '';
      if (uri.isEmpty) return null;
      return {'uri': uri, 'name': name.isEmpty ? 'Picked folder' : name};
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearExportTree() async {
    try {
      if (Get.isRegistered<HiveService>()) {
        final hive = Get.find<HiveService>();
        await hive.setSetting(AppConstants.keyExportTreeUri, '');
        await hive.setSetting(AppConstants.keyExportTreeName, '');
      }
    } catch (_) {}
  }

  /// Saves [bytes] straight into the app export folder — no dialog.
  /// Android: Download/\<subfolder\> via MediaStore (no permission needed).
  /// Desktop/iOS: Documents (or the custom dir) / \<subfolder\>.
  /// Returns the saved display path, or null on failure.
  static Future<String?> saveToAppFolder({
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
  }) async {
    if (kIsWeb) {
      try {
        if (await downloadWebFile(
            bytes, fileName, mimeType ?? _mimeFor(fileName))) {
          return fileName;
        }
      } catch (_) {}
      return null;
    }
    if (Platform.isAndroid) {
      // A user-picked system folder wins; on lost permission fall back
      // to the default (and drop the stale keys so Settings reflects it).
      try {
        final hive = Get.isRegistered<HiveService>()
            ? Get.find<HiveService>()
            : null;
        final treeUri = hive?.getSetting<String>(
                AppConstants.keyExportTreeUri) ??
            '';
        if (treeUri.isNotEmpty) {
          final ok = await _androidChannel.invokeMethod<bool>(
              'checkTreeFolderAccess', {'treeUri': treeUri});
          if (ok == true) {
            final path = await _androidChannel.invokeMethod<String>(
                'saveBytesToTreeFolder', {
              'filename': fileName,
              'bytes': bytes,
              'mimeType': mimeType ?? _mimeFor(fileName),
              'treeUri': treeUri,
            });
            if (path != null && path.isNotEmpty) return path;
          } else {
            await clearExportTree();
          }
        }
      } catch (_) {}
      try {
        final path =
            await _androidChannel.invokeMethod<String>('saveBytesToDownloads', {
          'filename': fileName,
          'bytes': bytes,
          'mimeType': mimeType ?? _mimeFor(fileName),
          'subfolder': appSubfolder(),
        });
        return (path == null || path.isEmpty) ? null : path;
      } catch (_) {
        return null;
      }
    }
    try {
      final dir = await _desktopExportDir();
      final f = File('${dir.path}${Platform.pathSeparator}$fileName');
      await f.writeAsBytes(bytes, flush: true);
      return f.path;
    } catch (_) {
      return null;
    }
  }

  /// Text twin of [saveToAppFolder].
  static Future<String?> saveTextToAppFolder({
    required String text,
    required String fileName,
    String? mimeType,
  }) =>
      saveToAppFolder(
        bytes: Uint8List.fromList(utf8.encode(text)),
        fileName: fileName,
        mimeType: mimeType,
      );

  static Future<Directory> _desktopExportDir() async {
    try {
      final custom = Get.isRegistered<HiveService>()
          ? (Get.find<HiveService>()
                  .getSetting<String>(AppConstants.keyExportCustomDir) ??
              '')
          : '';
      if (custom.isNotEmpty) {
        final d = Directory(custom);
        if (await d.exists()) return d;
      }
    } catch (_) {}
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory('${docs.path}${Platform.pathSeparator}${appSubfolder()}');
    await d.create(recursive: true);
    return d;
  }

  static String _mimeFor(String fileName) {
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'json':
        return 'application/json';
      case 'md':
      case 'markdown':
      case 'txt':
      case 'log':
        return 'text/plain';
      case 'html':
      case 'htm':
        return 'text/html';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'zip':
        return 'application/zip';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      default:
        return 'application/octet-stream';
    }
  }

  /// Shares [bytes] via the system share sheet (staged through cache).
  static Future<bool> shareBytes({
    required Uint8List bytes,
    required String fileName,
    String? text,
    String? subject,
  }) async {
    try {
      if (kIsWeb) {
        await Share.share(text ?? fileName, subject: subject);
        return true;
      }
      final tmp = await getTemporaryDirectory();
      final dir =
          Directory('${tmp.path}${Platform.pathSeparator}cubiclm_share');
      await dir.create(recursive: true);
      final f = File('${dir.path}${Platform.pathSeparator}$fileName');
      await f.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([XFile(f.path)],
          text: text, subject: subject);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// One-call export: saves into the app folder (no dialog), then shows a
  /// snackbar with the location and a Share action. Returns the saved
  /// path, or null on failure (a failure snackbar is shown).
  static Future<String?> quickExport({
    Uint8List? bytes,
    String? text,
    required String fileName,
    String? mimeType,
    String? shareText,
    String? shareSubject,
  }) async {
    final data = bytes ??
        (text != null ? Uint8List.fromList(utf8.encode(text)) : null);
    if (data == null) return null;
    final saved = await saveToAppFolder(
        bytes: data, fileName: fileName, mimeType: mimeType);
    if (saved == null) {
      Get.snackbar('Export failed', 'Could not save $fileName.',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 3));
      return null;
    }
    Get.snackbar(
      'Export saved',
      saved,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 5),
      mainButton: TextButton(
        onPressed: () {
          try {
            if (Get.isSnackbarOpen) Get.back();
          } catch (_) {}
          unawaited(shareBytes(
              bytes: data,
              fileName: fileName,
              text: shareText,
              subject: shareSubject));
        },
        child: const Text('Share'),
      ),
    );
    return saved;
  }
}
