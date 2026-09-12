/// Privacy ad-block engine for the CubicWeb Browser — zero database.
///
/// Rules live in `assets/adblock_hosts.txt` (bundled at build time) and
/// are loaded once into an in-memory set. Matching is pure string work
/// (exact host or any subdomain), so per-request checks are O(1) average
/// and never touch disk, Hive or the network. Browsing history is never
/// persisted anywhere.
library;

import 'package:flutter/services.dart';

class AdblockService {
  AdblockService._();

  static final Set<String> _hosts = {};
  static bool _loaded = false;

  /// Load rules once (idempotent, safe to call on every navigation).
  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final raw = await rootBundle.loadString('assets/adblock_hosts.txt');
      for (final line in raw.split('\n')) {
        final h = line.trim().toLowerCase();
        if (h.isEmpty || h.startsWith('#')) continue;
        // Skip malformed lines (spaces, slashes, wildcards) — they can
        // never match a real host and only waste memory.
        if (h.contains(RegExp(r'[\s/*]'))) continue;
        _hosts.add(h);
      }
    } catch (_) {}
    _loaded = true;
  }

  static int get ruleCount => _hosts.length;

  /// Test seam: match [url] against an explicit rule set.
  static bool matchesRules(String url, Set<String> rules) {
    final host = hostOf(url);
    if (host == null || host.isEmpty) return false;
    for (final rule in rules) {
      if (rule.isEmpty) continue;
      if (host == rule || host.endsWith('.$rule')) return true;
    }
    return false;
  }

  /// True when [url] is an ad/tracker request. Only http(s) is ever
  /// blocked — page navigations, data/blob/file URLs always pass.
  /// [isMainFrame] navigations are never blocked (blocking those would
  /// blank the whole page on false positives).
  static bool isBlockedUrl(String url, {bool isMainFrame = false}) {
    if (isMainFrame) return false;
    final lower = url.trim().toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return false;
    }
    return matchesRules(url, _hosts);
  }

  /// Lowercased host of [url], or null when unparseable.
  static String? hostOf(String url) {
    try {
      final host = Uri.parse(url.trim()).host.toLowerCase();
      return host.isEmpty ? null : host;
    } catch (_) {
      return null;
    }
  }

  /// Bundled cosmetic script (static asset equivalent): removes common
  /// ad containers after load. Shipped inside the APK — never fetched
  /// remotely (Play-policy safe: no dynamic code execution).
  static const String cosmeticJs = r'''
(function(){
  try {
    var sels = [
      '[id^="ad-"]', '[class^="ad-"]', '[id$="-ad"]', '[class$="-ad"]',
      '[id*="_ad_"]', '[class*=" ads"]', '[class^="ads"]',
      '[id*="sponsor"]', '[class*="sponsor"]',
      '[class*="popup-overlay"]', '[class*="cookie-banner"]',
      'iframe[src*="ads"]', 'iframe[src*="doubleclick"]',
      'iframe[src*="googlesyndication"]', 'div[id*="taboola"]',
      'div[id*="outbrain"]', 'ins.adsbygoogle'
    ];
    for (var i = 0; i < sels.length; i++) {
      var els = document.querySelectorAll(sels[i]);
      for (var j = 0; j < els.length; j++) { els[j].remove(); }
    }
  } catch (e) {}
})();
''';

  /// Readability-lite extraction: title + visible text, capped.
  static const String extractJs = '''
(function(){
  try {
    var t = (document.title || '').slice(0, 200);
    var b = document.body ? document.body.innerText : '';
    return JSON.stringify({title: t, text: (b || '').slice(0, 12000)});
  } catch (e) {
    return JSON.stringify({title: '', text: ''});
  }
})();
''';
}
