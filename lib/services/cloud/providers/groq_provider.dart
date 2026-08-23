import 'package:flutter/material.dart';

import 'openai_compatible_provider.dart';

/// Groq provider — ultra-fast LPU inference for open models.
class GroqProvider extends OpenAICompatibleProvider {
  @override
  String get id => 'groq';

  @override
  String get name => 'Groq';

  @override
  String get description => 'Ultra-fast Llama, Qwen, DeepSeek';

  @override
  IconData get icon => Icons.bolt_outlined;

  @override
  String get endpoint => 'https://api.groq.com/openai/v1/chat/completions';

  @override
  String? get modelListEndpoint => 'https://api.groq.com/openai/v1/models';

  @override
  List<String> getModelListCandidates(String apiKey) => [
        'https://api.groq.com/openai/v1/models',
      ];
}
