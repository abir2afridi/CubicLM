import 'package:flutter/material.dart';

import 'openai_compatible_provider.dart';

/// OpenRouter provider implementation.
class OpenRouterProvider extends OpenAICompatibleProvider {
  @override
  String get id => 'openrouter';

  @override
  String get name => 'OpenRouter';

  @override
  String get description => 'Free model list · OpenAI compatible';

  @override
  IconData get icon => Icons.hub_outlined;

  @override
  String get endpoint =>
      'https://openrouter.ai/api/v1/chat/completions';

  @override
  String? get modelListEndpoint =>
      'https://openrouter.ai/api/v1/models';

  @override
  Map<String, String> buildAuthHeaders(String apiKey) {
    return {
      'Authorization': 'Bearer $apiKey',
      'HTTP-Referer': 'https://cubiclm.app',
      'X-Title': 'CubicLM',
    };
  }

  @override
  List<String> getModelListCandidates(String apiKey) => [
        'https://openrouter.ai/api/v1/models',
        'https://openrouter.ai/api/v1/models?supported_parameters=tools',
      ];

  @override
  Map<String, List<String>> parseModelTags(String body) {
    final tags = <String, List<String>>{};
    final data = Map<String, dynamic>.from(
        (body as dynamic) is String ? {} : {});
    if (data.isEmpty) return tags;

    final raw = data['data'] as List? ?? [];
    for (final model in raw) {
      if (model is! Map) continue;
      final id = model['id']?.toString();
      if (id == null || id.isEmpty) continue;

      final modelTags = <String>[];

      final pricing = model['pricing'];
      if (pricing is Map) {
        final prompt = _pricingValue(pricing['prompt']);
        final completion = _pricingValue(pricing['completion']);
        final request = _pricingValue(pricing['request']);
        if (prompt == 0 &&
            completion == 0 &&
            (request == null || request == 0)) {
          modelTags.add('FREE');
        }
      }

      if (id.toLowerCase().contains(':free')) {
        modelTags.add('FREE');
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
}
