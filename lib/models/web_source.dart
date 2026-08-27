class WebSource {
  final String url;
  final String domain;
  final String faviconUrl;
  final String title;
  final bool success;

  WebSource({
    required this.url,
    required this.domain,
    required this.faviconUrl,
    this.title = '',
    this.success = true,
  });

  Map<String, dynamic> toMap() => {
        'url': url,
        'domain': domain,
        'faviconUrl': faviconUrl,
        'title': title,
        'success': success,
      };

  factory WebSource.fromMap(Map<dynamic, dynamic> map) => WebSource(
        url: map['url'] ?? '',
        domain: map['domain'] ?? '',
        faviconUrl: map['faviconUrl'] ?? '',
        title: map['title'] ?? '',
        success: map['success'] ?? true,
      );

  static String domainFromUrl(String url) {
    try {
      return Uri.parse(url).host.replaceFirst('www.', '');
    } catch (_) {
      return url;
    }
  }

  static String faviconFor(String url) {
    final domain = domainFromUrl(url);
    if (domain.isEmpty) return '';
    // Google S2 favicon service — reliable, no CORS issues.
    return 'https://www.google.com/s2/favicons?domain=$domain&sz=32';
  }

  static String titleFromHtml(String html, String fallbackUrl) {
    final match = RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false).firstMatch(html);
    if (match != null) {
      var t = match.group(1) ?? '';
      t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (t.isNotEmpty && t.length <= 120) return t;
      if (t.length > 120) return '${t.substring(0, 117)}…';
    }
    return domainFromUrl(fallbackUrl);
  }
}
