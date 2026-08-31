import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';

import 'app_log_service.dart';

/// Stores all cloud-provider API keys in platform secure storage
/// (Android Keystore / iOS Keychain / Windows DPAPI) instead of the
/// plaintext Hive settings box.
class SecureKeyStore extends GetxService {
  static const _optionKey = 'clm_key_';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  final Map<String, String> _cache = {};

  bool _initialized = false;

  Future<SecureKeyStore> init() async {
    if (_initialized) return this;
    _initialized = true;
    try {
      final all = await _storage.readAll();
      for (final e in all.entries) {
        if (e.key.startsWith(_optionKey)) {
          _cache[e.key.substring(_optionKey.length)] = e.value;
        }
      }
    } catch (e) {
      _log('readAll failed: $e');
    }
    return this;
  }

  void _log(String msg) {
    if (Get.isRegistered<AppLogService>()) {
      Get.find<AppLogService>()
          .info('[SecureKeyStore] $msg', category: LogCategory.system);
    }
  }

  /// Reads a key. Returns '' when absent (never throws).
  String read(String optionKey) {
    return _cache[optionKey] ?? '';
  }

  /// Writes a key and persists it. Empty value deletes the entry.
  Future<void> write(String optionKey, String value) async {
    final v = value.trim();
    if (v.isEmpty) {
      _cache.remove(optionKey);
      try {
        await _storage.delete(key: _optionKey + optionKey);
      } catch (e) {
        _log('delete failed for $optionKey: $e');
      }
      return;
    }
    _cache[optionKey] = v;
    try {
      await _storage.write(key: _optionKey + optionKey, value: v);
    } catch (e) {
      _log('write failed for $optionKey: $e');
    }
  }

  bool has(String optionKey) => read(optionKey).isNotEmpty;

  Future<void> delete(String optionKey) => write(optionKey, '');
}
