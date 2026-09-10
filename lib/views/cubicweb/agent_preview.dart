import 'dart:convert';
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
  OverlayEntry? _promptOverlay;
  final _promptLayer = LayerLink();
  final _canvasPromptCtrl = TextEditingController();

  bool _forwardedLoadError = false;
  InAppWebViewController? _webCtrl;

  /// JS Bridge for hover & click selection + Error interceptor.
  static const _pickerJs = '''
(function(){
  if (window.__cubicPickInstalled) return;
  window.__cubicPickInstalled = true;
  window.__cubicPickArmed = false;

  // Visual Error Interceptor
  window.onerror = function(msg, url, line, col, error) {
    window.flutter_inappwebview.callHandler('cubicOnRuntimeError', JSON.stringify({
      message: msg,
      file: (url||'').split('/').pop(),
      line: line,
      column: col,
      stack: error ? error.stack : ''
    }));
    return false;
  };

  // Promise Error Interceptor
  window.onunhandledrejection = function(event) {
    window.flutter_inappwebview.callHandler('cubicOnRuntimeError', JSON.stringify({
      message: 'Unhandled Rejection: ' + (event.reason ? event.reason.message : 'Unknown'),
      file: 'async',
      line: 0,
      column: 0,
      stack: event.reason ? event.reason.stack : ''
    }));
  };
  
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
      el.style.cursor = 'crosshair';
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
      // Visual feedback for selection
      el.style.backgroundColor = 'rgba(59, 130, 246, 0.2)';
      setTimeout(() => el.style.backgroundColor = '', 1000);
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

  void _showFloatingPrompt(BuildContext context, String info) {
    _hideFloatingPrompt();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Map<String, dynamic> data = jsonDecode(info);
    final double x = (data['x'] as num).toDouble();
    final double y = (data['y'] as num).toDouble();
    final tag = data['tag'] ?? 'element';

    _promptOverlay = OverlayEntry(
      builder: (context) => Positioned(
        width: 300,
        child: CompositedTransformFollower(
          link: _promptLayer,
          showWhenUnlinked: false,
          offset: Offset(x.clamp(0, 50), y + 20), // Basic positioning
          child: Material(
            elevation: 12,
            borderRadius: BorderRadius.circular(12),
            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Dt.accent.withValues(alpha: 0.5), width: 1.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.sparkles, size: 14, color: Dt.accent),
                      const SizedBox(width: 8),
                      Text('Edit <$tag>', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(LucideIcons.x, size: 14),
                        onPressed: _hideFloatingPrompt,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _canvasPromptCtrl,
                    autofocus: true,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'e.g., make this blue, larger font...',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onSubmitted: (val) {
                      if (val.trim().isNotEmpty) {
                        Get.find<AgentController>().topic.value = val;
                        Get.find<AgentController>().modifyProject();
                        _hideFloatingPrompt();
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Dt.accent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        final val = _canvasPromptCtrl.text;
                        if (val.trim().isNotEmpty) {
                          Get.find<AgentController>().topic.value = val;
                          Get.find<AgentController>().modifyProject();
                          _hideFloatingPrompt();
                        }
                      },
                      child: const Text('Apply Change', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_promptOverlay!);
  }

  void _hideFloatingPrompt() {
    _promptOverlay?.remove();
    _promptOverlay = null;
    _canvasPromptCtrl.clear();
  }

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
                      width: (currentWidth - 16).clamp(0.0, double.infinity),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: isDark ? Colors.white10 : Dt.hairline),
                      ),
                      child: CompositedTransformTarget(
                        link: _promptLayer,
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
                                    _showFloatingPrompt(context, info);
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
                              ctrl.addJavaScriptHandler(
                                handlerName: 'cubicOnRuntimeError',
                                callback: (args) {
                                  if (args.isNotEmpty) {
                                    try {
                                      final Map<String, dynamic> data = jsonDecode('${args.first}');
                                      ac.runtimeError.value = data;
                                    } catch (_) {}
                                  }
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
                              final level = msg.messageLevel.toString().split('.').last.toLowerCase();
                              ac.addConsoleLog(level, msg.message);
                              
                              if (msg.messageLevel == ConsoleMessageLevel.ERROR && mounted) {
                                widget.onConsoleError(msg.message);
                              }
                            },
                          ),
                          if (_loading) const LinearProgressIndicator(minHeight: 2),
                        ]),
                      ),
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

                // Error Overlay
                Obx(() {
                  final err = ac.runtimeError.value;
                  if (err == null) return const SizedBox.shrink();
                  return _errorOverlay(context, err);
                }),
              ],
            ),
          ),
        ],
      );
    });
  }

  Widget _errorOverlay(BuildContext context, Map<String, dynamic> err) {
    return Positioned(
      bottom: 20,
      left: 20,
      right: 20,
      child: Material(
        elevation: 12,
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFFFEE2E2), // Red-100
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.withValues(alpha: 0.5), width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.alertCircle, size: 18, color: Colors.red),
                  const SizedBox(width: 10),
                  Text('Runtime Error Detected',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13, fontWeight: FontWeight.w800, color: Colors.red)),
                  const Spacer(),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(LucideIcons.x, size: 16, color: Colors.red),
                    onPressed: () => Get.find<AgentController>().runtimeError.value = null,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(err['message'] ?? 'Unknown error',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.firaCode(fontSize: 11, color: Colors.red[900])),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(LucideIcons.fileCode, size: 12, color: Colors.red),
                  const SizedBox(width: 6),
                  Text('${err['file'] ?? 'unknown'} : ${err['line'] ?? 0}',
                      style: const TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(LucideIcons.wand2, size: 14),
                  label: const Text('Quick Fix with AI', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    Get.find<AgentController>().runtimeError.value = null;
                    Get.find<AgentController>().repairFromError();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
