import 'package:flutter/material.dart';

import 'openai_compatible_provider.dart';

/// Cohere provider — Command R models via OpenAI-compatible endpoint.
class CohereProvider extends OpenAICompatibleProvider {
  @override
  String get id => 'cohere';

  @override
  String get name => 'Cohere';

  @override
  String get description => 'Command-A, Command-R, Aya';

  @override
  IconData get icon => Icons.record_voice_over_outlined;

  @override
  String get endpoint =>
      'https://api.cohere.ai/compatibility/v1/chat/completions';

  @override
  String? get modelListEndpoint =>
      'https://api.cohere.ai/compatibility/v1/models';

  @override
  List<String> getModelListCandidates(String apiKey) => [
        'https://api.cohere.ai/compatibility/v1/models',
      ];
}
