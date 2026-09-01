import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/constants.dart';
import 'hive_service.dart';
import 'secure_key_store.dart';
import 'cloud/cloud_provider.dart';
import 'cloud/cloud_provider_registry.dart';
import 'cloud/providers/openai_compatible_provider.dart';

/// Cloud API service that delegates to provider implementations.
///
/// This is a thin coordinator that:
/// 1. Reads provider configuration from Hive
/// 2. Looks up the provider from the registry
/// 3. Delegates API calls to the provider
class CloudService extends GetxService {
  final HiveService _hive = Get.find<HiveService>();

  String get _provider =>
      _hive.getSetting(AppConstants.keyCloudProvider, defaultValue: 'openrouter') ??
      'openrouter';

  String get _apiKey => _readApiKey(_provider);
  String get _model => _readModel(_provider);

  String _readSecure(String key) {
    if (Get.isRegistered<SecureKeyStore>()) {
      final v = Get.find<SecureKeyStore>().read(key);
      if (v.isNotEmpty) return v;
    }
    return _hive.getSetting(key) ?? '';
  }

  bool get isConfigured {
    if (_provider == 'custom') {
      return (_hive.getSetting(AppConstants.keyCustomCloudBaseUrl) ?? '')
              .toString()
              .isNotEmpty &&
          _readSecure(AppConstants.keyCustomCloudKey).isNotEmpty;
    }
    return _apiKey.isNotEmpty;
  }

  /// Send a chat completion message.
  Future<String> sendMessage({
    required List<Map<String, String>> messages,
    String? imageBase64,
    double? temperature,
    int? maxTokens,
    void Function(String)? onToken,
  }) async {
    final provider = _getActiveProvider();

    if (onToken != null && provider.supportsStreaming) {
      final buffer = StringBuffer();
      await for (final chunk in provider.streamMessage(
        messages: messages,
        apiKey: _apiKey,
        model: _model,
        imageBase64: imageBase64,
        temperature: temperature,
        maxTokens: maxTokens,
      )) {
        buffer.write(chunk);
        onToken(chunk);
      }
      return buffer.toString();
    }

    return provider.sendMessage(
      messages: messages,
      apiKey: _apiKey,
      model: _model,
      imageBase64: imageBase64,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  /// Send a streaming chat completion message.
  Stream<String> streamMessage(
    List<Map<String, String>> messages, {
    String? imageBase64,
    double? temperature,
    int? maxTokens,
  }) async* {
    final provider = _getActiveProvider();
    yield* provider.streamMessage(
      messages: messages,
      apiKey: _apiKey,
      model: _model,
      imageBase64: imageBase64,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  CloudProvider _getActiveProvider() {
    if (_provider == 'custom') {
      final baseUrl =
          (_hive.getSetting(AppConstants.keyCustomCloudBaseUrl) ?? '')
              .toString()
              .replaceAll(RegExp(r'/+$'), '');
      final customEndpoint = '$baseUrl/chat/completions';
      return _CustomProviderAdapter(endpoint: customEndpoint);
    }

    final provider = CloudProviderRegistry.getById(_provider);
    if (provider == null) {
      throw Exception('Unknown provider: $_provider');
    }
    return provider;
  }

  String _readApiKey(String provider) {
    String key;
    switch (provider) {
      case 'anthropic':
        key = AppConstants.keyAnthropicKey;
        break;
      case 'google':
        key = AppConstants.keyGoogleKey;
        break;
      case 'kimi':
        key = AppConstants.keyKimiKey;
        break;
      case 'stability':
        key = AppConstants.keyStabilityKey;
        break;
      case 'nvidia':
        key = AppConstants.keyNvidiaKey;
        break;
      case 'openrouter':
        key = AppConstants.keyOpenRouterKey;
        break;
      case 'deepseek':
        key = AppConstants.keyDeepSeekKey;
        break;
      case 'zai':
        key = AppConstants.keyZaiKey;
        break;
      case 'groq':
        key = AppConstants.keyGroqKey;
        break;
      case 'mistral':
        key = AppConstants.keyMistralKey;
        break;
      case 'together':
        key = AppConstants.keyTogetherKey;
        break;
      case 'xai':
        key = AppConstants.keyXaiKey;
        break;
      case 'perplexity':
        key = AppConstants.keyPerplexityKey;
        break;
      case 'cerebras':
        key = AppConstants.keyCerebrasKey;
        break;
      case 'fireworks':
        key = AppConstants.keyFireworksKey;
        break;
      case 'cohere':
        key = AppConstants.keyCohereKey;
        break;
      case 'huggingface':
        key = AppConstants.keyHuggingFaceKey;
        break;
      case 'xkiro':
        key = AppConstants.keyXkiroKey;
        break;
      case 'tokenrouter':
        key = AppConstants.keyTokenRouterKey;
        break;
      case 'custom':
        key = AppConstants.keyCustomCloudKey;
        break;
      default:
        key = AppConstants.keyOpenaiKey;
        break;
    }
    return _readSecure(key);
  }

  String _readModel(String provider) {
    switch (provider) {
      case 'anthropic':
        return _hive.getSetting(AppConstants.keyAnthropicModel) ??
            'claude-sonnet-4-6';
      case 'google':
        return _hive.getSetting(AppConstants.keyGoogleModel) ??
            'gemini-2.5-flash';
      case 'kimi':
        return _hive.getSetting(AppConstants.keyKimiModel) ?? 'kimi-k2.6';
      case 'stability':
        return _hive.getSetting(AppConstants.keyStabilityModel) ??
            'sd3.5-flash';
      case 'nvidia':
        return _hive.getSetting(AppConstants.keyNvidiaModel) ??
            'meta/llama-3.1-8b-instruct';
      case 'openrouter':
        return _hive.getSetting(AppConstants.keyOpenRouterModel) ??
            'openai/gpt-4o-mini';
      case 'deepseek':
        return _hive.getSetting(AppConstants.keyDeepSeekModel) ??
            'deepseek-v4-flash';
      case 'zai':
        return _hive.getSetting(AppConstants.keyZaiModel) ?? 'glm-4.7-flash';
      case 'groq':
        return _hive.getSetting(AppConstants.keyGroqModel) ??
            'llama-3.3-70b-versatile';
      case 'mistral':
        return _hive.getSetting(AppConstants.keyMistralModel) ??
            'mistral-large-latest';
      case 'together':
        return _hive.getSetting(AppConstants.keyTogetherModel) ??
            'meta-llama/Llama-3.3-70B-Instruct-Turbo';
      case 'xai':
        return _hive.getSetting(AppConstants.keyXaiModel) ?? 'grok-4-fast';
      case 'perplexity':
        return _hive.getSetting(AppConstants.keyPerplexityModel) ??
            'sonar-pro';
      case 'cerebras':
        return _hive.getSetting(AppConstants.keyCerebrasModel) ??
            'llama-3.3-70b';
      case 'fireworks':
        return _hive.getSetting(AppConstants.keyFireworksModel) ??
            'accounts/fireworks/models/llama-v3p3-70b-instruct';
      case 'cohere':
        return _hive.getSetting(AppConstants.keyCohereModel) ??
            'command-a-03-2025';
      case 'huggingface':
        return _hive.getSetting(AppConstants.keyHuggingFaceModel) ??
            'meta-llama/Llama-3.3-70B-Instruct';
      case 'xkiro':
        return _hive.getSetting(AppConstants.keyXkiroModel) ?? 'openai/gpt-5.2';
      case 'tokenrouter':
        return _hive.getSetting(AppConstants.keyTokenRouterModel) ??
            'openai/gpt-5.2';      case 'custom':
        return _hive.getSetting(AppConstants.keyCustomCloudModel) ?? '';
      default:
        return _hive.getSetting(AppConstants.keyOpenaiModel) ?? 'gpt-5.2';
    }
  }
}

/// Internal adapter for custom providers.
class _CustomProviderAdapter extends OpenAICompatibleProvider {
  final String _customEndpoint;

  _CustomProviderAdapter({required String endpoint})
      : _customEndpoint = endpoint;

  @override
  String get id => 'custom';

  @override
  String get name => 'Custom API';

  @override
  String get description => 'OpenAI-compatible endpoint';

  @override
  IconData get icon => Icons.settings_input_component;

  @override
  bool get requiresKeyForList => true;

  @override
  bool get supportsFetch => true;

  @override
  String get endpoint => _customEndpoint;

  @override
  String? get modelListEndpoint => null;

  @override
  bool get supportsStreaming => true;

  @override
  List<String> getModelListCandidates(String apiKey) {
    final base = _customEndpoint
        .replaceAll(RegExp(r'/chat/completions$'), '')
        .replaceAll(RegExp(r'/+$'), '');
    return ['$base/models', '$base/v1/models'];
  }
}
