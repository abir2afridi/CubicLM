import 'package:flutter/material.dart';

import 'openai_compatible_provider.dart';

/// NVIDIA NIM provider implementation.
class NvidiaProvider extends OpenAICompatibleProvider {
  @override
  String get id => 'nvidia';

  @override
  String get name => 'NVIDIA NIM';

  @override
  String get description => 'Llama, Nemotron hosted models';

  @override
  IconData get icon => Icons.memory_outlined;

  @override
  String get endpoint =>
      'https://integrate.api.nvidia.com/v1/chat/completions';

  @override
  String? get modelListEndpoint => 'https://integrate.api.nvidia.com/v1/models';

  @override
  List<String> getModelListCandidates(String apiKey) => [
        'https://integrate.api.nvidia.com/v1/models',
        'https://integrate.api.nvidia.com/models',
      ];
}
