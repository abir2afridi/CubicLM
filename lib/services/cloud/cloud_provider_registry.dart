import 'cloud_provider.dart';
import 'providers/openai_provider.dart';
import 'providers/anthropic_provider.dart';
import 'providers/google_provider.dart';
import 'providers/nvidia_provider.dart';
import 'providers/openrouter_provider.dart';
import 'providers/deepseek_provider.dart';
import 'providers/zai_provider.dart';
import 'providers/kimi_provider.dart';
import 'providers/stability_provider.dart';
import 'providers/groq_provider.dart';
import 'providers/mistral_provider.dart';
import 'providers/together_provider.dart';
import 'providers/xai_provider.dart';
import 'providers/perplexity_provider.dart';
import 'providers/cerebras_provider.dart';
import 'providers/fireworks_provider.dart';
import 'providers/cohere_provider.dart';

/// Registry of all cloud AI providers.
///
/// Use this class to access provider instances by ID.
class CloudProviderRegistry {
  CloudProviderRegistry._();

  static final Map<String, CloudProvider> _providers = {
    'openrouter': OpenRouterProvider(),
    'openai': OpenAIProvider(),
    'deepseek': DeepSeekProvider(),
    'google': GoogleProvider(),
    'nvidia': NvidiaProvider(),
    'zai': ZaiProvider(),
    'anthropic': AnthropicProvider(),
    'kimi': KimiProvider(),
    'stability': StabilityProvider(),
    'groq': GroqProvider(),
    'mistral': MistralProvider(),
    'together': TogetherProvider(),
    'xai': XaiProvider(),
    'perplexity': PerplexityProvider(),
    'cerebras': CerebrasProvider(),
    'fireworks': FireworksProvider(),
    'cohere': CohereProvider(),
  };

  /// Get a provider by its ID.
  ///
  /// Returns null if no provider with the given ID exists.
  static CloudProvider? getById(String id) {
    return _providers[id];
  }

  /// Get all registered providers.
  static List<CloudProvider> get all => _providers.values.toList();

  /// Get all built-in provider IDs.
  static List<String> get allIds => _providers.keys.toList();

  /// Get all OpenAI-compatible providers.
  static List<CloudProvider> get openAICompatible =>
      _providers.values.where((p) => p.protocol == ProviderProtocol.openAICompatible).toList();

  /// Register a custom provider dynamically.
  static void register(String id, CloudProvider provider) {
    _providers[id] = provider;
  }

  /// Unregister a provider.
  static void unregister(String id) {
    _providers.remove(id);
  }

  /// Check if a provider is registered.
  static bool contains(String id) => _providers.containsKey(id);
}
