import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../controllers/agent_controller.dart';
import '../../core/colors.dart';
import '../../theme/design_tokens.dart';

/// Preview WebView with console-error forwarding to the agent loop,
/// plus the v0-style element picker bridge.
/// Extracted from views/agent_ide_view.dart.
/// Preview WebView with console-error forwarding to the agent loop.
class AgentPreview extends StatefulWidget {
  final String url;
  final void Function(String) onConsoleError;
  final bool pickMode;
  final void Function(String) onElementPicked;
  const AgentPreview(
      {super.key,
      required this.url,
      required this.onConsoleError,
      this.pickMode = false,
      required this.onElementPicked});

  @override
  State<AgentPreview> createState() => _AgentPreviewState();
}

class _AgentPreviewState extends State<AgentPreview> {
  bool _loading = true;
  String? _error;

  /// Forwarded to the agent loop at most once per page load, and never
  /// while AI is writing or the dev server is (re)starting — a reload
  /// racing a restart must not trigger pointless file rewrites.
  bool _forwardedLoadError = false;
  InAppWebViewController? _webCtrl;

  /// Long-press (touch) / click (mouse, pick mode only) element picker.
  /// Armed via `window.__cubicPickArmed`; reports JSON to `cubicOnElement`.
  static const _pickerJs = '''
(function(){
  if (window.__cubicPickInstalled) return;
  window.__cubicPickInstalled = true;
  window.__cubicPickArmed = false;
  var t = null, target = null;
  function info(el){
    try {
      var r = el.getBoundingClientRect();
      return JSON.stringify({tag: (el.tagName||'').toLowerCase(),
        id: el.id||'', cls: String(el.className||'').slice(0,120),
        text: (el.innerText||'').slice(0,300),
        html: el.outerHTML.slice(0,800),
        x: Math.round(r.x), y: Math.round(r.y)});
    } catch(e){ return '{}'; }
  }
  function send(el){
    try { window.flutter_inappwebview.callHandler('cubicOnElement', info(el)); } catch(e){}
    window.__cubicPickArmed = false;
  }
  document.addEventListener('touchstart', function(e){
    if (!window.__cubicPickArmed) return;
    var touch = e.touches[0];
    target = document.elementFromPoint(touch.clientX, touch.clientY);
    t = setTimeout(function(){
      if (target && target.tagName) {
        try { target.style.outline = '2px solid #D97757'; } catch(e){}
        setTimeout(function(){ send(target); }, 150);
      }
    }, 550);
  }, {passive:true});
  document.addEventListener('touchend', function(){ clearTimeout(t); }, {passive:true});
  document.addEventListener('mousedown', function(e){
    if (!window.__cubicPickArmed) return;
    var el = e.target;
    if (el && el.tagName) {
      try { el.style.outline = '2px solid #D97757'; } catch(err){}
      e.preventDefault();
      setTimeout(function(){ send(el); }, 150);
    }
  });
})();
''';

  @override
  void didUpdateWidget(covariant AgentPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pickMode != widget.pickMode) {
      _armPicker(widget.pickMode);
    }
  }

  Future<void> _armPicker(bool armed) async {
    try {
      await _webCtrl?.evaluateJavascript(
          source: 'window.__cubicPickArmed = ${armed ? 'true' : 'false'};');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 460,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(widget.url)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              domStorageEnabled: true,
              supportZoom: true,
              transparentBackground: false,
            ),
            onWebViewCreated: (ctrl) {
              _webCtrl = ctrl;
              try {
                Get.find<AgentController>().previewWebController = ctrl;
              } catch (_) {}
              try {
                ctrl.addJavaScriptHandler(
                  handlerName: 'cubicOnElement',
                  callback: (args) {
                    final info = args.isNotEmpty ? '${args.first}' : '';
                    if (info.isNotEmpty && info != '{}') {
                      widget.onElementPicked(info);
                    }
                  },
                );
              } catch (_) {}
            },
            onLoadStop: (_, __) {
              if (mounted) {
                setState(() {
                  _loading = false;
                  _error = null;
                });
              }
              try {
                _webCtrl?.evaluateJavascript(source: _pickerJs);
              } catch (_) {}
              _armPicker(widget.pickMode);
            },
            onReceivedError: (_, __, err) {
              if (mounted) {
                final wasLoading = _loading;
                setState(() {
                  _loading = false;
                  _error = err.description;
                });
                // PREVIEW_LOAD_FAILED → agent loop (once per load, never
                // mid-generation/restart where failures are expected).
                if (wasLoading && !_forwardedLoadError) {
                  _forwardedLoadError = true;
                  try {
                    final ac = Get.find<AgentController>();
                    if (!ac.generating.value &&
                        !ac.fixing.value &&
                        !ac.devServerStarting.value) {
                      ac.onConsoleError('Page load failed: ${err.description}');
                    }
                  } catch (_) {}
                }
              }
            },
            onConsoleMessage: (_, msg) {
              final text = msg.message;
              if (msg.messageLevel == ConsoleMessageLevel.ERROR &&
                  text.isNotEmpty &&
                  mounted) {
                setState(() => _error = text);
                widget.onConsoleError(text);
              }
            },
          ),
          if (_loading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (widget.pickMode && !_loading)
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Dt.accent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('Long-press an element to edit it',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
              ),
            ),
          if (_error != null && !_loading)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_error!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: AppColors.error)),
              ),
            ),
        ]),
      ),
    );
  }
}
