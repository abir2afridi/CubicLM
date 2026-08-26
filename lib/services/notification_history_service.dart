import 'package:get/get.dart';

import '../models/notification_entry.dart';
import 'hive_service.dart';

class NotificationHistoryService extends GetxService {
  late final HiveService _hive;

  final RxList<NotificationEntry> notifications = <NotificationEntry>[].obs;

  int get unreadCount => notifications.where((n) => !n.isRead).length;

  // Keep only last 100 entries.
  static const int _maxEntries = 100;

  Future<NotificationHistoryService> init() async {
    _hive = Get.find<HiveService>();
    _load();
    return this;
  }

  void _load() {
    final raw = _hive.getAllNotifications();
    final entries = raw.map((m) => NotificationEntry.fromMap(m)).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    notifications.assignAll(entries);
  }

  Future<void> add({
    required String title,
    required String message,
    String type = 'model_switched',
    String iconName = 'layers',
  }) async {
    final entry = NotificationEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      message: message,
      type: type,
      iconName: iconName,
      timestamp: DateTime.now(),
      isRead: false,
    );
    notifications.insert(0, entry);
    if (notifications.length > _maxEntries) {
      final overflow = notifications.sublist(_maxEntries);
      for (final n in overflow) {
        await _hive.deleteNotification(n.id);
      }
      notifications.removeRange(_maxEntries, notifications.length);
    }
    await _hive.saveNotification(entry.id, entry.toMap());
  }

  Future<void> markAllRead() async {
    bool changed = false;
    for (var i = 0; i < notifications.length; i++) {
      if (!notifications[i].isRead) {
        final updated = notifications[i].copyWith(isRead: true);
        notifications[i] = updated;
        await _hive.saveNotification(updated.id, updated.toMap());
        changed = true;
      }
    }
    if (changed) notifications.refresh();
  }

  Future<void> markRead(String id) async {
    final idx = notifications.indexWhere((n) => n.id == id);
    if (idx == -1 || notifications[idx].isRead) return;
    final updated = notifications[idx].copyWith(isRead: true);
    notifications[idx] = updated;
    await _hive.saveNotification(id, updated.toMap());
  }

  Future<void> delete(String id) async {
    notifications.removeWhere((n) => n.id == id);
    await _hive.deleteNotification(id);
  }

  Future<void> clearAll() async {
    notifications.clear();
    await _hive.clearAllNotifications();
  }
}
