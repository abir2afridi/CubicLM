import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/battle_arena_controller.dart';
import '../core/colors.dart';
import '../theme/design_tokens.dart';

/// Battle Arena: race up to 4 cloud models on one prompt with a live
/// monitor (finish order, speed, information) and an overall verdict.
class BattleArenaView extends StatefulWidget {
  const BattleArenaView({super.key});

  @override
  State<BattleArenaView> createState() => _BattleArenaViewState();
}

class _BattleArenaViewState extends State<BattleArenaView> {
  late final BattleArenaController c;
  final _promptCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    c = Get.isRegistered<BattleArenaController>()
        ? Get.find<BattleArenaController>()
        : Get.put(BattleArenaController());
    _promptCtrl.text = c.prompt.value;
  }

  @override
  void dispose() {
    _promptCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text('Battle Arena',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
      ),
      body: Obx(() {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _contendersCard(context, isDark),
            const SizedBox(height: 12),
            _promptCard(context, isDark),
            if (c.entries.isNotEmpty) ...[
              const SizedBox(height: 12),
              _monitorCard(context, isDark),
            ],
            if (c.verdict.value != null) ...[
              const SizedBox(height: 12),
              _verdictCard(context, isDark),
            ],
            if (c.entries.isNotEmpty) ...[
              const SizedBox(height: 12),
              _responsesHeader(context),
              for (final e in c.entries) _responseTile(context, isDark, e),
            ],
          ],
        );
      }),
    );
  }

  // ── Contenders ──

  Widget _contendersCard(BuildContext context, bool isDark) {
    return _card(isDark, [
      Row(children: [
        const Icon(LucideIcons.swords, size: 18, color: Dt.accent),
        const SizedBox(width: 10),
        Expanded(
          child: Text('Contenders (${c.picks.length}/${BattleArenaController.maxContenders})',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 15, fontWeight: FontWeight.w800)),
        ),
        TextButton.icon(
          onPressed:
              c.running.value ? null : () => _showPicker(context, isDark),
          icon: const Icon(LucideIcons.plus, size: 16),
          label: const Text('Add models'),
        ),
      ]),
      if (c.picks.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Pick up to ${BattleArenaController.maxContenders} cloud models — same or different providers. Only providers with a saved API key are listed.',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5, color: Theme.of(context).hintColor, height: 1.4),
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in c.picks)
                Chip(
                  label: Text(p.label,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  onDeleted: c.running.value
                      ? null
                      : () => c.togglePick(p.provider, p.model),
                ),
            ],
          ),
        ),
    ]);
  }

  void _showPicker(BuildContext context, bool isDark) {
    final groups = c.pickableModels();
    final query = ValueNotifier('');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.surface : Colors.white,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(children: [
                Expanded(
                  child: Text('Pick fighters',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 17, fontWeight: FontWeight.w800)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(sheetCtx),
                  child: const Text('Done'),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search models…',
                  isDense: true,
                  prefixIcon: Icon(LucideIcons.search, size: 18),
                ),
                onChanged: (v) => query.value = v.trim().toLowerCase(),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: groups.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No configured provider has models yet.\nAdd an API key in Explore → Online first.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              color: Theme.of(context).hintColor,
                              height: 1.5),
                        ),
                      ),
                    )
                  : ValueListenableBuilder<String>(
                      valueListenable: query,
                      builder: (_, q, __) => ListView(
                        controller: scrollCtrl,
                        padding:
                            const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        children: [
                          if (c.loadedLocalName.isNotEmpty &&
                              (q.isEmpty ||
                                  'on-device'
                                      .contains(q) ||
                                  c.loadedLocalName
                                      .toLowerCase()
                                      .contains(q))) ...[
                            Padding(
                              padding: const EdgeInsets.only(
                                  top: 12, bottom: 4),
                              child: Text('ON-DEVICE (SEQUENTIAL ONLY)',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.6)),
                            ),
                            Obx(() => CheckboxListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(c.loadedLocalName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          GoogleFonts.plusJakartaSans(
                                              fontSize: 13)),
                                  value: c.isPicked(
                                      'local', c.loadedLocalName),
                                  activeColor: Dt.accent,
                                  onChanged: c.running.value
                                      ? null
                                      : (_) => c.togglePick(
                                          'local', c.loadedLocalName),
                                )),
                          ],
                          for (final pid in groups.keys)
                            ..._pickerGroup(
                                sheetCtx, pid, groups[pid]!, q),
                        ],
                      ),
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  List<Widget> _pickerGroup(
      BuildContext sheetCtx, String providerId, List<String> models, String q) {
    final name = c.providerName(providerId);
    final filtered = q.isEmpty
        ? models
        : models
            .where((m) =>
                m.toLowerCase().contains(q) ||
                name.toLowerCase().contains(q))
            .toList();
    if (filtered.isEmpty) return [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(name,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6)),
      ),
      for (final m in filtered.take(60))
        Obx(() => CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(m,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(fontSize: 13)),
              value: c.isPicked(providerId, m),
              activeColor: Dt.accent,
              onChanged: c.running.value
                  ? null
                  : (_) => c.togglePick(providerId, m),
            )),
    ];
  }

  // ── Prompt + fight ──

  Widget _promptCard(BuildContext context, bool isDark) {
    return _card(isDark, [
      TextField(
        controller: _promptCtrl,
        enabled: !c.running.value,
        maxLines: 4,
        minLines: 2,
        onChanged: (v) => c.prompt.value = v,
        style: GoogleFonts.plusJakartaSans(fontSize: 14, height: 1.45),
        decoration: InputDecoration(
          hintText: 'One prompt for every contender…',
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.all(12),
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'parallel',
              icon: Icon(LucideIcons.zap, size: 15),
              label: Text('Same-time'),
            ),
            ButtonSegment(
              value: 'sequential',
              icon: Icon(LucideIcons.listOrdered, size: 15),
              label: Text('One-by-one'),
            ),
          ],
          selected: {c.mode.value},
          onSelectionChanged:
              c.running.value ? null : (s) => c.setMode(s.first),
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.compact,
          ),
        ),
      ),
      if (c.mode.value == 'sequential')
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Runs in pick order — each starts instantly when the previous finishes. On-device contender allowed.',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11.5, color: Theme.of(context).hintColor),
          ),
        ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: c.running.value
            ? OutlinedButton.icon(
                onPressed: c.stop,
                icon: const Icon(LucideIcons.square, size: 16),
                label: const Text('Stop battle'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: BorderSide(
                      color: AppColors.error.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              )
            : FilledButton.icon(
                onPressed: c.canFight ? c.fight : null,
                icon: const Icon(LucideIcons.swords, size: 18),
                label: const Text('FIGHT'),
                style: FilledButton.styleFrom(
                  backgroundColor: Dt.accent,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
      ),
    ]);
  }

  // ── Monitor ──

  Widget _monitorCard(BuildContext context, bool isDark) {
    return _card(isDark, [
      Row(children: [
        const Icon(LucideIcons.activity, size: 18, color: Dt.accent),
        const SizedBox(width: 10),
        Text('Monitor',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 15, fontWeight: FontWeight.w800)),
        const Spacer(),
        if (c.running.value)
          Text('LIVE',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.error)),
      ]),
      const SizedBox(height: 8),
      for (final e in c.entries) _monitorRow(context, e),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          c.mode.value == 'sequential'
              ? 'One-by-one: finish order = run order; speed + length decide.'
              : 'Finish 40% · speed 30% · length 30%. Speed ≈ output ÷ time.',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 11, color: Theme.of(context).hintColor),
        ),
      ),
    ]);
  }

  Widget _monitorRow(BuildContext context, BattleEntry e) {
    return Obx(() {
      final place = c.placeOf(e.pick.id);
      final medal = place == 1
          ? '🥇'
          : place == 2
              ? '🥈'
              : place == 3
                  ? '🥉'
                  : '';
      final st = e.status.value;
      final secs = (e.elapsedMs.value / 1000).toStringAsFixed(1);
      final detail = st == 'error'
          ? (e.error ?? 'error')
          : st == 'running'
              ? '$secs s · ${e.tokensPerSec.toStringAsFixed(1)} tok/s · ${e.chars} chars'
              : '$secs s · ${e.tokensPerSec.toStringAsFixed(1)} tok/s · ${e.chars} chars';
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(children: [
          SizedBox(
            width: 26,
            child: st == 'running'
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(medal,
                    style: const TextStyle(fontSize: 16)),
          ),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.pick.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  Text(detail,
                      maxLines: st == 'error' ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5,
                          color: st == 'error'
                              ? AppColors.error
                              : Theme.of(context).hintColor)),
                ]),
          ),
        ]),
      );
    });
  }

  // ── Verdict ──

  Widget _verdictCard(BuildContext context, bool isDark) {
    final v = c.verdict.value!;
    final winnerId = v.winnerId;
    final winner = c.entries.firstWhere((e) => e.pick.id == winnerId,
        orElse: () => c.entries.first);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Dt.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Dt.accent.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(LucideIcons.trophy, size: 20, color: Dt.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Overall best: ${winner.pick.label}',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 15, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 10),
        for (final id in v.order)
          Builder(builder: (_) {
            final row = v.rows[id]!;
            final entry = c.entries.firstWhere((e) => e.pick.id == id,
                orElse: () => c.entries.first);
            final secs =
                ((entry.doneMs ?? entry.elapsedMs.value) / 1000)
                    .toStringAsFixed(1);
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '#${v.order.indexOf(id) + 1} ${entry.pick.label} — '
                'finish #${row.finishRank}, speed #${row.speedRank} '
                '(${entry.tokensPerSec.toStringAsFixed(1)} tok/s), '
                'length #${row.lengthRank} (${entry.chars} chars, ${secs}s)',
                style: GoogleFonts.plusJakartaSans(fontSize: 12, height: 1.45),
              ),
            );
          }),
      ]),
    );
  }

  // ── Responses ──

  Widget _responsesHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Text('RESPONSES',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: Theme.of(context).hintColor)),
    );
  }

  Widget _responseTile(
      BuildContext context, bool isDark, BattleEntry e) {
    return Obx(() => Card(
          child: ExpansionTile(
            title: Text(e.pick.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, fontWeight: FontWeight.w700)),
            subtitle: Text(
              e.status.value == 'running'
                  ? 'writing… ${e.chars} chars'
                  : e.status.value,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: e.status.value == 'error'
                      ? AppColors.error
                      : Theme.of(context).hintColor),
            ),
            trailing: IconButton(
              tooltip: 'Copy response',
              icon: const Icon(LucideIcons.copy, size: 16),
              onPressed: e.text.value.isEmpty
                  ? null
                  : () => Clipboard.setData(
                      ClipboardData(text: e.text.value)),
            ),
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E1E2E)
                      : const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  e.text.value.isEmpty ? '(no output)' : e.text.value,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, height: 1.5),
                ),
              ),
            ],
          ),
        ));
  }

  Widget _card(bool isDark, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Dt.hairline),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}
