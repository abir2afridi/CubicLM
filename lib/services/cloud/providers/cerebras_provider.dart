import 'package:flutter/material.dart';

import 'openai_compatible_provider.dart';

/// Cerebras provider — fastest inference (wafer-scale engines).
class CerebrasProvider extends OpenAICompatibleProvider {
  @override
  String get id => 'cerebras';

  @override
  String get name => 'Cerebras';

  @override
  String get description => 'Fastest Llama, Qwen, GPT-OSS';

  @override
  IconData get icon => Icons.speed_outlined;

  @override
  String get endpoint => 'https://api.cerebras.ai/v1/chat/completions';

  @override
  String? get modelListEndpoint => 'https://api.cerebras.ai/v1/models';

  @override
  List<String> getModelListCandidates(String apiKey) => [
        'https://api.cerebras.ai/v1/models',
      ];
}
