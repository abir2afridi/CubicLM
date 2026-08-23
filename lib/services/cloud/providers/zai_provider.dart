import 'package:flutter/material.dart';

import 'openai_compatible_provider.dart';

/// Z.AI provider implementation.
///
/// Uses OpenAI-compatible API format.
/// Note: Z.AI does not have a /models endpoint, so model list is from catalog.
class ZaiProvider extends OpenAICompatibleProvider {
  @override
  String get id => 'zai';

  @override
  String get name => 'Z.AI';

  @override
  String get description => 'GLM-5.3, GLM-4.7 Flash (free)';

  @override
  IconData get icon => Icons.bolt;

  @override
  String get endpoint =>
      'https://api.z.ai/api/paas/v4/chat/completions';

  @override
  bool get supportsFetch => false; // No /models endpoint

  @override
  String? get modelListEndpoint => null;

  @override
  List<String> getModelListCandidates(String apiKey) => [];

  /// Complete catalog of Z.AI models from their OpenAPI spec.
  /// Used as the source of truth since no /models endpoint exists.
  static const List<String> catalogModels = [
    // Free models first
    'glm-4.7-flash',
    'glm-4.5-flash',
    'glm-4.6v-flash',
    // Cheap models
    'glm-4.7-flashx',
    'glm-ocr',
    'glm-4.6v-flashx',
    'glm-4-32b-0414-128k',
    'glm-4.5-air',
    // Standard models
    'glm-4.7',
    'glm-4.6',
    'glm-4.5',
    'glm-4.5-x',
    'glm-4.5-airx',
    // Flagship models
    'glm-5.3',
    'glm-5.2',
    'glm-5.1',
    'glm-5',
    'glm-5-turbo',
    // Vision models
    'glm-5v-turbo',
    'glm-4.5v',
    'glm-4.6v',
  ];

  /// Free models in the Z.AI catalog.
  static const Set<String> freeModels = {
    'glm-4.7-flash',
    'glm-4.5-flash',
    'glm-4.6v-flash',
  };

  /// Context window sizes for Z.AI models.
  static const Map<String, String> contextSizes = {
    'glm-5.3': '128K',
    'glm-5.2': '128K',
    'glm-5.1': '128K',
    'glm-5': '128K',
    'glm-5-turbo': '128K',
    'glm-5v-turbo': '128K',
    'glm-4.7': '128K',
    'glm-4.7-flash': '128K',
    'glm-4.7-flashx': '128K',
    'glm-4.6': '128K',
    'glm-4.5': '128K',
    'glm-4.5-x': '128K',
    'glm-4.5-air': '128K',
    'glm-4.5-airx': '128K',
    'glm-4.5-flash': '128K',
    'glm-4.5v': '128K',
    'glm-4.6v': '128K',
    'glm-4.6v-flash': '128K',
    'glm-4.6v-flashx': '128K',
    'glm-4-32b-0414-128k': '128K',
    'glm-ocr': '128K',
  };

  /// Get tags for a model in the Z.AI catalog.
  static List<String> getTags(String modelId) {
    final tags = <String>[];
    if (freeModels.contains(modelId)) tags.add('FREE');
    final ctx = contextSizes[modelId];
    if (ctx != null) tags.add(ctx);
    tags.add('Z.AI');
    return tags;
  }
}
