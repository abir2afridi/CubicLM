import 'package:flutter/material.dart';

import 'openai_compatible_provider.dart';

/// OpenAI provider implementation.
class OpenAIProvider extends OpenAICompatibleProvider {
  @override
  String get id => 'openai';

  @override
  String get name => 'OpenAI';

  @override
  String get description => 'GPT-4o, GPT-5 series models';

  @override
  IconData get icon => Icons.auto_awesome;

  @override
  String get endpoint => 'https://api.openai.com/v1/chat/completions';

  @override
  String? get modelListEndpoint => 'https://api.openai.com/v1/models';

  @override
  List<String> getModelListCandidates(String apiKey) => [
        'https://api.openai.com/v1/models',
        'https://api.openai.com/models',
      ];
}
