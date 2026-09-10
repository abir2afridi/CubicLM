import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import '../core/constants.dart';
import '../models/chat_session.dart';
import 'app_log_service.dart';
import 'hive_service.dart';
import '../utils/export_file.dart';

/// Chat backup + settings transfer (export/import JSON).
/// Extracted from controllers/chat_controller.dart.
/// Pure functions over [HiveService] - no controller state.
/// Build the backup JSON string, or null when there is nothing to back
/// up. Shared by manual export and silent auto-backup.
///
/// - [includeImages]: keep base64 image payloads (much larger file).
/// - [passphrase]: non-empty encrypts the payload (AES-256-CBC,
///   SHA-256 key). Import then requires the same passphrase.
Future<String?> buildBackupJson(
  HiveService hive, {
  bool includeImages = false,
  String? passphrase,
}) async {
  final sessionsRaw = hive.getAllSessions();
  final messagesRaw = hive.getAllMessagesRaw();
  if (sessionsRaw.isEmpty) return null;

  final sessionsOut = sessionsRaw
      .map((s) {
        final m = Map<String, dynamic>.from(s);
        if (!includeImages) m.remove('imageBase64');
        return m;
      })
      .map((s) => ChatSession.fromMap(s).toMap())
      .toList();

  final messagesOut = messagesRaw.map((m) {
    final c = Map<String, dynamic>.from(m);
    // File paths never transfer across devices.
    c['imagePath'] = null;
    if (!includeImages) c['imageBase64'] = null;
    return c;
  }).toList();

  final inner = {
    'sessions': sessionsOut,
    'messages': messagesOut,
  };
  final Map<String, dynamic> payload;
  final pass = (passphrase ?? '').trim();
  if (pass.isNotEmpty) {
    final plain = Uint8List.fromList(utf8.encode(
      '${HiveService.backupMagic}${jsonEncode(inner)}',
    ));
    final packed = await hive.encryptBackupBytes(plain, pass);
    payload = {
      'app': 'CubicLM',
      'type': 'chat_backup_encrypted',
      'version': 1,
      'algo': 'aes256cbc-sha256',
      'exportedAt': DateTime.now().toIso8601String(),
      'data': base64Encode(packed),
    };
  } else {
    payload = {
      'app': 'CubicLM',
      'type': 'chat_backup',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      ...inner,
    };
  }
  return jsonEncode(payload);
}

/// Export every session + message to a single JSON backup file, saved
/// straight to the device via the system Save dialog (no share sheet).
/// Desktop has no share sheet — a native save dialog is shown instead
/// so the user picks the destination directly.
Future<String?> exportAllChats(
  HiveService hive, {
  bool includeImages = false,
  String? passphrase,
}) async {
  try {
    final jsonStr = await buildBackupJson(hive,
        includeImages: includeImages, passphrase: passphrase);
    if (jsonStr == null) return 'empty';

    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return await _exportChatsDesktop(jsonStr);
    }

    final stamp = DateTime.now().toIso8601String().split('T').first;
    final saved = await ExportFile.saveTextToAppFolder(
      text: jsonStr,
      fileName: 'cubiclm_chat_backup_$stamp.json',
      mimeType: 'application/json',
    );
    return saved == null ? 'error' : null;
  } catch (e) {
    Get.find<AppLogService>()
        .error('Backup export failed', details: e, category: LogCategory.chat);
    return 'error';
  }
}

/// Desktop export: writes the JSON into the configured export folder
/// (Settings → Export folder). Returns null on success, 'error' on failure.
Future<String?> _exportChatsDesktop(String jsonStr) async {
  try {
    final stamp = DateTime.now().toIso8601String().split('T').first;
    final outPath = await ExportFile.saveTextToAppFolder(
      text: jsonStr,
      fileName: 'cubiclm_chat_backup_$stamp.json',
      mimeType: 'application/json',
    );
    if (outPath == null) return 'error';
    Get.snackbar(
      'Backup saved',
      outPath,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 6),
    );
    Get.find<AppLogService>().info('Chat backup exported',
        details: outPath, category: LogCategory.chat);
    return null;
  } catch (e) {
    Get.find<AppLogService>()
        .error('Backup export failed', details: e, category: LogCategory.chat);
    return 'error';
  }
}

/// Silent scheduled backup: writes unencrypted JSON (no images) to the
/// app documents dir when enabled and due, keeping the last 3 files.
/// Runs once per process from onInit. Never throws, never prompts.
/// NOTE: auto-backups are unencrypted (no unattended passphrase) —
/// use manual export with a passphrase for sensitive chats.
Future<void> maybeAutoBackup(HiveService hive) async {
  try {
    final enabled = hive.getSetting<bool>(AppConstants.keyAutoBackupEnabled,
            defaultValue: false) ??
        false;
    if (enabled != true) return;
    if (kIsWeb) return;
    final days =
        hive.getSetting<int>(AppConstants.keyAutoBackupDays, defaultValue: 7) ??
            7;
    final last =
        hive.getSetting<int>(AppConstants.keyLastAutoBackup, defaultValue: 0) ??
            0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - last < days * 24 * 60 * 60 * 1000) return;
    final jsonStr = await buildBackupJson(hive);
    if (jsonStr == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final stamp =
        DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final file = File('${dir.path}/cubiclm_auto_backup_$stamp.json');
    await file.writeAsString(jsonStr, flush: true);
    // Prune to the last 3 auto-backups.
    final autos = Directory(dir.path)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('cubiclm_auto_backup_'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final old in autos.skip(3)) {
      try {
        await old.delete();
      } catch (_) {}
    }
    await hive.setSetting(AppConstants.keyLastAutoBackup, nowMs);
    Get.find<AppLogService>().info('Auto backup saved',
        details: file.path, category: LogCategory.chat);
  } catch (_) {}
}

/// Export app settings WITHOUT secrets (API keys live in secure
/// storage and custom-profile inline keys are excluded too).
/// Returns null on success, or an error string. Desktop shows a native
/// save dialog; mobile shares the file.
final _settingsSecretKeys = {
  AppConstants.keyOpenaiKey,
  AppConstants.keyAnthropicKey,
  AppConstants.keyGoogleKey,
  AppConstants.keyKimiKey,
  AppConstants.keyStabilityKey,
  AppConstants.keyNvidiaKey,
  AppConstants.keyOpenRouterKey,
  AppConstants.keyDeepSeekKey,
  AppConstants.keyZaiKey,
  AppConstants.keyGroqKey,
  AppConstants.keyMistralKey,
  AppConstants.keyTogetherKey,
  AppConstants.keyXaiKey,
  AppConstants.keyPerplexityKey,
  AppConstants.keyCerebrasKey,
  AppConstants.keyFireworksKey,
  AppConstants.keyCohereKey,
  AppConstants.keyHuggingFaceKey,
  AppConstants.keyXkiroKey,
  AppConstants.keyTokenRouterKey,
  AppConstants.keyCustomCloudKey,
  AppConstants.keyCustomCloudProfiles,
  AppConstants.keyServerApiKey,
};
final _settingsSecretPattern = RegExp(
    r'token|secret|password|apikey|api_key|credential',
    caseSensitive: false);

Future<String?> exportSettings(HiveService hive) async {
  try {
    final all = hive.getAllSettingsRaw();
    all.removeWhere((k, _) =>
        _settingsSecretKeys.contains(k) || _settingsSecretPattern.hasMatch(k));
    final payload = {
      'app': 'CubicLM',
      'type': 'settings_backup',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'settings': all,
    };
    final jsonStr = jsonEncode(payload);
    final stamp = DateTime.now().toIso8601String().split('T').first;
    final fileName = 'cubiclm_settings_$stamp.json';
    final outPath = await ExportFile.saveTextToAppFolder(
      text: jsonStr,
      fileName: fileName,
      mimeType: 'application/json',
    );
    if (outPath == null) return 'error';
    Get.find<AppLogService>().info('Settings exported',
        details: outPath, category: LogCategory.chat);
    return null;
  } catch (e) {
    Get.find<AppLogService>().error('Settings export failed',
        details: e, category: LogCategory.chat);
    return 'error';
  }
}

/// Import a settings backup. Secrets are never imported (skipped).
/// Returns null on success, or an error string. Some settings apply
/// after an app restart.
Future<String?> importSettings(HiveService hive) async {
  try {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (picked == null || picked.files.isEmpty) return 'cancelled';
    final bytes = picked.files.first.bytes ??
        await File(picked.files.first.path!).readAsBytes();
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map || decoded['type'] != 'settings_backup') {
      return 'Not a CubicLM settings file.';
    }
    final map = Map<String, dynamic>.from(decoded['settings'] ?? {});
    var applied = 0;
    for (final e in map.entries) {
      if (_settingsSecretKeys.contains(e.key) ||
          _settingsSecretPattern.hasMatch(e.key)) {
        continue;
      }
      try {
        // Only JSON-native values cross devices safely.
        jsonEncode(e.value);
        await hive.setSetting(e.key, e.value);
        applied++;
      } catch (_) {}
    }
    Get.find<AppLogService>().info('Settings imported: $applied applied',
        category: LogCategory.chat);
    return null;
  } catch (e) {
    return 'Import failed: $e';
  }
}
