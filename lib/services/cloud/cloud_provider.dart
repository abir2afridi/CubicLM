import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Abstract base class for all cloud AI providers.
///
/// Each provider implements this interface to handle:
/// - Provider metadata (name, icon, description)
/// - API communication (send messages)
/// - Model list fetching
/// - Endpoint configuration
abstract class CloudProvider {
  /// Unique identifier for this provider (e.g., 'openai', 'anthropic').
  String get id;

  /// Display name (e.g., 'OpenAI', 'Anthropic').
  String get name;

  /// Short description for the UI.
  String get description;

  /// Material icon for the provider.
  IconData get icon;

  /// Whether this provider requires an API key for model list fetching.
  bool get requiresKeyForList => true;

  /// Whether this provider supports fetching model lists from API.
  bool get supportsFetch => true;

  /// The base endpoint URL for API calls.
  String get endpoint;

  /// The model list endpoint URL (may be null if not supported).
  String? get modelListEndpoint => null;

  /// Whether this provider supports streaming responses.
  bool get supportsStreaming => false;

  /// The protocol type used by this provider.
  ProviderProtocol get protocol => ProviderProtocol.openAICompatible;

  /// Send a chat completion request.
  ///
  /// [messages] - List of message maps with 'role' and 'content' keys.
  /// [apiKey] - The API key for authentication.
  /// [model] - The model ID to use.
  /// [imageBase64] - Optional base64-encoded image for multimodal requests.
  /// [temperature] - Sampling temperature (0.0-1.0).
  /// [maxTokens] - Maximum tokens in the response.
  ///
  /// Returns the assistant's response text.
  Future<String> sendMessage({
    required List<Map<String, String>> messages,
    required String apiKey,
    required String model,
    String? imageBase64,
    double? temperature,
    int? maxTokens,
  });

  /// Send a streaming chat completion request.
  ///
  /// Returns a stream of response chunks.
  Stream<String> streamMessage({
    required List<Map<String, String>> messages,
    required String apiKey,
    required String model,
    String? imageBase64,
    double? temperature,
    int? maxTokens,
  }) async* {
    throw UnimplementedError(
        'Streaming not supported for ${runtimeType.toString()}');
  }

  /// Fetch the list of available models from the provider's API.
  ///
  /// Returns a list of model ID strings.
  /// Throws an exception if the fetch fails.
  Future<List<String>> fetchModels({
    required String apiKey,
  }) async {
    if (modelListEndpoint == null) {
      throw UnsupportedError(
          'Model list not supported for ${runtimeType.toString()}');
    }

    final response = await http
        .get(
          Uri.parse(modelListEndpoint!),
          headers: {'Authorization': 'Bearer $apiKey'},
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch models: ${response.statusCode}');
    }

    return parseModelIds(response.body);
  }

  /// Parse model IDs from API response body.
  ///
  /// Default implementation handles OpenAI-compatible format (data[].id)
  /// plus common alternates. Override for provider-specific formats.
  List<String> parseModelIds(String body) {
    try {
      final data = jsonDecode(body);

      List<String> fromList(List raw) {
        return raw
            .map((m) {
              if (m is! Map) return null;
              return m['id']?.toString() ??
                  m['name']?.toString() ??
                  m['model']?.toString();
            })
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList();
      }

      if (data is Map<String, dynamic>) {
        for (final key in ['data', 'models', 'results', 'items', 'model_list']) {
          final raw = data[key];
          if (raw is List && raw.isNotEmpty) {
            final ids = fromList(raw);
            if (ids.isNotEmpty) return ids;
          }
        }
        return const [];
      }

      if (data is List) {
        return fromList(data);
      }

      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// Parse model tags from API response body.
  ///
  /// Returns a map of model ID to list of tags (e.g., 'FREE', '128K').
  Map<String, List<String>> parseModelTags(String body) {
    return const {};
  }

  /// Get candidate URLs for model list fetching.
  ///
  /// Providers can override this to try multiple endpoints.
  List<String> getModelListCandidates(String apiKey) {
    if (modelListEndpoint != null) {
      return [modelListEndpoint!];
    }
    return [];
  }

  /// Build the authorization headers for API requests.
  Map<String, String> buildAuthHeaders(String apiKey) {
    return {'Authorization': 'Bearer $apiKey'};
  }

  /// Build the request body for chat completions.
  ///
  /// Default implementation builds OpenAI-compatible format.
  /// Override for providers with different request formats.
  Map<String, dynamic> buildRequestBody({
    required List<Map<String, String>> messages,
    required String model,
    String? imageBase64,
    double? temperature,
    int? maxTokens,
    bool stream = false,
  }) {
    final apiMessages = <Map<String, dynamic>>[];

    for (final msg in messages) {
      if (msg['role'] == 'user' &&
          imageBase64 != null &&
          msg == messages.last) {
        apiMessages.add({
          'role': 'user',
          'content': [
            {'type': 'text', 'text': msg['content']},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/jpeg;base64,$imageBase64'}
            },
          ],
        });
      } else {
        apiMessages.add({'role': msg['role'], 'content': msg['content']});
      }
    }

    final body = <String, dynamic>{
      'model': model,
      'messages': apiMessages,
    };

    if (temperature != null) body['temperature'] = temperature;
    if (maxTokens != null) body['max_tokens'] = maxTokens;
    if (stream) body['stream'] = true;

    return body;
  }
}

/// Protocol types supported by cloud providers.
enum ProviderProtocol {
  /// Standard OpenAI-compatible API format.
  openAICompatible,

  /// Anthropic's native Messages API format.
  anthropic,

  /// Google Gemini's native generateContent format.
  gemini,

  /// Custom protocol (e.g., multipart form-data for image generation).
  custom,
}
