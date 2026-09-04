import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';

import '../hive_service.dart';
import 'mcp_config.dart';
import 'mcp_connection.dart';

/// Per-server live state.
class _Slot {
  final McpConfig config;
  McpConnection? connection;
  StreamSubscription<McpStatus>? sub;
  List<McpTool> tools = const [];
  _Slot(this.config);
}

/// Multi-server MCP registry.
///
/// Each configured server gets its own connection, token slot, and status.
/// [tools] merges every connected server's tools; on name collision the
/// exposed name is prefixed `<server>__<tool>` and [callTool] routes back
/// to the owning connection. Single-server consumers keep working through
/// the aggregate getters ([config], [status], [isEnabledAndConnected]).
class McpRegistryService extends GetxService with WidgetsBindingObserver {
  static const String _legacyTokenKey = 'mcp_bearer_token';
  static const String _legacyConfigKey = 'config';
  static const String _configsKey = 'configs';
  static String _tokenKeyFor(String id) => 'mcp_bearer_token_$id';

  late final HiveService _hive;
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  /// All saved servers (enabled or not).
  final RxList<McpConfig> configs = <McpConfig>[].obs;

  /// Per-server status / error, keyed by config id.
  final RxMap<String, McpStatus> statuses = <String, McpStatus>{}.obs;
  final RxMap<String, String> errors = <String, String>{}.obs;

  /// Merged tools across connected servers (collision-prefixed).
  final RxList<McpTool> tools = <McpTool>[].obs;

  // ── Aggregate (back-compat with single-server consumers) ──
  final Rx<McpStatus> status = McpStatus.disconnected.obs;
  final RxString lastError = ''.obs;

  /// First enabled config, else first config, else null. Kept as a real
  /// field (not a computed getter) so Obx stays reactive.
  final Rxn<McpConfig> config = Rxn<McpConfig>();

  final Map<String, _Slot> _slots = {};
  final Map<String, String> _toolOwner = {}; // exposed name -> server id
  final Map<String, String> _toolOriginal = {}; // exposed name -> real name

  Future<McpRegistryService> init() async {
    _hive = Get.find<HiveService>();
    await _migrateLegacy();
    _loadConfigs();
    WidgetsBinding.instance.addObserver(this);
    // Lazily connect enabled servers (don't block init).
    unawaited(connect());
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
      if (_slots.values.any((s) =>
          s.config.enabled &&
          (statuses[s.config.id] ?? McpStatus.disconnected) ==
              McpStatus.disconnected)) {
        unawaited(connect());
      }
    }
  }

  // ── Persistence + migration ──

  /// One-time: legacy single 'config' (+ shared token) → configs list with
  /// per-server id + token slot.
  Future<void> _migrateLegacy() async {
    try {
      if (_hive.mcpBox.containsKey(_configsKey)) return;
      final raw = _hive.mcpBox.get(_legacyConfigKey);
      if (raw is! Map) return;
      final id = _newId();
      final cfg =
          McpConfig.fromMap(Map<dynamic, dynamic>.from(raw)).copyWith(id: id);
      await _hive.mcpBox.put(_configsKey, [cfg.toMap()]);
      try {
        final tok = await _secure.read(key: _legacyTokenKey);
        if (tok != null && tok.isNotEmpty) {
          await _secure.write(key: _tokenKeyFor(id), value: tok);
          await _secure.delete(key: _legacyTokenKey);
        }
      } catch (_) {}
      await _hive.mcpBox.delete(_legacyConfigKey);
    } catch (_) {}
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  void _loadConfigs() {
    try {
      final raw = _hive.mcpBox.get(_configsKey);
      if (raw is List) {
        configs.assignAll(raw
            .whereType<Map>()
            .map((e) => McpConfig.fromMap(Map<dynamic, dynamic>.from(e))));
      }
    } catch (_) {}
    for (final c in configs) {
      statuses.putIfAbsent(c.id, () => McpStatus.disconnected);
      _slots.putIfAbsent(c.id, () => _Slot(c));
    }
    _refreshPrimary();
  }

  /// First enabled config, else first — keeps [config] reactive.
  void _refreshPrimary() {
    McpConfig? pick;
    for (final c in configs) {
      if (c.enabled) {
        pick = c;
        break;
      }
    }
    config.value = pick ?? (configs.isEmpty ? null : configs.first);
  }

  Future<void> _persistConfigs() async {
    try {
      await _hive.mcpBox
          .put(_configsKey, configs.map((c) => c.toMap()).toList());
    } catch (_) {}
  }

  // ── CRUD ──

  /// Upserts a server, returns its id. Connects/disconnects on enable flip.
  Future<String> saveConfig(McpConfig c) async {
    final cfg = c.id.isEmpty ? c.copyWith(id: _newId()) : c;
    final idx = configs.indexWhere((e) => e.id == cfg.id);
    if (idx >= 0) {
      configs[idx] = cfg;
    } else {
      configs.add(cfg);
    }
    statuses.putIfAbsent(cfg.id, () => McpStatus.disconnected);
    final old = _slots[cfg.id];
    _slots[cfg.id] = _Slot(cfg)
      ..connection = old?.connection
      ..sub = old?.sub
      ..tools = old?.tools ?? const [];
    await _persistConfigs();
    configs.refresh();
    _refreshPrimary();
    if (cfg.enabled) {
      await connect(id: cfg.id);
    } else {
      await disconnect(id: cfg.id);
    }
    return cfg.id;
  }

  Future<void> removeConfig(String id) async {
    await disconnect(id: id);
    configs.removeWhere((c) => c.id == id);
    statuses.remove(id);
    errors.remove(id);
    _slots.remove(id);
    try {
      await _secure.delete(key: _tokenKeyFor(id));
    } catch (_) {}
    await _persistConfigs();
    _refreshPrimary();
    _rebuildTools();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final idx = configs.indexWhere((c) => c.id == id);
    if (idx < 0) return;
    configs[idx] = configs[idx].copyWith(enabled: enabled);
    await _persistConfigs();
    configs.refresh();
    _refreshPrimary();
    if (enabled) {
      await connect(id: id);
    } else {
      await disconnect(id: id);
    }
  }

  // ── Secure tokens (per server) ──

  Future<void> setToken(String id, String token) async {
    final v = token.trim();
    try {
      if (v.isEmpty) {
        await _secure.delete(key: _tokenKeyFor(id));
      } else {
        await _secure.write(key: _tokenKeyFor(id), value: v);
      }
    } catch (_) {}
  }

  Future<String?> getToken([String? id]) async {
    try {
      if (id != null) return await _secure.read(key: _tokenKeyFor(id));
      // Legacy single-token callers: first server that has one.
      for (final c in configs) {
        final t = await _secure.read(key: _tokenKeyFor(c.id));
        if (t != null && t.isNotEmpty) return t;
      }
      return await _secure.read(key: _legacyTokenKey);
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasToken(String id) async {
    final t = await getToken(id);
    return t != null && t.isNotEmpty;
  }

  // ── Connections ──

  /// Connects one server ([id]) or every enabled server. Returns merged tools.
  Future<List<McpTool>> connect({String? id}) async {
    final targets = configs
        .where((c) => c.enabled && (id == null || c.id == id))
        .toList();
    if (targets.isEmpty) {
      if (id != null) {
        statuses[id] = McpStatus.error;
        lastError.value = 'No server configured';
        throw McpError('No server configured');
      }
      return cachedTools;
    }
    final all = <McpTool>[];
    for (final c in targets) {
      try {
        final t = await _connectOne(c);
        all.addAll(t);
      } catch (e) {
        lastError.value = '${c.name}: $e';
      }
    }
    return cachedTools;
  }

  Future<List<McpTool>> _connectOne(McpConfig c) async {
    final slot = _slots.putIfAbsent(c.id, () => _Slot(c));
    await slot.connection?.disconnect();
    slot.connection?.dispose();
    await slot.sub?.cancel();

    statuses[c.id] = McpStatus.connecting;
    final conn = McpConnection(
      config: c,
      getAuthToken: () => getToken(c.id),
    );
    slot.connection = conn;
    slot.sub = conn.statusStream.listen((s) {
      statuses[c.id] = s;
      errors[c.id] = conn.lastError ?? '';
      if (s == McpStatus.connected) {
        slot.tools = List.unmodifiable(conn.cachedTools);
      } else if (s == McpStatus.error) {
        lastError.value = '${c.name}: ${conn.lastError ?? 'error'}';
      }
      _rebuildTools();
    });

    try {
      final t = await conn.connect();
      slot.tools = List.unmodifiable(t);
      statuses[c.id] = McpStatus.connected;
      errors[c.id] = '';
      _rebuildTools();
      return t;
    } catch (e) {
      statuses[c.id] = McpStatus.error;
      errors[c.id] = e.toString();
      lastError.value = '${c.name}: $e';
      _rebuildTools();
      rethrow;
    }
  }

  /// Disconnects one server ([id]) or all. Cached tools survive for sends.
  Future<void> disconnect({String? id}) async {
    final ids =
        id == null ? _slots.keys.toList() : (_slots.containsKey(id) ? [id] : const <String>[]);
    for (final sid in ids) {
      final slot = _slots[sid];
      try {
        await slot?.connection?.disconnect();
        slot?.connection?.dispose();
        await slot?.sub?.cancel();
      } catch (_) {}
      if (slot != null) {
        slot.connection = null;
        slot.sub = null;
      }
      statuses[sid] = McpStatus.disconnected;
    }
    _recomputeAggregate();
  }

  Future<void> testConnection(String id) async {
    await connect(id: id);
  }

  Future<Map<String, dynamic>> callTool(
      String name, Map<String, dynamic> args) async {
    final ownerId = _toolOwner[name];
    McpConnection? conn;
    String realName = _toolOriginal[name] ?? name;
    if (ownerId != null) {
      conn = _slots[ownerId]?.connection;
    } else {
      // Back-compat: single connected server answers unprefixed names.
      final live = _slots.values.where((s) =>
          s.connection != null &&
          (statuses[s.config.id] == McpStatus.connected));
      if (live.length == 1) conn = live.first.connection;
    }
    if (conn == null) throw McpError('Not connected');
    return conn.callTool(realName, args);
  }

  List<McpTool> get cachedTools => List.unmodifiable(tools);

  /// Merged tools exposed by one server (for per-server badges).
  List<McpTool> toolsFor(String id) {
    final out = <McpTool>[];
    for (final t in tools) {
      if (_toolOwner[t.name] == id) out.add(t);
    }
    return out;
  }

  bool get isEnabledAndConnected => _slots.values.any((s) =>
      s.config.enabled &&
      (statuses[s.config.id] ?? McpStatus.disconnected) ==
          McpStatus.connected);

  bool get isConfigured =>
      configs.any((c) => c.isValid);

  McpStatus statusOf(String id) =>
      statuses[id] ?? McpStatus.disconnected;

  // ── Merge ──

  /// Rebuilds [tools] + owner routing + aggregate status.
  void _rebuildTools() {
    _toolOwner.clear();
    _toolOriginal.clear();
    final counts = <String, int>{};
    for (final slot in _slots.values) {
      if ((statuses[slot.config.id] ?? McpStatus.disconnected) !=
          McpStatus.connected) {
        continue;
      }
      for (final t in slot.tools) {
        counts[t.name] = (counts[t.name] ?? 0) + 1;
      }
    }
    final merged = <McpTool>[];
    for (final slot in _slots.values) {
      if ((statuses[slot.config.id] ?? McpStatus.disconnected) !=
          McpStatus.connected) {
        continue;
      }
      final slug = _slug(slot.config.name);
      for (final t in slot.tools) {
        final exposed =
            (counts[t.name] ?? 0) > 1 ? '${slug}__${t.name}' : t.name;
        _toolOwner[exposed] = slot.config.id;
        _toolOriginal[exposed] = t.name;
        merged.add(exposed == t.name
            ? t
            : McpTool(
                name: exposed,
                description: '[${slot.config.name}] ${t.description}',
                inputSchema: t.inputSchema,
              ));
      }
    }
    tools.assignAll(merged);
    _recomputeAggregate();
  }

  void _recomputeAggregate() {
    McpStatus agg = McpStatus.disconnected;
    String err = '';
    for (final slot in _slots.values) {
      final s = statuses[slot.config.id] ?? McpStatus.disconnected;
      if (s == McpStatus.connected) {
        agg = McpStatus.connected;
        break;
      }
      if (s == McpStatus.connecting) agg = McpStatus.connecting;
      if (s == McpStatus.error && agg == McpStatus.disconnected) {
        agg = McpStatus.error;
        err = errors[slot.config.id] ?? '';
      }
    }
    status.value = agg;
    if (err.isNotEmpty) lastError.value = err;
  }

  String _slug(String name) {
    final s = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    if (s.isEmpty) return 'srv';
    return s.length <= 12 ? s : s.substring(0, 12);
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final slot in _slots.values) {
      slot.connection?.dispose();
      slot.sub?.cancel();
    }
    super.onClose();
  }
}
