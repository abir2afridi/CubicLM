import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import 'app_log_service.dart';

/// Lightweight web access for chat.
///
/// When the user's message contains URLs, each page is fetched, stripped
/// down to readable text and appended to the prompt — giving the model
/// real content to reason over (works for both local and cloud models).
class WebFetchService {
  WebFetchService._();

  static final RegExp _urlRegex = RegExp(
    r'https?://[^\s<>"\)\]]+',
    caseSensitive: false,
  );

  static const int _maxUrlsPerMessage = 3;
  static const int _maxCharsPerPage = 9000;
  static const Duration _timeout = Duration(seconds: 15);

  /// Extracts all http(s) URLs from [text].
  static List<String> extractUrls(String text) {
    return _urlRegex
        .allMatches(text)
        .map((m) => m.group(0)!)
        .map((u) => u.replaceAll(RegExp(r'[.,;:!?]+$'), ''))
        .toSet()
        .take(_maxUrlsPerMessage)
        .toList();
  }

  /// Number of unique fetchable links in [text] (after the cap).
  static int countUrls(String text) => extractUrls(text).length;

  /// If [text] contains URLs, fetches them and returns the original text
  /// with the readable page contents appended. Returns [text] unchanged
  /// when there are no URLs (or every fetch failed).
  static Future<String> augmentWithWebContent(String text) async {
    final urls = extractUrls(text);
    if (urls.isEmpty) return text;

    final buffer = StringBuffer(text);
    var fetched = 0;

    for (final url in urls) {
      final page = await fetchAsText(url);
      if (page == null || page.isEmpty) continue;
      fetched++;
      buffer
        ..writeln()
        ..writeln()
        ..writeln('--- Web content from $url ---')
        ..writeln(page)
        ..writeln('--- End of web content ---');
    }

    if (fetched > 0) {
      try {
        Get.find<AppLogService>().info(
          'Web access: fetched $fetched page(s)',
          details: urls.join(', '),
          category: LogCategory.chat,
        );
      } catch (_) {}
      return buffer.toString();
    }
    return text;
  }

  /// Downloads [url] and converts the HTML to readable plain text.
  /// Returns null on network errors or non-200 responses.
  static Future<String?> fetchAsText(String url) async {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;

      final response = await http.get(uri, headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Mobile Safari/537.36 CubicLM/1.0',
        'Accept': 'text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.5',
        'Accept-Language': 'en-US,en;q=0.9',
      }).timeout(_timeout);

      if (response.statusCode != 200) return null;

      final contentType =
          response.headers['content-type'] ?? 'text/html';
      String body = response.body;
      if (contentType.contains('json')) {
        // Leave JSON mostly intact but trim noise.
        body = body.length > _maxCharsPerPage * 2
            ? body.substring(0, _maxCharsPerPage * 2)
            : body;
        return _truncate(body);
      }
      if (!contentType.contains('html') && !contentType.contains('text')) {
        return null; // Skip binaries/images.
      }
      return _truncate(_htmlToText(body));
    } catch (_) {
      return null;
    }
  }

  /// Very small HTML → text extractor: drops scripts/styles, converts
  /// block tags to line breaks, strips tags and decodes common entities.
  static String _htmlToText(String html) {
    var s = html;
    s = s.replaceFirst(RegExp(r'<head[\s\S]*?</head>', caseSensitive: false), '');
    s = s.replaceAll(
        RegExp(r'<(script|style|noscript|svg)[\s\S]*?</\1>',
            caseSensitive: false),
        ' ');
    s = s.replaceAll(
        RegExp(r'</?(p|div|br|li|tr|h[1-6]|section|article|blockquote|pre)[^>]*>',
            caseSensitive: false),
        '\n');
    s = s.replaceAll(RegExp(r'<[^>]+>'), ' ');
    s = _decodeEntities(s);
    s = s.replaceAll(RegExp(r'[ \t]+'), ' ');
    s = s.replaceAll(RegExp(r'\n\s*\n+'), '\n\n');
    return s.trim();
  }

  static String _decodeEntities(String s) {
    return s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1)!);
      return code != null && code > 0 ? String.fromCharCode(code) : '';
    }).replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
      final code = int.tryParse(m.group(1)!, radix: 16);
      return code != null && code > 0 ? String.fromCharCode(code) : '';
    });
  }

  static String _truncate(String s) {
    if (s.length <= _maxCharsPerPage) return s;
    return '${s.substring(0, _maxCharsPerPage)}…[truncated]';
  }
}
