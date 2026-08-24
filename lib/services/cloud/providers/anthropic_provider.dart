import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../cloud_provider.dart';

/// Anthropic provider implementation.
///
/// Uses Anthropic's native Messages API format, not OpenAI-compatible.
class AnthropicProvider extends CloudProvider {
  @override
  String get id => 'anthropic';

  @override
  String get name => 'Anthropic';

  @override
  String get description => 'Claude 4, Claude 3.5 Sonnet';

  @override
  IconData get icon => Icons.psychology_outlined;

  @override
  ProviderProtocol get protocol => ProviderProtocol.anthropic;

  @override
  bool get supportsStreaming => true;

  @override
  String get endpoint => 'https://api.anthropic.com/v1/messages';

  @override
  String? get modelListEndpoint => 'https://api.anthropic.com/v1/models';

  @override
  Map<String, String> buildAuthHeaders(String apiKey) {
    return {
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    };
  }

  @override
  Future<String> sendMessage({
    required List<Map<String, String>> messages,
    required String apiKey,
    required String model,
    String? imageBase64,
    double? temperature,
    int? maxTokens,
  }) async {
    final apiMessages = <Map<String, dynamic>>[];
    String? systemPrompt;

    for (final msg in messages) {
      if (msg['role'] == 'system') {
        systemPrompt = msg['content'];
      } else if (msg['role'] == 'user' &&
          imageBase64 != null &&
          msg == messages.last) {
        apiMessages.add({
          'role': 'user',
          'content': [
            {
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': 'image/jpeg',
                'data': imageBase64,
              },
            },
            {'type': 'text', 'text': msg['content']},
          ],
        });
      } else {
        apiMessages.add({'role': msg['role'], 'content': msg['content']});
      }
    }

    final body = <String, dynamic>{
      'model': model,
      'messages': apiMessages,
      'max_tokens': maxTokens ?? 8192,
    };

    if (systemPrompt != null) body['system'] = systemPrompt;
    if (temperature != null) body['temperature'] = temperature;

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
          'Anthropic API error: ${response.statusCode} ${response.body}');
    }

    final data = jsonDecode(response.body);
    final content = data['content'] as List? ?? [];
    if (content.isEmpty) return '';

    final textBlocks =
        content.where((b) => b['type'] == 'text').map((b) => b['text']);
    return textBlocks.join('\n');
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
    final apiMessages = <Map<String, dynamic>>[];
    String? systemPrompt;

    for (final msg in messages) {
      if (msg['role'] == 'system') {
        systemPrompt = msg['content'];
      } else if (msg['role'] == 'user' &&
          imageBase64 != null &&
          msg == messages.last) {
        apiMessages.add({
          'role': 'user',
          'content': [
            {
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': 'image/jpeg',
                'data': imageBase64,
              },
            },
            {'type': 'text', 'text': msg['content']},
          ],
        });
      } else {
        apiMessages.add({'role': msg['role'], 'content': msg['content']});
      }
    }

    final body = <String, dynamic>{
      'model': model,
      'messages': apiMessages,
      'max_tokens': maxTokens ?? 8192,
      'stream': true,
    };

    if (systemPrompt != null) body['system'] = systemPrompt;
    if (temperature != null) body['temperature'] = temperature;

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
          'Anthropic streaming error: ${streamedResponse.statusCode} $errorBody');
    }

    String buffer = '';
    await for (final chunk
        in streamedResponse.stream.transform(utf8.decoder)) {
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
          if (data['type'] == 'content_block_delta') {
            final delta = data['delta']?['text'];
            if (delta != null) yield delta.toString();
          }
        } catch (_) {}
      }
    }
  }

  @override
  List<String> getModelListCandidates(String apiKey) => [
        'https://api.anthropic.com/v1/models',
      ];

  @override
  List<String> parseModelIds(String body) {
    final data = jsonDecode(body);
    final raw = data['data'] as List? ?? [];
    return raw
        .map((m) => m is Map ? m['id']?.toString() : null)
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
  }
}
