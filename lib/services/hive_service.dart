import 'dart:async';

import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/constants.dart';

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
  late Box _sessionsBox;
  late Box _messagesBox;
  late Box _tasksBox;
  late Box _settingsBox;
  late Box _notificationsBox;
  late Box _skillsBox;
  late Box _mcpBox;

  bool _isFallback = false;
  bool get isFallback => _isFallback;

  Box get sessionsBox => _sessionsBox;
  Box get messagesBox => _messagesBox;
  Box get tasksBox => _tasksBox;
  Box get settingsBox => _settingsBox;
  Box get notificationsBox => _notificationsBox;
  Box get skillsBox => _skillsBox;
  Box get mcpBox => _mcpBox;

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
    // Try normal open with short timeout.
    try {
      return await Hive.openBox(name)
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // Try delete + retry once.
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

  Future<HiveService> init() async {
    // Open each box individually so one corrupted box doesn't kill all 7.
    final results = await Future.wait<Box>([
      _openBoxWithFallback(AppConstants.chatSessionsBox),
      _openBoxWithFallback(AppConstants.chatMessagesBox),
      _openBoxWithFallback(AppConstants.tasksBox),
      _openBoxWithFallback(AppConstants.settingsBox),
      _openBoxWithFallback(AppConstants.notificationsBox),
      _openBoxWithFallback(AppConstants.skillsBox),
      _openBoxWithFallback(AppConstants.mcpBox),
    ]);
    _sessionsBox = results[0];
    _messagesBox = results[1];
    _tasksBox = results[2];
    _settingsBox = results[3];
    _notificationsBox = results[4];
    _skillsBox = results[5];
    _mcpBox = results[6];

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

  T? getSetting<T>(String key, {T? defaultValue}) {
    try {
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
          .map((v) => Map<dynamic, dynamic>.from(v as Map))
          .toList();
    } on HiveError {
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<void> saveSession(String id, Map<String, dynamic> data) async {
    try {
      if (!_isBoxUsable(_sessionsBox)) return;
      await _sessionsBox.put(id, data);
    } on HiveError {
      // Box closed — data will persist on next launch.
    } catch (_) {}
  }

  Future<void> deleteSession(String id) async {
    try {
      if (_isBoxUsable(_sessionsBox)) await _sessionsBox.delete(id);
    } on HiveError {
      // Box closed — session data will persist on next launch.
    } catch (_) {}
    // Delete all messages for this session
    try {
      if (!_isBoxUsable(_messagesBox)) return;
      final keysToDelete = <dynamic>[];
      for (var key in _messagesBox.keys) {
        final msg = _messagesBox.get(key);
        if (msg is Map && msg['chatId'] == id) {
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
      return _messagesBox.values
          .where((v) => v is Map && v['chatId'] == chatId)
          .map((v) => Map<dynamic, dynamic>.from(v as Map))
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
      await _messagesBox.put(id, data);
    } on HiveError {
      // Box closed — message will persist on next launch.
    } catch (_) {}
  }

  Future<void> deleteMessage(String id) async {
    try {
      if (!_isBoxUsable(_messagesBox)) return;
      await _messagesBox.delete(id);
    } on HiveError {
      // Box closed — message will persist on next launch.
    } catch (_) {}
  }

  // ─── Tasks ─────────────────────────────────────

  List<Map<dynamic, dynamic>> getAllTasks() {
    try {
      if (!_isBoxUsable(_tasksBox)) return [];
      return _tasksBox.values.map((v) => Map<dynamic, dynamic>.from(v as Map)).toList();
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
          .map((v) => Map<dynamic, dynamic>.from(v as Map))
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
}
