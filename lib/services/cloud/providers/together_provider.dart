import 'package:flutter/material.dart';

import 'openai_compatible_provider.dart';

/// Together AI provider — open-source model cloud.
class TogetherProvider extends OpenAICompatibleProvider {
  @override
  String get id => 'together';

  @override
  String get name => 'Together AI';

  @override
  String get description => 'Llama, DeepSeek, Qwen turbo';

  @override
  IconData get icon => Icons.groups_outlined;

  @override
  String get endpoint => 'https://api.together.xyz/v1/chat/completions';

  @override
  String? get modelListEndpoint => 'https://api.together.xyz/v1/models';

  @override
  List<String> getModelListCandidates(String apiKey) => [
        'https://api.together.xyz/v1/models',
      ];
}
