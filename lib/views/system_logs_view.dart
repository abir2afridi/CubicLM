/// CubicWeb System Logs — developer diagnostics console (§19).
///
/// Lists structured RUNTIME/PLATFORM events (never user-code errors —
/// those stay on the AI path). Severity filters, text search, detail
/// sheets with evidence + contextual actions, clear-all.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/agent_controller.dart';
import '../core/colors.dart';
import '../services/cubicweb/cubicweb_event.dart';
import '../services/cubicweb/cubicweb_logger.dart';
import '../theme/design_tokens.dart';
import '../utils/app_snackbar.dart';

class SystemLogsView extends StatefulWidget {
  const SystemLogsView({super.key});

  @override
  State<SystemLogsView> createState() => _SystemLogsViewState();
}

class _SystemLogsViewState extends State<SystemLogsView> {
  CwSeverity? _sevFilter;
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    try {
      Get.find<CubicWebLogger>().markAllRead();
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    CubicWebLogger logger;
    try {
      logger = Get.find<CubicWebLogger>();
    } catch (_) {
      return Scaffold(
        appBar: AppBar(title: const Text('CubicWeb System Logs')),
        body: const Center(child: Text('Logger unavailable.')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('CubicWeb System Logs',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800)),
            Obx(() {
              final n = logger.events.length;
              return Text(
                  n == 0
                      ? 'No system events'
                      : '$n event${n == 1 ? '' : 's'} (newest first)',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).hintColor));
            }),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Clear logs',
            icon: const Icon(LucideIcons.trash2, size: 20),
            onPressed: () async {
              final ok = await Get.dialog<bool>(AlertDialog(
                title: const Text('Clear System Logs?'),
                content: const Text(
                    'Removes all stored diagnostics (in-memory + persisted).'),
                actions: [
                  TextButton(
                      onPressed: () => Get.back(result: false),
                      child: const Text('Cancel')),
                  FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.error),
                    onPressed: () => Get.back(result: true),
                    child: const Text('Clear'),
                  ),
                ],
              ));
              if (ok == true) {
                await logger.clear();
                if (context.mounted) setState(() {});
              }
            },
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(children: [
            _filterChip(context, 'All', null),
            const SizedBox(width: 6),
            _filterChip(context, 'Errors', CwSeverity.error),
            const SizedBox(width: 6),
            _filterChip(context, 'Warnings', CwSeverity.warning),
            const SizedBox(width: 6),
            _filterChip(context, 'Info', CwSeverity.info),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            style: GoogleFonts.plusJakartaSans(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search code, message, project, command…',
              hintStyle: GoogleFonts.plusJakartaSans(fontSize: 13),
              prefixIcon:
                  const Icon(LucideIcons.search, size: 18),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(LucideIcons.x, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    ),
              isDense: true,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
            ),
          ),
        ),
        Expanded(
          child: Obx(() {
            final items = logger.events.reversed.where((e) {
              if (_sevFilter != null && e.severity != _sevFilter) {
                return false;
              }
              final q = _query.trim().toLowerCase();
              if (q.isEmpty) return true;
              return e.errorCode.toLowerCase().contains(q) ||
                  e.title.toLowerCase().contains(q) ||
                  e.message.toLowerCase().contains(q) ||
                  e.projectId.toLowerCase().contains(q) ||
                  e.component.toLowerCase().contains(q) ||
                  e.command.toLowerCase().contains(q) ||
                  e.traceId.toLowerCase().contains(q);
            }).toList();
            if (items.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    logger.events.isEmpty
                        ? 'No system events yet.\nRuntime and platform failures will appear here — code errors stay with the AI debugger.'
                        : 'No events match this filter.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        height: 1.5,
                        color: Theme.of(context).hintColor),
                  ),
                ),
              );
            }
            return ListView.builder(
              padding:
                  const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: items.length,
              itemBuilder: (_, i) =>
                  _eventCard(context, isDark, items[i]),
            );
          }),
        ),
      ]),
    );
  }

  Widget _filterChip(
      BuildContext context, String label, CwSeverity? sev) {
    final selected = _sevFilter == sev;
    return InkWell(
      onTap: () => setState(() => _sevFilter = sev),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? Dt.accent.withValues(alpha: 0.15)
              : (Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.05)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected
                  ? Dt.accent.withValues(alpha: 0.4)
                  : Colors.transparent),
        ),
        child: Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: selected
                    ? Dt.accent
                    : Theme.of(context).hintColor)),
      ),
    );
  }

  Widget _eventCard(
      BuildContext context, bool isDark, SystemLogEvent e) {
    final dot = e.severity == CwSeverity.error
        ? AppColors.error
        : e.severity == CwSeverity.warning
            ? const Color(0xFFFBBF24)
            : const Color(0xFF4ADE80);
    return GestureDetector(
      onTap: () => _showDetail(context, e),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surface : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : Dt.hairline),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: dot)),
                const SizedBox(width: 6),
                if (e.errorCode.isNotEmpty)
                  Text(e.errorCode,
                      style: GoogleFonts.firaCode(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: dot)),
                if (e.errorCode.isNotEmpty)
                  const SizedBox(width: 6),
                Expanded(
                  child: Text(e.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w800)),
                ),
                if (e.occurrenceCount > 1)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: dot.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('×${e.occurrenceCount}',
                        style: GoogleFonts.firaCode(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: dot)),
                  ),
              ]),
              const SizedBox(height: 4),
              Text(
                  '${e.component} · ${e.category.name.toUpperCase()} · ${_fmtTime(e.lastAtMs)}',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 10.5,
                      color: Theme.of(context).hintColor)),
              const SizedBox(height: 4),
              Text(e.message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, height: 1.4)),
              if (!e.aiCanFix) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text("AI can't fix — environment issue",
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.error)),
                ),
              ],
            ]),
      ),
    );
  }

  String _fmtTime(int ms) {
    if (ms <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final t = '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
    if (d.year == now.year &&
        d.month == now.month &&
        d.day == now.day) {
      return t;
    }
    return '$t · ${d.month}/${d.day}';
  }

  void _showDetail(BuildContext context, SystemLogEvent e) {
    final c = Get.isRegistered<AgentController>()
        ? Get.find<AgentController>()
        : null;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, scrollCtrl) => ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(sheetCtx)
                        .hintColor
                        .withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(e.title,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              _kv('Error code', e.errorCode.isEmpty ? '—' : e.errorCode, mono: true),
              _kv('Severity', e.severity.name.toUpperCase()),
              _kv('Category', e.category.name.toUpperCase()),
              _kv('Component', e.component),
              _kv('Time', _fmtTime(e.timestampMs)),
              _kv('Trace ID', e.traceId, mono: true),
              if (e.projectId.isNotEmpty)
                _kv('Project', e.projectId, mono: true),
              if (e.operation.isNotEmpty)
                _kv('Operation', e.operation, mono: true),
              if (e.command.isNotEmpty)
                _kv('Command', e.command, mono: true),
              if (e.exitCode != null)
                _kv('Exit code', '${e.exitCode}'),
              if (e.platform.isNotEmpty)
                _kv('Platform', e.platform, mono: true),
              if (e.runtime.isNotEmpty)
                _kv('Runtime', e.runtime, mono: true),
              _kv('AI can fix',
                  e.aiCanFix ? 'Yes — route to AI debugger' : 'No — environment issue'),
              if (e.fallbackAvailable.isNotEmpty)
                _kv('Fallback', e.fallbackAvailable, mono: true),
              if (e.fallbackUsed.isNotEmpty)
                _kv('Fallback used', e.fallbackUsed, mono: true),
              if (e.occurrenceCount > 1)
                _kv('Occurrences',
                    '×${e.occurrenceCount} (first ${_fmtTime(e.firstAtMs)}, last ${_fmtTime(e.lastAtMs)})'),
              const SizedBox(height: 8),
              Text(e.message,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, height: 1.5)),
              if (e.technicalDetails.isNotEmpty) ...[
                const SizedBox(height: 12),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('Technical details',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF101014),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(e.technicalDetails,
                          style: GoogleFonts.firaCode(
                              fontSize: 10.5,
                              height: 1.5,
                              color:
                                  const Color(0xFFCDD6F4))),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.tonalIcon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(
                        text:
                            '${e.errorCode.isEmpty ? e.title : '${e.errorCode} — ${e.title}'}\n${e.message}'));
                    Get.back();
                    AppSnackbar.showTop(
                        'Copied', 'Error summary copied.',
                        logHistory: false);
                  },
                  icon: const Icon(LucideIcons.copy, size: 16),
                  label: const Text('Copy Error'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(
                        ClipboardData(text: _fullExport(e)));
                    Get.back();
                    AppSnackbar.showTop(
                        'Copied', 'Full details copied.',
                        logHistory: false);
                  },
                  icon:
                      const Icon(LucideIcons.clipboardList, size: 16),
                  label: const Text('Copy Details'),
                ),
                if (e.fallbackAvailable == 'USE_CLOUD_RUNTIME' &&
                    c != null)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: Dt.accent),
                    onPressed: () {
                      Get.back();
                      c.useCloudFallback();
                    },
                    icon: const Icon(LucideIcons.cloud, size: 16),
                    label: const Text('Use Cloud'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => Get.back(),
                  icon:
                      const Icon(LucideIcons.terminal, size: 16),
                  label: const Text('Back to Terminal'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v, {bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 110,
          child: Text(k,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: Dt.textSecondary)),
        ),
        Expanded(
          child: SelectableText(v,
              style: mono
                  ? GoogleFonts.firaCode(fontSize: 12)
                  : GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  String _fullExport(SystemLogEvent e) {
    final b = StringBuffer()
      ..writeln('${e.errorCode.isEmpty ? '' : '${e.errorCode} — '}${e.title}')
      ..writeln(
          'Severity: ${e.severity.name} · Category: ${e.category.name} · Component: ${e.component}')
      ..writeln('Trace: ${e.traceId} · Occurrences: ${e.occurrenceCount}')
      ..writeln(e.message);
    if (e.command.isNotEmpty) b.writeln('Command: ${e.command}');
    if (e.exitCode != null) b.writeln('Exit: ${e.exitCode}');
    if (e.technicalDetails.isNotEmpty) {
      b.writeln('--- evidence ---');
      b.writeln(e.technicalDetails);
    }
    return b.toString();
  }
}
