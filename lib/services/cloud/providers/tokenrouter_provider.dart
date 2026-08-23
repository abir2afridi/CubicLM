import 'package:flutter/material.dart';

import 'openai_compatible_provider.dart';

/// TokenRouter — unified multi-model hub (OpenAI-compatible).
///
/// 100+ models across vendors with vendor/model IDs like
/// 'z-ai/glm-5.3', 'xiaomi/mimo-v2.5', 'openai/gpt-5.2'.
class TokenRouterProvider extends OpenAICompatibleProvider {
  @override
  String get id => 'tokenrouter';

  @override
  String get name => 'TokenRouter';

  @override
  String get description => 'Unified hub · 100+ vendor models';

  @override
  IconData get icon => Icons.route_outlined;

  @override
  String get endpoint =>
      'https://api.tokenrouter.com/v1/chat/completions';

  @override
  String? get modelListEndpoint => 'https://api.tokenrouter.com/v1/models';

  @override
  List<String> getModelListCandidates(String apiKey) => [
        'https://api.tokenrouter.com/v1/models',
      ];
}
