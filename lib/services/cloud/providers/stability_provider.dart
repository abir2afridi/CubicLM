import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../cloud_provider.dart';

/// Stability AI provider implementation.
///
/// Uses multipart form-data for image generation, completely different protocol.
class StabilityProvider extends CloudProvider {
  @override
  String get id => 'stability';

  @override
  String get name => 'Stability AI';

  @override
  String get description => 'SD3.5 image generation';

  @override
  IconData get icon => Icons.image_outlined;

  @override
  bool get requiresKeyForList => true;

  @override
  bool get supportsFetch => false;

  @override
  ProviderProtocol get protocol => ProviderProtocol.custom;

  @override
  String get endpoint =>
      'https://api.stability.ai/v2beta/stable-image/generate/sd3';

  @override
  String? get modelListEndpoint => null;

  @override
  Future<String> sendMessage({
    required List<Map<String, String>> messages,
    required String apiKey,
    required String model,
    String? imageBase64,
    double? temperature,
    int? maxTokens,
  }) async {
    final prompt = messages
        .where((m) => m['role'] == 'user')
        .map((m) => m['content'])
        .join('\n');

    final request = http.MultipartRequest('POST', Uri.parse(endpoint));
    request.headers['Authorization'] = 'Bearer $apiKey';
    request.headers['Accept'] = 'image/*';

    request.fields['prompt'] = prompt;
    request.fields['output_format'] = 'jpeg';

    if (imageBase64 != null) {
      final imageBytes = base64Decode(imageBase64);
      request.files.add(http.MultipartFile.fromBytes(
        'image',
        imageBytes,
        filename: 'input.jpg',
      ));
    }

    final response = await request.send().timeout(
          const Duration(minutes: 2),
        );

    if (response.statusCode != 200) {
      final errorBody = await response.stream.bytesToString();
      throw Exception(
          'Stability AI error: ${response.statusCode} $errorBody');
    }

    final imageBytes = await response.stream.toBytes();
    final base64Image = base64Encode(imageBytes);
    return '[IMAGE_BASE64]$base64Image';
  }

  @override
  List<String> getModelListCandidates(String apiKey) => [];

  @override
  List<String> parseModelIds(String body) {
    return ['sd3.5-flash', 'sd3.5-medium', 'sd3-large'];
  }
}
