import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../controllers/agent_controller.dart';
import '../../theme/design_tokens.dart';

/// Enhanced Preview WebView with "Studio" features:
/// 1. Browser-style header with URL bar.
/// 2. Draggable resize handle.
/// 3. Canvas-style element hover & selection bridge.
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
  double _widthFactor = 1.0;
  bool _isResizing = false;

  bool _forwardedLoadError = false;
  InAppWebViewController? _webCtrl;

  /// JS Bridge for hover & click selection.
  static const _pickerJs = '''
(function(){
  if (window.__cubicPickInstalled) return;
  window.__cubicPickInstalled = true;
  window.__cubicPickArmed = false;
  
  var lastEl = null;
  
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
  
  function clearLast(){
    if(lastEl) {
      lastEl.style.outline = lastEl.__cubicOldOutline || '';
      lastEl = null;
    }
  }

  document.addEventListener('mousemove', function(e){
    if (!window.__cubicPickArmed) return;
    var el = document.elementFromPoint(e.clientX, e.clientY);
    if(el === lastEl) return;
    clearLast();
    if(el && el.tagName && el.tagName !== 'HTML' && el.tagName !== 'BODY') {
      lastEl = el;
      el.__cubicOldOutline = el.style.outline;
      el.style.outline = '2px solid #3B82F6'; // Blue highlight
      window.flutter_inappwebview.callHandler('cubicOnHover', el.tagName.toLowerCase());
    }
  });

  document.addEventListener('click', function(e){
    if (!window.__cubicPickArmed) return;
    e.preventDefault();
    e.stopPropagation();
    var el = document.elementFromPoint(e.clientX, e.clientY);
    if (el && el.tagName) {
      window.flutter_inappwebview.callHandler('cubicOnElement', info(el));
      clearLast();
      window.__cubicPickArmed = false;
    }
  }, true);

  // Mobile Touch Support
  var t = null;
  document.addEventListener('touchstart', function(e){
    if (!window.__cubicPickArmed) return;
    var touch = e.touches[0];
    var target = document.elementFromPoint(touch.clientX, touch.clientY);
    t = setTimeout(function(){
      if (target && target.tagName) {
        target.style.outline = '2px solid #3B82F6';
        setTimeout(function(){ 
          window.flutter_inappwebview.callHandler('cubicOnElement', info(target)); 
          target.style.outline = '';
        }, 150);
      }
    }, 500);
  }, {passive:true});
  document.addEventListener('touchend', function(){ clearTimeout(t); }, {passive:true});
})();
''';

  @override
  void didUpdateWidget(covariant AgentPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pickMode != widget.pickMode) {
      _armPicker(widget.pickMode);
    }
    if (oldWidget.url != widget.url) {
      _forwardedLoadError = false;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ac = Get.find<AgentController>();

    return LayoutBuilder(builder: (context, constraints) {
      final maxWidth = constraints.maxWidth;
      final currentWidth = maxWidth * _widthFactor;

      return Column(
        children: [
          // Browser Header
          _browserHeader(context, isDark),
          
          Expanded(
            child: Stack(
              children: [
                Row(
                  children: [
                    Container(
                      width: currentWidth,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: isDark ? Colors.white10 : Dt.hairline),
                      ),
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
                            ac.previewWebController = ctrl;
                            ctrl.addJavaScriptHandler(
                              handlerName: 'cubicOnElement',
                              callback: (args) {
                                final info = args.isNotEmpty ? '${args.first}' : '';
                                if (info.isNotEmpty && info != '{}') {
                                  widget.onElementPicked(info);
                                }
                              },
                            );
                            ctrl.addJavaScriptHandler(
                              handlerName: 'cubicOnHover',
                              callback: (args) {
                                if (args.isNotEmpty) ac.hoveredElement.value = '${args.first}';
                              },
                            );
                          },
                          onLoadStop: (_, __) {
                            if (mounted) setState(() => _loading = false);
                            _webCtrl?.evaluateJavascript(source: _pickerJs);
                            _armPicker(widget.pickMode);
                          },
                          onReceivedError: (_, __, err) {
                            if (mounted) setState(() => _loading = false);
                            if (!_forwardedLoadError) {
                              _forwardedLoadError = true;
                              if (!ac.generating.value && !ac.fixing.value) {
                                ac.onConsoleError('Page load failed: ${err.description}');
                              }
                            }
                          },
                          onConsoleMessage: (_, msg) {
                            if (msg.messageLevel == ConsoleMessageLevel.ERROR && mounted) {
                              widget.onConsoleError(msg.message);
                            }
                          },
                        ),
                        if (_loading) const LinearProgressIndicator(minHeight: 2),
                      ]),
                    ),
                    // Resize Handle
                    GestureDetector(
                      onHorizontalDragStart: (_) => setState(() => _isResizing = true),
                      onHorizontalDragUpdate: (details) {
                        setState(() {
                          _widthFactor = (_widthFactor + details.delta.dx / maxWidth).clamp(0.2, 1.0);
                        });
                      },
                      onHorizontalDragEnd: (_) => setState(() => _isResizing = false),
                      child: Container(
                        width: 16,
                        color: Colors.transparent,
                        child: Center(
                          child: Container(
                            width: 4,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _isResizing ? Dt.accent : (isDark ? Colors.white10 : Dt.hairline),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                
                // Hover Label (Canvas Mode)
                if (widget.pickMode)
                  Obx(() => ac.hoveredElement.value != null
                      ? Positioned(
                          top: 10,
                          left: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Dt.accent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              ac.hoveredElement.value!,
                              style: GoogleFonts.firaCode(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink()),

                // Dimensions Overlay
                if (_isResizing)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${currentWidth.round()}px',
                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    });
  }

  Widget _browserHeader(BuildContext context, bool isDark) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF3F4F6),
        border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Dt.hairline)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(LucideIcons.rotateCw, size: 14),
            onPressed: () => _webCtrl?.reload(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: isDark ? Colors.black26 : Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: isDark ? Colors.white10 : Dt.hairline),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.globe, size: 12, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(fontSize: 11, color: isDark ? Colors.white70 : Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(LucideIcons.monitor, size: 14, color: Colors.grey),
          const SizedBox(width: 4),
          const Icon(LucideIcons.tablet, size: 14, color: Colors.grey),
          const SizedBox(width: 4),
          const Icon(LucideIcons.smartphone, size: 14, color: Colors.grey),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}
