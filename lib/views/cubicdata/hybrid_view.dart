/// CubicDataSheet hybrid canvas: bento blocks (spreadsheet, document,
/// code, checklist, prompt, reference) with per-block titles, delete
/// safety, prompt variable binding and compact description tabs.
/// Personal on-device space: no database, no sharing.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../services/cubicdata/controller.dart';
import '../../services/cubicdata/models.dart';
import '../../theme/design_tokens.dart';
import 'datasheet_home_view.dart';

class HybridEditorView extends StatefulWidget {
  final String fileId;
  const HybridEditorView({super.key, required this.fileId});

  @override
  State<HybridEditorView> createState() => _HybridEditorViewState();
}

class _HybridEditorViewState extends State<HybridEditorView> {
  CubicDataController get _c => datasheetController();

  final _titleCtrls = <String, TextEditingController>{};
  final _textCtrls = <String, TextEditingController>{};
  final _newChecklist = <String, TextEditingController>{};
  final _bindings = <String, String>{};
  final _activeTab = <String, int>{};
  String? _copiedFeedback;

  @override
  void dispose() {
    for (final c in _titleCtrls.values) {
      c.dispose();
    }
    for (final c in _textCtrls.values) {
      c.dispose();
    }
    for (final c in _newChecklist.values) {
      c.dispose();
    }
    super.dispose();
  }

  SmartFile? get _file => _c.byId(widget.fileId);
  List<HybridBlock> get _blocks => _file?.hybridBlocks ?? [];

  void _persist(SmartFile f, [String detail = 'Edited']) {
    f.touch();
    _c.files.refresh();
    _c.log('edit', '$detail: ${f.name}', fileId: f.id, fileName: f.name);
    _c.scheduleSave();
  }

  TextEditingController _titleOf(HybridBlock b) =>
      _titleCtrls.putIfAbsent(
          b.id, () => TextEditingController(text: b.title));

  /// Cached controller for free-text inputs (cells, notes, tab fields).
  /// Text typing mutates + schedules a save WITHOUT refreshing Rx, so
  /// rebuilds never steal the cursor. Structural ops still refresh.
  TextEditingController _textOf(String key, String value) {
    final existing = _textCtrls[key];
    if (existing != null) {
      if (existing.text != value) {
        existing.text = value;
        existing.selection =
            TextSelection.collapsed(offset: value.length);
      }
      return existing;
    }
    final c = TextEditingController(text: value);
    _textCtrls[key] = c;
    return c;
  }

  /// Quiet persist for keystrokes: vault save without Rx refresh or
  /// activity-log spam (structural ops use saveFile instead).
  void _typeSaved() => _c.scheduleSave();

  void _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    _c.pushClipboard(content: text, type: what, fileName: _file?.name);
    setState(() => _copiedFeedback = '$what copied!');
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copiedFeedback = null);
    });
  }

  void _deleteBlock(SmartFile f, HybridBlock b, int index) {
    if (b.title.trim().isEmpty) {
      f.hybridBlocks!.removeAt(index);
      _persist(f, 'Deleted block');
      setState(() {});
      return;
    }
    final confirmCtrl = TextEditingController();
    Get.dialog(AlertDialog(
      title: const Text('Delete block?'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Type the title "${b.title}" to confirm.'),
        const SizedBox(height: 8),
        TextField(
          controller: confirmCtrl,
          autofocus: true,
          decoration: const InputDecoration(isDense: true),
          onSubmitted: (v) {
            if (v.trim() == b.title.trim()) {
              f.hybridBlocks!.removeAt(index);
              _persist(f, 'Deleted block');
              Get.back();
              setState(() {});
            }
          },
        ),
      ]),
      actions: [
        TextButton(
            onPressed: () => Get.back(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (confirmCtrl.text.trim() == b.title.trim()) {
              f.hybridBlocks!.removeAt(index);
              _persist(f, 'Deleted block');
              Get.back();
              setState(() {});
            } else {
              Get.snackbar('No match', 'Type the exact title.',
                  snackPosition: SnackPosition.BOTTOM);
            }
          },
          child: const Text('Delete'),
        ),
      ],
    ));
  }

  void _appendMenu(SmartFile f) {
    const types = [
      ('spreadsheet', 'Mini sheet', LucideIcons.tableProperties),
      ('document', 'Note', LucideIcons.fileText),
      ('code', 'Code', LucideIcons.code),
      ('checklist', 'Checklist', LucideIcons.listChecks),
      ('prompt', 'Prompt', LucideIcons.terminalSquare),
      ('reference', 'Reference', LucideIcons.link),
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
            child: Text('Append component',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ),
          for (final t in types)
            ListTile(
              dense: true,
              leading: Icon(t.$3, size: 18),
              title: Text(t.$2, style: const TextStyle(fontSize: 14)),
              onTap: () {
                Get.back();
                _appendBlock(f, t.$1, t.$2);
              },
            ),
        ]),
      ),
    ));
  }

  void _appendBlock(SmartFile f, String type, String title) {
    f.hybridBlocks ??= [];
    final b = HybridBlock(
      id: CubicDataController.newId('hy_'),
      type: type,
      title: title,
    );
    switch (type) {
      case 'spreadsheet':
        b.rows = 5;
        b.cols = 5;
        b.spreadsheetCells = {
          'A1': CellData(value: 'Label'),
          'B1': CellData(value: 'Weight'),
        };
        break;
      case 'document':
        b.docContent = '';
        break;
      case 'code':
        b.codeLanguage = 'typescript';
        b.docContent = '';
        break;
      case 'checklist':
        b.checklistItems = [];
        break;
      case 'prompt':
        b.promptTemplate = 'Draft a \$PROMPTVAR outline';
        b.descriptionTabs = [];
        break;
      case 'reference':
        b.referenceUrl = '';
        b.docContent = '';
        break;
    }
    f.hybridBlocks!.add(b);
    _persist(f, 'Added $title block');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Obx(() {
      final f = _file;
      if (f == null) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text('File not found.')),
        );
      }
      return Scaffold(
        backgroundColor: isDark ? Dt.canvasDark : Dt.canvas,
        appBar: AppBar(
          title: Text(f.name,
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w800, fontSize: 17)),
        ),
        body: Column(children: [
          if (_copiedFeedback != null)
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Dt.accent.withValues(alpha: 0.15),
              child: Text(_copiedFeedback!,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Dt.accent)),
            ),
          Expanded(
            child: _blocks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.layoutGrid,
                            size: 44, color: Colors.grey),
                        const SizedBox(height: 12),
                        const Text('Empty canvas.'),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () => _appendMenu(f),
                          icon: const Icon(LucideIcons.plus, size: 16),
                          label: const Text('Append component'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding:
                        const EdgeInsets.fromLTRB(12, 8, 12, 90),
                    itemCount: _blocks.length,
                    itemBuilder: (_, i) =>
                        _blockCard(f, _blocks[i], i, isDark),
                  ),
          ),
        ]),
        floatingActionButton: _blocks.isEmpty
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _appendMenu(f),
                backgroundColor: Dt.accent,
                icon: const Icon(LucideIcons.plus,
                    size: 18, color: Colors.white),
                label: const Text('Append',
                    style: TextStyle(color: Colors.white)),
              ),
      );
    });
  }

  Widget _blockCard(
      SmartFile f, HybridBlock b, int index, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isDark ? Colors.white10 : Dt.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Dt.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${index + 1}',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: Dt.accent)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _titleOf(b),
                readOnly: b.locked,
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800, fontSize: 14),
                decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero),
                onChanged: (v) {
                  if (b.locked) return;
                  b.title = v.toUpperCase();
                  _persist(f);
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _typeColor(b.type).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(b.type,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _typeColor(b.type))),
            ),
            IconButton(
              tooltip: 'Delete block',
              icon: const Icon(LucideIcons.trash2, size: 16),
              onPressed: () => _deleteBlock(f, b, index),
            ),
          ]),
          const SizedBox(height: 8),
          _blockBody(f, b, isDark),
          _descTabs(f, b),
        ],
      ),
    );
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'spreadsheet':
        return const Color(0xFF10B981);
      case 'code':
        return Colors.purpleAccent;
      case 'checklist':
        return Colors.orange;
      case 'prompt':
        return Colors.blueAccent;
      case 'reference':
        return Colors.teal;
      default:
        return Colors.cyan;
    }
  }

  Widget _blockBody(SmartFile f, HybridBlock b, bool isDark) {
    switch (b.type) {
      case 'spreadsheet':
        return _miniSheet(f, b, isDark);
      case 'document':
        return _plainArea(
          cacheKey: '${b.id}|doc',
          initial: b.docContent ?? '',
          hint: 'Write a note…',
          readOnly: false,
          onChanged: (v) {
            b.docContent = v;
            _typeSaved();
          },
        );
      case 'code':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text((b.codeLanguage ?? 'code').toUpperCase(),
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).hintColor)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
              ),
              child: _plainArea(
                cacheKey: '${b.id}|code',
                initial: b.docContent ?? '',
                hint: '// code…',
                readOnly: false,
                mono: true,
                onChanged: (v) {
                  b.docContent = v;
                  _typeSaved();
                },
              ),
            ),
          ],
        );
      case 'checklist':
        return _checklist(f, b);
      case 'prompt':
        return _promptBlock(f, b);
      case 'reference':
        return Column(children: [
          TextField(
            controller: _textOf(
                '${b.id}|url', b.referenceUrl ?? ''),
            decoration: const InputDecoration(
              hintText: 'https://…',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) {
              b.referenceUrl = v;
              _typeSaved();
            },
          ),
          const SizedBox(height: 8),
          Row(children: [
            OutlinedButton.icon(
              icon: const Icon(LucideIcons.copy, size: 14),
              label: const Text('Copy link'),
              onPressed: () {
                if ((b.referenceUrl ?? '').isEmpty) return;
                _copy(b.referenceUrl!, 'URL');
              },
            ),
          ]),
          const SizedBox(height: 8),
          _plainArea(
            cacheKey: '${b.id}|notes',
            initial: b.docContent ?? '',
            hint: 'Notes about this link…',
            readOnly: false,
            onChanged: (v) {
              b.docContent = v;
              _typeSaved();
            },
          ),
        ]);
      default:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).hintColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text('Multi canvas — compose freely in code blocks.',
              style: TextStyle(fontSize: 12)),
        );
    }
  }

  Widget _plainArea({
    required String cacheKey,
    required String initial,
    required String hint,
    required bool readOnly,
    required ValueChanged<String> onChanged,
    bool mono = false,
  }) {
    return TextField(
      controller: _textOf(cacheKey, initial),
      readOnly: readOnly,
      maxLines: null,
      style: mono
          ? const TextStyle(
              fontFamily: 'monospace', fontSize: 12.5, height: 1.5)
          : const TextStyle(fontSize: 13.5, height: 1.5),
      decoration: InputDecoration(
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: onChanged,
    );
  }

  Widget _miniSheet(SmartFile f, HybridBlock b, bool isDark) {
    final rows = b.rows ?? 5;
    final cols = b.cols ?? 5;
    b.spreadsheetCells ??= {};
    final line = isDark ? Colors.white10 : Dt.hairline;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const SizedBox(width: 30),
            for (var c = 0; c < cols; c++)
              Container(
                width: 84,
                padding: const EdgeInsets.symmetric(vertical: 4),
                alignment: Alignment.center,
                child: Text(String.fromCharCode(65 + c),
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700)),
              ),
          ]),
          for (var r = 0; r < rows; r++)
            Row(children: [
              SizedBox(
                width: 30,
                child: Text('${r + 1}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700)),
              ),
              for (var c = 0; c < cols; c++)
                Container(
                  width: 84,
                  decoration: BoxDecoration(
                      border: Border.all(color: line, width: 0.5)),
                  child: Builder(builder: (_) {
                    final addr =
                        '${String.fromCharCode(65 + c)}${r + 1}';
                    return TextField(
                      controller: _textOf(
                          '${b.id}|$addr',
                          b.spreadsheetCells![addr]?.value ?? ''),
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 6, vertical: 8),
                      ),
                      onChanged: (v) {
                        final cell = b.spreadsheetCells!
                            .putIfAbsent(addr, () => CellData());
                        cell.value = v;
                        _typeSaved();
                      },
                    );
                  }),
                ),
            ]),
        ],
      ),
    );
  }

  Widget _checklist(SmartFile f, HybridBlock b) {
    b.checklistItems ??= [];
    final newCtrl = _newChecklist.putIfAbsent(
        b.id, () => TextEditingController());
    return Column(children: [
      for (final item in b.checklistItems!)
        Row(children: [
          Checkbox(
            value: item.done,
            activeColor: Dt.accent,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (v) {
              item.done = v ?? false;
              _persist(f);
              setState(() {});
            },
          ),
          Expanded(
            child: Text(item.text,
                style: TextStyle(
                  fontSize: 13.5,
                  decoration: item.done
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                  color: item.done ? Colors.grey : null,
                )),
          ),
          IconButton(
            icon: const Icon(LucideIcons.x, size: 15),
            onPressed: () {
              b.checklistItems!
                  .removeWhere((e) => e.id == item.id);
              _persist(f);
              setState(() {});
            },
          ),
        ]),
      Row(children: [
        Expanded(
          child: TextField(
            controller: newCtrl,
            decoration: const InputDecoration(
              hintText: 'New item…',
              isDense: true,
            ),
            onSubmitted: (v) {
              if (v.trim().isEmpty) return;
              b.checklistItems!.add(HybridChecklistItem(
                  id: CubicDataController.newId('ci_'),
                  text: v.trim()));
              newCtrl.clear();
              _persist(f);
              setState(() {});
            },
          ),
        ),
        TextButton(
          onPressed: () {
            final v = newCtrl.text.trim();
            if (v.isEmpty) return;
            b.checklistItems!.add(HybridChecklistItem(
                id: CubicDataController.newId('ci_'), text: v));
            newCtrl.clear();
            _persist(f);
            setState(() {});
          },
          child: const Text('Add'),
        ),
      ]),
    ]);
  }

  Widget _promptBlock(SmartFile f, HybridBlock b) {
    final bound = (_bindings[b.id] ?? '').trim();
    final rendered = bound.isEmpty
        ? (b.promptTemplate ?? '')
        : (b.promptTemplate ?? '').replaceAll('\$PROMPTVAR', bound);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text(
              b.locked ? 'Locked' : 'Template (use \$PROMPTVAR)',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11, color: Theme.of(context).hintColor),
            ),
          ),
          InkWell(
            onTap: () {
              b.locked = !b.locked;
              _persist(f, b.locked ? 'Locked prompt' : 'Unlocked prompt');
              setState(() {});
            },
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(
                  b.locked ? LucideIcons.lock : LucideIcons.unlock,
                  size: 15,
                  color: b.locked ? Colors.orange : null),
            ),
          ),
          OutlinedButton.icon(
            icon: const Icon(LucideIcons.copy, size: 14),
            label: const Text('Copy'),
            onPressed: () => _copy(rendered, 'Prompt'),
          ),
        ]),
        const SizedBox(height: 6),
        _plainArea(
          cacheKey: '${b.id}|prompt',
          initial: b.promptTemplate ?? '',
          hint: 'Prompt template…',
          readOnly: b.locked,
          mono: true,
          onChanged: (v) {
            if (b.locked) return;
            b.promptTemplate = v;
            _typeSaved();
          },
        ),
        const SizedBox(height: 8),
        TextField(
          decoration: const InputDecoration(
            hintText: 'Bind value for \$PROMPTVAR…',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _bindings[b.id] = v),
        ),
        if (bound.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Dt.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(rendered,
                style: const TextStyle(fontSize: 12.5, height: 1.5)),
          ),
        ],
      ],
    );
  }

  Widget _descTabs(SmartFile f, HybridBlock b) {
    b.descriptionTabs ??= [];
    final tabs = b.descriptionTabs!;
    final active = (_activeTab[b.id] ?? 0).clamp(0, tabs.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (var i = 0; i < tabs.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(tabs[i].title.isEmpty
                      ? 'Tab ${i + 1}'
                      : tabs[i].title),
                  selected: i == active && tabs.isNotEmpty,
                  onSelected: (_) =>
                      setState(() => _activeTab[b.id] = i),
                ),
              ),
            TextButton.icon(
              icon: const Icon(LucideIcons.plus, size: 14),
              label: const Text('Tab'),
              onPressed: () {
                tabs.add(HybridDescriptionTab(
                    id: CubicDataController.newId('dt_'),
                    title: 'Tab ${tabs.length + 1}'));
                _activeTab[b.id] = tabs.length - 1;
                _persist(f, 'Added tab');
                setState(() {});
              },
            ),
          ]),
        ),
        if (tabs.isNotEmpty && active < tabs.length) ...[
          const SizedBox(height: 6),
          TextField(
            controller:
                _textOf('${tabs[active].id}|title', tabs[active].title),
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(
              hintText: 'Tab title…',
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (v) {
              tabs[active].title = v;
              _persist(f);
            },
          ),
          _plainArea(
            cacheKey: '${tabs[active].id}|content',
            initial: tabs[active].content,
            hint: 'Tab content…',
            readOnly: false,
            onChanged: (v) {
              tabs[active].content = v;
              _typeSaved();
            },
          ),
        ],
      ],
    );
  }
}
