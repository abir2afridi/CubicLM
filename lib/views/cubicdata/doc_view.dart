/// CubicDataSheet document editor: Notion-style blocks (headings,
/// bullets, checklist, code, quote), slash-command insert, outline,
/// metrics and Markdown export. Personal on-device space: no database,
/// no sharing (export uses the app folder + system share sheet).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../services/cubicdata/controller.dart';
import '../../services/cubicdata/models.dart';
import '../../services/app_log_service.dart';
import '../../theme/design_tokens.dart';
import '../../utils/export_file.dart';
import 'datasheet_home_view.dart';

class DocEditorView extends StatefulWidget {
  final String fileId;
  const DocEditorView({super.key, required this.fileId});

  @override
  State<DocEditorView> createState() => _DocEditorViewState();
}

class _DocEditorViewState extends State<DocEditorView> {
  CubicDataController get _c => datasheetController();

  final _ctrls = <String, TextEditingController>{};
  final _focus = <String, FocusNode>{};
  final _keys = <String, GlobalKey>{};
  final _scroll = ScrollController();
  String? _slashFor;

  @override
  void initState() {
    super.initState();
    AppLogService.trackScreen('DataSheet Doc');
  }

  @override
  void dispose() {
    AppLogService.untrackScreen('DataSheet Doc');
    _scroll.dispose();
    for (final c in _ctrls.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  SmartFile? get _file => _c.byId(widget.fileId);

  List<DocumentBlock> get _blocks => _file?.docBlocks ?? [];

  TextEditingController _ctrlOf(DocumentBlock b) {
    return _ctrls.putIfAbsent(b.id, () {
      final c = TextEditingController(text: b.content);
      return c;
    });
  }

  FocusNode _focusOf(String id) =>
      _focus.putIfAbsent(id, () => FocusNode());

  GlobalKey _keyOf(String id) =>
      _keys.putIfAbsent(id, () => GlobalKey());

  void _persist(SmartFile f, [String detail = 'Edited']) {
    f.touch();
    _c.files.refresh();
    _c.log('edit', '$detail: ${f.name}', fileId: f.id, fileName: f.name);
    _c.scheduleSave();
  }

  void _setContent(SmartFile f, DocumentBlock b, String v) {
    b.content = v;
    // Local rebuild only (metrics + slash menu): controllers are cached
    // so the cursor never jumps. Vault save is debounced; no per-key
    // activity spam or Rx refresh — structural ops still use _persist.
    if (v == '/') {
      setState(() => _slashFor = b.id);
    } else if (_slashFor == b.id) {
      setState(() => _slashFor = null);
    } else {
      setState(() {});
    }
    _c.scheduleSave();
  }

  void _insertBelow(SmartFile f, int index, {String type = 'paragraph'}) {
    final nb = DocumentBlock(
        id: CubicDataController.newId('blk_'), type: type);
    f.docBlocks!.insert(index + 1, nb);
    _persist(f, 'Inserted block');
    setState(() {});
    Future.delayed(const Duration(milliseconds: 60), () {
      if (!mounted) return;
      _focusOf(nb.id).requestFocus();
    });
  }

  void _deleteBlock(SmartFile f, int index) {
    if (f.docBlocks!.length <= 1) {
      Get.snackbar('Keep one block', 'A document needs at least one block.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    final removed = f.docBlocks!.removeAt(index);
    _ctrls.remove(removed.id)?.dispose();
    _focus.remove(removed.id)?.dispose();
    _keys.remove(removed.id);
    _persist(f, 'Deleted block');
    setState(() {});
  }

  void _convert(SmartFile f, DocumentBlock b, String type) {
    b.type = type;
    if (type == 'checklist_item') b.checked = false;
    _persist(f, 'Converted block');
    setState(() => _slashFor = null);
    _focusOf(b.id).requestFocus();
  }

  void _mergeBack(SmartFile f, int index) {
    if (index <= 0) return;
    final cur = f.docBlocks![index];
    final prev = f.docBlocks![index - 1];
    if (cur.content.isNotEmpty) return;
    f.docBlocks!.removeAt(index);
    _ctrls.remove(cur.id)?.dispose();
    _focus.remove(cur.id)?.dispose();
    _keys.remove(cur.id);
    _persist(f, 'Merged blocks');
    setState(() {});
    Future.delayed(const Duration(milliseconds: 60), () {
      if (!mounted) return;
      _focusOf(prev.id).requestFocus();
      final c = _ctrlOf(prev);
      c.selection = TextSelection.collapsed(offset: c.text.length);
    });
  }

  String _toMarkdown(SmartFile f) {
    final buf = StringBuffer('# ${f.name}\n\n');
    var num = 0;
    for (final b in f.docBlocks ?? const <DocumentBlock>[]) {
      switch (b.type) {
        case 'heading1':
          buf.writeln('# ${b.content}\n');
          num = 0;
          break;
        case 'heading2':
          buf.writeln('## ${b.content}\n');
          num = 0;
          break;
        case 'bullet_list_item':
          buf.writeln('- ${b.content}');
          num = 0;
          break;
        case 'numbered_list_item':
          num++;
          buf.writeln('$num. ${b.content}');
          break;
        case 'checklist_item':
          buf.writeln('- [${b.checked ? 'x' : ' '}] ${b.content}');
          num = 0;
          break;
        case 'code_block':
          buf.writeln('```${b.language ?? ''}\n${b.content}\n```\n');
          num = 0;
          break;
        case 'quote':
          buf.writeln('> ${b.content}\n');
          num = 0;
          break;
        default:
          buf.writeln('${b.content}\n');
          num = 0;
      }
    }
    return buf.toString();
  }

  Map<String, int> _metrics() {
    var words = 0;
    var chars = 0;
    for (final b in _blocks) {
      final t = b.content.trim();
      if (t.isEmpty) continue;
      chars += b.content.length;
      words += t.split(RegExp(r'\s+')).length;
    }
    return {'words': words, 'chars': chars, 'read': (words / 220).ceil()};
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
      final m = _metrics();
      return Scaffold(
        backgroundColor: isDark ? Dt.canvasDark : Dt.canvas,
        appBar: AppBar(
          title: Text(f.name,
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w800, fontSize: 17)),
          actions: [
            IconButton(
              tooltip: 'Outline',
              icon: const Icon(LucideIcons.listTree, size: 20),
              onPressed: () => _outlineSheet(f),
            ),
            IconButton(
              tooltip: 'Export Markdown',
              icon: const Icon(LucideIcons.share, size: 20),
              onPressed: () {
                final md = _toMarkdown(f);
                ExportFile.quickExport(
                  text: md,
                  fileName:
                      '${f.name.replaceAll(RegExp(r'[^\w\-. ]'), '_')}.md',
                  mimeType: 'text/markdown',
                  shareText: md,
                );
              },
            ),
          ],
        ),
        body: Column(children: [
          Expanded(
            child: _blocks.isEmpty
                ? const Center(child: Text('Empty document.'))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
                    itemCount: _blocks.length,
                    itemBuilder: (_, i) =>
                        _blockRow(f, _blocks[i], i, isDark),
                  ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
                16, 8, 16, 8 + MediaQuery.of(context).padding.bottom),
            decoration: BoxDecoration(
              border: Border(
                  top: BorderSide(
                      color: isDark ? Colors.white10 : Dt.hairline)),
            ),
            child: Row(children: [
              Text(
                  '${m['words']} words · ${m['chars']} chars · ${m['read']} min',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: Theme.of(context).hintColor)),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: () {
                  final nb = DocumentBlock(
                      id: CubicDataController.newId('blk_'),
                      type: 'paragraph');
                  f.docBlocks!.add(nb);
                  _persist(f, 'Inserted block');
                  setState(() {});
                  Future.delayed(const Duration(milliseconds: 80), () {
                    if (!mounted) return;
                    _scroll.jumpTo(_scroll.position.maxScrollExtent);
                    _focusOf(nb.id).requestFocus();
                  });
                },
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('Block'),
              ),
            ]),
          ),
        ]),
      );
    });
  }

  Widget _blockRow(
      SmartFile f, DocumentBlock b, int index, bool isDark) {
    final ctrl = _ctrlOf(b);
    if (ctrl.text != b.content &&
        !(_slashFor == b.id && ctrl.text == '/')) {
      ctrl.text = b.content;
    }
    final totalNumbered = _numberFor(index);
    return Container(
      key: _keyOf(b.id),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _gutter(f, b, index),
              if (b.type == 'checklist_item')
                Padding(
                  padding: const EdgeInsets.only(top: 10, right: 4),
                  child: Checkbox(
                    value: b.checked,
                    activeColor: Dt.accent,
                    materialTapTargetSize:
                        MaterialTapTargetSize.shrinkWrap,
                    onChanged: (v) {
                      b.checked = v ?? false;
                      _persist(f, 'Toggled checklist');
                      setState(() {});
                    },
                  ),
                ),
              if (b.type == 'bullet_list_item')
                const Padding(
                  padding: EdgeInsets.only(top: 12, right: 8, left: 4),
                  child: Text('•',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w900)),
                ),
              if (b.type == 'numbered_list_item')
                Padding(
                  padding:
                      const EdgeInsets.only(top: 12, right: 8, left: 4),
                  child: Text('$totalNumbered.',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              if (b.type == 'quote')
                Container(
                  width: 4,
                  margin:
                      const EdgeInsets.only(top: 8, bottom: 8, right: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              Expanded(
                child: Container(
                  padding: b.type == 'code_block'
                      ? const EdgeInsets.all(10)
                      : EdgeInsets.zero,
                  decoration: b.type == 'code_block'
                      ? BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(4),
                        )
                      : null,
                  child: KeyboardListener(
                    focusNode: FocusNode(skipTraversal: true),
                    onKeyEvent: (e) {
                      if (e is KeyDownEvent &&
                          e.logicalKey ==
                              LogicalKeyboardKey.backspace &&
                          ctrl.text.isEmpty) {
                        _mergeBack(f, index);
                      }
                    },
                    child: TextField(
                      controller: ctrl,
                      focusNode: _focusOf(b.id),
                      maxLines: null,
                      style: _textStyle(b),
                      decoration: InputDecoration(
                        hintText: _hintFor(b),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (v) => _setContent(f, b, v),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_slashFor == b.id) _slashMenu(f, b),
        ],
      ),
    );
  }

  int _numberFor(int index) {
    var n = 0;
    for (var i = 0; i <= index; i++) {
      if (_blocks[i].type == 'numbered_list_item') {
        n++;
      } else if (_blocks[i].type != 'numbered_list_item' &&
          _blocks[i].content.isNotEmpty) {
        n = 0;
      }
    }
    return n < 1 ? 1 : n;
  }

  Widget _gutter(SmartFile f, DocumentBlock b, int index) {
    return InkWell(
      onTap: () => _blockMenu(f, b, index),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(LucideIcons.gripVertical,
            size: 15, color: Theme.of(context).hintColor),
      ),
    );
  }

  void _blockMenu(SmartFile f, DocumentBlock b, int index) {
    Get.bottomSheet(SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _menuTile(LucideIcons.plus, 'Insert block below', () {
              Get.back();
              _insertBelow(f, index);
            }),
            const Divider(height: 8),
            _menuTile(LucideIcons.text, 'Paragraph',
                () => _pickConvert(f, b, 'paragraph')),
            _menuTile(LucideIcons.heading1, 'Heading 1',
                () => _pickConvert(f, b, 'heading1')),
            _menuTile(LucideIcons.heading2, 'Heading 2',
                () => _pickConvert(f, b, 'heading2')),
            _menuTile(LucideIcons.list, 'Bullet list',
                () => _pickConvert(f, b, 'bullet_list_item')),
            _menuTile(LucideIcons.listOrdered, 'Numbered list',
                () => _pickConvert(f, b, 'numbered_list_item')),
            _menuTile(LucideIcons.listChecks, 'Checklist',
                () => _pickConvert(f, b, 'checklist_item')),
            _menuTile(LucideIcons.code, 'Code block',
                () => _pickConvert(f, b, 'code_block')),
            _menuTile(LucideIcons.quote, 'Quote',
                () => _pickConvert(f, b, 'quote')),
            const Divider(height: 8),
            _menuTile(LucideIcons.trash2, 'Delete block', () {
              Get.back();
              _deleteBlock(f, index);
            }),
          ]),
        ),
      ),
    ));
  }

  void _pickConvert(SmartFile f, DocumentBlock b, String type) {
    Get.back();
    _convert(f, b, type);
  }

  Widget _menuTile(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 18),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      onTap: onTap,
    );
  }

  Widget _slashMenu(SmartFile f, DocumentBlock b) {
    const templates = [
      ('paragraph', 'Text', 'Just start writing', LucideIcons.text),
      ('heading1', 'Heading 1', 'Big section heading', LucideIcons.heading1),
      ('heading2', 'Heading 2', 'Smaller heading', LucideIcons.heading2),
      ('bullet_list_item', 'Bullet', 'Bulleted list item', LucideIcons.list),
      (
        'numbered_list_item',
        'Numbered',
        'Numbered list item',
        LucideIcons.listOrdered
      ),
      ('checklist_item', 'Checklist', 'Todo with checkbox',
          LucideIcons.listChecks),
      ('code_block', 'Code', 'Monospace code block', LucideIcons.code),
      ('quote', 'Quote', 'Highlighted quote', LucideIcons.quote),
    ];
    return Container(
      margin: const EdgeInsets.only(top: 4, left: 28),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 12)
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text('Insert block',
                style:
                    TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          for (final t in templates)
            ListTile(
              dense: true,
              leading: Icon(t.$4, size: 16),
              title: Text(t.$2, style: const TextStyle(fontSize: 13)),
              subtitle: Text(t.$3,
                  style: const TextStyle(fontSize: 11)),
              onTap: () => _convert(f, b, t.$1),
            ),
        ],
      ),
    );
  }

  TextStyle _textStyle(DocumentBlock b) {
    switch (b.type) {
      case 'heading1':
        return GoogleFonts.plusJakartaSans(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Colors.cyan.shade300);
      case 'heading2':
        return GoogleFonts.plusJakartaSans(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF6EE7B7));
      case 'code_block':
        return const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12.5,
            color: Colors.white70,
            height: 1.5);
      case 'quote':
        return const TextStyle(
            fontSize: 14, fontStyle: FontStyle.italic, height: 1.5);
      case 'checklist_item':
        return TextStyle(
          fontSize: 14,
          height: 1.45,
          decoration:
              b.checked ? TextDecoration.lineThrough : TextDecoration.none,
          color: b.checked ? Colors.grey : null,
        );
      default:
        return const TextStyle(fontSize: 14, height: 1.45);
    }
  }

  String _hintFor(DocumentBlock b) {
    switch (b.type) {
      case 'heading1':
        return 'Heading 1';
      case 'heading2':
        return 'Heading 2';
      case 'code_block':
        return 'Code…';
      case 'quote':
        return 'Quote…';
      default:
        return 'Type / for blocks…';
    }
  }

  void _outlineSheet(SmartFile f) {
    final heads = <int>[];
    for (var i = 0; i < _blocks.length; i++) {
      if (_blocks[i].type == 'heading1' ||
          _blocks[i].type == 'heading2') {
        heads.add(i);
      }
    }
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
            child: Text('Outline',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ),
          if (heads.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No headings yet.'),
            ),
          for (final i in heads)
            ListTile(
              dense: true,
              leading: Icon(
                  _blocks[i].type == 'heading1'
                      ? LucideIcons.heading1
                      : LucideIcons.heading2,
                  size: 16),
              title: Text(
                  _blocks[i].content.isEmpty
                      ? '(empty heading)'
                      : _blocks[i].content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize:
                          _blocks[i].type == 'heading1' ? 14 : 13)),
              onTap: () {
                Get.back();
                final key = _keyOf(_blocks[i].id);
                final ctx = key.currentContext;
                if (ctx != null) {
                  Scrollable.ensureVisible(ctx,
                      duration: const Duration(milliseconds: 300));
                }
                _focusOf(_blocks[i].id).requestFocus();
              },
            ),
        ]),
      ),
    ));
  }
}
