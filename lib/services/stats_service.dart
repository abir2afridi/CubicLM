import 'dart:async';

import 'package:get/get.dart';

import 'hive_service.dart';
/// Opt-in, local-only usage statistics. No backend, no telemetry leaves
/// the device — counts live in Hive and can be wiped with one tap.
/// Events: chat_sent, image_generated, model_loaded, cloud_call.
class StatsService extends GetxService {
  static const _kEnabled = 'stats_enabled';
  static const _kCounts = 'stats_counts';

  static const eventChatSent = 'chat_sent';
  static const eventImageGenerated = 'image_generated';
  static const eventModelLoaded = 'model_loaded';
  static const eventCloudCall = 'cloud_call';

  final enabled = false.obs;
  final version = 0.obs; // refresh trigger for viewers

  HiveService get _hive {
    try {
      return Get.find<HiveService>();
    } catch (_) {
      throw StateError('no-hive');
    }
  }

  Future<StatsService> init() async {
    try {
      enabled.value =
          _hive.getSetting<bool>(_kEnabled, defaultValue: false) ?? false;
    } catch (_) {}
    return this;
  }

  Future<void> setEnabled(bool v) async {
    enabled.value = v;
    try {
      await _hive.setSetting(_kEnabled, v);
    } catch (_) {}
    version.value++;
  }

  /// Increment [event]. Silent no-op unless opted in. Never throws.
  Future<void> count(String event) async {
    if (!enabled.value) return;
    try {
      final raw = _hive.getSetting<Map>(_kCounts);
      final map = <String, int>{};
      if (raw != null) {
        for (final e in raw.entries) {
          final v = e.value;
          map[e.key.toString()] =
              v is int ? v : int.tryParse(v.toString()) ?? 0;
        }
      }
      map[event] = (map[event] ?? 0) + 1;
      await _hive.setSetting(_kCounts, map);
      version.value++;
    } catch (_) {}
  }

  Map<String, int> snapshot() {    try {
      final raw = _hive.getSetting<Map>(_kCounts);
      if (raw == null) return {};
      final map = <String, int>{};
      for (final e in raw.entries) {
        final v = e.value;
        map[e.key.toString()] =
            v is int ? v : int.tryParse(v.toString()) ?? 0;
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  Future<void> reset() async {
    try {
      await _hive.setSetting(_kCounts, <String, int>{});
    } catch (_) {}
    version.value++;
  }

  static String label(String event) {
    switch (event) {
      case eventChatSent:
        return 'Messages sent';
      case eventImageGenerated:
        return 'Images generated';
      case eventModelLoaded:
        return 'Models loaded';
      case eventCloudCall:
        return 'Cloud calls';
      default:
        return event;
    }
  }

  /// Fire-and-forget counter from anywhere. No-op when the service is
  /// unregistered or the user never opted in. Never throws.
  static void tap(String event) {
    try {
      if (Get.isRegistered<StatsService>()) {
        unawaited(Get.find<StatsService>().count(event));
      }
    } catch (_) {}
  }
}
