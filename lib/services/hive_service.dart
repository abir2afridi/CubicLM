import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/constants.dart';

class HiveService extends GetxService {
  late Box _sessionsBox;
  late Box _messagesBox;
  late Box _tasksBox;
  late Box _settingsBox;
  late Box _notificationsBox;
  late Box _skillsBox;
  late Box _mcpBox;

  Box get sessionsBox => _sessionsBox;
  Box get messagesBox => _messagesBox;
  Box get tasksBox => _tasksBox;
  Box get settingsBox => _settingsBox;
  Box get notificationsBox => _notificationsBox;
  Box get skillsBox => _skillsBox;
  Box get mcpBox => _mcpBox;

  Future<HiveService> init() async {
    _sessionsBox = await Hive.openBox(AppConstants.chatSessionsBox);
    _messagesBox = await Hive.openBox(AppConstants.chatMessagesBox);
    _tasksBox = await Hive.openBox(AppConstants.tasksBox);
    _settingsBox = await Hive.openBox(AppConstants.settingsBox);
    _notificationsBox = await Hive.openBox(AppConstants.notificationsBox);
    _skillsBox = await Hive.openBox(AppConstants.skillsBox);
    _mcpBox = await Hive.openBox(AppConstants.mcpBox);
    // Preserve current local-server settings and purge obsolete provider data.
    final obsoleteServerKeys = _settingsBox.keys.where((key) =>
        key is String &&
        key.startsWith('server_') &&
        key != AppConstants.keyServerApiKey &&
        key != AppConstants.keyServerUseApiKey);
    await _settingsBox.deleteAll(obsoleteServerKeys);
    return this;
  }

  // ─── Settings helpers ───────────────────────────

  T? getSetting<T>(String key, {T? defaultValue}) {
    return _settingsBox.get(key, defaultValue: defaultValue) as T?;
  }

  Future<void> setSetting(String key, dynamic value) async {
    await _settingsBox.put(key, value);
  }

  Future<void> deleteSetting(String key) async {
    await _settingsBox.delete(key);
  }

  // ─── Chat Sessions ─────────────────────────────

  List<Map<dynamic, dynamic>> getAllSessions() {
    return _sessionsBox.values
        .map((v) => Map<dynamic, dynamic>.from(v))
        .toList();
  }

  Future<void> saveSession(String id, Map<String, dynamic> data) async {
    await _sessionsBox.put(id, data);
  }

  Future<void> deleteSession(String id) async {
    await _sessionsBox.delete(id);
    // Delete all messages for this session
    final keysToDelete = <dynamic>[];
    for (var key in _messagesBox.keys) {
      final msg = _messagesBox.get(key);
      if (msg is Map && msg['chatId'] == id) {
        keysToDelete.add(key);
      }
    }
    await _messagesBox.deleteAll(keysToDelete);
  }

  // ─── Chat Messages ─────────────────────────────

  List<Map<dynamic, dynamic>> getMessagesForChat(String chatId) {
    return _messagesBox.values
        .where((v) => v is Map && v['chatId'] == chatId)
        .map((v) => Map<dynamic, dynamic>.from(v))
        .toList();
  }

  Future<void> saveMessage(String id, Map<String, dynamic> data) async {
    await _messagesBox.put(id, data);
  }

  Future<void> deleteMessage(String id) async {
    await _messagesBox.delete(id);
  }

  // ─── Tasks ─────────────────────────────────────

  List<Map<dynamic, dynamic>> getAllTasks() {
    return _tasksBox.values.map((v) => Map<dynamic, dynamic>.from(v)).toList();
  }

  Future<void> saveTask(String id, Map<String, dynamic> data) async {
    await _tasksBox.put(id, data);
  }

  Future<void> deleteTask(String id) async {
    await _tasksBox.delete(id);
  }

  // ─── Notifications ───────────────────────────────

  List<Map<dynamic, dynamic>> getAllNotifications() {
    return _notificationsBox.values
        .map((v) => Map<dynamic, dynamic>.from(v as Map))
        .toList();
  }

  Future<void> saveNotification(
      String id, Map<String, dynamic> data) async {
    await _notificationsBox.put(id, data);
  }

  Future<void> deleteNotification(String id) async {
    await _notificationsBox.delete(id);
  }

  Future<void> clearAllNotifications() async {
    await _notificationsBox.clear();
  }
}
