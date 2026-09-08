import 'package:flutter/material.dart';

import 'openai_compatible_provider.dart';

/// OrcaRouter — OpenAI-compatible gateway at provider cost price.
///
/// vendor/model IDs like 'openai/gpt-4o-mini', 'orcarouter/auto';
/// keys start with 'sk-orca-' (console at orcarouter.ai).
class OrcaRouterProvider extends OpenAICompatibleProvider {
  @override
  String get id => 'orcarouter';

  @override
  String get name => 'OrcaRouter';

  @override
  String get description => 'Cost-price gateway · vendor/model IDs';

  @override
  IconData get icon => Icons.sailing_outlined;

  @override
  String get endpoint => 'https://api.orcarouter.ai/v1/chat/completions';

  @override
  String? get modelListEndpoint => 'https://api.orcarouter.ai/v1/models';

  @override
  List<String> getModelListCandidates(String apiKey) => [
        'https://api.orcarouter.ai/v1/models',
      ];
}
