import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../controllers/agent_controller.dart';
import '../../theme/design_tokens.dart';
import '../../core/colors.dart';
import '../../utils/syntax_highlight.dart';
import 'file_cards.dart';

class DiffView extends StatefulWidget {
  final bool isDark;
  final bool fullPage;
  const DiffView({super.key, required this.isDark, this.fullPage = false});

  @override
  State<DiffView> createState() => _DiffViewState();
}

class _DiffViewState extends State<DiffView> {
  String? _selectedPath;
  final _scrollOriginal = ScrollController();
  final _scrollModified = ScrollController();

  @override
  void initState() {
    super.initState();
    // Synchronize scrolling
    _scrollOriginal.addListener(() {
      if (_scrollOriginal.hasClients && _scrollModified.hasClients && _scrollOriginal.offset != _scrollModified.offset) {
        _scrollModified.jumpTo(_scrollOriginal.offset);
      }
    });
    _scrollModified.addListener(() {
      if (_scrollModified.hasClients && _scrollOriginal.hasClients && _scrollModified.offset != _scrollOriginal.offset) {
        _scrollOriginal.jumpTo(_scrollModified.offset);
      }
    });
  }

  @override
  void dispose() {
    _scrollOriginal.dispose();
    _scrollModified.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Get.find<AgentController>();
    final paths = c.pendingChanges.keys.toList();
    if (_selectedPath == null && paths.isNotEmpty) {
      _selectedPath = paths.first;
    }

    final content = Container(
      color: widget.isDark ? AppColors.surface : Colors.white,
      child: Column(
        children: [
          _header(context, c),
          Expanded(
            child: Row(
              children: [
                _sidebar(paths),
                const VerticalDivider(width: 1, thickness: 1),
                if (_selectedPath != null)
                  Expanded(child: _diffSplitView(_selectedPath!, c.pendingChanges[_selectedPath!]!))
                else
                  const Expanded(child: Center(child: Text('No changes to review'))),
              ],
            ),
          ),
        ],
      ),
    );

    if (widget.fullPage) {
      return Scaffold(body: SafeArea(child: content));
    }
    return content;
  }

  Widget _header(BuildContext context, AgentController c) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: widget.isDark ? const Color(0xFF1A1A24) : const Color(0xFFF9FAFB),
        border: Border(bottom: BorderSide(color: widget.isDark ? Colors.white10 : Dt.hairline)),
      ),
      child: Row(
        children: [
          if (widget.fullPage)
            IconButton(
              icon: const Icon(LucideIcons.arrowLeft, size: 20),
              onPressed: () => Get.back(),
            ),
          const Icon(LucideIcons.gitCompare, size: 20, color: Dt.accent),
          const SizedBox(width: 12),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Review Changes',
                style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              Text(
                '${c.pendingChanges.length} files modified',
                style: GoogleFonts.plusJakartaSans(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const Spacer(),
          TextButton.icon(
            icon: const Icon(LucideIcons.trash2, size: 16),
            label: const Text('Discard'),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            onPressed: () {
              c.pendingChanges.clear();
              c.reviewingChanges.value = false;
              if (widget.fullPage) Get.back();
            },
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            icon: const Icon(LucideIcons.check, size: 16),
            label: const Text('Apply All Changes'),
            style: FilledButton.styleFrom(
              backgroundColor: Dt.accent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              c.applyPendingChanges();
              if (widget.fullPage) Get.back();
            },
          ),
        ],
      ),
    );
  }

  Widget _sidebar(List<String> paths) {
    return Container(
      width: 240,
      color: widget.isDark ? const Color(0xFF14141D) : const Color(0xFFF3F4F6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('MODIFIED FILES', style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 0.5)),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: paths.length,
              itemBuilder: (context, i) {
                final p = paths[i];
                final active = p == _selectedPath;
                final fileName = p.split('/').last;
                final dirPath = p.contains('/') ? p.substring(0, p.lastIndexOf('/')) : '';

                return InkWell(
                  onTap: () => setState(() => _selectedPath = p),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: active ? Dt.accent.withValues(alpha: 0.1) : Colors.transparent,
                      border: Border(left: BorderSide(color: active ? Dt.accent : Colors.transparent, width: 3)),
                    ),
                    child: Row(
                      children: [
                        Icon(_iconFor(p), size: 14, color: active ? Dt.accent : Colors.grey),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fileName,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                                  color: active ? Dt.accent : (widget.isDark ? Colors.white70 : Colors.black87),
                                ),
                              ),
                              if (dirPath.isNotEmpty)
                                Text(
                                  dirPath,
                                  style: GoogleFonts.plusJakartaSans(fontSize: 10, color: Colors.grey),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _diffSplitView(String path, Map<String, String> change) {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _codePane(
                  'ORIGINAL',
                  path,
                  change['old'] ?? '',
                  Colors.red.withValues(alpha: 0.05),
                  _scrollOriginal,
                ),
              ),
              const VerticalDivider(width: 1, thickness: 1),
              Expanded(
                child: _codePane(
                  'MODIFIED',
                  path,
                  change['new'] ?? '',
                  Colors.green.withValues(alpha: 0.05),
                  _scrollModified,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _codePane(String label, String path, String code, Color bg, ScrollController scroll) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          width: double.infinity,
          decoration: BoxDecoration(
            color: bg.withValues(alpha: 0.2),
            border: Border(bottom: BorderSide(color: widget.isDark ? Colors.white10 : Colors.black12)),
          ),
          child: Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w800, color: label == 'ORIGINAL' ? Colors.redAccent : Colors.greenAccent)),
        ),
        Expanded(
          child: Container(
            color: widget.isDark ? const Color(0xFF0D0D12) : const Color(0xFFFCFCFD),
            child: LineNumberWrapper(
              content: code,
              isDark: widget.isDark,
              scrollController: scroll,
              child: Text.rich(
                buildHighlightedSpan(highlight(code, path)),
                style: GoogleFonts.firaCode(fontSize: 12, height: 1.5),
                softWrap: false,
              ),
            ),
          ),
        ),
      ],
    );
  }

  IconData _iconFor(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.html')) return LucideIcons.globe;
    if (p.endsWith('.css')) return LucideIcons.palette;
    if (p.endsWith('.js') || p.endsWith('.jsx') || p.endsWith('.ts') || p.endsWith('.tsx')) return LucideIcons.fileCode2;
    if (p.endsWith('.json')) return LucideIcons.braces;
    return LucideIcons.file;
  }
}
