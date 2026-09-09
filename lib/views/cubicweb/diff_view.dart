import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../controllers/agent_controller.dart';
import '../../theme/design_tokens.dart';
import '../../core/colors.dart';

class DiffView extends StatefulWidget {
  final bool isDark;
  const DiffView({super.key, required this.isDark});

  @override
  State<DiffView> createState() => _DiffViewState();
}

class _DiffViewState extends State<DiffView> {
  String? _selectedPath;

  @override
  Widget build(BuildContext context) {
    final c = Get.find<AgentController>();
    final paths = c.pendingChanges.keys.toList();
    if (_selectedPath == null && paths.isNotEmpty) {
      _selectedPath = paths.first;
    }

    return Container(
      color: widget.isDark ? AppColors.surface : Colors.white,
      child: Column(
        children: [
          _header(context, c),
          Expanded(
            child: Row(
              children: [
                _sidebar(paths),
                const VerticalDivider(width: 1),
                if (_selectedPath != null)
                  Expanded(child: _diffSplitView(c.pendingChanges[_selectedPath]!))
                else
                  const Expanded(child: Center(child: Text('No changes to review'))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, AgentController c) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: widget.isDark ? Colors.white10 : Dt.hairline)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.gitCompare, size: 20, color: Dt.accent),
          const SizedBox(width: 12),
          Text(
            'Review Changes',
            style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const Spacer(),
          TextButton(
            onPressed: () {
              c.pendingChanges.clear();
              c.reviewingChanges.value = false;
            },
            child: const Text('Discard'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Dt.accent),
            onPressed: () => c.applyPendingChanges(),
            child: const Text('Apply Changes'),
          ),
        ],
      ),
    );
  }

  Widget _sidebar(List<String> paths) {
    return Container(
      width: 200,
      color: widget.isDark ? Colors.black12 : Colors.grey[50],
      child: ListView.builder(
        itemCount: paths.length,
        itemBuilder: (context, i) {
          final p = paths[i];
          final active = p == _selectedPath;
          return ListTile(
            dense: true,
            selected: active,
            selectedTileColor: Dt.accent.withValues(alpha: 0.1),
            title: Text(
              p.split('/').last,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? Dt.accent : null,
              ),
            ),
            subtitle: Text(p, style: const TextStyle(fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => setState(() => _selectedPath = p),
          );
        },
      ),
    );
  }

  Widget _diffSplitView(Map<String, String> change) {
    return Row(
      children: [
        Expanded(child: _codeSide('Original', change['old'] ?? '', Colors.red.withValues(alpha: 0.05))),
        const VerticalDivider(width: 1),
        Expanded(child: _codeSide('Modified', change['new'] ?? '', Colors.green.withValues(alpha: 0.05))),
      ],
    );
  }

  Widget _codeSide(String title, String code, Color bg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          width: double.infinity,
          color: bg.withValues(alpha: 0.1),
          child: Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              code,
              style: GoogleFonts.firaCode(fontSize: 12, height: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
