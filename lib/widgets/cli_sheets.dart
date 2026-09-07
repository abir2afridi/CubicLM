/// Bottom sheets for the terminal CLI manager: installed list, install
/// catalog, install/update/repair flow, CLI details, recent commands.
/// Mobile-first: one primary action per card, rest behind ⋮ / sheets.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/agent_controller.dart';
import '../core/colors.dart';
import '../services/runtime/cli_manager.dart';
import '../services/runtime/cli_manifest.dart';
import '../services/runtime/cli_providers.dart';
import '../theme/design_tokens.dart';
import '../utils/app_snackbar.dart';
import 'app_ui.dart';

Color _statusColor(CliStatus s) {
  switch (s) {
    case CliStatus.ready:
    case CliStatus.updateAvailable:
      return const Color(0xFF4ADE80);
    case CliStatus.installing:
    case CliStatus.verifying:
    case CliStatus.uninstalling:
      return Dt.accent;
    case CliStatus.authRequired:
      return const Color(0xFFFBBF24);
    case CliStatus.notInstalled:
      return const Color(0xFF6E6B65);
    case CliStatus.runtimeMissing:
    case CliStatus.binaryMissing:
    case CliStatus.broken:
    case CliStatus.error:
      return AppColors.error;
    case CliStatus.installed:
      return const Color(0xFF89DCEB);
  }
}

// ── Installed CLI Tools ──

/// Entry point from the terminal strip header.
void showCliManagerSheet(BuildContext context) {
  final c = Get.find<AgentController>();
  final mgr = Get.find<CliManagerService>();
  // Refresh statuses live whenever the sheet opens (never stale Ready).
  unawaited(mgr.verifyAll());
  showAppBottomSheet(
    context,
    builder: (sheetCtx) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AppSheetHeader(
              title: 'Installed CLI Tools',
              onClose: () => Navigator.pop(sheetCtx)),
          Flexible(
            child: Obx(() {
              final items = kCliCatalog;
              return ListView.separated(
                shrinkWrap: true,
                itemCount: items.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  if (i == items.length) {
                    return _storageFooter(sheetCtx, mgr);
                  }
                  return _cliRow(context, sheetCtx, c, mgr, items[i]);
                },
              );
            }),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Dt.accent),
              icon: const Icon(LucideIcons.plus, size: 18),
              label: const Text('Install CLI'),
              onPressed: () {
                Navigator.pop(sheetCtx);
                showCliCatalogSheet(context);
              },
            ),
          ),
        ]),
      ),
    ),
  );
}

Widget _cliRow(BuildContext context, BuildContext sheetCtx,
    AgentController c, CliManagerService mgr, CliManifest m) {
  final st = mgr.statusOf(m);
  final ver = mgr.versions[m.id] ?? '';
  final launchable = cliIsLaunchable(st);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: Theme.of(sheetCtx).cardColor,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
          color: Theme.of(sheetCtx).brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.07)
              : Dt.hairline),
    ),
    child: Row(children: [
      Container(
          width: 9,
          height: 9,
          decoration:
              BoxDecoration(shape: BoxShape.circle, color: _statusColor(st))),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(m.displayName,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              Text(
                  ver.isNotEmpty ? '$ver · ${cliStatusLabel(st)}' : cliStatusLabel(st),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      color: Theme.of(sheetCtx).hintColor)),
            ]),
      ),
      if (launchable)
        TextButton(
          onPressed: () {
            Navigator.pop(sheetCtx);
            c.openCli(m.id);
          },
          child: const Text('Open'),
        ),
      // Unhealthy states get an inline Fix shortcut (§13) — full
      // actions stay in the detail sheet to keep cards clean (§5).
      if (!launchable &&
          (st == CliStatus.runtimeMissing ||
              st == CliStatus.binaryMissing ||
              st == CliStatus.broken ||
              st == CliStatus.error))
        TextButton(
          onPressed: () {
            Navigator.pop(sheetCtx);
            showCliDetailSheet(context, m);
          },
          child: Text('Fix',
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700, color: AppColors.error)),
        ),
      IconButton(
        tooltip: 'More actions',
        icon: const Icon(LucideIcons.moreVertical, size: 18),
        onPressed: () {
          Navigator.pop(sheetCtx);
          showCliDetailSheet(context, m);
        },
      ),
    ]),
  );
}

Widget _storageFooter(BuildContext sheetCtx, CliManagerService mgr) {
  return FutureBuilder<CliStorageInfo>(
    future: mgr.storageInfo(),
    builder: (_, snap) {
      final info = snap.data;
      final txt = info == null
          ? 'CLI storage: …'
          : 'CLI storage: ${_fmtBytes(info.cliBytes)} · cache ${_fmtBytes(info.cacheBytes)}';
      return Row(children: [
        Expanded(
          child: Text(txt,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11.5,
                  color: Theme.of(sheetCtx).hintColor)),
        ),
        TextButton(
          onPressed: () async {
            final ok = await Get.dialog<bool>(AlertDialog(
              title: const Text('Clear npm cache?'),
              content: const Text(
                  'Only the download cache is removed. Installed CLIs and runtimes stay.'),
              actions: [
                TextButton(
                    onPressed: () => Get.back(result: false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Get.back(result: true),
                    child: const Text('Clear')),
              ],
            ));
            if (ok != true) return;
            try {
              final msg = await mgr.clearNpmCache();
              AppSnackbar.showTop('Storage', msg, logHistory: false);
            } catch (e) {
              AppSnackbar.showTop('Cache clear failed', '$e',
                  logHistory: false);
            }
          },
          child: const Text('Clear cache'),
        ),
      ]);
    },
  );
}

String _fmtBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
}

// ── Install catalog ──

void showCliCatalogSheet(BuildContext context) {
  final mgr = Get.find<CliManagerService>();
  showAppBottomSheet(
    context,
    builder: (sheetCtx) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AppSheetHeader(
              title: 'Install CLI',
              onClose: () => Navigator.pop(sheetCtx)),
          Flexible(
            child: Obx(() {
              final groups = <String, List<CliManifest>>{};
              for (final m in kCliCatalog) {
                if (m.provider != CliProviderKind.npm) continue;
                groups.putIfAbsent(m.category, () => []).add(m);
              }
              return ListView(
                shrinkWrap: true,
                children: [
                  for (final cat in groups.keys) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                      child: Text(cat,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Theme.of(sheetCtx).hintColor)),
                    ),
                    for (final m in groups[cat]!)
                      _catalogRow(context, sheetCtx, mgr, m),
                  ],
                ],
              );
            }),
          ),
        ]),
      ),
    ),
  );
}

Widget _catalogRow(BuildContext context, BuildContext sheetCtx,
    CliManagerService mgr, CliManifest m) {
  final registered = mgr.isRegistered(m.id);
  final installing = mgr.installingId.value == m.id;
  final st = mgr.statusOf(m);
  return Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: Theme.of(sheetCtx).cardColor,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
          color: Theme.of(sheetCtx).brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.07)
              : Dt.hairline),
    ),
    child: Row(children: [
      Expanded(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(m.displayName,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14, fontWeight: FontWeight.w700)),
          Text(m.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11.5,
                  color: Theme.of(sheetCtx).hintColor)),
          const SizedBox(height: 2),
          Text('Runtime: ${m.runtime}${m.minNodeMajor > 0 ? ' ${m.minNodeMajor}+' : ''}',
              style: GoogleFonts.firaCode(
                  fontSize: 10.5,
                  color: Theme.of(sheetCtx).hintColor)),
        ]),
      ),
      const SizedBox(width: 8),
      if (registered)
        Text(cliStatusLabel(st),
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _statusColor(st)))
      else if (installing)
        const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2))
      else
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: Dt.accent,
              visualDensity: VisualDensity.compact),
          onPressed: () {
            Navigator.pop(sheetCtx);
            showCliOpSheet(context, m,
                title: 'Install ${m.displayName}',
                runner: (onStep, onLog, isCancelled) async {
              await mgr.install(m,
                  onStep: onStep, onLog: onLog, isCancelled: isCancelled);
              return mgr.versions[m.id];
            });
          },
          child: const Text('Install'),
        ),
    ]),
  );
}

// ── Install / update / repair flow ──

typedef _OpRunner = Future<String?> Function(
    CliStepFn onStep, void Function(String) onLog, bool Function() isCancelled);

/// Operation sheet with REAL step progress (never faked): each step flips
/// to ✓/✗ only when the underlying operation actually finishes/fails.
void showCliOpSheet(BuildContext context, CliManifest m,
    {required String title, required _OpRunner runner}) {
  showAppBottomSheet(
    context,
    builder: (sheetCtx) => _CliOpSheet(
      manifest: m,
      title: title,
      runner: runner,
    ),
  );
}

class _CliOpSheet extends StatefulWidget {
  final CliManifest manifest;
  final String title;
  final _OpRunner runner;

  const _CliOpSheet(
      {required this.manifest, required this.title, required this.runner});

  @override
  State<_CliOpSheet> createState() => _CliOpSheetState();
}

class _Step {
  final String id;
  final String label;
  String state = 'wait'; // run | ok | fail | wait
  String detail = '';
  _Step(this.id, this.label);
}

class _CliOpSheetState extends State<_CliOpSheet> {
  final steps = <_Step>[
    _Step('check-device', 'Checking device'),
    _Step('check-runtime', 'Checking required runtime'),
    _Step('install-package', 'Installing package'),
    _Step('verify-binary', 'Verifying executable'),
    _Step('detect-version', 'Detecting version'),
  ];
  bool _cancelled = false;
  bool _done = false;
  bool _failed = false;
  String? _version;
  String _error = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  void _onStep(String id, String state, String detail) {
    if (!mounted) return;
    setState(() {
      for (final s in steps) {
        if (s.id == id) {
          s.state = state;
          s.detail = detail;
        }
      }
    });
  }

  Future<void> _run() async {
    final c = Get.find<AgentController>();
    try {
      final v = await widget.runner(
        _onStep,
        (line) => c.term('  $line'),
        () => _cancelled,
      );
      if (!mounted) return;
      setState(() {
        _done = true;
        _version = v;
      });
      c.term('✓ ${widget.manifest.displayName} ready${v?.isNotEmpty == true ? ' ($v)' : ''}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _error = '$e';
      });
      Get.find<AgentController>()
          .term('✗ ${widget.manifest.displayName}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = !_done && !_failed;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AppSheetHeader(
              title: widget.title,
              onClose: () => Navigator.pop(context)),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final s in steps)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      SizedBox(
                        width: 20,
                        child: s.state == 'run'
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                            : Text(
                                s.state == 'ok'
                                    ? '✓'
                                    : s.state == 'fail'
                                        ? '✗'
                                        : '·',
                                style: GoogleFonts.firaCode(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: s.state == 'ok'
                                        ? const Color(0xFF4ADE80)
                                        : s.state == 'fail'
                                            ? AppColors.error
                                            : Theme.of(context)
                                                .hintColor),
                              ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(s.label,
                                  style:
                                      GoogleFonts.plusJakartaSans(
                                          fontSize: 13.5,
                                          fontWeight:
                                              FontWeight.w600)),
                              if (s.detail.isNotEmpty)
                                Text(s.detail,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.firaCode(
                                        fontSize: 10.5,
                                        color: Theme.of(context)
                                            .hintColor)),
                            ]),
                      ),
                    ]),
                  ),
                if (_failed) ...[
                  const SizedBox(height: 8),
                  Text(_error,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5, color: AppColors.error)),
                ],
                if (_done && _version?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text('Version detected: $_version',
                      style: GoogleFonts.firaCode(
                          fontSize: 12,
                          color: const Color(0xFF4ADE80))),
                ],
                if (_done && widget.manifest.authNote.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(widget.manifest.authNote,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5,
                          color: Theme.of(context).hintColor)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (running)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => setState(() => _cancelled = true),
                child: const Text('Cancel'),
              ),
            )
          else if (_done)
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: Dt.accent),
                  onPressed: () {
                    Navigator.pop(context);
                    Get.find<AgentController>()
                        .openCli(widget.manifest.id);
                  },
                  child: Text('Open ${widget.manifest.displayName}'),
                ),
              ),
            ])
          else
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () => setState(() {
                    _failed = false;
                    _cancelled = false;
                    for (final s in steps) {
                      s.state = 'wait';
                      s.detail = '';
                    }
                    _run();
                  }),
                  child: const Text('Retry'),
                ),
              ),
            ]),
        ]),
      ),
    );
  }
}

// ── CLI details ──

void showCliDetailSheet(BuildContext context, CliManifest m) {
  final c = Get.find<AgentController>();
  final mgr = Get.find<CliManagerService>();
  showAppBottomSheet(
    context,
    builder: (sheetCtx) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AppSheetHeader(
              title: m.displayName,
              onClose: () => Navigator.pop(sheetCtx)),
          Flexible(
            child: Obx(() {
              final st = mgr.statusOf(m);
              final ver = mgr.versions[m.id] ?? '';
              final latest = mgr.latestVersions[m.id] ?? '';
              final entry = mgr.installed
                  .firstWhereOrNull((e) => e.manifestId == m.id);
              return ListView(shrinkWrap: true, children: [
                _detailRow('Version', ver.isEmpty ? '—' : ver),
                if (latest.isNotEmpty && latest != ver)
                  _detailRow('Latest', latest,
                      color: const Color(0xFF4ADE80)),
                _detailRow('Status', cliStatusLabel(st),
                    color: _statusColor(st)),
                _detailRow('Runtime', m.runtime),
                _detailRow(
                    'Location',
                    entry == null
                        ? (m.provider == CliProviderKind.system
                            ? 'System'
                            : '—')
                        : 'Managed by CubicLM'),
                if (entry != null)
                  _detailRow('Installed', _fmtDate(entry.installedAtMs)),
                if (m.platformNote.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(m.platformNote,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12.5,
                            color: Theme.of(sheetCtx).hintColor)),
                  ),
                if (m.authNote.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(m.authNote,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12.5,
                            color: Theme.of(sheetCtx).hintColor)),
                  ),
                const SizedBox(height: 12),
                if (cliIsLaunchable(st))
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: Dt.accent),
                      onPressed: () {
                        Navigator.pop(sheetCtx);
                        c.openCli(m.id);
                      },
                      child: const Text('Open'),
                    ),
                  ),
                const SizedBox(height: 8),
                _detailAction(
                  icon: LucideIcons.checkCircle2,
                  label: 'Verify installation',
                  busy: mgr.busyIds.contains(m.id),
                  onTap: () async {
                    final s = await mgr.verify(m);
                    AppSnackbar.showTop(m.displayName,
                        'Status: ${cliStatusLabel(s)}',
                        logHistory: false);
                  },
                ),
                if (m.provider == CliProviderKind.npm &&
                    mgr.isRegistered(m.id)) ...[
                  _detailAction(
                    icon: LucideIcons.arrowUpCircle,
                    label: 'Update to latest',
                    busy: mgr.busyIds.contains(m.id),
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      showCliOpSheet(context, m,
                          title: 'Update ${m.displayName}',
                          runner: (onStep, onLog, isCancelled) async {
                        await mgr.update(m,
                            onStep: onStep,
                            onLog: onLog,
                            isCancelled: isCancelled);
                        return mgr.versions[m.id];
                      });
                    },
                  ),
                  _detailAction(
                    icon: LucideIcons.wrench,
                    label: 'Repair installation',
                    busy: mgr.busyIds.contains(m.id),
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      showCliOpSheet(context, m,
                          title: 'Repair ${m.displayName}',
                          runner: (onStep, onLog, isCancelled) async {
                        await mgr.repair(m,
                            onStep: onStep,
                            onLog: onLog,
                            isCancelled: isCancelled);
                        return mgr.versions[m.id];
                      });
                    },
                  ),
                  _detailAction(
                    icon: LucideIcons.trash2,
                    label: 'Uninstall',
                    destructive: true,
                    busy: mgr.busyIds.contains(m.id),
                    onTap: () async {
                      final ok = await Get.dialog<bool>(AlertDialog(
                        title: Text('Uninstall ${m.displayName}?'),
                        content: const Text(
                            'This removes the CLI and its managed installation files.\n\nYour project files will NOT be deleted.'),
                        actions: [
                          TextButton(
                              onPressed: () =>
                                  Get.back(result: false),
                              child: const Text('Cancel')),
                          FilledButton(
                            style: FilledButton.styleFrom(
                                backgroundColor: AppColors.error),
                            onPressed: () =>
                                Get.back(result: true),
                            child: const Text('Uninstall'),
                          ),
                        ],
                      ));
                      if (ok != true || !sheetCtx.mounted) return;
                      Navigator.pop(sheetCtx);
                      try {
                        await mgr.uninstall(m);
                        AppSnackbar.showTop(
                            '✓ ${m.displayName} removed', '',
                            logHistory: false);
                      } catch (e) {
                        AppSnackbar.showTop(
                            'Uninstall failed', '$e',
                            logHistory: false);
                      }
                    },
                  ),
                ],
              ]);
            }),
          ),
        ]),
      ),
    ),
  );
}

Widget _detailRow(String k, String v, {Color? color}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      SizedBox(
        width: 90,
        child: Text(k,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5, color: Dt.textSecondary)),
      ),
      Expanded(
        child: Text(v,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: color)),
      ),
    ]),
  );
}

Widget _detailAction({
  required IconData icon,
  required String label,
  required VoidCallback onTap,
  bool busy = false,
  bool destructive = false,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(children: [
            Icon(icon,
                size: 20,
                color: destructive ? AppColors.error : Dt.textPrimary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: destructive ? AppColors.error : null)),
            ),
            if (busy)
              const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
        ),
      ),
    ),
  );
}

String _fmtDate(int ms) {
  if (ms <= 0) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

// ── Recent commands ──

void showRecentCommandsSheet(
    BuildContext context, void Function(String cmd) onPick) {
  final mgr = Get.find<CliManagerService>();
  showAppBottomSheet(
    context,
    builder: (sheetCtx) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AppSheetHeader(
              title: 'Recent commands',
              onClose: () => Navigator.pop(sheetCtx)),
          Flexible(
            child: Obx(() => mgr.recentCommands.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('No commands yet.',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color:
                                Theme.of(sheetCtx).hintColor)),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: mgr.recentCommands.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 4),
                    itemBuilder: (_, i) {
                      final cmd = mgr.recentCommands[i];
                      return ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(10)),
                        title: Text(cmd,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.firaCode(
                                fontSize: 12.5)),
                        trailing: const Icon(
                            LucideIcons.cornerUpLeft,
                            size: 16),
                        onTap: () {
                          Navigator.pop(sheetCtx);
                          onPick(cmd);
                        },
                      );
                    },
                  )),
          ),
        ]),
      ),
    ),
  );
}

// ── Terminal-detected CLI ──

void showCliDetectedDialog(CliManifest m, String version) {
  final mgr = Get.find<CliManagerService>();
  Get.dialog(AlertDialog(
    title: const Text('New CLI detected'),
    content: Text(
        '${m.displayName}${version.isNotEmpty ? ' $version' : ''} is now available from the terminal.\n\nAdd to Installed CLI Tools?'),
    actions: [
      TextButton(
          onPressed: () => Get.back(), child: const Text('Ignore')),
      FilledButton(
        onPressed: () async {
          Get.back();
          await mgr.registerDetected();
          AppSnackbar.showTop(
              '✓ ${m.displayName} added', 'Status: Ready',
              logHistory: false);
        },
        child: const Text('Add'),
      ),
    ],
  ));
}
