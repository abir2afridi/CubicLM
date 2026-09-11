/// CubicDataSheet spreadsheet editor: grid, formula bar, per-cell
/// copy/lock/note/style actions, sheets tabs, notes+history drawer.
///
/// Personal on-device space: no database, no sharing. Every mutation
/// goes through [CubicDataController.saveFile] (debounced vault persist).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../services/cubicdata/controller.dart';
import '../../services/cubicdata/formulas.dart';
import '../../services/app_log_service.dart';
import '../../services/cubicdata/models.dart';
import '../../core/colors.dart';
import '../../theme/design_tokens.dart';

class SheetEditorView extends StatefulWidget {
  final String fileId;
  const SheetEditorView({super.key, required this.fileId});

  @override
  State<SheetEditorView> createState() => _SheetEditorViewState();
}

class _SheetEditorViewState extends State<SheetEditorView> {
  CubicDataController get _c {
    try {
      return Get.find<CubicDataController>();
    } catch (_) {
      return Get.put(CubicDataController());
    }
  }

  String? _selected;
  bool _unlockMode = false;
  bool _showStyles = false;
  final _hScroll = ScrollController();
  final _vHeadScroll = ScrollController();
  final List<ScrollController> _rowCtrls = [];
  bool _syncingScroll = false;
  final _formulaCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  static const _colWidth = 88.0;
  static const _rowHeight = 42.0;
  static const _headerWidth = 40.0;

  @override
  void initState() {
    super.initState();
    AppLogService.trackScreen('DataSheet Sheet');
  }

  @override
  void dispose() {
    AppLogService.untrackScreen('DataSheet Sheet');
    _hScroll.dispose();
    _vHeadScroll.dispose();
    for (final c in _rowCtrls) {
      c.dispose();
    }
    _formulaCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  SmartFile? get _file => _c.byId(widget.fileId);

  SheetData? get _sheet {
    final f = _file;
    if (f == null || f.sheets == null || f.sheets!.isEmpty) return null;
    for (final s in f.sheets!) {
      if (s.id == f.activeSheetId) return s;
    }
    return f.sheets!.first;
  }

  /// Keeps one controller per body row; all rows share identical widths
  /// so a single offset fits every list.
  void _ensureRowCtrls(int n) {
    while (_rowCtrls.length < n) {
      _rowCtrls.add(ScrollController());
    }
    while (_rowCtrls.length > n) {
      _rowCtrls.removeLast().dispose();
    }
  }

  /// Syncs sticky headers with the body: horizontal scrolls drive the
  /// column header + every row; vertical scrolls drive the row headers.
  /// Axis (not depth) distinguishes them, so nesting changes can't break it.
  bool _onGridScroll(ScrollNotification note) {
    if (_syncingScroll) return false;
    if (note is! ScrollUpdateNotification) return false;
    _syncingScroll = true;
    try {
      if (note.metrics.axis == Axis.horizontal) {
        final off = note.metrics.pixels;
        if (_hScroll.hasClients) _hScroll.jumpTo(off);
        for (final c in _rowCtrls) {
          if (c.hasClients) c.jumpTo(off);
        }
      } else {
        final off = note.metrics.pixels;
        if (_vHeadScroll.hasClients) _vHeadScroll.jumpTo(off);
      }
    } catch (_) {
      // Controllers mid-attach during first layout — next scroll syncs.
    } finally {
      _syncingScroll = false;
    }
    return false;
  }

  String _display(SheetData sheet, String addr) {
    final cell = sheet.cells[addr];
    if (cell == null) return '';
    if (cell.isCheckbox) return cell.isChecked ? 'TRUE' : 'FALSE';
    if (cell.formula != null && cell.formula!.startsWith('=')) {
      return evaluateFormula(cell.formula!, _file!.sheets!, sheet.id, {});
    }
    return cell.value;
  }

  void _select(String addr) {
    setState(() => _selected = addr);
    final cell = _sheet?.cells[addr];
    _formulaCtrl.text = cell?.formula ?? cell?.value ?? '';
  }

  void _saveCell(String raw) {
    final f = _file;
    final sheet = _sheet;
    final addr = _selected;
    if (f == null || sheet == null || addr == null) return;
    final cell = sheet.cells[addr];
    if (cell != null && cell.locked) {
      Get.snackbar('Locked', '$addr is locked — unlock it first.',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 2));
      return;
    }
    final text = raw.trim();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (text.isEmpty) {
      if (cell != null) {
        cell.history ??= [];
        cell.history!.add(CellHistoryEntry(
            timestamp: now,
            user: 'You',
            oldValue: cell.value,
            newValue: '',
            oldFormula: cell.formula,
            newFormula: null));
        cell.value = '';
        cell.formula = null;
      }
    } else if (text.startsWith('=')) {
      final err = detectFormulaError(text);
      if (err != null) {
        Get.snackbar('Formula issue', err,
            snackPosition: SnackPosition.BOTTOM,
            duration: const Duration(seconds: 2));
      }
      final c = sheet.cells.putIfAbsent(addr, () => CellData());
      c.history ??= [];
      c.history!.add(CellHistoryEntry(
          timestamp: now,
          user: 'You',
          oldValue: c.value,
          newValue: '',
          oldFormula: c.formula,
          newFormula: text));
      c.formula = text;
      c.value = '';
    } else {
      final c = sheet.cells.putIfAbsent(addr, () => CellData());
      c.history ??= [];
      c.history!.add(CellHistoryEntry(
          timestamp: now,
          user: 'You',
          oldValue: c.value,
          newValue: text,
          oldFormula: c.formula,
          newFormula: null));
      c.value = text;
      c.formula = null;
    }
    _c.saveFile(f, detail: 'Edited $addr');
  }

  void _onCellTap(SheetData sheet, SmartFile f, String addr) {
    final cell = sheet.cells[addr];
    if (cell != null && cell.locked) {
      if (_unlockMode) {
        _unlockFlow(f, sheet, addr, cell);
      } else {
        _select(addr);
        Get.snackbar(
            'Locked ($addr)', 'Turn on Unlock mode (header) to unlock it.',
            snackPosition: SnackPosition.BOTTOM,
            duration: const Duration(seconds: 2));
      }
      return;
    }
    if (cell != null && cell.isCheckbox) {
      cell.isChecked = !cell.isChecked;
      _c.saveFile(f, detail: 'Toggled $addr');
      _select(addr);
      return;
    }
    _select(addr);
  }

  // ── Lock / unlock ──

  void _lockFlow(SmartFile f, SheetData sheet, String addr) {
    var level = LockLevel.soft;
    final pwCtrl = TextEditingController();
    Get.dialog(
      AlertDialog(
        title: Text('Lock $addr'),
        content: StatefulBuilder(
          builder: (ctx, setState) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioGroup<LockLevel>(
                  groupValue: level,
                  onChanged: (v) =>
                      setState(() => level = v ?? LockLevel.soft),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final l in [
                        LockLevel.soft,
                        LockLevel.protected,
                        LockLevel.vault,
                        LockLevel.permanent
                      ])
                        RadioListTile<LockLevel>(
                          dense: true,
                          value: l,
                          title: Text(_lockLabel(l),
                              style:
                                  const TextStyle(fontSize: 14)),
                          subtitle: Text(_lockHint(l),
                              style:
                                  const TextStyle(fontSize: 11)),
                        ),
                    ],
                  ),
                ),
                if (level == LockLevel.vault)
                  TextField(
                    controller: pwCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'Password', isDense: true),
                  ),
                if (level == LockLevel.permanent)
                  const Text(
                      'Permanent locks need the word RESTORE to ever unlock.',
                      style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Get.back(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (level == LockLevel.vault && pwCtrl.text.isEmpty) {
                Get.snackbar('Password needed',
                    'Vault locks require a password.',
                    snackPosition: SnackPosition.BOTTOM);
                return;
              }
              final cell =
                  sheet.cells.putIfAbsent(addr, () => CellData());
              cell.lockLevel = level;
              cell.lockPassword =
                  level == LockLevel.vault ? pwCtrl.text : null;
              _c.saveFile(f, detail: 'Locked $addr');
              _c.log('lock', 'Locked $addr (${_lockLabel(level)})',
                  fileId: f.id, fileName: f.name);
              Get.back();
            },
            child: const Text('Lock'),
          ),
        ],
      ),
    );
  }

  void _unlockFlow(
      SmartFile f, SheetData sheet, String addr, CellData cell) {
    void doUnlock() {
      cell.lockLevel = LockLevel.none;
      cell.lockPassword = null;
      _c.saveFile(f, detail: 'Unlocked $addr');
      _c.log('unlock', 'Unlocked $addr',
          fileId: f.id, fileName: f.name);
    }

    switch (cell.lockLevel) {
      case LockLevel.none:
        return;
      case LockLevel.soft:
        doUnlock();
        return;
      case LockLevel.protected:
        Get.dialog(AlertDialog(
          title: Text('Unlock $addr?'),
          content: const Text(
              'This cell is protected. Unlocking allows edits again.'),
          actions: [
            TextButton(
                onPressed: () => Get.back(),
                child: const Text('Keep locked')),
            FilledButton(
                onPressed: () {
                  Get.back();
                  doUnlock();
                },
                child: const Text('Unlock')),
          ],
        ));
        return;
      case LockLevel.vault:
        final pwCtrl = TextEditingController();
        Get.dialog(AlertDialog(
          title: Text('Unlock $addr'),
          content: TextField(
            controller: pwCtrl,
            obscureText: true,
            autofocus: true,
            decoration:
                const InputDecoration(labelText: 'Password', isDense: true),
          ),
          actions: [
            TextButton(
                onPressed: () => Get.back(),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (pwCtrl.text == cell.lockPassword) {
                  Get.back();
                  doUnlock();
                } else {
                  Get.snackbar('Wrong password', 'Try again.',
                      snackPosition: SnackPosition.BOTTOM);
                }
              },
              child: const Text('Unlock'),
            ),
          ],
        ));
        return;
      case LockLevel.permanent:
        final phraseCtrl = TextEditingController();
        Get.dialog(AlertDialog(
          title: Text('Unlock $addr'),
          content: const Text(
              'Permanent locks need recovery: type RESTORE to unlock.'),
          actions: [
            TextButton(
                onPressed: () => Get.back(),
                child: const Text('Cancel')),
          ],
        ));
        // Phrase input lives in the same dialog via a second step.
        Get.dialog(AlertDialog(
          title: const Text('Type RESTORE'),
          content: TextField(
            controller: phraseCtrl,
            autofocus: true,
            decoration:
                const InputDecoration(labelText: 'Recovery phrase'),
            onSubmitted: (v) {
              if (v.trim() == 'RESTORE') {
                Get.back();
                doUnlock();
              } else {
                Get.snackbar('No match', 'Type RESTORE exactly.',
                    snackPosition: SnackPosition.BOTTOM);
              }
            },
          ),
          actions: [
            FilledButton(
              onPressed: () {
                if (phraseCtrl.text.trim() == 'RESTORE') {
                  Get.back();
                  doUnlock();
                } else {
                  Get.snackbar('No match', 'Type RESTORE exactly.',
                      snackPosition: SnackPosition.BOTTOM);
                }
              },
              child: const Text('Recover'),
            ),
          ],
        ));
        return;
    }
  }

  String _lockLabel(LockLevel l) {
    switch (l) {
      case LockLevel.none:
        return 'No lock';
      case LockLevel.soft:
        return 'Soft — one tap to unlock';
      case LockLevel.protected:
        return 'Protected — confirm to unlock';
      case LockLevel.vault:
        return 'Vault — password to unlock';
      case LockLevel.permanent:
        return 'Permanent — RESTORE phrase to unlock';
    }
  }

  String _lockHint(LockLevel l) {
    switch (l) {
      case LockLevel.none:
        return 'Editable by anyone';
      case LockLevel.soft:
        return 'Prevents accidental edits';
      case LockLevel.protected:
        return 'Asks before unlocking';
      case LockLevel.vault:
        return 'Only you, with the password';
      case LockLevel.permanent:
        return 'Strongest — recovery only';
    }
  }

  // ── Copy ──

  void _copySheet(SmartFile f, SheetData sheet, String addr) {
    final cell = sheet.cells[addr];
    final display = _display(sheet, addr);
    Get.bottomSheet(
      SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _copyOption(f, addr, 'Plain text', display, display),
              _copyOption(f, addr, 'Formula',
                  cell?.formula ?? display, cell?.formula ?? display),
              _copyOption(f, addr, 'Markdown', '|$addr|$display|',
                  '|$addr|$display|'),
              _copyOption(
                  f,
                  addr,
                  'JSON',
                  '{"cell":"$addr"}',
                  '{"cell":"$addr","value":"${cell?.value ?? ''}","formula":"${cell?.formula ?? ''}","lock":${cell?.lockLevel.index ?? 0}}'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _copyOption(SmartFile f, String addr, String label, String shown,
      String raw) {
    return ListTile(
      dense: true,
      leading: const Icon(LucideIcons.copy, size: 18),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      subtitle: Text(shown,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11)),
      onTap: () async {
        Get.back();
        await Clipboard.setData(ClipboardData(text: raw));
        _c.pushClipboard(
            content: raw,
            type: label,
            cellAddress: addr,
            fileName: f.name);
        _c.log('copy', 'Copied $addr ($label)',
            fileId: f.id, fileName: f.name);
        Get.snackbar('Copied', '$addr ($label)',
            snackPosition: SnackPosition.BOTTOM,
            duration: const Duration(seconds: 2));
      },
    );
  }

  // ── Notes + history ──

  void _notesSheet(SmartFile f, SheetData sheet, String addr) {
    final cell = sheet.cells[addr];
    if (cell != null && cell.locked) {
      Get.snackbar('Locked', '$addr is locked.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    _noteCtrl.text = cell?.note ?? '';
    Get.bottomSheet(
      SafeArea(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Notes — $addr',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 8),
                TextField(
                  controller: _noteCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Add a note…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) {
                    final c =
                        sheet.cells.putIfAbsent(addr, () => CellData());
                    c.note = v.isEmpty ? null : v;
                    _c.saveFile(f, detail: 'Noted $addr');
                  },
                ),
                const SizedBox(height: 12),
                Text('History',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 4),
                if (cell?.history == null || cell!.history!.isEmpty)
                  const Text('No edits yet.',
                      style: TextStyle(fontSize: 12))
                else
                  for (final h in cell.history!.reversed.take(20))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                          '"${h.oldValue}" → "${h.newValue}"${h.newFormula != null ? ' (${h.newFormula})' : ''}',
                          style: const TextStyle(fontSize: 12)),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Build ──

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
      final sheet = _sheet;
      if (sheet == null) {
        return Scaffold(
          appBar: AppBar(title: Text(f.name)),
          body: const Center(child: Text('No sheets yet.')),
        );
      }
      final sel = _selected;
      final selCell = sel != null ? sheet.cells[sel] : null;
      return Scaffold(
        backgroundColor: isDark ? Dt.canvasDark : Dt.canvas,
        appBar: AppBar(
          title: Text(f.name,
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w800, fontSize: 17)),
          actions: [
            IconButton(
              tooltip: _unlockMode ? 'Unlock mode ON' : 'Unlock mode',
              icon: Icon(
                  _unlockMode ? LucideIcons.unlock : LucideIcons.lock,
                  color: _unlockMode ? Dt.accent : null),
              onPressed: () =>
                  setState(() => _unlockMode = !_unlockMode),
            ),
            PopupMenuButton<String>(
              onSelected: (v) => _sheetMenu(f, v),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'add', child: Text('Add sheet')),
                PopupMenuItem(
                    value: 'duplicate', child: Text('Duplicate sheet')),
                PopupMenuItem(value: 'delete', child: Text('Delete sheet')),
              ],
            ),
          ],
        ),
        body: Column(children: [
          // Formula bar: ADDR | input.
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(
                      color: isDark ? Colors.white10 : Dt.hairline)),
            ),
            child: Row(children: [
              Container(
                width: 52,
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Dt.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(sel ?? '—',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: Dt.accent)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _formulaCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Value or =formula…',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 13),
                  onSubmitted: _saveCell,
                ),
              ),
              IconButton(
                tooltip: 'Save cell',
                icon: const Icon(LucideIcons.check, size: 18),
                onPressed: () => _saveCell(_formulaCtrl.text),
              ),
            ]),
          ),
          // Selected-cell actions.
          if (sel != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _actionChip(context, LucideIcons.copy, 'Copy',
                      () => _copySheet(f, sheet, sel)),
                  const SizedBox(width: 6),
                  _actionChip(
                      context,
                      (selCell?.locked ?? false)
                          ? LucideIcons.unlock
                          : LucideIcons.lock,
                      (selCell?.locked ?? false) ? 'Unlock' : 'Lock', () {
                    if (selCell != null && selCell.locked) {
                      if (_unlockMode) {
                        _unlockFlow(f, sheet, sel, selCell);
                      } else {
                        setState(() => _unlockMode = true);
                        Get.snackbar('Unlock mode ON',
                            'Tap the locked cell again to unlock.',
                            snackPosition: SnackPosition.BOTTOM,
                            duration: const Duration(seconds: 2));
                      }
                    } else {
                      _lockFlow(f, sheet, sel);
                    }
                  }),
                  const SizedBox(width: 6),
                  _actionChip(context, LucideIcons.stickyNote, 'Note',
                      () => _notesSheet(f, sheet, sel)),
                  const SizedBox(width: 6),
                  _actionChip(context, LucideIcons.checkSquare, 'Checkbox',
                      () {
                    final c = sheet.cells
                        .putIfAbsent(sel, () => CellData());
                    if (c.locked) {
                      Get.snackbar('Locked', '$sel is locked.',
                          snackPosition: SnackPosition.BOTTOM);
                      return;
                    }
                    if (c.isCheckbox) {
                      c.isChecked = !c.isChecked;
                    } else {
                      c.isCheckbox = true;
                      c.isChecked = false;
                      c.value = 'FALSE';
                    }
                    _c.saveFile(f, detail: 'Checkbox $sel');
                  }),
                  const SizedBox(width: 6),
                  _actionChip(context, LucideIcons.palette, 'Style', () {
                    setState(() => _showStyles = !_showStyles);
                  }),
                  const SizedBox(width: 6),
                  _actionChip(context, LucideIcons.eraser, 'Clear', () {
                    final c = sheet.cells[sel];
                    if (c == null) return;
                    if (c.locked) {
                      Get.snackbar('Locked', '$sel is locked.',
                          snackPosition: SnackPosition.BOTTOM);
                      return;
                    }
                    sheet.cells.remove(sel);
                    _formulaCtrl.clear();
                    _c.saveFile(f, detail: 'Cleared $sel');
                  }),
                ]),
              ),
            ),
          // Style bar.
          if (sel != null && _showStyles)
            _styleBar(f, sheet, sel, isDark),
          // Grid.
          Expanded(child: _grid(f, sheet, isDark)),
          // Sheets tabs.
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              border: Border(
                  top: BorderSide(
                      color: isDark ? Colors.white10 : Dt.hairline)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final s in f.sheets!)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(s.name),
                      selected: s.id == sheet.id,
                      onSelected: (_) {
                        f.activeSheetId = s.id;
                        setState(() => _selected = null);
                        _formulaCtrl.clear();
                        _c.saveFile(f, detail: 'Switched sheet');
                      },
                    ),
                  ),
                IconButton(
                  tooltip: 'Add sheet',
                  icon: const Icon(LucideIcons.plus, size: 18),
                  onPressed: () => _sheetMenu(f, 'add'),
                ),
              ]),
            ),
          ),
        ]),
      );
    });
  }

  Widget _actionChip(BuildContext context, IconData icon, String label,
      VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
              color: Theme.of(context).hintColor.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _styleBar(
      SmartFile f, SheetData sheet, String addr, bool isDark) {
    final cell = sheet.cells[addr];
    void apply(CellStyle Function(CellStyle) fn) {
      if (cell != null && cell.locked) {
        Get.snackbar('Locked', '$addr is locked.',
            snackPosition: SnackPosition.BOTTOM);
        return;
      }
      final c = sheet.cells.putIfAbsent(addr, () => CellData());
      final cur = c.style ?? const CellStyle();
      c.style = fn(cur);
      if (c.style!.isEmpty) c.style = null;
      _c.saveFile(f, detail: 'Styled $addr');
    }

    Widget swatch(Color color) {
      final hex =
          '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
      final active = cell?.style?.bg?.toUpperCase() == hex;
      return InkWell(
        onTap: () => apply((s) => CellStyle(
            bold: s.bold,
            italic: s.italic,
            underline: s.underline,
            color: s.color,
            bg: active ? null : hex,
            align: s.align,
            fontSize: s.fontSize)),
        child: Container(
          width: 26,
          height: 26,
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
                color: active
                    ? Dt.accent
                    : Theme.of(context).hintColor.withValues(alpha: 0.3),
                width: active ? 2 : 1),
          ),
        ),
      );
    }

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _styleBtn(context, LucideIcons.bold, cell?.style?.bold ?? false,
              () {
            final b = !(cell?.style?.bold ?? false);
            apply((s) => CellStyle(
                bold: b,
                italic: s.italic,
                underline: s.underline,
                color: s.color,
                bg: s.bg,
                align: s.align,
                fontSize: s.fontSize));
          }),
          _styleBtn(
              context, LucideIcons.italic, cell?.style?.italic ?? false,
              () {
            final v = !(cell?.style?.italic ?? false);
            apply((s) => CellStyle(
                bold: s.bold,
                italic: v,
                underline: s.underline,
                color: s.color,
                bg: s.bg,
                align: s.align,
                fontSize: s.fontSize));
          }),
          _styleBtn(context, LucideIcons.underline,
              cell?.style?.underline ?? false, () {
            final v = !(cell?.style?.underline ?? false);
            apply((s) => CellStyle(
                bold: s.bold,
                italic: s.italic,
                underline: v,
                color: s.color,
                bg: s.bg,
                align: s.align,
                fontSize: s.fontSize));
          }),
          const SizedBox(width: 8),
          for (final c in [
            const Color(0xFFFFEB3B),
            const Color(0xFF4CAF50),
            const Color(0xFF2196F3),
            const Color(0xFFFF9800),
            const Color(0xFFF44336),
            const Color(0xFF252525),
          ])
            swatch(c),
        ]),
      ),
    );
  }

  Widget _styleBtn(
      BuildContext context, IconData icon, bool active, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: active
                ? Dt.accent.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
                color: Theme.of(context)
                    .hintColor
                    .withValues(alpha: 0.3)),
          ),
          child: Icon(icon,
              size: 15, color: active ? Dt.accent : null),
        ),
      ),
    );
  }

  Color? _parseColor(String? hex) {
    if (hex == null) return null;
    var h = hex.trim();
    if (h.startsWith('#')) h = h.substring(1);
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return null;
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(v);
  }

  Widget _grid(SmartFile f, SheetData sheet, bool isDark) {
    final line = isDark ? Colors.white10 : Dt.hairline;
    _ensureRowCtrls(sheet.rows);

    return Column(children: [
      // Sticky column headers (share the body horizontal controller).
      Row(children: [
        Container(
          width: _headerWidth,
          height: _rowHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isDark ? AppColors.surface : const Color(0xFFF1F1F4),
            border: Border(
                right: BorderSide(color: line),
                bottom: BorderSide(color: line)),
          ),
          child: Text('#',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).hintColor)),
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: _hScroll,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: Row(children: [
              for (var c = 0; c < sheet.cols; c++)
                Container(
                  width: _colWidth,
                  height: _rowHeight,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color:
                        isDark ? AppColors.surface : const Color(0xFFF1F1F4),
                    border: Border(
                        right: BorderSide(color: line),
                        bottom: BorderSide(color: line)),
                  ),
                  child: Text(idxToColLabel(c),
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).hintColor)),
                ),
            ]),
          ),
        ),
      ]),
      Expanded(
        child: NotificationListener<ScrollNotification>(
          onNotification: _onGridScroll,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sticky row headers (driven by body vertical scroll).
              SizedBox(
                width: _headerWidth,
                child: ListView.builder(
                  controller: _vHeadScroll,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: sheet.rows,
                  itemBuilder: (_, r) => Container(
                    height: _rowHeight,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color:
                          isDark ? AppColors.surface : const Color(0xFFF1F1F4),
                      border:
                          Border(bottom: BorderSide(color: line)),
                    ),
                    child: Text('${r + 1}',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).hintColor)),
                  ),
                ),
              ),
              // Body rows: one vertical list, each row scrolls horizontally.
              Expanded(
                child: ListView.builder(
                  itemCount: sheet.rows,
                  itemBuilder: (_, r) => SizedBox(
                    height: _rowHeight,
                    child: ListView.builder(
                      controller: _rowCtrls[r],
                      scrollDirection: Axis.horizontal,
                      itemCount: sheet.cols,
                    itemBuilder: (_, c) => _cell(
                        f,
                        sheet,
                        '${idxToColLabel(c)}${r + 1}',
                        isDark,
                        line),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ]);
  }

  // NOTE: horizontal sync is driven by scroll notifications (see
  // _onGridScroll) — every row keeps its own controller because one
  // controller cannot attach to several scrollables.
  Widget _cell(SmartFile f, SheetData sheet, String addr, bool isDark,
      Color line) {
    final cell = sheet.cells[addr];
    final isSel = _selected == addr;
    final display = _display(sheet, addr);
    final style = cell?.style;
    final locked = cell?.locked ?? false;
    Border border = Border(
        right: BorderSide(color: line), bottom: BorderSide(color: line));
    if (isSel) {
      border = Border.all(color: Dt.accent, width: 2);
    } else if (locked) {
      border = Border(
          right: BorderSide(color: line),
          bottom: BorderSide(color: line),
          left: BorderSide(color: _lockColor(cell!.lockLevel), width: 3));
    }
    return InkWell(
      onTap: () => setState(() => _onCellTap(sheet, f, addr)),
      child: Container(
        width: _colWidth,
        height: _rowHeight,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: _alignOf(style?.align),
        decoration: BoxDecoration(
          color: _parseColor(style?.bg) ??
              (isSel
                  ? Dt.accent.withValues(alpha: 0.08)
                  : Colors.transparent),
          border: border,
        ),
        child: cell != null && cell.isCheckbox
            ? Checkbox(
                value: cell.isChecked,
                activeColor: Dt.accent,
                materialTapTargetSize:
                    MaterialTapTargetSize.shrinkWrap,
                onChanged: (_) =>
                    setState(() => _onCellTap(sheet, f, addr)),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (locked)
                    Padding(
                      padding: const EdgeInsets.only(right: 3),
                      child: Icon(LucideIcons.lock,
                          size: 10,
                          color: _lockColor(cell!.lockLevel)),
                    ),
                  Flexible(
                    child: Text(
                      display,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: (style?.bold ?? false)
                            ? FontWeight.w700
                            : FontWeight.w400,
                        fontStyle: (style?.italic ?? false)
                            ? FontStyle.italic
                            : FontStyle.normal,
                        decoration: (style?.underline ?? false)
                            ? TextDecoration.underline
                            : TextDecoration.none,
                        color: _parseColor(style?.color) ??
                            (display.startsWith('#')
                                ? AppColors.error
                                : null),
                        fontSize: style?.fontSize ?? 12.5,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Alignment _alignOf(String? a) {
    switch (a) {
      case 'center':
        return Alignment.center;
      case 'right':
        return Alignment.centerRight;
      default:
        return Alignment.centerLeft;
    }
  }

  Color _lockColor(LockLevel l) {
    switch (l) {
      case LockLevel.none:
        return Colors.transparent;
      case LockLevel.soft:
        return Colors.lightBlue;
      case LockLevel.protected:
        return Colors.amber;
      case LockLevel.vault:
        return Colors.orange;
      case LockLevel.permanent:
        return Colors.red;
    }
  }

  void _sheetMenu(SmartFile f, String action) {
    final sheets = f.sheets ?? [];
    if (action == 'add') {
      final n = sheets.length + 1;
      final s = SheetData(
          id: CubicDataController.newId('sh_'), name: 'Sheet$n');
      f.sheets = [...sheets, s];
      f.activeSheetId = s.id;
      _c.saveFile(f, detail: 'Added ${s.name}');
      setState(() {
        _selected = null;
      });
      _formulaCtrl.clear();
      return;
    }
    final sheet = _sheet;
    if (sheet == null) return;
    if (action == 'duplicate') {
      final copy = SheetData(
        id: CubicDataController.newId('sh_'),
        name: '${sheet.name} (Copy)',
        rows: sheet.rows,
        cols: sheet.cols,
        cells: {
          for (final e in sheet.cells.entries)
            e.key: CellData.fromJson(e.value.toJson())
        },
        frozenRows: sheet.frozenRows,
        frozenCols: sheet.frozenCols,
      );
      f.sheets = [...sheets, copy];
      f.activeSheetId = copy.id;
      _c.saveFile(f, detail: 'Duplicated ${sheet.name}');
      return;
    }
    if (action == 'delete') {
      if (sheets.length <= 1) {
        Get.snackbar('Keep one sheet',
            'A spreadsheet needs at least one sheet.',
            snackPosition: SnackPosition.BOTTOM);
        return;
      }
      Get.dialog(AlertDialog(
        title: Text('Delete ${sheet.name}?'),
        content: const Text('Cells in this sheet will be lost.'),
        actions: [
          TextButton(
              onPressed: () => Get.back(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              f.sheets = sheets.where((s) => s.id != sheet.id).toList();
              f.activeSheetId = f.sheets!.first.id;
              setState(() => _selected = null);
              _formulaCtrl.clear();
              _c.saveFile(f, detail: 'Deleted ${sheet.name}');
              Get.back();
            },
            child: const Text('Delete'),
          ),
        ],
      ));
    }
  }
}
