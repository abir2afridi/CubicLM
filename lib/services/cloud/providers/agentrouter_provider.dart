import 'package:flutter/material.dart';

import 'openai_compatible_provider.dart';

/// AgentRouter — non-profit OpenAI-compatible gateway.
///
/// Dozens of models (Claude, GPT, Gemini, DeepSeek, GLM…) behind one
/// key at https://agentrouter.org/v1 (keys from /console/token).
class AgentRouterProvider extends OpenAICompatibleProvider {
  @override
  String get id => 'agentrouter';

  @override
  String get name => 'AgentRouter';

  @override
  String get description => 'OpenAI gateway · Claude/GPT/Gemini/GLM';

  @override
  IconData get icon => Icons.hub_outlined;

  @override
  String get endpoint => 'https://agentrouter.org/v1/chat/completions';

  @override
  String? get modelListEndpoint => 'https://agentrouter.org/v1/models';

  @override
  List<String> getModelListCandidates(String apiKey) => [
        'https://agentrouter.org/v1/models',
      ];
}
