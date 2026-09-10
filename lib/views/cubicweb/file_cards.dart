import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../controllers/agent_controller.dart';
import '../../core/colors.dart';
import '../../services/agent_workspace.dart';
import '../../services/cloud_service.dart';
import '../../theme/design_tokens.dart';
import '../../utils/app_snackbar.dart';
import '../../utils/syntax_highlight.dart';

/// File cards + template/component models for the Files pane.
class WebComponent {
  final String name;
  final IconData icon;
  final String prompt;
  const WebComponent(this.name, this.icon, this.prompt);
}

/// Live streaming file card: read-only highlighted view of the code
/// AS the AI writes it.
class StreamingFileCard extends StatefulWidget {
  final String path;
  final bool isDark;
  const StreamingFileCard({super.key, required this.path, required this.isDark});

  @override
  State<StreamingFileCard> createState() => StreamingFileCardState();
}

class StreamingFileCardState extends State<StreamingFileCard> {
  final _scroll = ScrollController();
  int _shown = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Get.find<AgentController>();
    return Obx(() {
      final content = c.streamingFiles[widget.path] ?? '';
      if (content.length != _shown) {
        _shown = content.length;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients && _scroll.position.maxScrollExtent > 0) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
        });
      }
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Dt.accent.withValues(alpha: 0.4)),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: Dt.accent)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(widget.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.firaCode(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFE0E0E6))),
                ),
                Text('${(content.length / 1024).toStringAsFixed(1)} KB',
                    style: GoogleFonts.firaCode(
                        fontSize: 10, color: const Color(0xFF707076))),
              ]),
              const SizedBox(height: 10),
              Container(
                constraints: const BoxConstraints(maxHeight: 360),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: LineNumberWrapper(
                  content: content,
                  isDark: true,
                  scrollController: _scroll,
                  child: SelectableText.rich(
                    buildHighlightedSpan(highlight(content, widget.path)),
                    style: GoogleFonts.firaCode(fontSize: 11.5, height: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
                const SizedBox(width: 8),
                Text('AI is writing… edits unlock when done',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF707076))),
              ]),
            ]),
      );
    });
  }
}

/// File editor card: owns its controller so parent rebuilds never wipe
/// in-progress edits. Save writes through the workspace service.
class FileEditorCard extends StatefulWidget {
  final String path;
  final String initial;
  final bool isDark;
  const FileEditorCard({
    super.key,
    required this.path,
    required this.initial,
    required this.isDark,
  });

  @override
  State<FileEditorCard> createState() => FileEditorCardState();
}

class FileEditorCardState extends State<FileEditorCard> {
  late final SyntaxHighlightingController _ctrl;
  bool _dirty = false;
  bool _viewMode = false; // false = edit, true = highlighted view
  final _aiEditCtrl = TextEditingController();
  Timer? _ghostTimer;
  bool _requestingGhost = false;

  void _onTextChanged() {
    if (!mounted) return;
    setState(() {
      _dirty = _ctrl.text != widget.initial;
    });
    
    // Ghost Autocomplete Logic
    _ghostTimer?.cancel();
    if (_ctrl.text.isNotEmpty && _ctrl.selection.isCollapsed && _ctrl.selection.baseOffset == _ctrl.text.length) {
      _ghostTimer = Timer(const Duration(milliseconds: 1200), _fetchGhostSuggestion);
    } else {
      if (_ctrl.ghostText != null) {
        setState(() => _ctrl.ghostText = null);
      }
    }
  }

  Future<void> _fetchGhostSuggestion() async {
    if (_requestingGhost || !mounted) return;
    _requestingGhost = true;
    
    try {
      final prompt = 'Complete the following code in "${widget.path}". Return ONLY the next 1-3 lines of code. No prose.\n\nCODE:\n${_ctrl.text}';
      
      final cloud = Get.find<CloudService>();
      final suggestion = await cloud.sendMessage(
        messages: [{'role': 'user', 'content': prompt}],
        maxTokens: 50,
      );
      
      if (mounted && suggestion.trim().isNotEmpty && !suggestion.startsWith('```')) {
        setState(() => _ctrl.ghostText = suggestion);
      }
    } catch (_) {
    } finally {
      _requestingGhost = false;
    }
  }

  void _acceptGhost() {
    if (_ctrl.ghostText != null) {
      final text = _ctrl.text + _ctrl.ghostText!;
      _ctrl.text = text;
      _ctrl.selection = TextSelection.collapsed(offset: text.length);
      setState(() => _ctrl.ghostText = null);
    }
  }

  void _showAiEditDialog() {
    final selection = _ctrl.selection.textInside(_ctrl.text);
    if (selection.trim().isEmpty) {
      AppSnackbar.showTop('Select Text', 'Highlight some code first to use AI Edit.');
      return;
    }

    Get.dialog(
      AlertDialog(
        title: const Row(
          children: [
            Icon(LucideIcons.sparkles, size: 20, color: Dt.accent),
            SizedBox(width: 10),
            Text('AI Inline Edit'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                selection.length > 100 ? '${selection.substring(0, 100)}...' : selection,
                style: GoogleFonts.firaCode(fontSize: 10, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _aiEditCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'e.g., refactor to arrow function, add comments...',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _performAiEdit(selection),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Dt.accent),
            onPressed: () => _performAiEdit(selection),
            child: const Text('Edit with AI'),
          ),
        ],
      ),
    );
  }

  void _performAiEdit(String selection) {
    final prompt = _aiEditCtrl.text.trim();
    if (prompt.isEmpty) return;
    Get.back();
    Get.find<AgentController>().inlineEdit(widget.path, selection, prompt);
    _aiEditCtrl.clear();
  }

  @override
  void initState() {
    super.initState();
    _ctrl = SyntaxHighlightingController(text: widget.initial, path: widget.path);
    _ctrl.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _ghostTimer?.cancel();
    _ctrl.removeListener(_onTextChanged);
    _ctrl.dispose();
    _aiEditCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: widget.isDark
                ? Colors.white.withValues(alpha: 0.07)
                : Dt.hairline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: widget.isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(LucideIcons.fileCode, size: 16, color: Dt.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(widget.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, fontWeight: FontWeight.w800)),
          ),
          if (_dirty)
            Container(
              margin: const EdgeInsets.only(right: 6),
              width: 7,
              height: 7,
              decoration:
                  const BoxDecoration(color: Dt.accent, shape: BoxShape.circle),
            ),
          _actionIcon(LucideIcons.copy, 'Copy', () {
            Clipboard.setData(ClipboardData(text: _ctrl.text));
            AppSnackbar.showTop('Copied', 'Code copied to clipboard', logHistory: false);
          }),
          _actionIcon(LucideIcons.sparkles, 'AI Edit', _showAiEditDialog, color: Dt.accent),
          _actionIcon(_viewMode ? LucideIcons.pencil : LucideIcons.eye,
              _viewMode ? 'Edit' : 'Preview',
              () => setState(() => _viewMode = !_viewMode)),
          _actionIcon(LucideIcons.check, 'Save', () async {
            final ws = Get.find<AgentWorkspaceService>();
            final ac = Get.find<AgentController>();
            final pid = ac.project.value?.id;
            if (pid == null) return;
            final err = await ws.writeFile(pid, widget.path, _ctrl.text);
            if (err != null && context.mounted) {
              AppSnackbar.showTop('Save failed', err);
            } else {
              await ac.notifyFilesChanged();
              if (mounted) setState(() => _dirty = false);
              AppSnackbar.showTop('Saved', widget.path, logHistory: false);
            }
          }, color: Dt.accent),
        ]),
        const SizedBox(height: 10),
        Container(
          constraints: const BoxConstraints(maxHeight: 400),
          width: double.infinity,
          decoration: BoxDecoration(
            color: widget.isDark
                ? const Color(0xFF16161E)
                : const Color(0xFFF8F9FB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isDark ? Colors.white.withValues(alpha: 0.03) : Dt.hairline,
            ),
          ),
          child: LineNumberWrapper(
            content: _ctrl.text,
            isDark: widget.isDark,
            child: _viewMode
                ? SelectableText.rich(
                    buildHighlightedSpan(highlight(_ctrl.text, widget.path)),
                    style: GoogleFonts.firaCode(fontSize: 12, height: 1.5),
                  )
                : CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.tab): () {
                        if (_ctrl.ghostText != null) {
                          _acceptGhost();
                        }
                      },
                    },
                    child: TextField(
                      controller: _ctrl,
                      maxLines: null,
                      scrollPhysics: const NeverScrollableScrollPhysics(),
                      keyboardType: TextInputType.multiline,
                      style: GoogleFonts.firaCode(fontSize: 12, height: 1.5),
                      decoration: const InputDecoration.collapsed(hintText: ''),
                    ),
                  ),
          ),
        ),
      ]),
    );
  }

  Widget _actionIcon(IconData icon, String tooltip, VoidCallback onTap, {Color? color}) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, size: 16, color: color),
        onPressed: onTap,
      ),
    );
  }
}

class FileNode {
  final String name;
  final String path;
  final bool isDir;
  final List<FileNode> children;
  bool isExpanded;

  FileNode({
    required this.name,
    required this.path,
    this.isDir = false,
    this.children = const [],
    this.isExpanded = false,
  });
}

class WebTemplate {
  final String name;
  final IconData icon;
  final String desc;
  final String prompt;
  final String framework;
  const WebTemplate(
      this.name, this.icon, this.desc, this.prompt, this.framework);
}

/// A wrapper that adds VS Code style line numbers to the left of its child.
class LineNumberWrapper extends StatelessWidget {
  final String content;
  final Widget child;
  final bool isDark;
  final double fontSize;
  final ScrollController? scrollController;

  const LineNumberWrapper({
    super.key,
    required this.content,
    required this.child,
    required this.isDark,
    this.fontSize = 12,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final lines = content.split('\n');
    final lineCount = lines.length;
    final lineDigits = lineCount.toString().length;
    final gutterWidth = (lineDigits * 8.0) + 32.0; // More room for numbers
    
    return SingleChildScrollView(
      controller: scrollController,
      scrollDirection: Axis.vertical,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Line Numbers column (Sticky-ish)
          Container(
            width: gutterWidth,
            padding: const EdgeInsets.only(top: 12, right: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F0F14) : Colors.black.withValues(alpha: 0.03),
              border: Border(right: BorderSide(color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(lineCount, (i) {
                return SizedBox(
                  height: fontSize * 1.5, // Match line height (1.5)
                  child: Text(
                    '${i + 1}',
                    style: GoogleFonts.firaCode(
                      fontSize: fontSize * 0.85,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white24 : Colors.black26,
                    ),
                  ),
                );
              }),
            ),
          ),
          // Code content with horizontal scroll
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), // More padding
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

