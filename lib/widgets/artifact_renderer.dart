import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../controllers/chat_controller.dart';
import '../services/code_interpreter_service.dart';
import '../core/colors.dart';
import '../theme/design_tokens.dart';
import '../utils/prompt_export.dart';

class ArtifactRenderer extends StatefulWidget {
  final String id;
  final List<Map<String, String>> versions;
  final VoidCallback onClose;

  const ArtifactRenderer({
    super.key,
    required this.id,
    required this.versions,
    required this.onClose,
  });

  @override
  State<ArtifactRenderer> createState() => _ArtifactRendererState();
}

class _ArtifactRendererState extends State<ArtifactRenderer> {
  late int _currentIndex;
  bool _isEditing = false;
  bool _isRunning = false;
  late TextEditingController _editController;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.versions.length - 1;
    _editController = TextEditingController(text: widget.versions[_currentIndex]['content']);
  }

  @override
  void didUpdateWidget(covariant ArtifactRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.versions.length != oldWidget.versions.length) {
      _currentIndex = widget.versions.length - 1;
      if (!_isEditing) {
        _editController.text = widget.versions[_currentIndex]['content'] ?? '';
      }
    }
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  void _save() {
    Get.find<ChatController>().updateArtifact(widget.id, _editController.text);
    setState(() => _isEditing = false);
  }

  void _runCode() async {
    final code = _editController.text;
    setState(() => _isRunning = true);

    try {
      final interpreter = Get.find<CodeInterpreterService>();
      final result = await interpreter.executeJs(code);

      if (mounted) {
        showModalBottomSheet(
          context: context,
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? Dt.canvasDark
              : Dt.canvas,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.terminal, size: 20, color: AppColors.primary),
                      const SizedBox(width: 12),
                      Text(
                        'Console Output',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(LucideIcons.x, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SelectableText(
                      result.isEmpty ? '(No output)' : result,
                      style: GoogleFonts.firaCode(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final current = widget.versions[_currentIndex];
    final type = current['type'];
    final title = current['title'] ?? 'Artifact';

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Dt.canvasDark : Dt.canvas,
        border: Border(
          left: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          _header(context, isDark, title, type),
          if (widget.versions.length > 1) _historyBar(isDark),
          Expanded(child: _isEditing ? _editor(isDark) : _content(context, isDark, current['content'] ?? '', type)),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, bool isDark, String title, String? type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _getIcon(type),
            size: 18,
            color: AppColors.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: isDark ? AppColors.textPrimary : Dt.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_isEditing)
            IconButton(
              icon: const Icon(LucideIcons.save, size: 20, color: AppColors.success),
              onPressed: _save,
              tooltip: 'Save changes',
            )
          else ...[
            if (type == 'code' || type == 'javascript' || type == 'js')
              IconButton(
                icon: _isRunning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(LucideIcons.play, size: 18, color: AppColors.success),
                onPressed: _runCode,
                tooltip: 'Run Javascript',
              ),
            IconButton(
              icon: const Icon(LucideIcons.copy, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _editController.text));
                Get.snackbar('Copied', 'Artifact content copied to clipboard', snackPosition: SnackPosition.BOTTOM);
              },
              tooltip: 'Copy content',
            ),
            IconButton(
              icon: const Icon(LucideIcons.download, size: 18),
              onPressed: () => PromptExport.shareAsMarkdown(_editController.text, baseName: title),
              tooltip: 'Download as Markdown',
            ),
            IconButton(
              icon: const Icon(LucideIcons.edit3, size: 18),
              onPressed: () => setState(() => _isEditing = true),
              tooltip: 'Edit artifact',
            ),
          ],
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(LucideIcons.x, size: 20),
            onPressed: widget.onClose,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _historyBar(bool isDark) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.02) : Colors.black.withValues(alpha: 0.02),
      ),
      child: Row(
        children: [
          Text(
            'Version ${_currentIndex + 1} of ${widget.versions.length}',
            style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, color: Dt.textSecondary),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(LucideIcons.chevronLeft, size: 16),
            onPressed: _currentIndex > 0 ? () => setState(() {
              _currentIndex--;
              _editController.text = widget.versions[_currentIndex]['content'] ?? '';
            }) : null,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(LucideIcons.chevronRight, size: 16),
            onPressed: _currentIndex < widget.versions.length - 1 ? () => setState(() {
              _currentIndex++;
              _editController.text = widget.versions[_currentIndex]['content'] ?? '';
            }) : null,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _editor(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _editController,
        maxLines: null,
        expands: true,
        style: GoogleFonts.firaCode(
          fontSize: 13,
          color: isDark ? AppColors.textPrimary : Dt.textPrimary,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          hintText: 'Edit your content here...',
        ),
      ),
    );
  }

  Widget _content(BuildContext context, bool isDark, String content, String? type) {
    if (type == 'html') {
      return InAppWebView(
        initialData: InAppWebViewInitialData(
          data: content,
          mimeType: 'text/html',
          encoding: 'utf-8',
        ),
        initialSettings: InAppWebViewSettings(
          transparentBackground: true,
          supportZoom: true,
        ),
      );
    }

    // Default to Markdown/Code view
    return Markdown(
      data: '```${type ?? ""}\n$content\n```',
      selectable: true,
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        codeblockDecoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.02) : Colors.black.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  IconData _getIcon(String? type) {
    switch (type) {
      case 'html':
        return LucideIcons.layout;
      case 'code':
        return LucideIcons.code2;
      case 'mermaid':
        return LucideIcons.gitBranch;
      default:
        return LucideIcons.fileText;
    }
  }
}
