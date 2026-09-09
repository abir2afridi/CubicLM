import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../controllers/agent_controller.dart';
import '../../core/colors.dart';
import '../../services/agent_workspace.dart';
import '../../theme/design_tokens.dart';
import '../../utils/syntax_highlight.dart';

/// File cards + template/component models for the Files pane.
/// Extracted from views/agent_ide_view.dart.
class WebComponent {
  final String name;
  final IconData icon;
  final String prompt;
  const WebComponent(this.name, this.icon, this.prompt);
}

/// Live streaming file card: read-only highlighted view of the code
/// AS the AI writes it. Auto-scrolls while open; replaced by the real
/// editor once the file lands on disk.
class StreamingFileCard extends StatefulWidget {
  final String path;
  final bool isDark;
  const StreamingFileCard(
      {super.key, required this.path, required this.isDark});

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
          if (_scroll.hasClients) {
            try {
              _scroll.jumpTo(_scroll.position.maxScrollExtent);
            } catch (_) {}
          }
        });
      }
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF101014),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Dt.accent.withValues(alpha: 0.35)),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: Dt.accent)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(widget.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.firaCode(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFCDD6F4))),
                ),
                Text('${(content.length / 1024).toStringAsFixed(1)}k',
                    style: GoogleFonts.firaCode(
                        fontSize: 10, color: const Color(0xFF6E6B65))),
              ]),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: SingleChildScrollView(
                  controller: _scroll,
                  child: SelectableText.rich(
                    buildHighlightedSpan(highlight(content, widget.path)),
                    style: GoogleFonts.firaCode(fontSize: 11, height: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text('AI is writing… edits unlock when done',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 10.5, color: const Color(0xFF6E6B65))),
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
  late final TextEditingController _ctrl;
  bool _dirty = false;
  bool _viewMode = false; // false = edit, true = highlighted view

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
    _ctrl.addListener(() {
      final d = _ctrl.text != widget.initial;
      if (d != _dirty && mounted) setState(() => _dirty = d);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: widget.isDark
                ? Colors.white.withValues(alpha: 0.07)
                : Dt.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(widget.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, fontWeight: FontWeight.w800)),
          ),
          if (_dirty)
            Container(
              margin: const EdgeInsets.only(right: 4),
              width: 8,
              height: 8,
              decoration:
                  const BoxDecoration(color: Dt.accent, shape: BoxShape.circle),
            ),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(LucideIcons.copy, size: 16),
            onPressed: () => Clipboard.setData(ClipboardData(text: _ctrl.text)),
          ),
          IconButton(
            tooltip: _viewMode ? 'Edit code' : 'View highlighted',
            icon: Icon(_viewMode ? LucideIcons.pencil : LucideIcons.eye,
                size: 16),
            onPressed: () => setState(() => _viewMode = !_viewMode),
          ),
          IconButton(
            tooltip: 'Save edits',
            icon: const Icon(LucideIcons.check, size: 18),
            color: Dt.accent,
            onPressed: () async {
              final ws = Get.find<AgentWorkspaceService>();
              final ac = Get.find<AgentController>();
              final pid = ac.project.value?.id;
              if (pid == null) return;
              final err = await ws.writeFile(pid, widget.path, _ctrl.text);
              if (err != null && context.mounted) {
                Get.snackbar('Save failed', err,
                    snackPosition: SnackPosition.BOTTOM);
              } else {
                await ac.notifyFilesChanged();
                if (context.mounted) {
                  Get.snackbar('Saved', widget.path,
                      snackPosition: SnackPosition.BOTTOM,
                      duration: const Duration(seconds: 1));
                }
              }
            },
          ),
        ]),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxHeight: 320),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: widget.isDark
                ? const Color(0xFF1E1E2E)
                : const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(10),
          ),
          child: _viewMode
              ? SingleChildScrollView(
                  padding: EdgeInsets.zero,
                  child: SelectableText.rich(
                    buildHighlightedSpan(highlight(_ctrl.text, widget.path)),
                    style: GoogleFonts.firaCode(fontSize: 12, height: 1.5),
                  ),
                )
              : SingleChildScrollView(
                  child: TextField(
                    controller: _ctrl,
                    maxLines: null,
                    style: GoogleFonts.firaCode(fontSize: 12, height: 1.5),
                    decoration: const InputDecoration.collapsed(hintText: ''),
                  ),
                ),
        ),
      ]),
    );
  }
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
