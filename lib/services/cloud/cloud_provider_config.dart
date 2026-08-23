import 'package:flutter/material.dart';

/// Configuration data for a cloud AI provider.
///
/// This class holds all provider-specific metadata and configuration.
/// Each provider should have a single config instance.
class CloudProviderConfig {
  /// Unique identifier for this provider (e.g., 'openai', 'anthropic').
  final String id;

  /// Display name (e.g., 'OpenAI', 'Anthropic').
  final String name;

  /// Short description for the UI.
  final String description;

  /// Material icon for the provider.
  final IconData icon;

  /// Whether this provider requires an API key for model list fetching.
  final bool requiresKeyForList;

  /// Whether this provider supports fetching model lists from API.
  final bool supportsFetch;

  /// The base endpoint URL for API calls.
  final String endpoint;

  /// The model list endpoint URL (may be null if not supported).
  final String? modelListEndpoint;

  /// Whether this provider supports streaming responses.
  final bool supportsStreaming;

  /// Default model ID for this provider.
  final String defaultModel;

  /// Hive key for storing the API key.
  final String apiKeyHiveKey;

  /// Hive key for storing the selected model.
  final String modelHiveKey;

  /// Candidate URLs for model list fetching (tried in order).
  final List<String> Function(String apiKey)? getModelListCandidates;

  /// Constructor.
  const CloudProviderConfig({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    this.requiresKeyForList = true,
    this.supportsFetch = true,
    required this.endpoint,
    this.modelListEndpoint,
    this.supportsStreaming = false,
    required this.defaultModel,
    required this.apiKeyHiveKey,
    required this.modelHiveKey,
    this.getModelListCandidates,
  });
}

/// Registry of all cloud provider configurations.
///
/// Use this class to access provider configs by ID.
class CloudProviderConfigRegistry {
  CloudProviderConfigRegistry._();

  static final Map<String, CloudProviderConfig> _configs = {};

  /// Register a provider configuration.
  static void register(CloudProviderConfig config) {
    _configs[config.id] = config;
  }

  /// Get a provider configuration by ID.
  static CloudProviderConfig? getById(String id) {
    return _configs[id];
  }

  /// Get all registered configurations.
  static List<CloudProviderConfig> get all => _configs.values.toList();

  /// Get all registered provider IDs.
  static List<String> get allIds => _configs.keys.toList();

  /// Check if a provider is registered.
  static bool contains(String id) => _configs.containsKey(id);
}
