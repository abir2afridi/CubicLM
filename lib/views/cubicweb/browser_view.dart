/// CubicWeb Browser: privacy-focused in-app browser for the Toolkit.
///
/// - Static ad-block list (assets, in-memory only) via
///   shouldInterceptRequest + a bundled cosmetic script. No remote
///   scripts, no history database — back/forward stacks die with the page.
/// - Extract button reads the page text and drops it into the chat
///   composer for the local model (user reviews before sending).
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../controllers/chat_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../services/browser/adblock_service.dart';
import '../../theme/design_tokens.dart';

class BrowserView extends StatefulWidget {
  const BrowserView({super.key});

  /// True for search phrases: contains a space, or a bare word with no
  /// dot/port/scheme (e.g. "weather dhaka"). Anything address-like
  /// ("example.com", "localhost:8080", "https://…") is a URL.
  /// Test seam — [_BrowserViewState._go] routes through here.
  static bool looksLikeSearch(String s) {
    if (s.contains(' ')) return true;
    if (s.contains('://')) return false;
    if (s.contains(':')) return false; // host:port
    return !s.contains('.');
  }

  /// Test seam for [_BrowserViewState._go].
  static String searchUrl(String query) =>
      'https://duckduckgo.com/?q=${Uri.encodeQueryComponent(query)}';

  /// Push with a cap (oldest drops). Test seam for history routing.
  static void pushCapped(List<String> stack, String url, [int cap = 50]) {
    stack.add(url);
    while (stack.length > cap) {
      stack.removeAt(0);
    }
  }

  @override
  State<BrowserView> createState() => _BrowserViewState();
}

class _BrowserViewState extends State<BrowserView> {
  InAppWebViewController? _webCtrl;
  final _urlCtrl = TextEditingController();
  final _backStack = <String>[];
  final _fwdStack = <String>[];
  String _current = '';
  // First navigation can arrive before the platform view reports its
  // controller — hold it here and fire from onWebViewCreated.
  String? _pendingUrl;
  // True while a back/forward load is in flight so onLoadStart files the
  // previous page on the opposite stack instead of treating it as new.
  bool _historyNav = false;
  bool _historyBack = true;
  double _progress = 0;
  bool _loading = false;
  int _blockedCount = 0;

  /// Single source of truth for the toggle — read live every call so the
  /// request interceptor and load-stop hook never run on a stale copy.
  bool _adblockEnabledNow() {
    try {
      if (Get.isRegistered<SettingsController>()) {
        return Get.find<SettingsController>().adblockEnabled.value;
      }
    } catch (_) {}
    return true;
  }

  @override
  void initState() {
    super.initState();
    AdblockService.ensureLoaded();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  String _normalize(String input) {
    var u = input.trim();
    if (u.isEmpty) return u;
    if (!u.contains('://')) u = 'https://$u';
    return u;
  }

  Future<void> _go(String input) async {
    final raw = input.trim();
    if (raw.isEmpty) return;
    // Plain words go to search so every input does something useful.
    final url = BrowserView.looksLikeSearch(raw)
        ? BrowserView.searchUrl(raw)
        : _normalize(raw);
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      Get.snackbar('Invalid URL', 'Type a valid web address.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    // Stacks are filed centrally in onLoadStart so in-page link taps,
    // redirects and typed navigations all behave the same.
    Get.focusScope?.unfocus();
    setState(() => _blockedCount = 0);
    await _loadUrl(url);
  }

  Future<void> _loadUrl(String url) async {
    final ctrl = _webCtrl;
    if (ctrl == null) {
      setState(() => _pendingUrl = url);
      return;
    }
    await ctrl.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  Future<void> _goBack() async {
    if (_backStack.isEmpty) return;
    final url = _backStack.removeLast();
    _historyNav = true;
    _historyBack = true;
    setState(() => _blockedCount = 0);
    await _loadUrl(url);
  }

  Future<void> _goForward() async {
    if (_fwdStack.isEmpty) return;
    final url = _fwdStack.removeLast();
    _historyNav = true;
    _historyBack = false;
    setState(() => _blockedCount = 0);
    await _loadUrl(url);
  }

  Future<void> _extractToChat() async {
    if (_current.isEmpty) {
      Get.snackbar('Nothing to extract', 'Open a page first.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    try {
      final raw = await _webCtrl?.evaluateJavascript(
          source: AdblockService.extractJs);
      String title = '';
      String text = '';
      if (raw is Map) {
        title = '${raw['title'] ?? ''}';
        text = '${raw['text'] ?? ''}';
      } else if (raw is String && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            title = '${decoded['title'] ?? ''}';
            text = '${decoded['text'] ?? ''}';
          }
        } catch (_) {}
      }
      text = text.trim();
      if (text.isEmpty) {
        Get.snackbar('Empty page', 'No readable text found.',
            snackPosition: SnackPosition.BOTTOM);
        return;
      }
      if (!Get.isRegistered<ChatController>()) {
        Get.snackbar('Chat unavailable', 'Open Chat first.',
            snackPosition: SnackPosition.BOTTOM);
        return;
      }
      Get.find<ChatController>()
          .insertBrowserExtract(title, _current, text);
      Get.snackbar('Added to chat',
          'Page text is in the composer — review and send.',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 3));
    } catch (e) {
      Get.snackbar('Extract failed', '$e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? Dt.canvasDark : Dt.canvas,
      appBar: AppBar(
        title: Text('CubicWeb Browser',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800, fontSize: 17)),
        actions: [
          Obx(() {
            var on = true;
            try {
              if (Get.isRegistered<SettingsController>()) {
                on = Get.find<SettingsController>()
                    .adblockEnabled
                    .value;
              }
            } catch (_) {}
            return IconButton(
              tooltip: on ? 'Ad-block on' : 'Ad-block off',
              icon: Icon(LucideIcons.shieldCheck,
                  size: 20, color: on ? Dt.accent : null),
              onPressed: () async {
                try {
                  if (Get.isRegistered<SettingsController>()) {
                    final s = Get.find<SettingsController>();
                    await s.setAdblockEnabled(!s.adblockEnabled.value);
                    setState(() => _blockedCount = 0);
                    await _webCtrl?.reload();
                  }
                } catch (_) {}
              },
            );
          }),
          IconButton(
            tooltip: 'Extract page to chat',
            icon: const Icon(LucideIcons.clipboardList, size: 20),
            onPressed: _extractToChat,
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(children: [
            IconButton(
              tooltip: 'Back',
              icon: const Icon(LucideIcons.arrowLeft, size: 20),
              onPressed: _backStack.isEmpty ? null : _goBack,
            ),
            IconButton(
              tooltip: 'Forward',
              icon: const Icon(LucideIcons.arrowRight, size: 20),
              onPressed: _fwdStack.isEmpty ? null : _goForward,
            ),
            IconButton(
              tooltip: 'Reload',
              icon: const Icon(LucideIcons.refreshCw, size: 18),
              onPressed: () => _webCtrl?.reload(),
            ),
            Expanded(
              child: TextField(
                controller: _urlCtrl,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                style: GoogleFonts.plusJakartaSans(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search or enter address',
                  isDense: true,
                  filled: true,
                  fillColor: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.04),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
                onSubmitted: _go,
              ),
            ),
          ]),
        ),
        if (_loading)
          LinearProgressIndicator(
            value: _progress <= 0 || _progress >= 1 ? null : _progress,
            minHeight: 2,
            backgroundColor: Colors.transparent,
            valueColor: const AlwaysStoppedAnimation<Color>(Dt.accent),
          ),
        if (_current.isNotEmpty || _blockedCount > 0)
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              Expanded(
                child: Text(
                  _current,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: Theme.of(context).hintColor),
                ),
              ),
              if (_blockedCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Dt.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('$_blockedCount blocked',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Dt.accent)),
                ),
            ]),
          ),
        Expanded(
          // The platform view must exist from the first frame — otherwise
          // the very first navigation has no controller to load into.
          // The welcome overlay covers it until a page actually loads.
          child: Stack(children: [
            InAppWebView(
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    domStorageEnabled: true,
                    supportZoom: true,
                    transparentBackground: false,
                    // Off on purpose: platform swipe nav would bypass the
                    // Dart back/forward stacks above.
                    allowsBackForwardNavigationGestures: false,
                  ),
                  onWebViewCreated: (ctrl) {
                    _webCtrl = ctrl;
                    final pending = _pendingUrl;
                    if (pending != null) {
                      _pendingUrl = null;
                      ctrl.loadUrl(
                          urlRequest:
                              URLRequest(url: WebUri(pending)));
                    }
                  },
                  shouldInterceptRequest:
                      (controller, request) async {
                    if (!_adblockEnabledNow()) return null;
                    final url = request.url.toString();
                    if (url.isEmpty) return null;
                    final mainFrame = request.isForMainFrame ?? false;
                    if (AdblockService.isBlockedUrl(url,
                        isMainFrame: mainFrame)) {
                      if (mounted) {
                        setState(() => _blockedCount++);
                      }
                      return WebResourceResponse(
                        contentType: 'text/plain',
                        statusCode: 404,
                        reasonPhrase: 'Blocked',
                        headers: const {},
                      );
                    }
                    return null;
                  },
                  onLoadStart: (_, url) {
                    final u = url?.toString() ?? '';
                    if (u.isNotEmpty && u != 'about:blank' && u != _current) {
                      // Central history filing: every committed navigation
                      // lands here — typed, tapped, redirected or
                      // back/forward — so Back always works.
                      setState(() {
                        if (_current.isNotEmpty) {
                          if (_historyNav) {
                            if (_historyBack) {
                              _fwdStack.add(_current);
                            } else {
                              _backStack.add(_current);
                            }
                          } else {
                            BrowserView.pushCapped(_backStack, _current);
                            _fwdStack.clear();
                          }
                        }
                        _current = u;
                        _urlCtrl.text = u;
                      });
                      _historyNav = false;
                    }
                    setState(() => _loading = true);
                  },
                  onProgressChanged: (_, progress) {
                    setState(() => _progress = progress / 100);
                  },
                  onLoadStop: (_, __) async {
                    setState(() {
                      _loading = false;
                      _progress = 0;
                    });
                    if (_adblockEnabledNow()) {
                      try {
                        await _webCtrl?.evaluateJavascript(
                            source: AdblockService.cosmeticJs);
                      } catch (_) {}
                    }
                  },
                  onReceivedError: (_, __, err) {
                    if (!mounted) return;
                    setState(() => _loading = false);
                    Get.snackbar(
                      'Page failed to load',
                      err.description.isNotEmpty
                          ? err.description
                          : 'Check your connection and try again.',
                      snackPosition: SnackPosition.BOTTOM,
                    );
                  },
                ),
            if (_current.isEmpty)
              Positioned.fill(
                child: Container(
                  color: isDark ? Dt.canvasDark : Dt.canvas,
                  child: _emptyState(context, isDark),
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _emptyState(BuildContext context, bool isDark) {
    const quick = [
      ('Wikipedia', 'wikipedia.org'),
      ('DuckDuckGo', 'duckduckgo.com'),
      ('arXiv', 'arxiv.org'),
      ('MDN Docs', 'developer.mozilla.org'),
    ];
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 24),
        Icon(LucideIcons.globe,
            size: 48, color: Dt.accent.withValues(alpha: 0.6)),
        const SizedBox(height: 16),
        Text('Private browsing',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          'Ads and trackers are blocked from a built-in list. '
          'No history is saved — ever.',
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              height: 1.5,
              color: Theme.of(context).hintColor),
        ),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final q in quick)
              ActionChip(
                label: Text(q.$1,
                    style: GoogleFonts.plusJakartaSans(fontSize: 12)),
                onPressed: () => _go(q.$2),
              ),
          ],
        ),
      ],
    );
  }
}
