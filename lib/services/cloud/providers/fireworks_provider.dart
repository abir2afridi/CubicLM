import 'package:flutter/material.dart';

import 'openai_compatible_provider.dart';

/// Fireworks AI provider — production open-model inference.
class FireworksProvider extends OpenAICompatibleProvider {
  @override
  String get id => 'fireworks';

  @override
  String get name => 'Fireworks AI';

  @override
  String get description => 'Llama, DeepSeek, Qwen hosted';

  @override
  IconData get icon => Icons.local_fire_department_outlined;

  @override
  String get endpoint =>
      'https://api.fireworks.ai/inference/v1/chat/completions';

  @override
  String? get modelListEndpoint =>
      'https://api.fireworks.ai/inference/v1/models';

  @override
  List<String> getModelListCandidates(String apiKey) => [
        'https://api.fireworks.ai/inference/v1/models',
      ];
}
