import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/constants.dart';
import 'secure_key_store.dart';

/// Worker for [HiveService.searchMessages] — must stay top-level for
/// `compute()`. Args: {'rows': List<List<String>> [content, chatId], 'q'}.
Set<String> _searchRows(Map<String, dynamic> args) {
  final q = args['q'] as String;
  final ids = <String>{};
  for (final row in args['rows'] as List) {
    final r = (row as List).map((e) => e.toString()).toList();
    if (r.length < 2 || r[1].isEmpty) continue;
    if (r[0].toLowerCase().contains(q)) ids.add(r[1]);
  }
  return ids;
}

/// Timestamp-tagged message row for paged chat queries.
class _TsRow {
  final int ms;
  final Map<dynamic, dynamic> map;
  _TsRow(this.ms, this.map);
}

/// Worker for [HiveService.encryptBackupBytes] — AES over megabytes must
/// not run on the UI thread (export would look hung).
Uint8List _encryptBackupWorker(Map<String, dynamic> args) {
  final plain = args['plain'] as Uint8List;
  final key = args['key'] as Uint8List;
  final cipher = HiveAesCipher(key);
  final out = Uint8List(cipher.maxEncryptedSize(plain));
  final n = cipher.encrypt(plain, 0, plain.length, out, 0);
  return Uint8List.sublistView(out, 0, n);
}

/// Worker for [HiveService.decryptBackupBytes].
Uint8List _decryptBackupWorker(Map<String, dynamic> args) {
  final packed = args['packed'] as Uint8List;
  final key = args['key'] as Uint8List;
  final cipher = HiveAesCipher(key);
  final out = Uint8List(packed.length);
  final n = cipher.decrypt(packed, 0, packed.length, out, 0);
  return Uint8List.sublistView(out, 0, n);
}
/// In-memory fallback that implements Hive [Box] without disk I/O.
/// Used when Hive is corrupted / storage slow — app stays usable with
/// defaults, data just won't persist until next clean launch.
class _MemoryBox implements Box<dynamic> {
  final Map<dynamic, dynamic> _map = {};
  @override
  String get name => '_memory';
  @override
  bool get isOpen => true;
  @override
  String? get path => null;
  @override
  bool get lazy => false;
  @override
  Iterable<dynamic> get keys => _map.keys;
  @override
  int get length => _map.length;
  @override
  bool get isEmpty => _map.isEmpty;
  @override
  bool get isNotEmpty => _map.isNotEmpty;
  @override
  Iterable<dynamic> get values => _map.values;
  @override
  dynamic keyAt(int index) => _map.keys.elementAt(index);
  @override
  Stream<BoxEvent> watch({dynamic key}) => const Stream.empty();
  @override
  bool containsKey(dynamic key) => _map.containsKey(key);
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      _map.containsKey(key) ? _map[key] : defaultValue;
  @override
  dynamic getAt(int index) => _map.values.elementAt(index);
  @override
  Map<dynamic, dynamic> toMap() => Map<dynamic, dynamic>.from(_map);
  @override
  Iterable<dynamic> valuesBetween({dynamic startKey, dynamic endKey}) =>
      _map.entries
          .where((e) {
            if (startKey != null &&
                e.key.toString().compareTo(startKey.toString()) < 0) {
              return false;
            }
            if (endKey != null &&
                e.key.toString().compareTo(endKey.toString()) > 0) {
              return false;
            }
            return true;
          })
          .map((e) => e.value);
  @override
  Future<void> put(dynamic key, dynamic value) async {
    _map[key] = value;
  }

  @override
  Future<void> putAt(int index, dynamic value) async {
    final key = _map.keys.elementAt(index);
    _map[key] = value;
  }

  @override
  Future<void> putAll(Map<dynamic, dynamic> entries) async {
    _map.addAll(entries);
  }

  @override
  Future<int> add(dynamic value) async {
    final key = _map.length;
    _map[key] = value;
    return key;
  }

  @override
  Future<Iterable<int>> addAll(Iterable<dynamic> values) async {
    final keys = <int>[];
    for (final v in values) {
      keys.add(await add(v));
    }
    return keys;
  }

  @override
  Future<void> delete(dynamic key) async {
    _map.remove(key);
  }

  @override
  Future<void> deleteAt(int index) async {
    final key = _map.keys.elementAt(index);
    _map.remove(key);
  }

  @override
  Future<void> deleteAll(Iterable<dynamic> keys) async {
    for (final k in keys) {
      _map.remove(k);
    }
  }

  @override
  Future<void> compact() async {}

  @override
  Future<int> clear() async {
    final count = _map.length;
    _map.clear();
    return count;
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> deleteFromDisk() async {
    _map.clear();
  }

  @override
  Future<void> flush() async {}
}

class HiveService extends GetxService {
  /// Gallery keeps at most this many generations — older rows (and their
  /// PNG files) are evicted on save. Prevents unbounded Hive + disk growth.
  static const int maxImageHistory = 200;

  late Box _sessionsBox;
  late Box _messagesBox;
  late Box _tasksBox;
  late Box _settingsBox;
  late Box _notificationsBox;
  late Box _skillsBox;
  late Box _mcpBox;
  late Box _imageHistoryBox;

  bool _isFallback = false;
  bool get isFallback => _isFallback;

  HiveAesCipher? _encryptionCipher;

  Box get sessionsBox => _sessionsBox;
  Box get messagesBox => _messagesBox;
  Box get tasksBox => _tasksBox;
  Box get settingsBox => _settingsBox;
  Box get notificationsBox => _notificationsBox;
  Box get skillsBox => _skillsBox;
  Box get mcpBox => _mcpBox;
  Box get imageHistoryBox => _imageHistoryBox;

  /// Pure memory fallback — no Hive disk access.
  HiveService.fallback() {
    _isFallback = true;
    _sessionsBox = _MemoryBox();
    _messagesBox = _MemoryBox();
    _tasksBox = _MemoryBox();
    _settingsBox = _MemoryBox();
    _notificationsBox = _MemoryBox();
    _skillsBox = _MemoryBox();
    _mcpBox = _MemoryBox();
    _imageHistoryBox = _MemoryBox();
  }

  HiveService();

  bool _isBoxUsable(Box? b) {
    try {
      return b != null && b.isOpen;
    } catch (_) {
      return false;
    }
  }

  Future<Box> _openBoxWithFallback(String name) async {
    // Try normal open with short timeout, using encryption if available.
    try {
      return await Hive.openBox(name,
              encryptionCipher: _encryptionCipher)
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // Encrypted open failed — might be migrating from plain-text.
      // Try to read data with no cipher, then re-encrypt.
      if (_encryptionCipher != null) {
        try {
          final plainBox =
              await Hive.openBox(name).timeout(const Duration(seconds: 3));
          if (plainBox.isNotEmpty) {
            final data = <dynamic, dynamic>{};
            for (final key in plainBox.keys) {
              data[key] = plainBox.get(key);
            }
            await plainBox.close();
            await Hive.deleteBoxFromDisk(name);
            final encryptedBox = await Hive.openBox(name,
                    encryptionCipher: _encryptionCipher)
                .timeout(const Duration(seconds: 3));
            await encryptedBox.putAll(data);
            return encryptedBox;
          }
          // Empty plain box — just close and reopen encrypted.
          await plainBox.close();
          await Hive.deleteBoxFromDisk(name);
          return await Hive.openBox(name,
                  encryptionCipher: _encryptionCipher)
              .timeout(const Duration(seconds: 3));
        } catch (_) {}
      }

      // Try delete + retry once (no encryption, fallback path).
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
      try {
        return await Hive.openBox(name)
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        // Disk still failing — use memory.
        _isFallback = true;
        return _MemoryBox();
      }
    }
  }

  Future<HiveService> init({SecureKeyStore? secureKeyStore}) async {
    // Set up AES encryption cipher if SecureKeyStore is available.
    if (secureKeyStore != null) {
      try {
        final key = await secureKeyStore.hiveEncryptionKey();
        _encryptionCipher = HiveAesCipher(key);
      } catch (_) {
        // Encryption setup failed — proceed without encryption.
      }
    }

    // Open each box individually so one corrupted box doesn't kill all 7.
    final results = await Future.wait<Box>([
      _openBoxWithFallback(AppConstants.chatSessionsBox),
      _openBoxWithFallback(AppConstants.chatMessagesBox),
      _openBoxWithFallback(AppConstants.tasksBox),
      _openBoxWithFallback(AppConstants.settingsBox),
      _openBoxWithFallback(AppConstants.notificationsBox),
      _openBoxWithFallback(AppConstants.skillsBox),
      _openBoxWithFallback(AppConstants.mcpBox),
      _openBoxWithFallback(AppConstants.imageHistoryBox),
    ]);
    _sessionsBox = results[0];
    _messagesBox = results[1];
    _tasksBox = results[2];
    _settingsBox = results[3];
    _notificationsBox = results[4];
    _skillsBox = results[5];
    _mcpBox = results[6];
    _imageHistoryBox = results[7];

    // One-time migration: prefix message keys with chatId for O(1) lookup.
    try {
      if (_isBoxUsable(_messagesBox) && _isBoxUsable(_settingsBox)) {
        final migrated = _settingsBox.get('messages_migrated_to_prefix',
                defaultValue: false) as bool? ??
            false;
        if (!migrated) {
          final keys = _messagesBox.keys.toList();
          for (final k in keys) {
            final ks = k.toString();
            if (ks.contains('/')) continue;
            final v = _messagesBox.get(k);
            if (v is Map &&
                v['chatId'] is String &&
                (v['chatId'] as String).isNotEmpty) {
              final chatId = v['chatId'] as String;
              final newKey = '$chatId/$ks';
              if (!_messagesBox.containsKey(newKey)) {
                await _messagesBox.put(newKey, v);
              }
              await _messagesBox.delete(k);
            }
          }
          await _settingsBox.put('messages_migrated_to_prefix', true);
        }
      }
    } catch (_) {}

    // Purge obsolete keys only if settings box is real Hive (memory is empty anyway).
    try {
      if (_isBoxUsable(_settingsBox)) {
        final obsoleteServerKeys = _settingsBox.keys.where((key) =>
            key is String &&
            key.startsWith('server_') &&
            key != AppConstants.keyServerApiKey &&
            key != AppConstants.keyServerUseApiKey);
        if (obsoleteServerKeys.isNotEmpty) {
          await _settingsBox.deleteAll(obsoleteServerKeys);
        }
      }
    } catch (_) {
      // Ignore — not critical.
    }
    return this;
  }

  // ─── Settings helpers ───────────────────────────

  /// All raw settings entries (for settings-only export).
  Map<String, dynamic> getAllSettingsRaw() {
    try {
      if (!_isBoxUsable(_settingsBox)) return {};
      final out = <String, dynamic>{};
      for (final k in _settingsBox.keys) {
        out[k.toString()] = _settingsBox.get(k);
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  T? getSetting<T>(String key, {T? defaultValue}) {    try {
      if (!_isBoxUsable(_settingsBox)) return defaultValue;
      return _settingsBox.get(key, defaultValue: defaultValue) as T?;
    } on HiveError {
      return defaultValue;
    } catch (_) {
      return defaultValue;
    }
  }

  Future<void> setSetting(String key, dynamic value) async {
    try {
      if (!_isBoxUsable(_settingsBox)) return;
      await _settingsBox.put(key, value);
    } on HiveError {
      // Ignore — box closed, will be reopened on next launch.
    } catch (_) {}
  }

  Future<void> deleteSetting(String key) async {
    try {
      if (!_isBoxUsable(_settingsBox)) return;
      await _settingsBox.delete(key);
    } on HiveError {
      // Box closed — will be reopened on next launch.
    } catch (_) {}
  }

  // ─── Chat Sessions ─────────────────────────────

  List<Map<dynamic, dynamic>> getAllSessions() {
    try {
      if (!_isBoxUsable(_sessionsBox)) return [];
      return _sessionsBox.values
          .map((v) => Map<dynamic, dynamic>.from(v))
          .toList();
    } on HiveError {
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Max chat sessions kept. Oldest unpinned sessions are evicted with
  /// their messages on save (pinned + recent survive).
  static const int maxSessions = 500;

  Future<void> saveSession(String id, Map<String, dynamic> data) async {
    try {
      if (!_isBoxUsable(_sessionsBox)) return;
      await _sessionsBox.put(id, data);
      if (_sessionsBox.length > maxSessions) {
        await _evictOldSessions();
      }
    } on HiveError {
      // Box closed - data will persist on next launch.
    } catch (_) {}
  }

  Future<void> _evictOldSessions() async {
    try {
      final rows = <Map<String, dynamic>>[];
      for (final k in _sessionsBox.keys) {
        final v = _sessionsBox.get(k);
        if (v is Map) {
          rows.add({
            'id': k.toString(),
            'pinned': v['pinned'] == true,
            'updatedAt': DateTime.tryParse(v['updatedAt']?.toString() ?? '')
                    ?.millisecondsSinceEpoch ??
                0,
          });
        }
      }
      rows.sort((a, b) => (a['updatedAt'] as int)
          .compareTo(b['updatedAt'] as int));
      var excess = rows.length - maxSessions;
      for (final r in rows) {
        if (excess <= 0) break;
        if (r['pinned'] as bool) continue;
        // deleteSession removes the session row + all its messages/files.
        await deleteSession(r['id'] as String);
        excess--;
      }
    } catch (_) {}
  }

  Future<void> deleteSession(String id) async {
    try {
      if (_isBoxUsable(_sessionsBox)) await _sessionsBox.delete(id);
    } on HiveError {
      // Box closed — session data will persist on next launch.
    } catch (_) {}
    // Delete all messages for this session (prefix-aware + file cleanup)
    try {
      if (!_isBoxUsable(_messagesBox)) return;
      final prefix = '$id/';
      final keysToDelete = <dynamic>[];
      for (final k
          in _messagesBox.keys.where((k) => k.toString().startsWith(prefix)).toList()) {
        final msg = _messagesBox.get(k);
        if (msg is Map) _deleteImageFile(msg['imagePath'] as String?);
        keysToDelete.add(k);
      }
      for (var key in _messagesBox.keys) {
        if (key.toString().contains('/')) continue;
        final msg = _messagesBox.get(key);
        if (msg is Map && msg['chatId'] == id) {
          _deleteImageFile(msg['imagePath'] as String?);
          keysToDelete.add(key);
        }
      }
      await _messagesBox.deleteAll(keysToDelete);
    } on HiveError {
      // Box closed — orphaned messages will be ignored on next launch.
    } catch (_) {}
  }

  // ─── Chat Messages ─────────────────────────────

  List<Map<dynamic, dynamic>> getMessagesForChat(String chatId) {
    try {
      if (!_isBoxUsable(_messagesBox)) return [];
      final prefix = '$chatId/';
      final out = <Map<dynamic, dynamic>>[];
      for (final k
          in _messagesBox.keys.where((k) => k.toString().startsWith(prefix))) {
        final v = _messagesBox.get(k);
        if (v is Map) out.add(Map<dynamic, dynamic>.from(v));
      }
      if (out.isEmpty) {
        for (final v in _messagesBox.values) {
          if (v is Map && v['chatId'] == chatId) {
            final id = v['id']?.toString() ?? '';
            if (id.isNotEmpty && !out.any((m) => m['id'] == id)) {
              out.add(Map<dynamic, dynamic>.from(v));
            }
          }
        }
      }
      return out;
    } on HiveError {
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Paged variant: newest-first window of [limit] messages older than
  /// [beforeTimestampMs] (exclusive, null = latest). Returns ASC-sorted
  /// like the unpaged version so callers sort identically.
  List<Map<dynamic, dynamic>> getMessagesForChatPaged(
    String chatId, {
    int? limit,
    int? beforeTimestampMs,
  }) {
    final all = getMessagesForChat(chatId);
    if (limit == null && beforeTimestampMs == null) return all;
    final rows = <_TsRow>[];
    for (final m in all) {
      final ts = DateTime.tryParse(m['timestamp']?.toString() ?? '');
      final ms = ts?.millisecondsSinceEpoch ?? 0;
      if (beforeTimestampMs != null && ms >= beforeTimestampMs) continue;
      rows.add(_TsRow(ms, m));
    }
    rows.sort((a, b) => b.ms.compareTo(a.ms));
    final taken =
        limit == null ? rows : rows.take(limit).toList(growable: false);
    taken.sort((a, b) => a.ms.compareTo(b.ms));
    return taken.map((r) => r.map).toList(growable: false);
  }

  /// All messages across every chat (for backup/export).
  List<Map<dynamic, dynamic>> getAllMessagesRaw() {
    try {
      if (!_isBoxUsable(_messagesBox)) return [];
      return _messagesBox.values
          .whereType<Map>()
          .map((v) => Map<dynamic, dynamic>.from(v))
          .toList();
    } on HiveError {
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<void> saveMessage(String id, Map<String, dynamic> data) async {
    try {
      if (!_isBoxUsable(_messagesBox)) return;
      final chatId = data['chatId']?.toString() ?? '';
      final key = chatId.isNotEmpty ? '$chatId/$id' : id;
      final toStore = Map<String, dynamic>.from(data);
      if (toStore['imageBase64'] is String &&
          (toStore['imageBase64'] as String).length > 8000 &&
          toStore['imagePath'] is String &&
          (toStore['imagePath'] as String).isNotEmpty) {
        toStore['imageBase64'] = null;
      }
      await _messagesBox.put(key, toStore);
    } on HiveError {
      // Box closed — message will persist on next launch.
    } catch (_) {}
  }

  Future<void> deleteMessage(String id) async {
    try {
      if (!_isBoxUsable(_messagesBox)) return;
      dynamic actualKey;
      if (_messagesBox.containsKey(id)) {
        actualKey = id;
      } else {
        for (final k in _messagesBox.keys) {
          if (k.toString().endsWith('/$id')) {
            actualKey = k;
            break;
          }
        }
      }
      if (actualKey != null) {
        final msg = _messagesBox.get(actualKey);
        if (msg is Map) _deleteImageFile(msg['imagePath'] as String?);
        await _messagesBox.delete(actualKey);
      }
    } on HiveError {
      // Box closed — message will persist on next launch.
    } catch (_) {}
  }

  // ─── Tasks ─────────────────────────────────────

  List<Map<dynamic, dynamic>> getAllTasks() {
    try {
      if (!_isBoxUsable(_tasksBox)) return [];
      return _tasksBox.values.map((v) => Map<dynamic, dynamic>.from(v)).toList();
    } on HiveError {
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<void> saveTask(String id, Map<String, dynamic> data) async {
    try {
      if (!_isBoxUsable(_tasksBox)) return;
      await _tasksBox.put(id, data);
    } on HiveError {
      // Box closed — task will persist on next launch.
    } catch (_) {}
  }

  Future<void> deleteTask(String id) async {
    try {
      if (!_isBoxUsable(_tasksBox)) return;
      await _tasksBox.delete(id);
    } on HiveError {
      // Box closed — task will persist on next launch.
    } catch (_) {}
  }

  // ─── Notifications ───────────────────────────────

  List<Map<dynamic, dynamic>> getAllNotifications() {
    try {
      if (!_isBoxUsable(_notificationsBox)) return [];
      return _notificationsBox.values
          .map((v) => Map<dynamic, dynamic>.from(v))
          .toList();
    } on HiveError {
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<void> saveNotification(
      String id, Map<String, dynamic> data) async {
    try {
      if (!_isBoxUsable(_notificationsBox)) return;
      await _notificationsBox.put(id, data);
    } on HiveError {
      // Box closed — notification will persist on next launch.
    } catch (_) {}
  }

  Future<void> deleteNotification(String id) async {
    try {
      if (!_isBoxUsable(_notificationsBox)) return;
      await _notificationsBox.delete(id);
    } on HiveError {
      // Box closed — notification will persist on next launch.
    } catch (_) {}
  }

  Future<void> clearAllNotifications() async {
    try {
      if (!_isBoxUsable(_notificationsBox)) return;
      await _notificationsBox.clear();
    } on HiveError {
      // Box closed — notifications will persist on next launch.
    } catch (_) {}
  }

  // ─── Search ────────────────────────────────────

  /// Case-insensitive full-text search across all stored messages.
  /// Returns the set of session IDs that have at least one message whose
  /// `content` contains [query] (case-insensitive). The scan runs on a
  /// worker isolate — a full-box lowercase pass per keystroke would jank
  /// the UI thread on large histories.
  Future<Set<String>> searchMessages(String query) async {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return <String>{};
    try {
      if (!_isBoxUsable(_messagesBox)) return <String>{};
      final rows = <List<String>>[];
      for (final v in _messagesBox.values) {
        if (v is Map) {
          rows.add([
            (v['content'] ?? '').toString(),
            (v['chatId'] ?? '').toString(),
          ]);
        }
      }
      return await compute(_searchRows, {'rows': rows, 'q': q});
    } catch (_) {
      return <String>{};
    }
  }

  // ─── Image History (Gallery) ─────────────────

  List<Map<dynamic, dynamic>> getAllImageHistory() {
    try {
      if (!_isBoxUsable(_imageHistoryBox)) return [];
      final list = _imageHistoryBox.values
          .map((v) => Map<dynamic, dynamic>.from(v as Map))
          .toList();
      list.sort((a, b) {
        final at = (a['timestampMs'] as num?)?.toInt() ?? 0;
        final bt = (b['timestampMs'] as num?)?.toInt() ?? 0;
        return bt.compareTo(at);
      });
      return list;
    } on HiveError {
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<void> saveImageHistory(String id, Map<String, dynamic> data) async {
    try {
      if (!_isBoxUsable(_imageHistoryBox)) return;
      await _imageHistoryBox.put(id, data);
      // Cap growth: evict oldest beyond 200 (files deleted with rows).
      if (_imageHistoryBox.length > maxImageHistory) {
        final stamps = <String, int>{};
        for (final k in _imageHistoryBox.keys) {
          final v = _imageHistoryBox.get(k);
          if (v is Map) {
            stamps[k.toString()] =
                (v['timestampMs'] as num?)?.toInt() ?? 0;
          }
        }
        final oldest = stamps.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        for (var i = 0; i < oldest.length - maxImageHistory; i++) {
          await deleteImageHistory(oldest[i].key);
        }
      }
    } on HiveError {
      // gallery write failures are non-fatal
    } catch (_) {}
  }

  Future<void> deleteImageHistory(String id) async {
    try {
      if (!_isBoxUsable(_imageHistoryBox)) return;
      final existing = _imageHistoryBox.get(id);
      if (existing is Map) _deleteImageFile(existing['path'] as String?);
      await _imageHistoryBox.delete(id);
    } on HiveError {
      // gallery delete failures are non-fatal
    } catch (_) {}
  }

  Future<void> clearImageHistory() async {
    try {
      if (!_isBoxUsable(_imageHistoryBox)) return;
      for (final v in _imageHistoryBox.values) {
        if (v is Map) _deleteImageFile(v['path'] as String?);
      }
      await _imageHistoryBox.clear();
    } on HiveError {
      // gallery clear failures are non-fatal
    } catch (_) {}
  }

  void _deleteImageFile(String? path) {
    if (path == null || path.isEmpty) return;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  // ─── Backup crypto (AES-256-CBC, same primitive as boxes) ───

  /// Magic prefix to distinguish wrong-passphrase garbage from valid JSON.
  static const String backupMagic = 'CLM1:';

  /// Encrypts [plain] with `SHA-256(passphrase)` key. Returns
  /// `IV[16] + ciphertext` bytes (IV is prepended by HiveAesCipher).
  /// Runs on a worker isolate (may be megabytes with images included).
  Future<Uint8List> encryptBackupBytes(
      Uint8List plain, String passphrase) async {
    final key =
        Uint8List.fromList(sha256.convert(utf8.encode(passphrase)).bytes);
    return compute(_encryptBackupWorker, {'plain': plain, 'key': key});
  }

  /// Decrypts bytes from [encryptBackupBytes]. Throws on wrong passphrase
  /// (bad padding) or corrupt data — callers map to 'invalid'.
  Future<Uint8List> decryptBackupBytes(
      Uint8List packed, String passphrase) async {
    final key =
        Uint8List.fromList(sha256.convert(utf8.encode(passphrase)).bytes);
    return compute(_decryptBackupWorker, {'packed': packed, 'key': key});
  }
}
