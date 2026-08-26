import 'package:dio/dio.dart';

class UrlSkillSource {
  static const int _maxBytes = 400 * 1024;
  final Dio _dio;

  UrlSkillSource({Dio? dio}) : _dio = dio ?? Dio();

  /// Fetches raw markdown from [url]. Enforces size cap and content-type check.
  Future<String> fetchFromUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      throw Exception('Invalid URL — must be http(s)');
    }

    final resp = await _dio.get<String>(
      uri.toString(),
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
        validateStatus: (_) => true,
        headers: {'Accept': 'text/markdown, text/plain, */*'},
      ),
    );

    if (resp.statusCode == null || resp.statusCode! < 200 || resp.statusCode! >= 300) {
      throw Exception('Failed to fetch (${resp.statusCode})');
    }

    final contentType = (resp.headers.value('content-type') ?? '').toLowerCase();
    // Reject obvious binary types.
    if (contentType.contains('image/') ||
        contentType.contains('video/') ||
        contentType.contains('audio/') ||
        contentType.contains('application/octet-stream') ||
        contentType.contains('application/zip') ||
        contentType.contains('application/gzip')) {
      throw Exception('URL did not return text/markdown (got $contentType)');
    }

    final body = resp.data ?? '';
    if (body.isEmpty) throw Exception('Empty response');
    if (body.length > _maxBytes) {
      throw Exception('Content too large (${body.length} chars, max $_maxBytes)');
    }
    // Basic markdown sanity: must contain some text, not just binary.
    if (body.codeUnits.any((c) => c == 0)) {
      throw Exception('Binary content detected — not a markdown file');
    }
    return body;
  }

  /// Tries to extract YAML frontmatter name/description if present.
  static Map<String, String> parseFrontmatter(String content) {
    final result = <String, String>{};
    final trimmed = content.trimLeft();
    if (!trimmed.startsWith('---')) return result;
    final end = trimmed.indexOf('\n---', 3);
    if (end == -1) return result;
    final fm = trimmed.substring(3, end);
    for (final line in fm.split('\n')) {
      final idx = line.indexOf(':');
      if (idx == -1) continue;
      final key = line.substring(0, idx).trim().toLowerCase();
      var value = line.substring(idx + 1).trim();
      // Strip quotes.
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }
      if (key == 'name' || key == 'description' || key == 'author') {
        result[key] = value;
      }
    }
    return result;
  }
}
