import 'package:flutter/material.dart';

import 'openai_compatible_provider.dart';

/// Perplexity provider — Sonar models with web search grounding.
class PerplexityProvider extends OpenAICompatibleProvider {
  @override
  String get id => 'perplexity';

  @override
  String get name => 'Perplexity';

  @override
  String get description => 'Sonar — web-grounded answers';

  @override
  IconData get icon => Icons.travel_explore_outlined;

  @override
  String get endpoint => 'https://api.perplexity.ai/chat/completions';

  @override
  bool get supportsFetch => false; // No public /models endpoint

  @override
  String? get modelListEndpoint => null;

  @override
  List<String> getModelListCandidates(String apiKey) => [];
}
