import 'package:flutter/material.dart';

import 'openai_compatible_provider.dart';

/// xAI provider — Grok models.
class XaiProvider extends OpenAICompatibleProvider {
  @override
  String get id => 'xai';

  @override
  String get name => 'xAI Grok';

  @override
  String get description => 'Grok-4, Grok-3, vision';

  @override
  IconData get icon => Icons.close_fullscreen_outlined;

  @override
  String get endpoint => 'https://api.x.ai/v1/chat/completions';

  @override
  String? get modelListEndpoint => 'https://api.x.ai/v1/models';

  @override
  List<String> getModelListCandidates(String apiKey) => [
        'https://api.x.ai/v1/models',
      ];
}
