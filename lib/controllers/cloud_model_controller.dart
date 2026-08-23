import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../core/constants.dart';
import '../services/app_log_service.dart';
import '../services/hive_service.dart';
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
      'gemini-1.5-flash',
      'gemini-1.5-pro',
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
  };

  final allProviders = <CloudProviderInfo>[].obs;

  List<CloudProviderInfo> get providers => allProviders;

  final modelsByProvider = <String, List<String>>{}.obs;
  final fetchedAtByProvider = <String, DateTime>{}.obs;
  final isLoadingProvider = <String, bool>{}.obs;
  final errorByProvider = <String, String>{}.obs;
  final searchByProvider = <String, String>{}.obs;
  final freeFirstByProvider = <String, bool>{}.obs;
  final modelTagsByProvider = <String, Map<String, List<String>>>{}.obs;
  final customProviderError = ''.obs;
  final providerSearchQuery = ''.obs;
  final _dynamicActiveModel = <String, String>{}.obs;

  final customNameController = TextEditingController();
  final customBaseUrlController = TextEditingController();
  final customApiKeyController = TextEditingController();
  final customModelController = TextEditingController();

  @override
  void onInit() {
    super.onInit();
    _initProviders();
    if (!providers.any((provider) => provider.id == activeProvider)) {
      _settings.setCloudProvider('openrouter');
    }
    for (final provider in providers) {
      _loadCachedModels(provider.id);
      ensureDefaultModels(provider.id);
    }
    _syncCustomControllers();
  }

  void _initProviders() {
    const builtIn = [
      CloudProviderInfo(id: 'openrouter', name: 'OpenRouter', description: 'Free model list · OpenAI compatible', icon: Icons.hub_outlined),
      CloudProviderInfo(id: 'openai', name: 'OpenAI', description: 'Native OpenAI chat models', icon: Icons.auto_awesome),
      CloudProviderInfo(id: 'deepseek', name: 'DeepSeek', description: 'OpenAI compatible V4 models', icon: Icons.psychology_alt_outlined),
      CloudProviderInfo(id: 'google', name: 'Google Gemini', description: 'Gemini native API models', icon: Icons.diamond_outlined),
      CloudProviderInfo(id: 'nvidia', name: 'NVIDIA NIM', description: 'OpenAI compatible hosted NIM models', icon: Icons.memory_outlined),
      CloudProviderInfo(id: 'zai', name: 'Z.AI', description: 'GLM series models · OpenAI compatible', icon: Icons.auto_awesome_outlined),
      CloudProviderInfo(id: 'custom', name: 'Custom API', description: 'Manual OpenAI-compatible endpoint', icon: Icons.tune, supportsFetch: false),
    ];
    allProviders.addAll(builtIn);

    final discovered = _loadDiscoveredProviders();
    for (final p in discovered) {
      if (!allProviders.any((e) => e.id == p.id)) {
        allProviders.add(p);
      }
    }
  }

  List<CloudProviderInfo> _loadDiscoveredProviders() {
    try {
      final raw = _hive.getSetting<List>(_discoveredProvidersKey);
      if (raw == null) return [];
      return raw.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return CloudProviderInfo(
          id: m['id'] ?? '',
          name: m['name'] ?? '',
          description: m['description'] ?? 'Auto-detected provider',
          icon: Icons.auto_awesome,
          requiresKeyForList: false,
        );
      }).where((p) => p.id.isNotEmpty && p.name.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveDiscoveredProviders() async {
    final discovered = allProviders
        .where((p) => !_isBuiltInProvider(p.id))
        .map((p) => {'id': p.id, 'name': p.name, 'description': p.description})
        .toList();
    await _hive.setSetting(_discoveredProvidersKey, discovered);
  }

  bool _isBuiltInProvider(String id) {
    return const ['openrouter', 'openai', 'deepseek', 'google', 'nvidia', 'zai', 'custom'].contains(id);
  }

  void autoDetectProvidersFromModels(String sourceProvider, List<String> modelIds) {
    final detected = <String, List<String>>{};
    for (final id in modelIds) {
      final slash = id.indexOf('/');
      if (slash <= 0) continue;
      final prefix = id.substring(0, slash).toLowerCase();
      if (_isBuiltInProvider(prefix) || prefix == 'custom') continue;
      detected.putIfAbsent(prefix, () => []).add(id);
    }

    for (final entry in detected.entries) {
      final prefix = entry.key;
      final models = entry.value;
      final existing = allProviders.any((p) => p.id == prefix);
      if (!existing) {
        final name = _knownCompanyNames[prefix] ?? _capitalise(prefix);
        final icon = _knownCompanyIcons[prefix] ?? Icons.cloud_outlined;
        allProviders.add(CloudProviderInfo(
          id: prefix,
          name: name,
          description: '$name models via $sourceProvider',
          icon: icon,
          requiresKeyForList: false,
        ));
        modelsByProvider[prefix] = models;
        Get.find<AppLogService>().info(
          'Auto-detected provider: $name (${models.length} models)',
          category: LogCategory.cloud,
        );
      } else {
        final existingModels = modelsByProvider[prefix] ?? [];
        final merged = {...existingModels, ...models}.toList();
        modelsByProvider[prefix] = merged;
      }
    }

    if (detected.isNotEmpty) {
      _saveDiscoveredProviders();
    }
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
      return _dynamicActiveModel[provider] ?? (modelsByProvider[provider]?.firstOrNull ?? '');
    }
    switch (provider) {
      case 'openrouter':
        return _settings.openRouterModel.value;
      case 'deepseek':
        return _settings.deepSeekModel.value;
      case 'google':
        return _settings.googleModel.value;
      case 'nvidia':
        return _settings.nvidiaModel.value;
      case 'zai':
        return _settings.zaiModel.value;
      case 'custom':
        return _settings.customCloudModel.value;
      default:
        return _settings.openaiModel.value;
    }
  }

  String apiKeyFor(String provider) {
    if (!_isBuiltInProvider(provider) && provider != 'custom') {
      return apiKeyFor('openrouter');
    }
    switch (provider) {
      case 'openrouter':
        return _settings.openRouterKey.value;
      case 'deepseek':
        return _settings.deepSeekKey.value;
      case 'google':
        return _settings.googleKey.value;
      case 'nvidia':
        return _settings.nvidiaKey.value;
      case 'zai':
        return _settings.zaiKey.value;
      case 'custom':
        return _settings.customCloudKey.value;
      default:
        return _settings.openaiKey.value;
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

  List<CloudProviderInfo> get filteredProviders {
    final query = providerSearchQuery.value.toLowerCase().trim();
    if (query.isEmpty) return providers;
    return providers.where((p) {
      if (p.name.toLowerCase().contains(query)) return true;
      if (p.id.toLowerCase().contains(query)) return true;
      if (p.description.toLowerCase().contains(query)) return true;
      final models = modelsByProvider[p.id] ?? [];
      return models.any((m) => m.toLowerCase().contains(query));
    }).toList();
  }

  List<String> filteredModelsFor(String provider) {
    final query = (searchByProvider[provider] ?? '').toLowerCase().trim();
    final active = activeModelFor(provider);
    final source = [...(modelsByProvider[provider] ?? const <String>[])];
    if (active.isNotEmpty && !source.contains(active)) {
      source.insert(0, active);
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
    return modelTagsFor(provider, modelId).contains('FREE') ||
        modelId.toLowerCase().contains(':free');
  }

  int freeModelCountFor(String provider) {
    return (modelsByProvider[provider] ?? const <String>[])
        .where((id) => isFreeModel(provider, id))
        .length;
  }

  void toggleFreeFirst(String provider) {
    freeFirstByProvider[provider] = !(freeFirstByProvider[provider] ?? false);
  }

  Future<void> saveApiKey(String provider, String value) async {
    await _settings.setApiKey(provider, value);
    if (value.isNotEmpty) {
      modelsByProvider.remove(provider);
      modelTagsByProvider.remove(provider);
      fetchedAtByProvider.remove(provider);
      Future.microtask(() => refreshModels(provider));
    }
  }

  Future<void> removeApiKey(String provider) async {
    await _settings.removeApiKey(provider);
    modelsByProvider.remove(provider);
    modelTagsByProvider.remove(provider);
    fetchedAtByProvider.remove(provider);
    isLoadingProvider.remove(provider);
    errorByProvider.remove(provider);
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

    modelsByProvider[provider] = [...defaults];

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
      await _settings.setCloudProvider(provider);
      await _settings.setInferenceMode('cloud');
      if (!showSnackbar) return;
      Get.snackbar('Cloud Model Active', '$provider · $normalized',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    await _settings.setCloudProvider(provider);
    await _settings.setCloudModel(provider, normalized);
    await _settings.setInferenceMode('cloud');
    if (!showSnackbar) return;
    Get.snackbar('Cloud Model Active', '$provider · $normalized',
        snackPosition: SnackPosition.BOTTOM);
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

    if (provider == 'zai') {
      final defaults = _defaultModelsByProvider[provider] ?? const [];
      modelsByProvider[provider] = [...defaults];
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
      http.Response? response;
      String? workingUrl;

      for (final url in candidates) {
        try {
          final resp = await http
              .get(Uri.parse(url), headers: {
                'Authorization': 'Bearer ${apiKeyFor(provider)}',
              })
              .timeout(const Duration(seconds: 15));
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
          modelsByProvider[provider] = [...defaults];
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
      modelsByProvider[provider] = ids;
      modelTagsByProvider[provider] = _parseModelTags(provider, response.body);
      final fetchedAt = DateTime.now();
      fetchedAtByProvider[provider] = fetchedAt;
      await _hive.setSetting('$_cachePrefix$provider', ids);
      await _hive.setSetting(
          '$_cacheTimePrefix$provider', fetchedAt.toIso8601String());
      await _hive.setSetting('$_workingUrlPrefix$provider', workingUrl);
      autoDetectProvidersFromModels(provider, ids);
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
    switch (provider) {
      case 'openai':
        return [
          'https://api.openai.com/v1/models',
          'https://api.openai.com/models',
        ];
      case 'anthropic':
        return [
          'https://api.anthropic.com/v1/models',
        ];
      case 'deepseek':
        return [
          '${AppConstants.deepSeekEndpoint}/models',
          '${AppConstants.deepSeekEndpoint}/v1/models',
        ];
      case 'google':
        return [
          '${AppConstants.googleEndpoint}?key=$key',
        ];
      case 'nvidia':
        return [
          '${AppConstants.nvidiaEndpoint}/models',
          'https://integrate.api.nvidia.com/models',
        ];
      case 'openrouter':
        return [
          '${AppConstants.openRouterEndpoint}/models',
          'https://openrouter.ai/api/v1/models',
        ];
      case 'zai':
        return [
          '${AppConstants.zaiEndpoint}/models',
          '${AppConstants.zaiEndpoint}/model/list',
          'https://api.z.ai/api/paas/v4/models',
          'https://api.z.ai/api/paas/v3/models',
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
      if (modelTags.isEmpty) {
        for (final pattern in freePatterns) {
          if (lowerId.contains(pattern) && (lowerId.contains('flash') || lowerId.endsWith('-free'))) {
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
