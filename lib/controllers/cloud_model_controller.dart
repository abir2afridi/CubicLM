import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../core/constants.dart';
import '../utils/app_snackbar.dart';
import '../services/app_log_service.dart';
import '../services/cloud/cloud_provider_registry.dart';
import '../services/cloud/model_health.dart';
import '../services/cloud_service.dart';
import '../services/hive_service.dart';
import '../services/inference_service.dart';
import '../services/local_image_service.dart';
import 'settings_controller.dart';

class CloudProviderInfo {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final bool requiresKeyForList;
  final bool supportsFetch;

  const CloudProviderInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    this.requiresKeyForList = true,
    this.supportsFetch = true,
  });
}

class CloudModelController extends GetxController {
  final HiveService _hive = Get.find<HiveService>();
  final SettingsController _settings = Get.find<SettingsController>();

  static const _cachePrefix = 'cloud_model_cache_';
  static const _cacheTimePrefix = 'cloud_model_cache_time_';
  static const _workingUrlPrefix = 'cloud_model_working_url_';
  static const _discoveredProvidersKey = 'cloud_discovered_providers';
  static const _healthPrefix = 'cloud_model_health_';
  static const _autoHideKey = 'cloud_auto_hide_failed';
  static const _syncIntervalKey = 'cloud_sync_interval_hours';
  static const _lastAutoSyncKey = 'cloud_last_auto_sync';
  static const _keyTimePrefix = 'cloud_key_set_at_';
  static const _pinnedKey = 'cloud_pinned_providers';
  static const _sortModeKey = 'cloud_provider_sort';

  static const _knownCompanyIcons = <String, IconData>{
    'openai': Icons.auto_awesome,
    'anthropic': Icons.psychology_outlined,
    'google': Icons.diamond_outlined,
    'meta': Icons.tag,
    'meta-llama': Icons.tag,
    'mistral': Icons.water_outlined,
    'mistralai': Icons.water_outlined,
    'nvidia': Icons.memory_outlined,
    'deepseek': Icons.psychology_alt_outlined,
    'xiaomi': Icons.phone_android,
    'qwen': Icons.smart_toy_outlined,
    'microsoft': Icons.window,
    'cohere': Icons.workspaces_outlined,
    'alibaba': Icons.storefront_outlined,
    'amazon': Icons.shopping_bag_outlined,
    'huggingface': Icons.emoji_emotions_outlined,
    'ibm': Icons.computer_outlined,
    'databricks': Icons.analytics_outlined,
    'minimax': Icons.tune,
    '01': Icons.looks_one_outlined,
    'moonshot': Icons.nightlight_round,
    'zhipu': Icons.account_balance,
    'yi': Icons.hourglass_bottom,
    'dbrx': Icons.route,
    'command': Icons.record_voice_over,
    'gemma': Icons.diamond_outlined,
    'phi': Icons.science_outlined,
    'stability': Icons.photo_library_outlined,
    'midjourney': Icons.brush_outlined,
    'flux': Icons.flutter_dash_outlined,
  };

  static const _knownCompanyNames = <String, String>{
    'openai': 'OpenAI',
    'anthropic': 'Anthropic',
    'google': 'Google',
    'meta': 'Meta',
    'meta-llama': 'Meta Llama',
    'mistral': 'Mistral AI',
    'mistralai': 'Mistral AI',
    'nvidia': 'NVIDIA',
    'deepseek': 'DeepSeek',
    'xiaomi': 'Xiaomi',
    'qwen': 'Alibaba Qwen',
    'microsoft': 'Microsoft',
    'cohere': 'Cohere',
    'alibaba': 'Alibaba',
    'amazon': 'Amazon',
    'huggingface': 'Hugging Face',
    'ibm': 'IBM',
    'databricks': 'Databricks',
    'minimax': 'MiniMax',
    '01': '01.AI',
    'moonshot': 'Moonshot AI',
    'zhipu': 'Zhipu AI',
    'yi': '01.AI Yi',
    'gemma': 'Google Gemma',
    'phi': 'Microsoft Phi',
    'stability': 'Stability AI',
  };

  static const _defaultModelsByProvider = <String, List<String>>{
    'openrouter': [
      'openai/gpt-3.5-turbo',
      'openai/gpt-4o-mini',
      'openai/gpt-4o',
      'openai/gpt-4.1',
      'anthropic/claude-3.5-sonnet',
      'google/gemini-2.5-flash',
      'google/gemma-3-27b-it',
      'deepseek/deepseek-chat',
      'meta-llama/llama-3.1-8b-instruct',
      'meta-llama/llama-4-scout-17b-16e-instruct',
      'nvidia/nemotron-3-8b- ultra',
      'nvidia/llama-3.1-nemotron-70b-instruct',
      'xiaomi/mimo-2.5',
      'qwen/qwen3-235b-a22b',
      'microsoft/phi-4',
      'mistralai/mistral-small-3.1-24b-instruct',
    ],
    'openai': [
      'gpt-5.2',
      'gpt-5.1',
      'gpt-4.1',
      'gpt-4.1-mini',
      'gpt-4o',
      'gpt-4o-mini',
      'gpt-3.5-turbo',
      'gpt-3.5-turbo-16k',
      'o3',
      'o3-mini',
      'o4-mini',
    ],
    'deepseek': [
      'deepseek-v4-flash',
      'deepseek-v4-pro',
      'deepseek-chat',
      'deepseek-reasoner',
      'deepseek-coder',
    ],
    'google': [
      'gemini-2.5-flash',
      'gemini-2.5-pro',
      'gemini-2.0-flash',
      'gemini-2.0-flash-lite',
      'gemma-3-27b-it',
      'gemma-3-12b-it',
      'gemma-3-4b-it',
    ],
    'nvidia': [
      'meta/llama-3.1-8b-instruct',
      'meta/llama-3.1-70b-instruct',
      'meta/llama-3.3-70b-instruct',
      'meta/llama-4-scout-17b-16e-instruct',
      'mistralai/mixtral-8x7b-instruct-v0.1',
      'nvidia/llama-3.1-nemotron-70b-instruct',
      'nvidia/nemotron-3-8b-ultra',
      'nvidia/nemotron-mini-4b-instruct',
      'xiaomi/mimo-2.5',
      'qwen/qwen3-235b-a22b',
      'deepseek/deepseek-r1',
    ],
    'zai': [
      'glm-4.7-flash',
      'glm-4.5-flash',
      'glm-4.6v-flash',
      'glm-4.7-flashx',
      'glm-4.7',
      'glm-4.6',
      'glm-4.5',
      'glm-4.5-air',
      'glm-4-32b-0414-128k',
      'glm-5.3',
      'glm-5.2',
      'glm-5.1',
      'glm-5',
      'glm-5-turbo',
      'glm-5v-turbo',
      'glm-4.5v',
      'glm-4.6v',
      'glm-4.5x',
      'glm-4.5-airx',
      'glm-ocr',
      'glm-4.6v-flashx',
    ],
    'anthropic': [
      'claude-sonnet-4-5',
      'claude-opus-4-1',
      'claude-haiku-4-5',
      'claude-3-7-sonnet-latest',
      'claude-3-5-haiku-latest',
    ],
    'kimi': [
      'kimi-k2.6',
      'kimi-k2-turbo-preview',
      'kimi-k2-0905-preview',
      'moonshot-v1-128k',
    ],
    'groq': [
      'llama-3.3-70b-versatile',
      'llama-3.1-8b-instant',
      'meta-llama/llama-4-scout-17b-16e-instruct',
      'openai/gpt-oss-120b',
      'qwen/qwen3-32b',
      'deepseek-r1-distill-llama-70b',
      'moonshotai/kimi-k2-instruct',
      'gemma2-9b-it',
    ],
    'mistral': [
      'mistral-large-latest',
      'mistral-medium-latest',
      'mistral-small-latest',
      'magistral-medium-latest',
      'codestral-latest',
      'pixtral-large-latest',
      'ministral-8b-latest',
      'open-mistral-nemo',
    ],
    'together': [
      'meta-llama/Llama-3.3-70B-Instruct-Turbo',
      'meta-llama/Meta-Llama-3.1-8B-Instruct-Turbo',
      'deepseek-ai/DeepSeek-V3',
      'Qwen/Qwen2.5-72B-Instruct-Turbo',
      'mistralai/Mixtral-8x7B-Instruct-v0.1',
      'lgai/exaone-3-5-32b-instruct',
    ],
    'xai': [
      'grok-4',
      'grok-4-fast',
      'grok-code-fast-1',
      'grok-3',
      'grok-3-mini',
      'grok-2-vision-1212',
    ],
    'perplexity': [
      'sonar-pro',
      'sonar',
      'sonar-reasoning-pro',
      'sonar-deep-research',
    ],
    'cerebras': [
      'llama-3.3-70b',
      'llama3.1-8b',
      'qwen-3-32b',
      'gpt-oss-120b',
    ],
    'fireworks': [
      'accounts/fireworks/models/llama-v3p3-70b-instruct',
      'accounts/fireworks/models/deepseek-v3',
      'accounts/fireworks/models/qwen2p5-72b-instruct',
      'accounts/fireworks/models/mixtral-8x22b-instruct',
    ],
    'cohere': [
      'command-a-03-2025',
      'command-r-plus-08-2024',
      'command-r-08-2024',
      'aya-expanse-8b',
    ],
    'huggingface': [
      'meta-llama/Llama-3.3-70B-Instruct',
      'deepseek-ai/DeepSeek-V3',
      'Qwen/Qwen2.5-72B-Instruct',
      'mistralai/Mistral-Small-24B-Instruct-2501',
      'moonshotai/Kimi-K2-Instruct',
    ],
    'xkiro': [
      'openai/gpt-5.2',
      'anthropic/claude-sonnet-4.6',
      'google/gemini-3-flash-preview',
      'deepseek/deepseek-v3.2',
      'z-ai/glm-4.7',
      'qwen/qwen3.7-max',
    ],
    'tokenrouter': [
      'openai/gpt-5.2',
      'anthropic/claude-opus-4.8',
      'z-ai/glm-5.3',
      'deepseek/deepseek-v4-pro',
      'xiaomi/mimo-v2.5',
      'nvidia/nemotron-3-super-120b-a12b',
      'moonshotai/kimi-k2.6',
      'minimax/minimax-m2.7',
    ],
  };

  final allProviders = <CloudProviderInfo>[].obs;

  List<CloudProviderInfo> get providers => allProviders;

  final modelsByProvider = <String, List<String>>{}.obs;
  final fetchedAtByProvider = <String, DateTime>{}.obs;
  final isLoadingProvider = <String, bool>{}.obs;
  final errorByProvider = <String, String>{}.obs;
  final searchByProvider = <String, String>{}.obs;
  final companyFilterByProvider = <String, String>{}.obs;
  final freeFirstByProvider = <String, bool>{}.obs;
  final modelTagsByProvider = <String, Map<String, List<String>>>{}.obs;

  /// Liveness per provider+model (online/failed/untested).
  final modelHealthByProvider =
      <String, Map<String, ModelHealth>>{}.obs;

  /// Test-all progress: provider → done count / total count.
  final testingByProvider = <String, bool>{}.obs;
  final testDoneByProvider = <String, int>{}.obs;
  final testTotalByProvider = <String, int>{}.obs;

  /// Hide failed models from lists when true (persisted).
  final autoHideFailed = false.obs;

  /// Auto-sync cadence in hours (persisted, 1–168, default 24).
  final modelSyncIntervalHours = 24.obs;

  /// Pinned provider ids, pin order (persisted). Keyed providers only.
  final pinnedProviders = <String>[].obs;

  /// Provider list sort: 'time' (key-set oldest first) or 'name' (A–Z).
  final providerSortMode = 'time'.obs;
  final customProviderError = ''.obs;
  final providerSearchQuery = ''.obs;
  final _dynamicActiveModel = <String, String>{}.obs;

  final customNameController = TextEditingController();
  final customBaseUrlController = TextEditingController();
  final customApiKeyController = TextEditingController();
  final customModelController = TextEditingController();

  String _dynamicKey(String provider) => 'dynamic_model_$provider';

  @override
  void onInit() {
    super.onInit();
    autoHideFailed.value =
        _hive.getSetting<bool>(_autoHideKey) ?? false;
    modelSyncIntervalHours.value =
        _clampInterval(_hive.getSetting<int>(_syncIntervalKey));
    final sort = _hive.getSetting<String>(_sortModeKey);
    providerSortMode.value = (sort == 'name') ? 'name' : 'time';
    try {
      final pins = _hive.getSetting<List>(_pinnedKey);
      if (pins != null) {
        pinnedProviders.assignAll(pins.whereType<String>());
      }
    } catch (_) {}
    _initProviders();
    if (!providers.any((provider) => provider.id == activeProvider)) {
      _settings.setCloudProvider('openrouter');
    }
    for (final provider in providers) {
      _loadCachedModels(provider.id);
      ensureDefaultModels(provider.id);
      // Restore persisted dynamic provider model selection.
      if (!_isBuiltInProvider(provider.id) && provider.id != 'custom') {
        final saved = _hive.getSetting<String>(_dynamicKey(provider.id));
        if (saved != null && saved.isNotEmpty) {
          _dynamicActiveModel[provider.id] = saved;
        }
      }
      // Ensure the active model is always visible in the list (prevents fallback to first model after restart).
      final active = activeModelFor(provider.id);
      if (active.isNotEmpty && !(modelsByProvider[provider.id]?.contains(active) ?? false)) {
        modelsByProvider[provider.id] = [...(modelsByProvider[provider.id] ?? []), active];
      }
      _loadHealth(provider.id);
    }
    _syncCustomControllers();
    Future.microtask(maybeAutoSync);
  }

  int _clampInterval(int? v) {
    if (v == null) return 24;
    return v.clamp(1, 168);
  }

  void _initProviders() {
    // Build-in providers from registry
    for (final provider in CloudProviderRegistry.all) {
      allProviders.add(CloudProviderInfo(
        id: provider.id,
        name: provider.name,
        description: provider.description,
        icon: provider.icon,
        requiresKeyForList: provider.requiresKeyForList,
        supportsFetch: provider.supportsFetch,
      ));
    }

    // Custom provider (special case)
    if (!allProviders.any((p) => p.id == 'custom')) {
      allProviders.add(const CloudProviderInfo(
        id: 'custom',
        name: 'Custom API',
        description: 'Manual OpenAI-compatible endpoint',
        icon: Icons.tune,
        supportsFetch: false,
      ));
    }

    // No auto-detected vendor cards: aggregator models live inside
    // their source card. Purge leftovers from older builds.
    Future.microtask(_purgeDynamicProviders);
  }

  bool _isBuiltInProvider(String id) {
    return CloudProviderRegistry.contains(id) || id == 'custom';
  }

  /// One-time purge of legacy auto-detected vendor cards (xiaomi, qwen,
  /// …): they duplicated the source card's model list and their ids
  /// can't serve chat. Drops their persisted caches so they never
  /// reappear; the stale-active guard in onInit resets the active
  /// provider if it pointed at one.
  Future<void> _purgeDynamicProviders() async {
    try {
      final raw = _hive.getSetting<List>(_discoveredProvidersKey);
      final ids = <String>[];
      if (raw != null) {
        for (final e in raw) {
          try {
            final m = Map<String, dynamic>.from(e as Map);
            final id = (m['id'] ?? '').toString();
            if (id.isNotEmpty) ids.add(id);
          } catch (_) {}
        }
      }
      for (final id in ids) {
        await _hive.deleteSetting('$_cachePrefix$id');
        await _hive.deleteSetting('$_cacheTimePrefix$id');
        await _hive.deleteSetting('$_workingUrlPrefix$id');
        await _hive.deleteSetting('$_healthPrefix$id');
        await _hive.deleteSetting(_dynamicKey(id));
        await _hive.deleteSetting('$_keyTimePrefix$id');
      }
      await _hive.deleteSetting(_discoveredProvidersKey);
    } catch (_) {}
  }

  String _capitalise(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  @override
  void onClose() {
    customNameController.dispose();
    customBaseUrlController.dispose();
    customApiKeyController.dispose();
    customModelController.dispose();
    super.onClose();
  }

  String get activeProvider => _settings.cloudProvider.value;

  String activeModelFor(String provider) {
    if (!_isBuiltInProvider(provider) && provider != 'custom') {
      final mem = _dynamicActiveModel[provider];
      if (mem != null && mem.isNotEmpty) return mem;
      final saved = _hive.getSetting<String>(_dynamicKey(provider));
      if (saved != null && saved.isNotEmpty) {
        // Restore to memory and ensure visible in list.
        _dynamicActiveModel[provider] = saved;
        final list = modelsByProvider[provider] ?? [];
        if (!list.contains(saved)) {
          modelsByProvider[provider] = [...list, saved];
        }
        return saved;
      }
      return modelsByProvider[provider]?.firstOrNull ?? '';
    }
    switch (provider) {
      case 'openrouter':
        return _settings.openRouterModel.value;
      case 'anthropic':
        return _settings.anthropicModel.value;
      case 'deepseek':
        return _settings.deepSeekModel.value;
      case 'google':
        return _settings.googleModel.value;
      case 'kimi':
        return _settings.kimiModel.value;
      case 'nvidia':
        return _settings.nvidiaModel.value;
      case 'zai':
        return _settings.zaiModel.value;
      case 'groq':
        return _settings.groqModel.value;
      case 'mistral':
        return _settings.mistralModel.value;
      case 'together':
        return _settings.togetherModel.value;
      case 'xai':
        return _settings.xaiModel.value;
      case 'perplexity':
        return _settings.perplexityModel.value;
      case 'cerebras':
        return _settings.cerebrasModel.value;
      case 'fireworks':
        return _settings.fireworksModel.value;
      case 'cohere':
        return _settings.cohereModel.value;
      case 'huggingface':
        return _settings.huggingfaceModel.value;
      case 'xkiro':
        return _settings.xkiroModel.value;
      case 'tokenrouter':
        return _settings.tokenrouterModel.value;      case 'custom':
        return _settings.customCloudModel.value;
      default:
        return _settings.openaiModel.value;
    }
  }

  String apiKeyFor(String provider) {
    // Fail closed: only explicit per-provider keys. No borrowing across
    // providers (that ghost-marked keyless providers as configured).
    switch (provider) {
      case 'openai':
        return _settings.openaiKey.value;
      case 'openrouter':
        return _settings.openRouterKey.value;
      case 'anthropic':
        return _settings.anthropicKey.value;
      case 'deepseek':
        return _settings.deepSeekKey.value;
      case 'google':
        return _settings.googleKey.value;
      case 'kimi':
        return _settings.kimiKey.value;
      case 'nvidia':
        return _settings.nvidiaKey.value;
      case 'zai':
        return _settings.zaiKey.value;
      case 'groq':
        return _settings.groqKey.value;
      case 'mistral':
        return _settings.mistralKey.value;
      case 'together':
        return _settings.togetherKey.value;
      case 'xai':
        return _settings.xaiKey.value;
      case 'perplexity':
        return _settings.perplexityKey.value;
      case 'cerebras':
        return _settings.cerebrasKey.value;
      case 'fireworks':
        return _settings.fireworksKey.value;
      case 'cohere':
        return _settings.cohereKey.value;
      case 'huggingface':
        return _settings.huggingfaceKey.value;
      case 'xkiro':
        return _settings.xkiroKey.value;
      case 'tokenrouter':
        return _settings.tokenrouterKey.value;
      case 'stability':
        return _settings.stabilityKey.value;
      case 'custom':
        return _settings.customCloudKey.value;
      default:
        // Fail closed: unknown ids are unconfigured (never borrow
        // another provider's key — that ghost-marks unkeyed providers
        // as configured and leaks keys across providers).
        return '';
    }
  }

  TextEditingController apiKeyControllerFor(String provider) {
    return _settings.apiKeyControllerFor(provider);
  }

  bool isConfigured(String provider) {
    if (provider == 'custom') {
      return _settings.customCloudBaseUrl.value.isNotEmpty &&
          _settings.customCloudModel.value.isNotEmpty &&
          _settings.customCloudKey.value.isNotEmpty;
    }
    return apiKeyFor(provider).isNotEmpty;
  }

  String statusLabel(String provider) {
    return isConfigured(provider) ? 'Connected' : 'Needs Key';
  }

  // ── Provider ordering: custom top, pinned, keyed (time|name), rest ──

  /// When this provider's API key was first set (persisted). Legacy
  /// keys predate tracking → epoch (oldest-first, alpha tiebreak).
  DateTime keySetAt(String provider) {
    try {
      final raw = _hive.getSetting<String>('$_keyTimePrefix$provider');
      return DateTime.tryParse(raw ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  Future<void> setProviderSortMode(String mode) async {
    providerSortMode.value = (mode == 'name') ? 'name' : 'time';
    try {
      await _hive.setSetting(_sortModeKey, providerSortMode.value);
    } catch (_) {}
  }

  bool isPinned(String provider) => pinnedProviders.contains(provider);

  /// Pin/unpin a KEYED provider (Custom API is always top — pin N/A).
  Future<void> togglePin(String provider) async {
    if (provider == 'custom' || !isConfigured(provider)) return;
    if (pinnedProviders.contains(provider)) {
      pinnedProviders.remove(provider);
    } else {
      pinnedProviders.add(provider);
    }
    try {
      await _hive.setSetting(_pinnedKey, pinnedProviders.toList());
    } catch (_) {}
  }

  void _unpin(String provider) {
    if (pinnedProviders.remove(provider)) {
      try {
        _hive.setSetting(_pinnedKey, pinnedProviders.toList());
      } catch (_) {}
    }
  }

  /// Card display order: Custom API always first, then pinned (pin
  /// order), then key-set (sort mode), then everything else.
  /// Provider list for Model Hub + switchers: Custom first → pinned →
  /// keyed (sorted by time or name). Unkeyed providers are excluded —
  /// they appear in [unkeyedProviders].
  List<CloudProviderInfo> orderedProviders() {
    final byId = {for (final p in allProviders) p.id: p};
    final out = <CloudProviderInfo>[];
    void take(String id) {
      final p = byId.remove(id);
      if (p != null) out.add(p);
    }

    // 1) Custom always first.
    take('custom');

    // 2) Pinned keyed providers (in pin order).
    for (final id in pinnedProviders.toList()) {
      if (id != 'custom' && isConfigured(id)) take(id);
    }

    // 3) Remaining keyed providers — sorted by time or name.
    final keyed = <CloudProviderInfo>[];
    for (final p in byId.values.toList()) {
      if (p.id != 'custom' && isConfigured(p.id)) {
        keyed.add(p);
        byId.remove(p.id);
      }
    }
    if (providerSortMode.value == 'name') {
      keyed.sort((a, b) =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } else {
      keyed.sort((a, b) {
        final c = keySetAt(a.id).compareTo(keySetAt(b.id));
        if (c != 0) return c;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    }
    out.addAll(keyed);
    return out;
  }

  /// Built-in providers without an API key — shown in a separate
  /// "Add API Key" section at the bottom of the Model Hub.
  /// (Legacy dynamic ids are excluded everywhere; they are purged
  /// on launch and can neither serve nor configure.)
  List<CloudProviderInfo> get unkeyedProviders {
    return allProviders
        .where((p) =>
            p.id != 'custom' &&
            _isBuiltInProvider(p.id) &&
            !isConfigured(p.id))
        .toList();
  }

  /// Display rank for shared switcher sorting (lower = higher).
  int providerOrderIndex(String id) {
    final order = orderedProviders();
    final i = order.indexWhere((p) => p.id == id);
    return i < 0 ? order.length : i;
  }

  List<CloudProviderInfo> get filteredProviders {
    final query = providerSearchQuery.value.toLowerCase().trim();
    if (query.isEmpty) return orderedProviders();
    return orderedProviders().where((p) {
      if (p.name.toLowerCase().contains(query)) return true;
      if (p.id.toLowerCase().contains(query)) return true;
      if (p.description.toLowerCase().contains(query)) return true;
      final models = modelsByProvider[p.id] ?? [];
      return models.any((m) => m.toLowerCase().contains(query));
    }).toList();
  }

  List<String> filteredModelsFor(String provider) {
    final query = (searchByProvider[provider] ?? '').toLowerCase().trim();
    final company = companyFilterByProvider[provider];
    final active = activeModelFor(provider);
    var source = [...(modelsByProvider[provider] ?? const <String>[])];
    if (active.isNotEmpty && !source.contains(active)) {
      source.insert(0, active);
    }
    // Auto-hide failed: drop failed models, but NEVER the active one —
    // hiding the in-use model would strand the picker.
    if (autoHideFailed.value) {
      final health = modelHealthByProvider[provider] ?? const {};
      source = source.where((id) {
        if (id == active) return true;
        return health[id]?.status != ModelHealthStatus.failed;
      }).toList();
    }
    if (company != null && company.isNotEmpty) {
      source = source
          .where((id) => id.toLowerCase().startsWith('$company/'))
          .toList();
    }
    final filtered = query.isEmpty
        ? source
        : source.where((id) => id.toLowerCase().contains(query)).toList();
    final freeFirst = freeFirstByProvider[provider] == true;
    filtered.sort((a, b) {
      if (a == active) return -1;
      if (b == active) return 1;
      if (freeFirst) {
        final aFree = isFreeModel(provider, a);
        final bFree = isFreeModel(provider, b);
        if (aFree != bFree) return aFree ? -1 : 1;
      }
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
    return filtered;
  }

  String fetchedLabel(String provider) {
    final fetchedAt = fetchedAtByProvider[provider];
    if (fetchedAt == null &&
        (modelsByProvider[provider] ?? const <String>[]).isNotEmpty) {
      return 'Built-in list';
    }
    if (fetchedAt == null) return 'Not fetched yet';
    final diff = DateTime.now().difference(fetchedAt);
    if (diff.inMinutes < 1) return 'Updated just now';
    if (diff.inHours < 1) return 'Updated ${diff.inMinutes}m ago';
    if (diff.inDays < 1) return 'Updated ${diff.inHours}h ago';
    return 'Updated ${diff.inDays}d ago';
  }

  List<String> modelTagsFor(String provider, String modelId) {
    final normalized =
        provider == 'google' ? modelId.replaceFirst('models/', '') : modelId;
    if (provider == 'nvidia') return const ['NIM'];
    return modelTagsByProvider[provider]?[normalized] ??
        modelTagsByProvider[provider]?[modelId] ??
        const <String>[];
  }

  bool isFreeModel(String provider, String modelId) {
    final lower = modelId.toLowerCase();
    return modelTagsFor(provider, modelId).contains('FREE') ||
        lower.contains(':free') ||
        lower.contains('-free');
  }

  int freeModelCountFor(String provider) {
    return (modelsByProvider[provider] ?? const <String>[])
        .where((id) => isFreeModel(provider, id))
        .length;
  }

  void toggleFreeFirst(String provider) {
    freeFirstByProvider[provider] = !(freeFirstByProvider[provider] ?? false);
  }

  /// Auto-detect company prefixes from model IDs (e.g. 'openai' from
  /// 'openai/gpt-5.2'). Used to build the company filter chips for
  /// aggregator providers like OpenRouter — no hardcoding needed.
  List<String> availableCompaniesFor(String provider) {
    final models = modelsByProvider[provider] ?? const <String>[];
    final set = <String>{};
    for (final m in models) {
      final slash = m.indexOf('/');
      if (slash <= 0) continue;
      set.add(m.substring(0, slash));
    }
    final list = set.toList()..sort();
    return list;
  }

  bool hasCompanyFilterFor(String provider) =>
      availableCompaniesFor(provider).length >= 2;

  String companyDisplayName(String prefix) =>
      _knownCompanyNames[prefix.toLowerCase()] ?? _capitalise(prefix);

  IconData? companyIcon(String prefix) =>
      _knownCompanyIcons[prefix.toLowerCase()];

  void setCompanyFilter(String provider, String? prefix) {
    if (prefix == null || prefix.isEmpty) {
      companyFilterByProvider.remove(provider);
    } else {
      companyFilterByProvider[provider] = prefix;
    }
  }

  /// Models found by the last successful verification, per provider.
  final verifiedModelCountByProvider = <String, int>{}.obs;

  /// Verify a candidate key WITHOUT saving it. Returns null when the
  /// provider's model-list endpoint answers 200 with a non-empty list,
  /// otherwise a short human-readable reason.
  Future<String?> verifyApiKey(String provider, String candidate) async {
    final key = candidate.trim();
    if (key.isEmpty) return 'Paste a key first.';
    // Wrong-key-type fast path: Google AI Studio keys always start
    // with "AIza" — anything else (e.g. "AQ.…") is rejected by Google
    // before any quota/model check, so say so without a network call.
    if (provider == 'google' && !key.startsWith('AIza')) {
      return 'Not a Gemini API key — AI Studio keys start with "AIza". '
          'Create one free at aistudio.google.com/apikey.';
    }
    try {
      final cloudProvider = CloudProviderRegistry.getById(provider);
      final urls = cloudProvider?.getModelListCandidates(key) ??
          const ['https://api.openai.com/v1/models'];
      final headers = cloudProvider?.buildAuthHeaders(key) ??
          {'Authorization': 'Bearer $key'};
      for (final url in urls.take(2)) {
        try {
          final resp = await http
              .get(Uri.parse(url), headers: headers)
              .timeout(const Duration(seconds: 15));
          if (resp.statusCode == 200) {
            final ids = _parseModelIds(provider, resp.body);
            if (ids.isNotEmpty) {
              verifiedModelCountByProvider[provider] = ids.length;
              return null;
            }
          } else if (resp.statusCode == 401 || resp.statusCode == 403) {
            return 'Invalid key (${resp.statusCode}) — check for typos.';
          } else if (resp.statusCode == 400 &&
              resp.body.contains('API_KEY_INVALID')) {
            // Google's "not a valid key" shape (wrong key type).
            return 'Invalid key (400) — this key is not valid for the Gemini API.';
          }
        } catch (_) {
          continue;
        }
      }
      return 'Verification failed — endpoint unreachable or key rejected.';
    } catch (e) {
      return 'Verification failed: $e';
    }
  }

  Future<void> saveApiKey(String provider, String value) async {
    await _settings.setApiKey(provider, value);
    if (value.isNotEmpty) {
      final hint = keyFormatHint(provider, value);
      if (hint != null) {
        AppSnackbar.showTop('Key looks unusual', hint,
            logHistory: false);
      }
      modelsByProvider.remove(provider);
      modelTagsByProvider.remove(provider);
      fetchedAtByProvider.remove(provider);
      // First-set timestamp drives time-sort (kept, not overwritten).
      try {
        if ((_hive.getSetting<String>('$_keyTimePrefix$provider') ?? '')
            .isEmpty) {
          await _hive.setSetting(
              '$_keyTimePrefix$provider',
              DateTime.now().toIso8601String());
        }
      } catch (_) {}
      Future.microtask(() => refreshModels(provider));
    }
  }

  Future<void> removeApiKey(String provider) async {
    await _settings.removeApiKey(provider);
    _unpin(provider);
    try {
      await _hive.deleteSetting('$_keyTimePrefix$provider');
    } catch (_) {}
    modelsByProvider.remove(provider);
    modelTagsByProvider.remove(provider);
    fetchedAtByProvider.remove(provider);
    isLoadingProvider.remove(provider);
    errorByProvider.remove(provider);
    companyFilterByProvider.remove(provider);
    await _hive.deleteSetting('$_cachePrefix$provider');
    await _hive.deleteSetting('$_cacheTimePrefix$provider');
    await _hive.deleteSetting('$_workingUrlPrefix$provider');
  }

  void ensureDefaultModels(String provider) {
    if (apiKeyFor(provider).isEmpty) return;
    final defaults = _defaultModelsByProvider[provider];
    if (defaults == null || defaults.isEmpty) return;

    final existing = modelsByProvider[provider] ?? const <String>[];
    if (existing.isNotEmpty) return;

    final withActive = [...defaults];
    final active = activeModelFor(provider);
    if (active.isNotEmpty && !withActive.contains(active)) {
      withActive.add(active);
    }
    modelsByProvider[provider] = withActive;

    if (provider == 'zai') {
      modelTagsByProvider[provider] = _zaiFreeTags(defaults);
    }
  }

  bool canFetchModels(String provider) {
    if (provider == 'custom') return false;
    return apiKeyFor(provider).isNotEmpty;
  }

  bool canSelectModel(String provider) {
    if (provider == 'custom') {
      return _settings.customCloudBaseUrl.value.isNotEmpty &&
          _settings.customCloudKey.value.isNotEmpty;
    }
    return apiKeyFor(provider).isNotEmpty;
  }

  Future<void> selectModel(
    String provider,
    String modelId, {
    bool showSnackbar = true,
  }) async {
    final normalized =
        provider == 'google' ? modelId.replaceFirst('models/', '') : modelId;
    if (!_isBuiltInProvider(provider) && provider != 'custom') {
      _dynamicActiveModel[provider] = normalized;
      await _hive.setSetting(_dynamicKey(provider), normalized);
      // Ensure the selected model stays in the list even after refresh.
      final list = modelsByProvider[provider] ?? [];
      if (!list.contains(normalized)) {
        modelsByProvider[provider] = [...list, normalized];
      }
      await _settings.setCloudProvider(provider);
      await _settings.setInferenceMode('cloud');
      if (!showSnackbar) return;
      AppSnackbar.cloudActive('$provider · $normalized');
      return;
    }
    await _settings.setCloudProvider(provider);
    await _settings.setCloudModel(provider, normalized);
    await _settings.setInferenceMode('cloud');
    if (!showSnackbar) return;
    AppSnackbar.cloudActive('$provider · $normalized');
  }

  /// Deactivates the active cloud provider: switches inference back to
  /// local mode and auto-loads the last downloaded local model so chat
  /// keeps working without any cloud API.
  Future<void> deactivateCloudProvider() async {
    // Reset to a neutral provider so nothing reads an empty ID.
    await _settings.setCloudProvider('openrouter');
    // Switch back to local inference immediately.
    await _settings.setInferenceMode('local');

    final inference = Get.find<InferenceService>();
    final imageService = Get.find<LocalImageService>();

    // If a local model is already resident we're done.
    if (inference.isModelLoaded.value || imageService.isModelLoaded.value) {
      AppSnackbar.localActive(inference.loadedModelName.value);
      return;
    }

    // Auto-load the last downloaded local text model (path validated —
    // same guards as the startup resume dialog).
    String? textName =
        _hive.getSetting<String>(AppConstants.keyLocalModelName);
    String? textPath = _hive.getSetting<String>(AppConstants.keyLocalModelPath);
    String? textRuntime =
        _hive.getSetting<String>(AppConstants.keyLocalModelRuntime);

    bool pathOk(String? p) {
      if (p == null || p.isEmpty) return false;
      try {
        final f = File(p);
        return f.existsSync() && f.lengthSync() > 0;
      } catch (_) {
        return false;
      }
    }

    if (!pathOk(textPath)) {
      // Clean stale pointers like the resume dialog does.
      await _hive.setSetting(AppConstants.keyLocalModelPath, '');
      await _hive.setSetting(AppConstants.keyLocalModelName, '');
      await _hive.setSetting(AppConstants.keyLocalModelRuntime, '');
      await _hive.setSetting(AppConstants.keyLocalModelBackend, '');
      textName = null;
      textPath = null;
      textRuntime = null;
    }

    if (textName != null && textName.isNotEmpty && pathOk(textPath)) {
      AppSnackbar.showTop('Switching back', 'Loading $textName…');
      try {
        await inference.loadModel(
          textPath!,
          modelName: textName,
          modelRuntime: textRuntime,
        );
      } catch (_) {}
      return;
    }

    // Fall back to a downloaded image model if no text model exists.
    final imageName =
        _hive.getSetting<String>(AppConstants.keyImageModelName);
    final imagePath = _hive.getSetting<String>(AppConstants.keyImageModelPath);
    if (imageName != null && imageName.isNotEmpty && pathOk(imagePath)) {
      AppSnackbar.showTop('Switching back', 'Loading $imageName…');
      try {
        await Get.find<LocalImageService>().loadModel(imagePath!,
            modelName: imageName);
      } catch (_) {}
      return;
    }

    AppSnackbar.showTop('No local model',
        'Download one from Explore → Local Models',
        duration: const Duration(seconds: 3));
  }

  Future<void> saveCustomProvider() async {
    final validationError = validateCustomProvider();
    if (validationError != null) {
      customProviderError.value = validationError;
      return;
    }
    customProviderError.value = '';
    await _settings.setCustomCloudConfig(
      name: customNameController.text,
      baseUrl: customBaseUrlController.text,
      apiKey: customApiKeyController.text,
      model: customModelController.text,
    );
    await selectModel(
      'custom',
      _settings.customCloudModel.value,
      showSnackbar: false,
    );
  }

  Future<void> clearCustomProvider() async {
    await _settings.clearCustomCloudConfig();
    customProviderError.value = '';
    _syncCustomControllers();
  }

  List<Map<String, String>> get customProfiles => _settings.customCloudProfiles;

  int get customProfileIndex => _settings.customCloudProfileIndex.value;

  Future<void> selectCustomProfile(int index) async {
    await _settings.selectCustomCloudProfile(index);
    _syncCustomControllers();
    customProviderError.value = '';
  }

  void beginNewCustomProfile() {
    _settings.beginNewCustomCloudProfile();
    _syncCustomControllers();
    customProviderError.value = '';
  }

  String? validateCustomProvider() {
    final baseUrl = customBaseUrlController.text.trim();
    final apiKey = customApiKeyController.text.trim();
    final model = customModelController.text.trim();

    if (baseUrl.isEmpty) return 'Base URL is required.';
    final uri = Uri.tryParse(baseUrl);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      return 'Enter a valid OpenAI-compatible base URL.';
    }
    if (apiKey.isEmpty) return 'API key is required.';
    if (model.isEmpty) return 'Model ID is required.';
    return null;
  }

  Future<void> refreshModels(String provider) async {
    if (provider == 'custom') {
      await refreshCustomModels();
      return;
    }

    if (apiKeyFor(provider).isEmpty) {
      errorByProvider.remove(provider);
      return;
    }

    isLoadingProvider[provider] = true;
    errorByProvider.remove(provider);
    companyFilterByProvider.remove(provider);

    if (provider == 'zai') {
      final defaults = _defaultModelsByProvider[provider] ?? const [];
      final withActive = [...defaults];
      final activeZai = activeModelFor(provider);
      if (activeZai.isNotEmpty && !withActive.contains(activeZai)) {
        withActive.add(activeZai);
      }
      modelsByProvider[provider] = withActive;
      modelTagsByProvider[provider] = _zaiFreeTags(defaults);
      fetchedAtByProvider[provider] = DateTime.now();
      await _hive.setSetting('$_cachePrefix$provider', defaults);
      await _hive.setSetting(
          '$_cacheTimePrefix$provider', DateTime.now().toIso8601String());
      isLoadingProvider[provider] = false;
      return;
    }

    try {
      final candidates = _modelListUrlCandidates(provider);
      final cloudProvider = CloudProviderRegistry.getById(provider);
      final headers = cloudProvider?.buildAuthHeaders(apiKeyFor(provider)) ??
          {'Authorization': 'Bearer ${apiKeyFor(provider)}'};
      http.Response? response;
      String? workingUrl;

      for (final url in candidates) {
        try {
          final resp =
              await http.get(Uri.parse(url), headers: headers).timeout(
                    const Duration(seconds: 15),
                  );
          if (resp.statusCode == 200) {
            final ids = _parseModelIds(provider, resp.body);
            if (ids.isNotEmpty) {
              response = resp;
              workingUrl = url;
              break;
            }
          }
        } catch (_) {
          continue;
        }
      }

      if (response == null || workingUrl == null) {
        final defaults = _defaultModelsByProvider[provider];
        if (defaults != null && defaults.isNotEmpty) {
          final withActive = [...defaults];
          final activeFallback = activeModelFor(provider);
          if (activeFallback.isNotEmpty && !withActive.contains(activeFallback)) {
            withActive.add(activeFallback);
          }
          modelsByProvider[provider] = withActive;
          fetchedAtByProvider[provider] = DateTime.now();
          await _hive.setSetting('$_cachePrefix$provider', defaults);
          await _hive.setSetting(
              '$_cacheTimePrefix$provider', DateTime.now().toIso8601String());
        } else {
          errorByProvider[provider] = 'Failed to fetch model list';
        }
        return;
      }

      final ids = _parseModelIds(provider, response.body);
      final active = activeModelFor(provider);
      if (active.isNotEmpty && !ids.contains(active)) {
        ids.add(active);
      }
      modelsByProvider[provider] = ids;
      modelTagsByProvider[provider] = _parseModelTags(provider, response.body);
      final fetchedAt = DateTime.now();
      fetchedAtByProvider[provider] = fetchedAt;
      await _hive.setSetting('$_cachePrefix$provider', ids);
      await _hive.setSetting(
          '$_cacheTimePrefix$provider', fetchedAt.toIso8601String());
      await _hive.setSetting('$_workingUrlPrefix$provider', workingUrl);
      // NOTE: no auto-detected vendor cards — aggregator models stay
      // inside their source card (company chips filter by vendor).
    } catch (e) {
      errorByProvider[provider] = '$e';
      Get.find<AppLogService>().warning(
        'Model list request failed for $provider',
        details: e,
        category: LogCategory.cloud,
      );
    } finally {
      isLoadingProvider[provider] = false;
    }
  }

  /// Explicit "Import from /models": fetch the provider's live model
  /// list and report how many NEW ids arrived (0 = already current).
  /// Returns the new-model count, or -1 when there is no API key.
  Future<int> importModels(String provider) async {
    if (provider != 'custom' && apiKeyFor(provider).isEmpty) {
      AppSnackbar.showTop('API key needed',
          'Add an API key for this provider first, then import.',
          logHistory: false);
      return -1;
    }
    final before =
        Set<String>.from(modelsByProvider[provider] ?? const <String>[]);
    await refreshModels(provider);
    final after = modelsByProvider[provider] ?? const <String>[];
    final fresh = findNewModels(before.toList(), after);
    if (errorByProvider[provider]?.isNotEmpty == true) {
      AppSnackbar.showTop(
          'Import failed', errorByProvider[provider] ?? 'Unknown error',
          logHistory: false);
      return 0;
    }
    if (fresh.isEmpty) {
      AppSnackbar.showTop('Already up to date',
          '${after.length} models — nothing new on /models.',
          logHistory: false);
    } else {
      AppSnackbar.showTop('Imported ${fresh.length} new model${fresh.length == 1 ? '' : 's'}',
          fresh.take(3).join(', ') +
              (fresh.length > 3 ? ' (+${fresh.length - 3} more)' : ''),
          logHistory: false);
    }
    return fresh.length;
  }

  // ── Test all models ──

  bool isTesting(String provider) =>
      testingByProvider[provider] == true;

  /// Ping every listed model with one tiny chat call (concurrency 3).
  /// A probe checks the CONNECTION, not the full reply: instant error
  /// = failed fast; first stream chunk (even an empty/thought opener
  /// from a reasoning model) = online immediately, no waiting for the
  /// final text. First-chunk window is 15s; transient failures
  /// (429/5xx/timeout) get ONE retry after 5s so burst probing doesn't
  /// mass-mark working models as failed.
  /// Records online/failed + latency per model. Cancel via
  /// [cancelTesting]. Skipped entirely without an API key.
  Future<void> testAllModels(String provider) async {
    if (isTesting(provider)) return;
    if (provider != 'custom' && apiKeyFor(provider).isEmpty) {
      AppSnackbar.showTop('API key needed',
          'Add an API key for this provider first, then test.',
          logHistory: false);
      return;
    }
    final models = [...(modelsByProvider[provider] ?? const <String>[])];
    if (models.isEmpty) {
      AppSnackbar.showTop(
          'Nothing to test', 'Import the model list first.',
          logHistory: false);
      return;
    }
    testingByProvider[provider] = true;
    testTotalByProvider[provider] = models.length;
    testDoneByProvider[provider] = 0;
    _testCancel[provider] = false;
    _setHealth(
        provider,
        Map<String, ModelHealth>.from(modelHealthByProvider[provider] ?? {}),
        persist: false);
    try {
      CloudService cloud;
      try {
        cloud = Get.find<CloudService>();
      } catch (_) {
        AppSnackbar.showTop(
            'Cloud unavailable', 'CloudService is not running.',
            logHistory: false);
        return;
      }
      var cursor = 0;
      Future<void> worker() async {
        while (true) {
          if (_testCancel[provider] == true) return;
          final i = cursor++;
          if (i >= models.length) return;
          final model = models[i];
          _setOneHealth(
              provider,
              ModelHealth(
                  modelId: model,
                  status: ModelHealthStatus.testing,
                  checkedAtMs:
                      DateTime.now().millisecondsSinceEpoch));
          final sw = Stopwatch()..start();
          try {
            await _probeModel(cloud, provider, model);
            sw.stop();
            _setOneHealth(
                provider,
                ModelHealth(
                    modelId: model,
                    status: ModelHealthStatus.online,
                    latencyMs: sw.elapsedMilliseconds,
                    checkedAtMs:
                        DateTime.now().millisecondsSinceEpoch));
          } catch (e) {
            sw.stop();
            _setOneHealth(
                provider,
                ModelHealth(
                    modelId: model,
                    status: ModelHealthStatus.failed,
                    latencyMs: sw.elapsedMilliseconds,
                    error: summarizeModelError(e),
                    checkedAtMs:
                        DateTime.now().millisecondsSinceEpoch));
          } finally {
            testDoneByProvider[provider] =
                (testDoneByProvider[provider] ?? 0) + 1;
          }
        }
      }

      await Future.wait([worker(), worker(), worker()]);
      await _saveHealth(provider);
      final ok = (modelHealthByProvider[provider] ?? {})
          .values
          .where((h) => h.status == ModelHealthStatus.online)
          .length;
      final bad = (modelHealthByProvider[provider] ?? {})
          .values
          .where((h) => h.status == ModelHealthStatus.failed)
          .length;
      AppSnackbar.showTop(
          _testCancel[provider] == true
              ? 'Testing cancelled'
              : 'Testing done',
          '$ok online · $bad failed',
          logHistory: false);
    } finally {
      testingByProvider[provider] = false;
      _testCancel.remove(provider);
    }
  }

  void cancelTesting(String provider) {
    _testCancel[provider] = true;
  }

  /// One model probe: streams 'Reply with: ok' and succeeds on the
  /// FIRST chunk — even an empty one (reasoning openers, role deltas).
  /// A chunk means key accepted + model serving; waiting for the full
  /// text would only waste time. Transient errors get a single retry
  /// after 5s backoff.
  Future<void> _probeModel(
      CloudService cloud, String provider, String model) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) {
        await Future.delayed(const Duration(seconds: 5));
      }
      try {
        var gotChunk = false;
        await for (final _ in cloud
            .streamMessageAs(
              providerId: provider,
              model: model,
              messages: const [
                {'role': 'user', 'content': 'Reply with: ok'}
              ],
            )
            .timeout(const Duration(seconds: 15))) {
          gotChunk = true;
          break;
        }
        if (!gotChunk) throw Exception('Empty response stream');
        return;
      } catch (e) {
        lastError = e;
        if (_testCancel[provider] == true) rethrow;
        if (attempt == 0 && isRetryableProbeError(summarizeModelError(e))) {
          continue;
        }
        rethrow;
      }
    }
    throw lastError ?? Exception('Probe failed');
  }

  final _testCancel = <String, bool>{};

  // ── Health store ──

  ModelHealth? healthFor(String provider, String model) =>
      modelHealthByProvider[provider]?[model];

  /// (online, failed) counts for badges.
  (int, int) healthSummaryFor(String provider) {
    var ok = 0;
    var bad = 0;
    for (final h in (modelHealthByProvider[provider] ?? {}).values) {
      if (h.status == ModelHealthStatus.online) ok++;
      if (h.status == ModelHealthStatus.failed) bad++;
    }
    return (ok, bad);
  }

  void _setOneHealth(String provider, ModelHealth h) {
    final map =
        Map<String, ModelHealth>.from(modelHealthByProvider[provider] ?? {});
    map[h.modelId] = h;
    _setHealth(provider, map, persist: false);
  }

  void _setHealth(String provider, Map<String, ModelHealth> map,
      {bool persist = true}) {
    modelHealthByProvider[provider] = map;
    if (persist) unawaited(_saveHealth(provider));
  }

  Future<void> _saveHealth(String provider) async {
    try {
      final map = modelHealthByProvider[provider] ?? {};
      // Cap stored rows to models still listed (stale ids dropped).
      final listed = (modelsByProvider[provider] ?? const <String>[]).toSet();
      final rows = map.values
          .where((h) => listed.contains(h.modelId))
          .map((h) => h.toMap())
          .toList();
      await _hive.setSetting('$_healthPrefix$provider', rows);
    } catch (_) {}
  }

  void _loadHealth(String provider) {
    try {
      final raw = _hive.getSetting<List>('$_healthPrefix$provider');
      if (raw == null) return;
      final map = <String, ModelHealth>{};
      for (final m in raw.whereType<Map>()) {
        try {
          final h = ModelHealth.fromMap(m);
          if (h.modelId.isNotEmpty) map[h.modelId] = h;
        } catch (_) {}
      }
      if (map.isNotEmpty) modelHealthByProvider[provider] = map;
    } catch (_) {}
  }

  // ── Auto-hide failed ──

  Future<void> setAutoHideFailed(bool v) async {
    autoHideFailed.value = v;
    try {
      await _hive.setSetting(_autoHideKey, v);
    } catch (_) {}
  }

  // ── Auto-sync ──

  Future<void> setSyncIntervalHours(int h) async {
    modelSyncIntervalHours.value = _clampInterval(h);
    try {
      await _hive.setSetting(
          _syncIntervalKey, modelSyncIntervalHours.value);
    } catch (_) {}
  }

  String autoSyncLabel() {
    final raw = _hive.getSetting<String>(_lastAutoSyncKey);
    if (raw == null || raw.isEmpty) return 'Never auto-synced';
    final at = DateTime.tryParse(raw);
    if (at == null) return 'Never auto-synced';
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'Auto-synced just now';
    if (diff.inHours < 1) return 'Auto-synced ${diff.inMinutes}m ago';
    if (diff.inDays < 1) return 'Auto-synced ${diff.inHours}h ago';
    return 'Auto-synced ${diff.inDays}d ago';
  }

  /// Manual "Sync now": refresh every configured provider right away
  /// and stamp the auto-sync clock.
  Future<void> syncAllNow() async {
    var synced = 0;
    for (final p in providers) {
      if (p.id == 'custom') continue;
      if (apiKeyFor(p.id).isEmpty) continue;
      try {
        await refreshModels(p.id);
        if (errorByProvider[p.id]?.isNotEmpty != true) synced++;
      } catch (_) {}
    }
    try {
      await _hive.setSetting(
          _lastAutoSyncKey, DateTime.now().toIso8601String());
    } catch (_) {}
    AppSnackbar.showTop('Sync complete',
        synced == 0
            ? 'No configured provider to refresh.'
            : '$synced provider${synced == 1 ? '' : 's'} refreshed.',
        logHistory: false);
  }

  /// Background auto-sync on start: refresh every configured provider
  /// whose cache is older than the interval (or never fetched).
  /// Fire-and-forget, per-provider guarded — never blocks startup.
  Future<void> maybeAutoSync() async {
    try {
      final last = _hive.getSetting<String>(_lastAutoSyncKey);
      if (!shouldAutoSync(
          lastSyncIso: last,
          intervalHours: modelSyncIntervalHours.value,
          now: DateTime.now())) {
        return;
      }
      var synced = 0;
      for (final p in providers) {
        if (p.id == 'custom') continue;
        if (apiKeyFor(p.id).isEmpty) continue;
        final fetched = fetchedAtByProvider[p.id];
        final stale = fetched == null ||
            DateTime.now().difference(fetched).inHours >=
                modelSyncIntervalHours.value;
        if (!stale) continue;
        try {
          await refreshModels(p.id);
          synced++;
        } catch (_) {}
      }
      await _hive.setSetting(
          _lastAutoSyncKey, DateTime.now().toIso8601String());
      if (synced > 0) {
        AppSnackbar.showTop('Models auto-synced',
            '$synced provider${synced == 1 ? '' : 's'} refreshed.',
            logHistory: false);
      }
    } catch (_) {}
  }

  Future<void> refreshCustomModels() async {
    final baseUrl = (_settings.customCloudBaseUrl.value)
        .toString()
        .replaceAll(RegExp(r'/+$'), '');
    final apiKey = _settings.customCloudKey.value;
    final manuallyEntered = _settings.customCloudModel.value.trim();

    if (baseUrl.isEmpty) return;

    isLoadingProvider['custom'] = true;
    errorByProvider.remove('custom');

    try {
      http.Response? response;
      final candidates = <String>[];
      if (baseUrl.toLowerCase().endsWith('/models')) {
        candidates.add(baseUrl);
      } else if (baseUrl.toLowerCase().endsWith('/v1')) {
        candidates.add('$baseUrl/models');
      } else {
        candidates.addAll(['$baseUrl/v1/models', '$baseUrl/models', baseUrl]);
      }
      for (final url in candidates) {
        try {
          final uri = Uri.parse(url);
          final headers = <String, String>{
            'Content-Type': 'application/json',
          };
          if (apiKey.isNotEmpty) {
            headers['Authorization'] = 'Bearer $apiKey';
          }
          response = await http.get(uri, headers: headers).timeout(
            const Duration(seconds: 10),
            onTimeout: () => http.Response('Timeout', 408),
          );
          if (response.statusCode == 200) break;
        } catch (_) {
          continue;
        }
      }

      if (response != null && response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final raw = data['data'] as List? ?? [];
        final ids = raw
            .map((m) => m is Map ? m['id']?.toString() : null)
            .whereType<String>()
            .toSet()
            .toList();
        // Always include the manually entered model
        if (manuallyEntered.isNotEmpty && !ids.contains(manuallyEntered)) {
          ids.insert(0, manuallyEntered);
        }
        modelsByProvider['custom'] = ids;
        // Tag all custom models as free (self-hosted = free)
        final tags = <String, List<String>>{};
        for (final id in ids) {
          tags[id] = const ['FREE'];
        }
        modelTagsByProvider['custom'] = tags;
        final fetchedAt = DateTime.now();
        fetchedAtByProvider['custom'] = fetchedAt;
        await _hive.setSetting('$_cachePrefix custom', ids);
        await _hive.setSetting(
            '${_cacheTimePrefix}custom', fetchedAt.toIso8601String());
      } else {
        // Even if fetch fails, ensure manually entered model is available
        if (manuallyEntered.isNotEmpty) {
          modelsByProvider['custom'] = [manuallyEntered];
          modelTagsByProvider['custom'] = {manuallyEntered: const ['FREE']};
        }
        final detail = response != null
            ? '${response.statusCode}: ${_shortBody(response.body)}'
            : 'Could not connect to $baseUrl';
        errorByProvider['custom'] = detail;
        Get.find<AppLogService>().warning(
          'Custom endpoint model list failed',
          details: detail,
          category: LogCategory.cloud,
        );
      }
    } catch (e) {
      if (manuallyEntered.isNotEmpty) {
        modelsByProvider['custom'] = [manuallyEntered];
        modelTagsByProvider['custom'] = {manuallyEntered: const ['FREE']};
      }
      errorByProvider['custom'] = '$e';
      Get.find<AppLogService>().warning(
        'Custom endpoint model list failed',
        details: e,
        category: LogCategory.cloud,
      );
    } finally {
      isLoadingProvider['custom'] = false;
    }
  }

  List<String> _modelListUrlCandidates(String provider) {
    final key = apiKeyFor(provider);
    final cloudProvider = CloudProviderRegistry.getById(provider);
    if (cloudProvider != null) {
      return cloudProvider.getModelListCandidates(key);
    }

    // Fallback for providers not in registry
    switch (provider) {
      case 'google':
        return [
          '${AppConstants.googleEndpoint}?key=$key',
        ];
      default:
        return ['https://api.openai.com/v1/models'];
    }
  }

  List<String> _parseModelIds(String provider, String body) {
    final data = jsonDecode(body);

    if (provider == 'google') {
      final raw = data['models'] as List? ?? [];
      return raw
          .map((model) => model is Map ? model['name']?.toString() : null)
          .whereType<String>()
          .toSet()
          .toList();
    }

    List<String> tryExtract(Map root) {
      final candidates = ['data', 'models', 'results', 'items', 'model_list'];
      for (final key in candidates) {
        final raw = root[key];
        if (raw is List && raw.isNotEmpty) {
          final ids = raw
              .map((m) {
                if (m is! Map) return null;
                return m['id']?.toString() ??
                    m['name']?.toString() ??
                    m['model']?.toString();
              })
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList();
          if (ids.isNotEmpty) return ids;
        }
      }
      if (root.containsKey('model') && root['model'] is String) {
        return [root['model'] as String];
      }
      return const <String>[];
    }

    if (data is Map<String, dynamic>) {
      final ids = tryExtract(data);
      if (ids.isNotEmpty) return ids;
    }

    if (data is List) {
      final ids = data
          .map((m) {
            if (m is! Map) return null;
            return m['id']?.toString() ??
                m['name']?.toString() ??
                m['model']?.toString();
          })
          .whereType<String>()
          .toSet()
          .toList();
      if (ids.isNotEmpty) return ids;
    }

    return const [];
  }

  Map<String, List<String>> _parseModelTags(String provider, String body) {
    final tags = <String, List<String>>{};

    final data = jsonDecode(body);
    List<dynamic> rawList = const [];
    if (data is Map<String, dynamic>) {
      for (final key in ['data', 'models', 'results', 'items', 'model_list']) {
        if (data[key] is List) {
          rawList = data[key] as List;
          break;
        }
      }
    } else if (data is List) {
      rawList = data;
    }

    const freePatterns = {
      'free', 'flash', 'mini', 'lite', 'nano',
    };

    for (final model in rawList) {
      if (model is! Map) continue;
      final id = model['id']?.toString() ?? model['name']?.toString();
      if (id == null || id.isEmpty) continue;

      final modelTags = <String>[];

      final pricing = model['pricing'];
      if (pricing is Map) {
        final prompt = _pricingValue(pricing['prompt']);
        final completion = _pricingValue(pricing['completion']);
        final request = _pricingValue(pricing['request']);
        if (prompt == 0 && completion == 0 && (request == null || request == 0)) {
          modelTags.add('FREE');
        }
      }

      final lowerId = id.toLowerCase();
      // Robust free detection: any model with :free / -free suffix is free,
      // even if pricing metadata is missing.
      if (lowerId.contains(':free') || lowerId.contains('-free')) {
        if (!modelTags.contains('FREE')) modelTags.add('FREE');
      } else if (modelTags.isEmpty) {
        for (final pattern in freePatterns) {
          if (lowerId.contains(pattern) && lowerId.contains('flash')) {
            modelTags.add('FREE');
            break;
          }
        }
      }

      final contextLength = model['context_length'] ?? model['max_context'];
      if (contextLength is num && contextLength >= 100000) {
        modelTags.add('${(contextLength / 1000).round()}K');
      }

      final owned = model['owned_by']?.toString();
      if (owned != null && owned.isNotEmpty) {
        modelTags.add(owned);
      }

      if (modelTags.isNotEmpty) {
        tags[id] = modelTags;
      }
    }

    return tags;
  }

  double? _pricingValue(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  Map<String, List<String>> _zaiFreeTags(List<String> models) {
    const freeSet = {
      'glm-4.7-flash', 'glm-4.5-flash', 'glm-4.6v-flash',
    };
    const contextMap = <String, String>{
      'glm-5.3': '128K', 'glm-5.2': '128K', 'glm-5.1': '128K',
      'glm-5': '128K', 'glm-5-turbo': '128K', 'glm-5v-turbo': '128K',
      'glm-4.7': '128K', 'glm-4.7-flash': '128K', 'glm-4.7-flashx': '128K',
      'glm-4.6': '128K', 'glm-4.5': '128K', 'glm-4.5-x': '128K',
      'glm-4.5-air': '128K', 'glm-4.5-airx': '128K',
      'glm-4.5-flash': '128K', 'glm-4.5v': '128K',
      'glm-4.6v': '128K', 'glm-4.6v-flash': '128K', 'glm-4.6v-flashx': '128K',
      'glm-4-32b-0414-128k': '128K', 'glm-ocr': '128K',
    };
    final tags = <String, List<String>>{};
    for (final id in models) {
      final t = <String>[];
      if (freeSet.contains(id)) t.add('FREE');
      final ctx = contextMap[id];
      if (ctx != null) t.add(ctx);
      t.add('Z.AI');
      tags[id] = t;
    }
    return tags;
  }

  void _loadCachedModels(String provider) {
    if (apiKeyFor(provider).isEmpty) return;
    final raw = _hive.getSetting<List>('$_cachePrefix$provider');
    if (raw != null) {
      modelsByProvider[provider] = raw.whereType<String>().toList();
    }
    final rawTime = _hive.getSetting<String>('$_cacheTimePrefix$provider');
    if (rawTime != null) {
      final parsed = DateTime.tryParse(rawTime);
      if (parsed != null) fetchedAtByProvider[provider] = parsed;
    }
  }

  void _syncCustomControllers() {
    customNameController.text = _settings.customCloudName.value;
    customBaseUrlController.text = _settings.customCloudBaseUrl.value;
    customApiKeyController.text = _settings.customCloudKey.value;
    customModelController.text = _settings.customCloudModel.value;
  }

  String _shortBody(String body) {
    final compact = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= 280) return compact;
    return '${compact.substring(0, 280)}...';
  }
}
