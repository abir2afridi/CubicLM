import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';

import '../hive_service.dart';
import 'mcp_config.dart';
import 'mcp_connection.dart';

class McpRegistryService extends GetxService with WidgetsBindingObserver {
  static const String _tokenKey = 'mcp_bearer_token';

  late final HiveService _hive;
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  final Rxn<McpConfig> config = Rxn<McpConfig>();
  final Rx<McpStatus> status = McpStatus.disconnected.obs;
  final RxString lastError = ''.obs;
  final RxList<McpTool> tools = <McpTool>[].obs;

  McpConnection? _connection;
  StreamSubscription<McpStatus>? _statusSub;

  Future<McpRegistryService> init() async {
    _hive = Get.find<HiveService>();
    _loadConfig();
    WidgetsBinding.instance.addObserver(this);
    // If config exists and enabled, try to connect lazily (don't block init).
    if (config.value != null && config.value!.enabled) {
      unawaited(connect());
    }
    return this;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      // Safe to call repeatedly; disconnect keeps tools cached for next send.
      unawaited(disconnect());
    } else if (state == AppLifecycleState.resumed) {
      if (config.value?.enabled == true && status.value == McpStatus.disconnected) {
        unawaited(connect());
      }
    }
  }

  void _loadConfig() {
    final raw = _hive.mcpBox.get('config');
    if (raw is Map) {
      try {
        config.value = McpConfig.fromMap(Map<dynamic, dynamic>.from(raw));
      } catch (_) {
        config.value = null;
      }
    }
  }

  Future<void> saveConfig(McpConfig c) async {
    config.value = c;
    await _hive.mcpBox.put('config', c.toMap());
    // If enabled changed, reconnect or disconnect.
    if (c.enabled) {
      await connect();
    } else {
      await disconnect();
    }
  }

  Future<void> removeConfig() async {
    await disconnect();
    config.value = null;
    await _hive.mcpBox.delete('config');
    await _secure.delete(key: _tokenKey);
    tools.clear();
    status.value = McpStatus.disconnected;
  }

  // ── Secure token ──
  Future<void> setToken(String token) async {
    final v = token.trim();
    if (v.isEmpty) {
      await _secure.delete(key: _tokenKey);
    } else {
      await _secure.write(key: _tokenKey, value: v);
    }
  }

  Future<String?> getToken() async {
    try {
      return await _secure.read(key: _tokenKey);
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasToken() async {
    final t = await getToken();
    return t != null && t.isNotEmpty;
  }

  // ── Connection ──
  Future<List<McpTool>> connect() async {
    final c = config.value;
    if (c == null || !c.isValid) {
      status.value = McpStatus.error;
      lastError.value = 'No server configured';
      throw McpError('No server configured');
    }
    // Dispose previous connection.
    await _connection?.disconnect();
    _connection?.dispose();
    _statusSub?.cancel();

    final conn = McpConnection(
      config: c,
      getAuthToken: getToken,
    );
    _connection = conn;
    _statusSub = conn.statusStream.listen((s) {
      status.value = s;
      lastError.value = conn.lastError ?? '';
      if (s == McpStatus.connected) {
        tools.assignAll(conn.cachedTools);
      }
    });

    try {
      final t = await conn.connect();
      tools.assignAll(t);
      status.value = McpStatus.connected;
      return t;
    } catch (e) {
      lastError.value = e.toString();
      rethrow;
    }
  }

  Future<void> disconnect() async {
    await _connection?.disconnect();
    _connection?.dispose();
    _connection = null;
    await _statusSub?.cancel();
    _statusSub = null;
    status.value = McpStatus.disconnected;
    tools.clear();
  }

  Future<void> testConnection() async {
    await connect();
  }

  Future<Map<String, dynamic>> callTool(
      String name, Map<String, dynamic> args) async {
    final conn = _connection;
    if (conn == null || status.value != McpStatus.connected) {
      throw McpError('Not connected');
    }
    return conn.callTool(name, args);
  }

  List<McpTool> get cachedTools => List.unmodifiable(tools);

  bool get isEnabledAndConnected =>
      config.value?.enabled == true && status.value == McpStatus.connected;

  bool get isConfigured => config.value != null && config.value!.isValid;

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _connection?.dispose();
    _statusSub?.cancel();
    super.onClose();
  }
}
