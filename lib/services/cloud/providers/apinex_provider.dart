import 'package:flutter/material.dart';

import 'openai_compatible_provider.dart';

/// APInex — one-key gateway across OpenAI, Anthropic, Gemini,
/// DeepSeek, Moonshot, Zhipu, xAI (console at apinex.bond).
class ApinexProvider extends OpenAICompatibleProvider {
  @override
  String get id => 'apinex';

  @override
  String get name => 'APInex';

  @override
  String get description => 'One-key gateway · 7 upstream vendors';

  @override
  IconData get icon => Icons.api_outlined;

  @override
  String get endpoint => 'https://apinex.bond/v1/chat/completions';

  @override
  String? get modelListEndpoint => 'https://apinex.bond/v1/models';

  @override
  List<String> getModelListCandidates(String apiKey) => [
        'https://apinex.bond/v1/models',
      ];
}
