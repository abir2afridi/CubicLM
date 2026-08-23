import 'dart:convert';

import 'package:http/http.dart' as http;

import '../cloud_provider.dart';

/// Abstract base class for providers that use OpenAI-compatible API format.
///
/// This includes OpenAI, DeepSeek, NVIDIA, OpenRouter, Z.AI, Kimi, and Custom.
/// Override specific methods for providers that need custom behavior.
/// Concrete subclasses must implement: id, name, description, icon, endpoint.
abstract class OpenAICompatibleProvider extends CloudProvider {
  @override
  ProviderProtocol get protocol => ProviderProtocol.openAICompatible;

  @override
  bool get supportsStreaming => true;

  @override
  Future<String> sendMessage({
    required List<Map<String, String>> messages,
    required String apiKey,
    required String model,
    String? imageBase64,
    double? temperature,
    int? maxTokens,
  }) async {
    final body = buildRequestBody(
      messages: messages,
      model: model,
      imageBase64: imageBase64,
      temperature: temperature,
      maxTokens: maxTokens,
      stream: false,
    );

    final response = await http
        .post(
          Uri.parse(endpoint),
          headers: {
            ...buildAuthHeaders(apiKey),
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(minutes: 3));

    if (response.statusCode != 200) {
      throw Exception(
          '${runtimeType.toString()} API error: ${response.statusCode} ${response.body}');
    }

    final data = jsonDecode(response.body);
    return data['choices'][0]['message']['content']?.toString() ?? '';
  }

  @override
  Stream<String> streamMessage({
    required List<Map<String, String>> messages,
    required String apiKey,
    required String model,
    String? imageBase64,
    double? temperature,
    int? maxTokens,
  }) async* {
    final body = buildRequestBody(
      messages: messages,
      model: model,
      imageBase64: imageBase64,
      temperature: temperature,
      maxTokens: maxTokens,
      stream: true,
    );

    final request = http.Request('POST', Uri.parse(endpoint));
    request.headers.addAll({
      ...buildAuthHeaders(apiKey),
      'Content-Type': 'application/json',
    });
    request.body = jsonEncode(body);

    final streamedResponse = await request.send().timeout(
          const Duration(minutes: 3),
        );

    if (streamedResponse.statusCode != 200) {
      final errorBody = await streamedResponse.stream.bytesToString();
      throw Exception(
          '${runtimeType.toString()} streaming error: ${streamedResponse.statusCode} $errorBody');
    }

    String buffer = '';
    await for (final chunk in streamedResponse.stream.transform(
        utf8.decoder)) {
      buffer += chunk;
      final lines = buffer.split('\n');
      buffer = lines.removeLast();

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || !trimmed.startsWith('data: ')) continue;
        final jsonStr = trimmed.substring(6);
        if (jsonStr == '[DONE]') return;

        try {
          final data = jsonDecode(jsonStr);
          final delta = data['choices']?[0]?['delta']?['content'];
          if (delta != null) yield delta.toString();
        } catch (_) {}
      }
    }

    if (buffer.trim().isNotEmpty) {
      final trimmed = buffer.trim();
      if (trimmed.startsWith('data: ') && trimmed.substring(6) != '[DONE]') {
        try {
          final data = jsonDecode(trimmed.substring(6));
          final delta = data['choices']?[0]?['delta']?['content'];
          if (delta != null) yield delta.toString();
        } catch (_) {}
      }
    }
  }

  @override
  List<String> parseModelIds(String body) {
    final data = jsonDecode(body);
    List<String> tryExtract(Map root) {
      for (final key in ['data', 'models', 'results', 'items', 'model_list']) {
        final raw = root[key];
        if (raw is List && raw.isNotEmpty) {
          final ids = raw
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
          if (ids.isNotEmpty) return ids;
        }
      }
      return const [];
    }

    if (data is Map<String, dynamic>) {
      final ids = tryExtract(data);
      if (ids.isNotEmpty) return ids;
    }

    if (data is List) {
      final ids = data
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
      if (ids.isNotEmpty) return ids;
    }

    return const [];
  }
}
