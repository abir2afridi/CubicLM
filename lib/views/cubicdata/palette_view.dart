/// CubicDataSheet command palette + global search: type to fuzzy-find
/// files, cells, docs and blocks; prefix with `>` for commands
/// (new file, backup, purge trash, dashboard). Ctrl+K equivalent on
/// mobile is the terminal icon / search entry points.
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../services/cubicdata/controller.dart';
import '../../services/cubicdata/models.dart';
import '../../services/cubicdata/search.dart';
import '../../theme/design_tokens.dart';
import '../../utils/export_file.dart';
import 'dashboard_view.dart';
import 'datasheet_home_view.dart';
import 'doc_view.dart';
import 'hybrid_view.dart';
import 'sheet_view.dart';

class DataSheetPaletteView extends StatefulWidget {
  const DataSheetPaletteView({super.key});

  @override
  State<DataSheetPaletteView> createState() => _DataSheetPaletteViewState();
}

class _DataSheetPaletteViewState extends State<DataSheetPaletteView> {
  CubicDataController get _c => datasheetController();
  final _query = TextEditingController();
  String _text = '';

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isCommand = _text.startsWith('>');
    return Scaffold(
      backgroundColor: isDark ? Dt.canvasDark : Dt.canvas,
      appBar: AppBar(
        title: TextField(
          controller: _query,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search or type > for commands…',
            border: InputBorder.none,
            isDense: true,
          ),
          style: const TextStyle(fontSize: 16),
          onChanged: (v) => setState(() => _text = v),
        ),
      ),
      body: Obx(() {
        if (isCommand) return _commands(_text.substring(1).trim());
        final q = _text.trim();
        if (q.isEmpty) return _hints();
        final results = searchWorkspace(q, _c.files.toList(), _c.folders.toList());
        if (results.isEmpty) {
          return ListView(children: [
            ListTile(
              leading: const Icon(LucideIcons.plus, size: 18),
              title: Text('New spreadsheet "$q"',
                  style: const TextStyle(fontSize: 14)),
              onTap: () {
                final f = _c.createFile(WorkspaceType.spreadsheet, q);
                Get.back();
                Get.to(() => SheetEditorView(fileId: f.id));
              },
            ),
          ]);
        }
        return ListView.builder(
          itemCount: results.length,
          itemBuilder: (_, i) {
            final r = results[i];
            return ListTile(
              dense: true,
              leading: Icon(_iconFor(r.fileType, r.matchType), size: 18),
              title: Text(r.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14)),
              subtitle: Text('${r.path} · ${r.matchSnippet}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11)),
              trailing: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Dt.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(r.matchType,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Dt.accent)),
              ),
              onTap: () => _openResult(r),
            );
          },
        );
      }),
    );
  }

  IconData _iconFor(WorkspaceType type, String match) {
    if (match == 'formula') return LucideIcons.functionSquare;
    switch (type) {
      case WorkspaceType.spreadsheet:
        return LucideIcons.tableProperties;
      case WorkspaceType.document:
        return LucideIcons.fileText;
      case WorkspaceType.hybrid:
        return LucideIcons.layoutGrid;
    }
  }

  void _openResult(SearchResult r) {
    final f = _c.byId(r.fileId);
    if (f == null) return;
    Get.back();
    switch (f.type) {
      case WorkspaceType.spreadsheet:
        Get.to(() => SheetEditorView(fileId: f.id));
        break;
      case WorkspaceType.document:
        Get.to(() => DocEditorView(fileId: f.id));
        break;
      case WorkspaceType.hybrid:
        Get.to(() => HybridEditorView(fileId: f.id));
        break;
    }
  }

  Widget _hints() {
    return ListView(children: const [
      ListTile(
        leading: Icon(LucideIcons.search, size: 18),
        title: Text('Type to search files, cells, docs',
            style: TextStyle(fontSize: 14)),
      ),
      ListTile(
        leading: Icon(LucideIcons.terminalSquare, size: 18),
        title: Text('Type > for commands (new, backup, purge…)',
            style: TextStyle(fontSize: 14)),
      ),
    ]);
  }

  Widget _commands(String q) {
    final all = <({String title, String desc, VoidCallback run})>[
      (
        title: 'New spreadsheet',
        desc: 'Create and open',
        run: () {
          final f = _c.createFile(WorkspaceType.spreadsheet,
              q.isEmpty ? 'Untitled sheet' : q);
          Get.back();
          Get.to(() => SheetEditorView(fileId: f.id));
        },
      ),
      (
        title: 'New document',
        desc: 'Create and open',
        run: () {
          final f = _c.createFile(
              WorkspaceType.document, q.isEmpty ? 'Untitled doc' : q);
          Get.back();
          Get.to(() => DocEditorView(fileId: f.id));
        },
      ),
      (
        title: 'New hybrid canvas',
        desc: 'Create and open',
        run: () {
          final f = _c.createFile(WorkspaceType.hybrid,
              q.isEmpty ? 'Untitled canvas' : q);
          Get.back();
          Get.to(() => HybridEditorView(fileId: f.id));
        },
      ),
      (
        title: 'Backup vault',
        desc: 'Export all data as JSON',
        run: () {
          Get.back();
          ExportFile.quickExport(
            text: _c.vaultJsonString(),
            fileName:
                'cubicdatasheet_backup_${DateTime.now().toIso8601String().split('T').first}.json',
            mimeType: 'application/json',
          );
        },
      ),
      (
        title: 'Purge trash',
        desc: 'Delete trashed items forever',
        run: () {
          _c.purgeTrash();
          Get.back();
          Get.snackbar('Trash emptied', '',
              snackPosition: SnackPosition.BOTTOM,
              duration: const Duration(seconds: 2));
        },
      ),
      (
        title: 'Dashboard',
        desc: 'Stats and activity',
        run: () {
          Get.back();
          Get.to(() => const DataSheetDashboardView());
        },
      ),
    ];
    final list = q.isEmpty
        ? all
        : all
            .where((c) =>
                c.title.toLowerCase().contains(q.toLowerCase()))
            .toList();
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (_, i) => ListTile(
        dense: true,
        leading: const Icon(LucideIcons.terminalSquare, size: 18),
        title:
            Text(list[i].title, style: const TextStyle(fontSize: 14)),
        subtitle: Text(list[i].desc,
            style: const TextStyle(fontSize: 11)),
        onTap: list[i].run,
      ),
    );
  }
}
