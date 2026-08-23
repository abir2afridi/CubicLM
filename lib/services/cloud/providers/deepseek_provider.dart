import 'package:flutter/material.dart';

import 'openai_compatible_provider.dart';

/// DeepSeek provider implementation.
class DeepSeekProvider extends OpenAICompatibleProvider {
  @override
  String get id => 'deepseek';

  @override
  String get name => 'DeepSeek';

  @override
  String get description => 'DeepSeek V4, R1 reasoning models';

  @override
  IconData get icon => Icons.psychology_alt_outlined;

  @override
  String get endpoint => 'https://api.deepseek.com/chat/completions';

  @override
  String? get modelListEndpoint => 'https://api.deepseek.com/models';

  @override
  List<String> getModelListCandidates(String apiKey) => [
        'https://api.deepseek.com/models',
        'https://api.deepseek.com/v1/models',
      ];
}
