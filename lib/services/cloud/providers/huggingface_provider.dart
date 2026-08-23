import 'package:flutter/material.dart';

import 'openai_compatible_provider.dart';

/// Hugging Face Router — Inference Providers aggregator.
///
/// Routes to dozens of upstream providers (serverless inference) with
/// vendor/model IDs like 'meta-llama/Llama-3.3-70B-Instruct'.
class HuggingFaceProvider extends OpenAICompatibleProvider {
  @override
  String get id => 'huggingface';

  @override
  String get name => 'Hugging Face';

  @override
  String get description => 'Inference Providers router · many vendors';

  @override
  IconData get icon => Icons.emoji_emotions_outlined;

  @override
  String get endpoint =>
      'https://router.huggingface.co/v1/chat/completions';

  @override
  String? get modelListEndpoint => 'https://router.huggingface.co/v1/models';

  @override
  List<String> getModelListCandidates(String apiKey) => [
        'https://router.huggingface.co/v1/models',
      ];
}
