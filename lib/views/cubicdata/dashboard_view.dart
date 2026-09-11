/// CubicDataSheet dashboard: vault counts, lock-level stats, audit
/// trail, clipboard cache with re-copy, and frequently accessed files.
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
import 'doc_view.dart';
import 'hybrid_view.dart';
import 'sheet_view.dart';

class DataSheetDashboardView extends StatelessWidget {
  const DataSheetDashboardView({super.key});

  CubicDataController get _c => datasheetController();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? Dt.canvasDark : Dt.canvas,
      appBar: AppBar(
        title: Text('Dashboard',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800, fontSize: 19)),
      ),
      body: Obx(() {
        var sheets = 0;
        var docs = 0;
        var hybrids = 0;
        final locks = <LockLevel, int>{
          LockLevel.soft: 0,
          LockLevel.protected: 0,
          LockLevel.vault: 0,
          LockLevel.permanent: 0,
        };
        for (final f in _c.files) {
          switch (f.type) {
            case WorkspaceType.spreadsheet:
              sheets++;
              for (final s in f.sheets ?? const <SheetData>[]) {
                for (final cell in s.cells.values) {
                  if (cell.locked) {
                    locks[cell.lockLevel] =
                        (locks[cell.lockLevel] ?? 0) + 1;
                  }
                }
              }
              break;
            case WorkspaceType.document:
              docs++;
              break;
            case WorkspaceType.hybrid:
              hybrids++;
              break;
          }
        }
        final lockedTotal = locks.values.fold(0, (a, b) => a + b);
        final recent = _c.files.toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Row(children: [
              _countCard(context, isDark, '$sheets', 'Sheets',
                  LucideIcons.tableProperties, const Color(0xFF10B981)),
              const SizedBox(width: 10),
              _countCard(context, isDark, '$docs', 'Docs',
                  LucideIcons.fileText, Colors.cyan),
              const SizedBox(width: 10),
              _countCard(context, isDark, '$hybrids', 'Hybrid',
                  LucideIcons.layoutGrid, Colors.orange),
              const SizedBox(width: 10),
              _countCard(context, isDark, '$lockedTotal', 'Locked',
                  LucideIcons.lock, Colors.amber),
            ]),
            const SizedBox(height: 16),
            _sectionTitle(context, 'Lock levels'),
            const SizedBox(height: 8),
            _card(
              context,
              isDark,
              Column(children: [
                _lockBar(context, 'Soft', locks[LockLevel.soft] ?? 0,
                    lockedTotal, Colors.lightBlue),
                _lockBar(context, 'Protected',
                    locks[LockLevel.protected] ?? 0, lockedTotal, Colors.amber),
                _lockBar(context, 'Vault',
                    locks[LockLevel.vault] ?? 0, lockedTotal, Colors.orange),
                _lockBar(context, 'Permanent',
                    locks[LockLevel.permanent] ?? 0, lockedTotal, Colors.red),
                if (lockedTotal == 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text('No locked cells yet.',
                        style: TextStyle(fontSize: 12)),
                  ),
              ]),
            ),
            const SizedBox(height: 16),
            _sectionTitle(context, 'Frequently accessed'),
            const SizedBox(height: 8),
            if (recent.isEmpty)
              _card(context, isDark,
                  const Text('Nothing here yet.', style: TextStyle(fontSize: 12)))
            else
              for (final f in recent.take(3))
                _card(
                  context,
                  isDark,
                  InkWell(
                    onTap: () => _openFile(f),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        Expanded(
                          child: Text(f.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13)),
                        ),
                        const Icon(LucideIcons.chevronRight,
                            size: 15, color: Colors.grey),
                      ]),
                    ),
                  ),
                ),
            const SizedBox(height: 16),
            _sectionTitle(context, 'Clipboard cache'),
            const SizedBox(height: 8),
            if (_c.clipboard.isEmpty)
              _card(context, isDark,
                  const Text('Nothing copied yet.', style: TextStyle(fontSize: 12)))
            else
              for (final cp in _c.clipboard.take(5))
                _card(
                  context,
                  isDark,
                  Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(cp.type,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Theme.of(context).hintColor)),
                          Text(cp.content,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await Clipboard.setData(
                            ClipboardData(text: cp.content));
                        Get.snackbar('Re-copied', cp.type,
                            snackPosition: SnackPosition.BOTTOM,
                            duration: const Duration(seconds: 2));
                      },
                      child: const Text('Re-copy'),
                    ),
                  ]),
                ),
            const SizedBox(height: 16),
            _sectionTitle(context, 'Audit trail'),
            const SizedBox(height: 8),
            if (_c.activity.isEmpty)
              _card(context, isDark,
                  const Text('No activity yet.', style: TextStyle(fontSize: 12)))
            else
              for (final a in _c.activity.take(15))
                _card(
                  context,
                  isDark,
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _activityColor(a.type)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(a.type,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: _activityColor(a.type))),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(a.details,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ]),
                ),
          ],
        );
      }),
    );
  }

  void _openFile(SmartFile f) {
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

  Color _activityColor(String type) {
    switch (type) {
      case 'delete':
        return Colors.red;
      case 'lock':
        return Colors.amber;
      case 'unlock':
        return const Color(0xFF10B981);
      case 'copy':
      case 'paste':
        return Colors.blueAccent;
      case 'restore':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Text(title,
        style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: Theme.of(context).hintColor));
  }

  Widget _card(BuildContext context, bool isDark, Widget child) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
            color: isDark ? Colors.white10 : Dt.hairline),
      ),
      child: child,
    );
  }

  Widget _countCard(BuildContext context, bool isDark, String value,
      String label, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
              color: isDark ? Colors.white10 : Dt.hairline),
        ),
        child: Column(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 6),
          Text(value,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 17, fontWeight: FontWeight.w800)),
          Text(label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 10, color: Theme.of(context).hintColor)),
        ]),
      ),
    );
  }

  Widget _lockBar(BuildContext context, String label, int count, int total,
      Color color) {
    final pct = total <= 0 ? 0.0 : (count / total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
          width: 80,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: 7,
              color: Theme.of(context)
                  .hintColor
                  .withValues(alpha: 0.15),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: pct,
                child: Container(color: color),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 30,
          child: Text('$count',
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}
