import 'dart:convert';

import 'package:get/get.dart';

import 'hive_service.dart';

/// Estimated cloud usage tracker (character-based, no provider changes).
///
/// Every [CloudService] call records input+output sizes per provider+model
/// into Hive settings JSON. Tokens are estimated at ~4 chars/token and
/// always labeled as estimates — no pricing table, so nothing goes stale.
/// A [version] counter refreshes Obx listeners after each record.
class UsageTrackerService extends GetxService {
  static const _kKey = 'cloud_usage_v1';

  final version = 0.obs;

  HiveService get _hive => Get.find<HiveService>();

  Map<String, dynamic> _read() {
    try {
      final raw = _hive.getSetting<String>(_kKey);
      if (raw == null || raw.isEmpty) return {};
      final m = jsonDecode(raw);
      return m is Map<String, dynamic> ? m : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _write(Map<String, dynamic> data) async {
    try {
      await _hive.setSetting(_kKey, jsonEncode(data));
    } catch (_) {}
    version.value++;
  }

  /// Record one completed call. Sizes are characters; tokens estimated.
  Future<void> record({
    required String provider,
    required String model,
    required int inChars,
    required int outChars,
  }) async {
    if (provider.isEmpty) return;
    try {
      final data = _read();
      final p = Map<String, dynamic>.from(data[provider] ?? {});
      p['in'] = (p['in'] as int? ?? 0) + inChars;
      p['out'] = (p['out'] as int? ?? 0) + outChars;
      p['calls'] = (p['calls'] as int? ?? 0) + 1;
      if (model.isNotEmpty) {
        final models = Map<String, dynamic>.from(p['models'] ?? {});
        final m = Map<String, dynamic>.from(models[model] ?? {});
        m['in'] = (m['in'] as int? ?? 0) + inChars;
        m['out'] = (m['out'] as int? ?? 0) + outChars;
        m['calls'] = (m['calls'] as int? ?? 0) + 1;
        models[model] = m;
        // Cap stored models per provider so the blob can't grow forever.
        if (models.length > 40) {
          final keys = models.keys.toList()..remove(model);
          for (final k in keys.take(models.length - 40)) {
            models.remove(k);
          }
        }
        p['models'] = models;
      }
      data[provider] = p;
      await _write(data);
    } catch (_) {}
  }

  /// {inTokens, outTokens, calls} summed across providers (estimates).
  Map<String, int> totals() {
    var i = 0, o = 0, c = 0;
    try {
      for (final v in _read().values) {
        if (v is! Map) continue;
        i += (v['in'] as int? ?? 0);
        o += (v['out'] as int? ?? 0);
        c += (v['calls'] as int? ?? 0);
      }
    } catch (_) {}
    return {'in': i ~/ 4, 'out': o ~/ 4, 'calls': c};
  }

  /// Per-provider estimates sorted by total desc.
  List<Map<String, dynamic>> byProvider() {
    final out = <Map<String, dynamic>>[];
    try {
      _read().forEach((provider, v) {
        if (v is! Map) return;
        final i = (v['in'] as int? ?? 0) ~/ 4;
        final o = (v['out'] as int? ?? 0) ~/ 4;
        out.add({
          'provider': provider,
          'in': i,
          'out': o,
          'calls': (v['calls'] as int? ?? 0),
        });
      });
    } catch (_) {}
    out.sort((a, b) =>
        ((b['in'] as int) + (b['out'] as int))
            .compareTo((a['in'] as int) + (a['out'] as int)));
    return out;
  }

  Future<void> reset() async {
    try {
      await _hive.setSetting(_kKey, '{}');
    } catch (_) {}
    version.value++;
  }

  /// 1250 → "1.2k", 2.5M etc.
  static String compact(int n) {
    if (n < 1000) return '$n';
    if (n < 1000000) {
      final v = n / 1000;
      return '${v.toStringAsFixed(v < 10 ? 1 : 0)}k';
    }
    final v = n / 1000000;
    return '${v.toStringAsFixed(v < 10 ? 1 : 0)}M';
  }
}
