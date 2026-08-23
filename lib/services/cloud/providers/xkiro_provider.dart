import 'package:flutter/material.dart';

import 'openai_compatible_provider.dart';

/// xKiro — unified AI gateway with smart routing and fallback.
///
/// One key for every model, vendor/model IDs like 'openai/gpt-5.2',
/// 20+ free models, OpenAI + Anthropic SDK compatible.
class XkiroProvider extends OpenAICompatibleProvider {
  @override
  String get id => 'xkiro';

  @override
  String get name => 'xKiro';

  @override
  String get description => 'Smart router · free tier · all vendors';

  @override
  IconData get icon => Icons.swap_horiz_outlined;

  @override
  String get endpoint => 'https://api.xkiro.com/v1/chat/completions';

  @override
  String? get modelListEndpoint => 'https://api.xkiro.com/v1/models';

  @override
  List<String> getModelListCandidates(String apiKey) => [
        'https://api.xkiro.com/v1/models',
      ];
}
