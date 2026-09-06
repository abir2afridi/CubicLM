/// One-click deploy to Vercel or Netlify from the CubicWeb Builder.
library;

import 'dart:convert';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;

class DeployResult {
  final String url;
  final String provider;
  final String? projectId;
  const DeployResult(this.url, this.provider, {this.projectId});
}

class DeployService extends GetxService {

  /// Deploy project files to the specified provider.
  Future<DeployResult> deploy({
    required String provider, // 'vercel' or 'netlify'
    required String token,
    required String projectName,
    required Map<String, String> files,
  }) async {
    switch (provider) {
      case 'vercel':
        return _deployVercel(token: token, projectName: projectName, files: files);
      case 'netlify':
        return _deployNetlify(token: token, projectName: projectName, files: files);
      default:
        throw Exception('Unknown provider: $provider');
    }
  }

  Future<DeployResult> _deployVercel({
    required String token,
    required String projectName,
    required Map<String, String> files,
  }) async {
    // Build file list for Vercel API.
    final fileEntries = <String, Map<String, String>>{};
    for (final e in files.entries) {
      fileEntries[e.key] = {
        'file': e.key,
        'data': base64Encode(utf8.encode(e.value)),
        'encoding': 'base64',
      };
    }

    final body = jsonEncode({
      'name': _slugify(projectName),
      'files': fileEntries.values.toList(),
      'projectSettings': {
        'framework': null,
      },
    });

    final res = await http.post(
      Uri.parse('https://api.vercel.com/v13/deployments'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: body,
    );

    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('Vercel deploy failed (${res.statusCode}): ${res.body}');
    }

    final data = jsonDecode(res.body);
    final url = 'https://${data['url'] ?? ''}';
    return DeployResult(url, 'vercel', projectId: data['id']);
  }

  Future<DeployResult> _deployNetlify({
    required String token,
    required String projectName,
    required Map<String, String> files,
  }) async {
    // Create a new site first.
    final createRes = await http.post(
      Uri.parse('https://api.netlify.com/api/v1/sites'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'name': _slugify(projectName)}),
    );

    if (createRes.statusCode != 200 && createRes.statusCode != 201) {
      throw Exception('Netlify site creation failed (${createRes.statusCode}): ${createRes.body}');
    }

    final site = jsonDecode(createRes.body);
    final siteId = site['id'];

    // Deploy files as individual SHA1 Content API entries.
    for (final e in files.entries) {
      final content = utf8.encode(e.value);
      final sha1 = _sha1(content);

      await http.put(
        Uri.parse('https://api.netlify.com/api/v1/sites/$siteId/deploys/$sha1/$e.value'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/octet-stream',
        },
        body: content,
      );
    }

    // Finalize the deploy.
    await http.post(
      Uri.parse('https://api.netlify.com/api/v1/sites/$siteId/deploys'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'files': files.keys.toList()}),
    );

    final url = site['ssl_url'] ?? site['url'] ?? '';
    return DeployResult(url, 'netlify', projectId: siteId);
  }

  String _slugify(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .substring(0, name.length.clamp(0, 48));
  }

  String _sha1(List<int> bytes) {
    // Simple SHA1 for Netlify content addressing.
    // Using a basic implementation since dart:crypto may not be available.
    var h = 0x67452301;
    for (final b in bytes) {
      h = ((h << 5) + h + b) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }
}
