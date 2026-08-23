import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../cloud_provider.dart';

/// Google Gemini provider implementation.
///
/// Uses Google's native generateContent API format.
class GoogleProvider extends CloudProvider {
  @override
  String get id => 'google';

  @override
  String get name => 'Google Gemini';

  @override
  String get description => 'Gemini 2.5 Flash, Gemini Pro';

  @override
  IconData get icon => Icons.diamond_outlined;

  @override
  ProviderProtocol get protocol => ProviderProtocol.gemini;

  @override
  bool get supportsStreaming => true;

  @override
  String get endpoint =>
      'https://generativelanguage.googleapis.com/v1beta/models';

  @override
  String? get modelListEndpoint =>
      'https://generativelanguage.googleapis.com/v1beta/models';

  @override
  Map<String, String> buildAuthHeaders(String apiKey) {
    return {}; // Google uses query parameter for auth
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
    final contents = <Map<String, dynamic>>[];

    for (final msg in messages) {
      if (msg['role'] == 'system') continue; // Gemini handles system differently

      final parts = <Map<String, dynamic>>[];

      if (msg['role'] == 'user' &&
          imageBase64 != null &&
          msg == messages.last) {
        parts.add({
          'inline_data': {
            'mime_type': 'image/jpeg',
            'data': imageBase64,
          },
        });
      }

      parts.add({'text': msg['content']});

      contents.add({
        'role': msg['role'] == 'assistant' ? 'model' : 'user',
        'parts': parts,
      });
    }

    final body = <String, dynamic>{
      'contents': contents,
      'generationConfig': <String, dynamic>{
        if (temperature != null) 'temperature': temperature,
        if (maxTokens != null) 'maxOutputTokens': maxTokens,
      },
    };

    // Add system instruction if present
    final systemMsg = messages.firstWhere(
      (m) => m['role'] == 'system',
      orElse: () => {'role': '', 'content': ''},
    );
    if (systemMsg['content']!.isNotEmpty) {
      body['systemInstruction'] = {
        'parts': [{'text': systemMsg['content']}]
      };
    }

    final url = '$endpoint/$model:generateContent?key=$apiKey';
    final response = await http
        .post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(minutes: 3));

    if (response.statusCode != 200) {
      throw Exception(
          'Google Gemini API error: ${response.statusCode} ${response.body}');
    }

    final data = jsonDecode(response.body);
    final candidates = data['candidates'] as List? ?? [];
    if (candidates.isEmpty) return '';

    final content = candidates[0]['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List? ?? [];
    return parts.map((p) => p['text']?.toString() ?? '').join('\n');
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
    final contents = <Map<String, dynamic>>[];

    for (final msg in messages) {
      if (msg['role'] == 'system') continue;

      final parts = <Map<String, dynamic>>[];

      if (msg['role'] == 'user' &&
          imageBase64 != null &&
          msg == messages.last) {
        parts.add({
          'inline_data': {
            'mime_type': 'image/jpeg',
            'data': imageBase64,
          },
        });
      }

      parts.add({'text': msg['content']});

      contents.add({
        'role': msg['role'] == 'assistant' ? 'model' : 'user',
        'parts': parts,
      });
    }

    final body = <String, dynamic>{
      'contents': contents,
      'generationConfig': <String, dynamic>{
        if (temperature != null) 'temperature': temperature,
        if (maxTokens != null) 'maxOutputTokens': maxTokens,
      },
    };

    final systemMsg = messages.firstWhere(
      (m) => m['role'] == 'system',
      orElse: () => {'role': '', 'content': ''},
    );
    if (systemMsg['content']!.isNotEmpty) {
      body['systemInstruction'] = {
        'parts': [{'text': systemMsg['content']}]
      };
    }

    final url = '$endpoint/$model:streamGenerateContent?alt=sse&key=$apiKey';
    final request = http.Request('POST', Uri.parse(url));
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode(body);

    final streamedResponse = await request.send().timeout(
          const Duration(minutes: 3),
        );

    if (streamedResponse.statusCode != 200) {
      final errorBody = await streamedResponse.stream.bytesToString();
      throw Exception(
          'Google Gemini streaming error: ${streamedResponse.statusCode} $errorBody');
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

        try {
          final data = jsonDecode(jsonStr);
          final candidates = data['candidates'] as List? ?? [];
          if (candidates.isEmpty) continue;
          final parts =
              candidates[0]['content']?['parts'] as List? ?? [];
          for (final part in parts) {
            final text = part['text']?.toString();
            if (text != null) yield text;
          }
        } catch (_) {}
      }
    }
  }

  @override
  List<String> getModelListCandidates(String apiKey) => [
        'https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey',
      ];

  @override
  List<String> parseModelIds(String body) {
    final data = jsonDecode(body);
    final raw = data['models'] as List? ?? [];
    return raw
        .map((model) => model is Map ? model['name']?.toString() : null)
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
  }
}
