/// CubicDataSheet vault persistence — uninstall-safe file storage.
///
/// The vault is ONE JSON file that survives app uninstall by living in
/// public storage: Download/CubicLM/DataSheet/ on Android (MediaStore,
/// no permission needed) and Documents/CubicLM/DataSheet/ on desktop.
/// App-private dirs (Hive, getApplicationDocumentsDirectory) are wiped
/// on uninstall, so they are deliberately NOT used here.
///
/// Android writes go through two small native methods on the existing
/// `com.cubiclm.app/model_import` channel:
/// - readVaultFile {name, subfolder} -> bytes? (query by display name)
/// - writeVaultFile {name, subfolder, bytes, mimeType} -> display path?
/// In-place truncate-update keeps a single file across reinstalls
/// (same package + signature regains write access to its own entries).
library;

import 'dart:convert';
import 'dart:io' show Directory, File, Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class CubicVaultStore {
  CubicVaultStore._();

  static const fileName = 'cubicdatasheet_vault.json';
  static const subfolder = 'DataSheet';
  static const _androidChannel =
      MethodChannel('com.cubiclm.app/model_import');

  /// Loads the vault JSON map, or null when no vault exists yet.
  static Future<Map<String, dynamic>?> load() async {
    try {
      if (kIsWeb) return null;
      if (Platform.isAndroid) {
        final bytes = await _androidChannel.invokeMethod<Uint8List>(
          'readVaultFile',
          {'name': fileName, 'subfolder': subfolder},
        );
        if (bytes == null || bytes.isEmpty) return null;
        final decoded = jsonDecode(utf8.decode(bytes));
        return decoded is Map<String, dynamic> ? decoded : null;
      }
      final f = await _desktopFile();
      if (!await f.exists()) return null;
      final decoded = jsonDecode(await f.readAsString());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// Writes the whole vault atomically (temp + rename on desktop;
  /// truncate-update on Android). Returns false on failure.
  static Future<bool> save(Map<String, dynamic> vault) async {
    try {
      if (kIsWeb) return false;
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(vault)));
      if (Platform.isAndroid) {
        final path =
            await _androidChannel.invokeMethod<String>('writeVaultFile', {
          'name': fileName,
          'subfolder': subfolder,
          'bytes': bytes,
          'mimeType': 'application/json',
        });
        return path != null && path.isNotEmpty;
      }
      final f = await _desktopFile();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(utf8.decode(bytes), flush: true);
      await tmp.rename(f.path);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<File> _desktopFile() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(
        '${docs.path}${Platform.pathSeparator}CubicLM${Platform.pathSeparator}$subfolder');
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}$fileName');
  }
}
