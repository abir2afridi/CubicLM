import 'package:flutter/material.dart';

import 'openai_compatible_provider.dart';

/// Mistral AI provider — European frontier models.
class MistralProvider extends OpenAICompatibleProvider {
  @override
  String get id => 'mistral';

  @override
  String get name => 'Mistral AI';

  @override
  String get description => 'Large, Codestral, Pixtral';

  @override
  IconData get icon => Icons.air_outlined;

  @override
  String get endpoint => 'https://api.mistral.ai/v1/chat/completions';

  @override
  String? get modelListEndpoint => 'https://api.mistral.ai/v1/models';

  @override
  List<String> getModelListCandidates(String apiKey) => [
        'https://api.mistral.ai/v1/models',
      ];
}
