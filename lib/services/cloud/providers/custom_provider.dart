import 'package:flutter/material.dart';

import '../providers/openai_compatible_provider.dart';

/// Custom OpenAI-compatible provider implementation.
///
/// User-configurable endpoint for any OpenAI-compatible API.
class CustomProvider extends OpenAICompatibleProvider {
  final String _endpoint;
  final String _modelListUrl;

  CustomProvider({
    required String endpoint,
    String? modelListUrl,
  })  : _endpoint = endpoint,
        _modelListUrl = modelListUrl ?? '';

  @override
  String get id => 'custom';

  @override
  String get name => 'Custom API';

  @override
  String get description => 'OpenAI-compatible endpoint';

  @override
  IconData get icon => Icons.settings_input_component;

  @override
  bool get requiresKeyForList => true;

  @override
  bool get supportsFetch => _modelListUrl.isNotEmpty || _endpoint.isNotEmpty;

  @override
  String get endpoint => _endpoint;

  @override
  String? get modelListEndpoint =>
      _modelListUrl.isNotEmpty ? _modelListUrl : null;

  @override
  List<String> getModelListCandidates(String apiKey) {
    if (_modelListUrl.isNotEmpty) {
      return [_modelListUrl];
    }

    // Try to derive model list URL from endpoint
    final base = _endpoint
        .replaceAll(RegExp(r'/chat/completions$'), '')
        .replaceAll(RegExp(r'/+$'), '');
    return [
      '$base/models',
      '$base/v1/models',
    ];
  }
}
