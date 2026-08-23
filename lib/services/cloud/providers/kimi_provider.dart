import 'package:flutter/material.dart';

import 'openai_compatible_provider.dart';

/// Kimi (Moonshot AI) provider implementation.
class KimiProvider extends OpenAICompatibleProvider {
  @override
  String get id => 'kimi';

  @override
  String get name => 'Kimi';

  @override
  String get description => 'Moonshot AI · Long context';

  @override
  IconData get icon => Icons.wb_sunny_outlined;

  @override
  String get endpoint => 'https://api.moonshot.ai/v1/chat/completions';

  @override
  String? get modelListEndpoint => 'https://api.moonshot.ai/v1/models';

  @override
  List<String> getModelListCandidates(String apiKey) => [
        'https://api.moonshot.ai/v1/models',
      ];
}
