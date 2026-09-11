/// CubicDataSheet home: personal file vault (folders + spreadsheets).
/// Everything persists into one uninstall-safe vault file; no database,
/// no sharing. Document/hybrid editors arrive in phase 2 — creation is
/// spreadsheet-first so every listed file always opens.
library;

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../services/cubicdata/controller.dart';
import '../../services/cubicdata/models.dart';
import '../../theme/design_tokens.dart';
import 'dashboard_view.dart';
import 'doc_view.dart';
import 'hybrid_view.dart';
import 'palette_view.dart';
import 'sheet_view.dart';

CubicDataController datasheetController() {
  try {
    return Get.find<CubicDataController>();
  } catch (_) {
    return Get.put(CubicDataController());
  }
}

class DataSheetHomeView extends StatefulWidget {
  const DataSheetHomeView({super.key});

  @override
  State<DataSheetHomeView> createState() => _DataSheetHomeViewState();
}

class _DataSheetHomeViewState extends State<DataSheetHomeView> {
  final _expanded = <String>{};

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = datasheetController();
    return Scaffold(
      backgroundColor: isDark ? Dt.canvasDark : Dt.canvas,
      appBar: AppBar(
        title: Text('CubicDataSheet',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800, fontSize: 19)),
        actions: [
          IconButton(
            tooltip: 'Search & commands',
            icon: const Icon(LucideIcons.search, size: 20),
            onPressed: () =>
                Get.to(() => const DataSheetPaletteView()),
          ),
          IconButton(
            tooltip: 'Dashboard',
            icon: const Icon(LucideIcons.layoutDashboard, size: 20),
            onPressed: () =>
                Get.to(() => const DataSheetDashboardView()),
          ),
          IconButton(
            tooltip: 'Import vault JSON',
            icon: const Icon(LucideIcons.upload, size: 20),
            onPressed: () => _importVault(),
          ),
          IconButton(
            tooltip: 'New folder',
            icon: const Icon(LucideIcons.folderPlus, size: 20),
            onPressed: () => _newFolder(),
          ),
          IconButton(
            tooltip: 'About CubicDataSheet',
            icon: const Icon(LucideIcons.info, size: 20),
            onPressed: () => _showAbout(context),
          ),
          Obx(() => c.trash.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  tooltip: 'Trash',
                  icon: Badge(
                    label: Text('${c.trash.length}'),
                    child: const Icon(LucideIcons.trash2, size: 20),
                  ),
                  onPressed: () =>
                      Get.to(() => const DataSheetTrashView()),
                )),
        ],
      ),
      body: Obx(() {
        if (!c.loaded.value) {
          return const Center(child: CircularProgressIndicator());
        }
        final roots =
            c.folders.where((f) => f.parentId == null).toList();
        final rootFiles = c.filesIn(null);
        if (roots.isEmpty && rootFiles.isEmpty) {
          return _emptyState(context, isDark);
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
          children: [
            for (final folder in roots) _folderNode(folder, 0, isDark),
            for (final file in rootFiles) _fileRow(file, isDark),
          ],
        );
      }),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newSheet(context),
        backgroundColor: Dt.accent,
        icon: const Icon(LucideIcons.plus, color: Colors.white),
        label: const Text('New', style: TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _emptyState(BuildContext context, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Dt.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child:
                  const Icon(LucideIcons.tableProperties, size: 44),
            ),
            const SizedBox(height: 16),
            Text('Your personal sheets',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
                'Spreadsheets with formulas, cell locks and per-cell copy. '
                'Stored on this device — yours alone.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    height: 1.5,
                    color: Theme.of(context).hintColor)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _newSheet(context),
              icon: const Icon(LucideIcons.plus, size: 18),
              label: const Text('New spreadsheet'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _folderNode(Folder folder, int depth, bool isDark) {
    final c = datasheetController();
    final open = _expanded.contains(folder.id);
    final kids = c.childFolders(folder.id);
    final docs = c.filesIn(folder.id);
    return Column(children: [
      InkWell(
        onTap: () => setState(() {
          open ? _expanded.remove(folder.id) : _expanded.add(folder.id);
        }),
        onLongPress: () => _folderMenu(folder),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: EdgeInsets.fromLTRB(12.0 + depth * 16, 10, 12, 10),
          child: Row(children: [
            Icon(open ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                size: 16, color: Theme.of(context).hintColor),
            const SizedBox(width: 6),
            const Icon(LucideIcons.folder, size: 18, color: Dt.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(folder.name,
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700, fontSize: 14)),
            ),
            Text('${docs.length}',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, color: Theme.of(context).hintColor)),
          ]),
        ),
      ),
      if (open) ...[
        for (final k in kids) _folderNode(k, depth + 1, isDark),
        for (final d in docs)
          Padding(
            padding: EdgeInsets.only(left: 16.0 + depth * 16),
            child: _fileRow(d, isDark),
          ),
      ],
    ]);
  }

  Widget _fileRow(SmartFile file, bool isDark) {
    return InkWell(
      onTap: () => _openFile(file),
      onLongPress: () => _fileMenu(file),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: _fileColor(file.type).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(_fileIcon(file.type),
                size: 18, color: _fileColor(file.type)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                  ),
                  if (file.isFavorite)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(LucideIcons.star,
                          size: 13, color: Colors.amber),
                    ),
                  if (file.isPinned)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(LucideIcons.pin,
                          size: 13, color: Colors.cyan),
                    ),
                ]),
                Text(_fileSubtitle(file),
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: Theme.of(context).hintColor)),
              ],
            ),
          ),
          const Icon(LucideIcons.chevronRight,
              size: 16, color: Colors.grey),
        ]),
      ),
    );
  }

  IconData _fileIcon(WorkspaceType type) {
    switch (type) {
      case WorkspaceType.spreadsheet:
        return LucideIcons.tableProperties;
      case WorkspaceType.document:
        return LucideIcons.fileText;
      case WorkspaceType.hybrid:
        return LucideIcons.layoutGrid;
    }
  }

  Color _fileColor(WorkspaceType type) {
    switch (type) {
      case WorkspaceType.spreadsheet:
        return const Color(0xFF10B981);
      case WorkspaceType.document:
        return Colors.cyan;
      case WorkspaceType.hybrid:
        return Colors.orange;
    }
  }

  String _fileSubtitle(SmartFile f) {
    switch (f.type) {
      case WorkspaceType.document:
        final n = f.docBlocks?.length ?? 0;
        return '$n block${n == 1 ? '' : 's'}';
      case WorkspaceType.hybrid:
        final n = f.hybridBlocks?.length ?? 0;
        return '$n component${n == 1 ? '' : 's'}';
      case WorkspaceType.spreadsheet:
        break;
    }
    final n = f.sheets?.length ?? 0;
    var cells = 0;
    for (final s in f.sheets ?? const <SheetData>[]) {
      cells += s.cells.length;
    }
    return '$n sheet${n == 1 ? '' : 's'} · $cells cells';
  }

  /// Imports a vault JSON (e.g. an orphaned cubicdatasheet_vault.json
  /// found in device storage): merges folders + files by id, skipping
  /// duplicates. Trash/activity are not imported.
  Future<void> _importVault() async {
    final c = datasheetController();
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (picked == null || picked.files.isEmpty) return;
      final bytes = picked.files.first.bytes;
      if (bytes == null || bytes.isEmpty) {
        Get.snackbar('Import failed', 'Could not read the file.',
            snackPosition: SnackPosition.BOTTOM);
        return;
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        Get.snackbar('Import failed', 'Not a CubicDataSheet vault file.',
            snackPosition: SnackPosition.BOTTOM);
        return;
      }
      final knownFiles = c.files.map((f) => f.id).toSet();
      final knownFolders = c.folders.map((f) => f.id).toSet();
      var filesIn = 0;
      var foldersIn = 0;
      var skipped = 0;
      if (decoded['folders'] is List) {
        for (final e in (decoded['folders'] as List)) {
          if (e is! Map) continue;
          try {
            final fo =
                Folder.fromJson(Map<String, dynamic>.from(e));
            if (fo.id.isEmpty || knownFolders.contains(fo.id)) {
              skipped++;
              continue;
            }
            knownFolders.add(fo.id);
            c.folders.add(fo);
            foldersIn++;
          } catch (_) {
            skipped++;
          }
        }
      }
      if (decoded['files'] is List) {
        for (final e in (decoded['files'] as List)) {
          if (e is! Map) continue;
          try {
            final f =
                SmartFile.fromJson(Map<String, dynamic>.from(e));
            if (f.id.isEmpty || knownFiles.contains(f.id)) {
              skipped++;
              continue;
            }
            knownFiles.add(f.id);
            c.files.add(f);
            filesIn++;
          } catch (_) {
            skipped++;
          }
        }
      }
      c.files.refresh();
      c.folders.refresh();
      // Never dangle: entries pointing at folders that were not
      // imported (or don't exist) fall back to root, otherwise they
      // would vanish from the tree.
      final folderIds = c.folders.map((fo) => fo.id).toSet();
      for (final fo in c.folders) {
        if (fo.parentId != null && !folderIds.contains(fo.parentId)) {
          fo.parentId = null;
        }
      }
      for (final f in c.files) {
        if (f.folderId != null && !folderIds.contains(f.folderId)) {
          f.folderId = null;
        }
      }
      c.files.refresh();
      c.folders.refresh();
      c.log('edit',
          'Imported vault: $filesIn files, $foldersIn folders ($skipped skipped)');
      c.scheduleSave();
      Get.snackbar('Import done',
          '$filesIn files, $foldersIn folders ($skipped skipped).',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 4));
    } catch (e) {
      Get.snackbar('Import failed', '$e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  void _showAbout(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('CubicDataSheet'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _aboutRow('What is this?',
                  'Your personal sheets and docs space: spreadsheets with formulas, documents, and hybrid canvases.'),
              _aboutRow('Where is my data?',
                  'One vault file in Download/CubicLM/DataSheet. It stays on your device even if the app is uninstalled — import it back anytime with the upload button above.'),
              _aboutRow('Cell locks',
                  'Lock levels Soft, Protected, Vault (password) and Permanent (RESTORE phrase). Turn on Unlock mode in a sheet header to unlock.'),
              _aboutRow('Copy anything',
                  'Every selected cell offers Plain, Formula, Markdown and JSON copy. The dashboard keeps a clipboard cache with re-copy.'),
              _aboutRow('Find everything',
                  'Use the search button for fuzzy search across files, cells, formulas, notes and docs — or type > for commands.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _aboutRow(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(body,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5, height: 1.45)),
        ],
      ),
    );
  }

  void _openFile(SmartFile file) {    switch (file.type) {
      case WorkspaceType.spreadsheet:
        Get.to(() => SheetEditorView(fileId: file.id));
        break;
      case WorkspaceType.document:
        Get.to(() => DocEditorView(fileId: file.id));
        break;
      case WorkspaceType.hybrid:
        Get.to(() => HybridEditorView(fileId: file.id));
        break;
    }
  }

  void _newSheet(BuildContext context) {
    // 8 new-file archetypes with the exact web names: plain types plus
    // hybrid files pre-seeded with one starter block.
    const archetypes = [
      ('spreadsheet', '', 'Grid Spreadsheet', LucideIcons.tableProperties),
      ('document', '', 'Document Memo Notes', LucideIcons.fileText),
      ('hybrid', 'spreadsheet', 'Micro Spreadsheet',
          LucideIcons.tableProperties),
      ('hybrid', 'code', 'Developer Script File', LucideIcons.code),
      ('hybrid', 'checklist', 'Bento Task Checker', LucideIcons.listChecks),
      ('hybrid', 'prompt', 'Automated Prompt File',
          LucideIcons.terminalSquare),
      ('hybrid', 'reference', 'Reference URL link', LucideIcons.link),
      ('hybrid', 'multi', 'Multi Module Canvas', LucideIcons.layoutGrid),
    ];
    Get.bottomSheet(SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('New file',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            childAspectRatio: 3.4,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final a in archetypes)
                InkWell(
                  onTap: () {
                    Get.back();
                    _nameAndCreate(context, a.$1, a.$2, null);
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    margin: const EdgeInsets.all(4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: Theme.of(context)
                              .hintColor
                              .withValues(alpha: 0.25)),
                    ),
                    child: Row(children: [
                      Icon(a.$4, size: 16, color: Dt.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(a.$3,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ]),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ]),
      ),
    ));
  }

  void _nameAndCreate(
      BuildContext context, String kind, String seed, String? folderId) {
    final nameCtrl = TextEditingController();
    Get.dialog(AlertDialog(
      title: const Text('Name your file'),
      content: TextField(
        controller: nameCtrl,
        autofocus: true,
        decoration: const InputDecoration(
            hintText: 'Budget 2026', isDense: true),
        onSubmitted: (_) =>
            _createAndOpen(nameCtrl.text, kind, seed, folderId),
      ),
      actions: [
        TextButton(
            onPressed: () => Get.back(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () =>
              _createAndOpen(nameCtrl.text, kind, seed, folderId),
          child: const Text('Create'),
        ),
      ],
    ));
  }

  void _createAndOpen(
      String name, String kind, String seed, String? folderId) {
    final c = datasheetController();
    final fileName = name.trim().isEmpty ? 'Untitled' : name.trim();
    final SmartFile file;
    if (kind == 'hybrid') {
      file = c.createHybridWith(seed, fileName, folderId: folderId);
    } else {
      file = c.createFile(
        kind == 'document'
            ? WorkspaceType.document
            : WorkspaceType.spreadsheet,
        fileName,
        folderId: folderId,
      );
    }
    Get.back();
    _openFile(file);
  }

  void _newFolder() {
    final nameCtrl = TextEditingController();
    Get.dialog(AlertDialog(
      title: const Text('New folder'),
      content: TextField(
        controller: nameCtrl,
        autofocus: true,
        decoration:
            const InputDecoration(hintText: 'Projects', isDense: true),
        onSubmitted: (_) {
          datasheetController().createFolder(nameCtrl.text);
          Get.back();
        },
      ),
      actions: [
        TextButton(
            onPressed: () => Get.back(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            datasheetController().createFolder(nameCtrl.text);
            Get.back();
          },
          child: const Text('Create'),
        ),
      ],
    ));
  }

  void _fileMenu(SmartFile file) {
    final c = datasheetController();
    Get.bottomSheet(SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(file.name,
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w800, fontSize: 15)),
            ),
          ),
          _menuTile(LucideIcons.pencil, 'Rename', () {
            Get.back();
            _renameFile(file);
          }),
          _menuTile(
              file.isFavorite ? LucideIcons.starOff : LucideIcons.star,
              file.isFavorite ? 'Unfavorite' : 'Favorite', () {
            c.toggleFavorite(file.id);
            Get.back();
          }),
          _menuTile(
              LucideIcons.pin, file.isPinned ? 'Unpin' : 'Pin', () {
            c.togglePin(file.id);
            Get.back();
          }),
          _menuTile(LucideIcons.folderInput, 'Move to folder', () {
            Get.back();
            _moveFile(file);
          }),
          _menuTile(LucideIcons.tags, 'Edit tags', () {
            Get.back();
            _editTags(file);
          }),
          _menuTile(LucideIcons.trash2, 'Delete', () {
            Get.back();
            _confirmDeleteFile(file);
          }),
        ]),
      ),
    ));
  }

  /// Delete file only after typing its exact name (web parity), with
  /// a copy button so long names need no retyping.
  void _confirmDeleteFile(SmartFile file) {
    final confirmCtrl = TextEditingController();
    var copied = false;
    Get.dialog(AlertDialog(
      title: const Text('Delete file?',
          style: TextStyle(color: Colors.red)),
      content: StatefulBuilder(
        builder: (ctx, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text('Type "${file.name}" to confirm deletion.',
                    style: const TextStyle(fontSize: 13)),
              ),
              IconButton(
                tooltip: 'Copy name',
                icon: Icon(
                    copied ? LucideIcons.check : LucideIcons.copy,
                    size: 15,
                    color: copied ? Colors.green : null),
                onPressed: () async {
                  await Clipboard.setData(
                      ClipboardData(text: file.name));
                  setState(() => copied = true);
                },
              ),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: confirmCtrl,
              autofocus: true,
              decoration: InputDecoration(
                  hintText: file.name, isDense: true),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) =>
                  _tryDeleteFile(file, confirmCtrl.text),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Get.back(), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: confirmCtrl.text.trim() == file.name.trim()
                ? Colors.red
                : Colors.grey,
          ),
          onPressed: () => _tryDeleteFile(file, confirmCtrl.text),
          child: const Text('Delete'),
        ),
      ],
    ));
  }

  void _tryDeleteFile(SmartFile file, String typed) {
    if (typed.trim() != file.name.trim()) {
      Get.snackbar('No match', 'Type the exact file name.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    datasheetController().deleteFile(file.id);
    Get.back();
    Get.snackbar('Moved to trash', file.name,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 3));
  }

  void _renameFile(SmartFile file) {
    final nameCtrl = TextEditingController(text: file.name);
    Get.dialog(AlertDialog(
      title: const Text('Rename'),
      content: TextField(
        controller: nameCtrl,
        autofocus: true,
        decoration: const InputDecoration(isDense: true),
        onSubmitted: (_) {
          datasheetController().renameFile(file.id, nameCtrl.text);
          Get.back();
        },
      ),
      actions: [
        TextButton(
            onPressed: () => Get.back(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            datasheetController().renameFile(file.id, nameCtrl.text);
            Get.back();
          },
          child: const Text('Save'),
        ),
      ],
    ));
  }

  void _moveFile(SmartFile file) {
    final c = datasheetController();
    Get.bottomSheet(SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _menuTile(LucideIcons.home, 'Root (no folder)', () {
            c.moveFile(file.id, null);
            Get.back();
          }),
          for (final fo in c.folders)
            _menuTile(LucideIcons.folder, '${c.folderPath(fo.id)}${fo.name}',
                () {
              c.moveFile(file.id, fo.id);
              Get.back();
            }),
        ]),
      ),
    ));
  }

  void _editTags(SmartFile file) {
    final tagCtrl = TextEditingController(text: file.tags.join(', '));
    Get.dialog(AlertDialog(
      title: const Text('Tags (comma separated)'),
      content: TextField(
        controller: tagCtrl,
        autofocus: true,
        decoration: const InputDecoration(
            hintText: 'finance, 2026', isDense: true),
        onSubmitted: (_) {
          datasheetController().setTags(
              file.id, tagCtrl.text.split(','));
          Get.back();
        },
      ),
      actions: [
        TextButton(
            onPressed: () => Get.back(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            datasheetController()
                .setTags(file.id, tagCtrl.text.split(','));
            Get.back();
          },
          child: const Text('Save'),
        ),
      ],
    ));
  }

  void _folderMenu(Folder folder) {
    final c = datasheetController();
    Get.dialog(AlertDialog(
      title: Text(folder.name),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          dense: true,
          leading: const Icon(LucideIcons.pencil, size: 18),
          title: const Text('Rename'),
          onTap: () {
            Get.back();
            final nameCtrl = TextEditingController(text: folder.name);
            Get.dialog(AlertDialog(
              title: const Text('Rename folder'),
              content: TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration:
                    const InputDecoration(isDense: true),
                onSubmitted: (_) {
                  c.renameFolder(folder.id, nameCtrl.text);
                  Get.back();
                },
              ),
              actions: [
                FilledButton(
                  onPressed: () {
                    c.renameFolder(folder.id, nameCtrl.text);
                    Get.back();
                  },
                  child: const Text('Save'),
                ),
              ],
            ));
          },
        ),
        ListTile(
          dense: true,
          leading: const Icon(LucideIcons.filePlus, size: 18),
          title: const Text('New spreadsheet here'),
          onTap: () {
            final file = c.createFile(
                WorkspaceType.spreadsheet, 'Untitled sheet',
                folderId: folder.id);
            Get.back();
            Get.to(() => SheetEditorView(fileId: file.id));
          },
        ),
        ListTile(
          dense: true,
          leading: const Icon(LucideIcons.folderPlus, size: 18),
          title: const Text('New subfolder'),
          onTap: () {
            Get.back();
            final nameCtrl = TextEditingController();
            Get.dialog(AlertDialog(
              title: const Text('New subfolder'),
              content: TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration:
                    const InputDecoration(isDense: true),
                onSubmitted: (_) {
                  c.createFolder(nameCtrl.text,
                      parentId: folder.id);
                  Get.back();
                },
              ),
              actions: [
                FilledButton(
                  onPressed: () {
                    c.createFolder(nameCtrl.text,
                        parentId: folder.id);
                    Get.back();
                  },
                  child: const Text('Create'),
                ),
              ],
            ));
          },
        ),
        ListTile(
          dense: true,
          leading:
              const Icon(LucideIcons.trash2, size: 18, color: Colors.red),
          title: const Text('Delete folder',
              style: TextStyle(color: Colors.red)),
          onTap: () {
            c.deleteFolder(folder.id);
            Get.back();
          },
        ),
      ]),
    ));
  }

  Widget _menuTile(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 18),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      onTap: onTap,
    );
  }
}

class DataSheetTrashView extends StatelessWidget {
  const DataSheetTrashView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = datasheetController();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trash'),
        actions: [
          Obx(() => c.trash.isEmpty
              ? const SizedBox.shrink()
              : TextButton(
                  onPressed: () => Get.dialog(AlertDialog(
                    title: const Text('Empty trash?'),
                    content: const Text(
                        'Everything in trash is deleted forever.'),
                    actions: [
                      TextButton(
                          onPressed: () => Get.back(),
                          child: const Text('Cancel')),
                      FilledButton(
                        onPressed: () {
                          c.purgeTrash();
                          Get.back();
                        },
                        child: const Text('Empty'),
                      ),
                    ],
                  )),
                  child: const Text('Empty all'),
                )),
        ],
      ),
      body: Obx(() {
        if (c.trash.isEmpty) {
          return const Center(child: Text('Trash is empty.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: c.trash.length,
          itemBuilder: (_, i) {
            final t = c.trash[i];
            return ListTile(
              dense: true,
              leading: Icon(
                  t.type == 'folder'
                      ? LucideIcons.folder
                      : LucideIcons.tableProperties,
                  size: 18),
              title: Text(t.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                  '${t.type} · deleted ${DateTime.fromMillisecondsSinceEpoch(t.deletedAt).toLocal().toString().split('.').first}',
                  style: const TextStyle(fontSize: 11)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Restore',
                  icon: const Icon(LucideIcons.undo2, size: 18),
                  onPressed: () {
                    if (!c.restoreTrash(t.id)) {
                      Get.snackbar('Restore failed',
                          'Could not read the trashed item.',
                          snackPosition: SnackPosition.BOTTOM);
                    }
                  },
                ),
                IconButton(
                  tooltip: 'Delete forever',
                  icon: const Icon(LucideIcons.trash2,
                      size: 18, color: Colors.red),
                  onPressed: () => c.purgeTrashItem(t.id),
                ),
              ]),
            );
          },
        );
      }),
    );
  }
}
