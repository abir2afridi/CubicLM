/// CubicDataSheet home: personal file vault (folders + spreadsheets).
/// Everything persists into one uninstall-safe vault file; no database,
/// no sharing. Document/hybrid editors arrive in phase 2 — creation is
/// spreadsheet-first so every listed file always opens.
library;

import 'package:flutter/material.dart';
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
            tooltip: 'New folder',
            icon: const Icon(LucideIcons.folderPlus, size: 20),
            onPressed: () => _newFolder(),
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
                borderRadius: BorderRadius.circular(24),
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
        borderRadius: BorderRadius.circular(12),
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
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: _fileColor(file.type).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
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

  void _openFile(SmartFile file) {
    switch (file.type) {
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
          _menuTile(LucideIcons.tableProperties, 'Spreadsheet', () {
            Get.back();
            _nameAndCreate(context, WorkspaceType.spreadsheet, null);
          }),
          _menuTile(LucideIcons.fileText, 'Document', () {
            Get.back();
            _nameAndCreate(context, WorkspaceType.document, null);
          }),
          _menuTile(LucideIcons.layoutGrid, 'Hybrid canvas', () {
            Get.back();
            _nameAndCreate(context, WorkspaceType.hybrid, null);
          }),
        ]),
      ),
    ));
  }

  void _nameAndCreate(
      BuildContext context, WorkspaceType type, String? folderId) {
    final nameCtrl = TextEditingController();
    Get.dialog(AlertDialog(
      title: Text('New ${_typeLabel(type)}'),
      content: TextField(
        controller: nameCtrl,
        autofocus: true,
        decoration: const InputDecoration(
            hintText: 'Name', isDense: true),
        onSubmitted: (_) =>
            _createAndOpen(nameCtrl.text, type, folderId),
      ),
      actions: [
        TextButton(
            onPressed: () => Get.back(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () =>
              _createAndOpen(nameCtrl.text, type, folderId),
          child: const Text('Create'),
        ),
      ],
    ));
  }

  String _typeLabel(WorkspaceType type) {
    switch (type) {
      case WorkspaceType.spreadsheet:
        return 'spreadsheet';
      case WorkspaceType.document:
        return 'document';
      case WorkspaceType.hybrid:
        return 'hybrid canvas';
    }
  }

  void _createAndOpen(String name, WorkspaceType type, String? folderId) {
    final file = datasheetController().createFile(
      type,
      name.trim().isEmpty ? 'Untitled' : name.trim(),
      folderId: folderId,
    );
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
          _menuTile(LucideIcons.trash2, 'Delete', () {
            c.deleteFile(file.id);
            Get.back();
            Get.snackbar('Moved to trash', file.name,
                snackPosition: SnackPosition.BOTTOM,
                duration: const Duration(seconds: 3));
          }),
        ]),
      ),
    ));
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
