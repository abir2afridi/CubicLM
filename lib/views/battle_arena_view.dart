import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/battle_arena_controller.dart';
import '../controllers/cloud_model_controller.dart';
import '../core/colors.dart';
import '../services/tts_service.dart';
import '../theme/design_tokens.dart';
import '../utils/prompt_export.dart';
import '../utils/thought_parser.dart';
import '../widgets/code_block.dart';

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
    final freeOnly = ValueNotifier(false);
    CloudModelController cmc() => Get.find<CloudModelController>();
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(children: [
                ValueListenableBuilder<bool>(
                  valueListenable: freeOnly,
                  builder: (_, on, __) => ChoiceChip(
                    label: Text('FREE',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11, fontWeight: FontWeight.w800)),
                    selected: on,
                    selectedColor:
                        AppColors.success.withValues(alpha: 0.2),
                    onSelected: (_) => freeOnly.value = !on,
                  ),
                ),
                const SizedBox(width: 8),
                ValueListenableBuilder<String>(
                  valueListenable: query,
                  builder: (_, q, __) => ValueListenableBuilder<bool>(
                    valueListenable: freeOnly,
                    builder: (_, fo, __) {
                      var n = 0;
                      groups.forEach((pid, list) {
                        for (final m in list) {
                          if (q.isNotEmpty &&
                              !m.toLowerCase().contains(q) &&
                              !c
                                  .providerName(pid)
                                  .toLowerCase()
                                  .contains(q)) {
                            continue;
                          }
                          if (fo) {
                            try {
                              if (!cmc().isFreeModel(pid, m)) {
                                continue;
                              }
                            } catch (_) {}
                          }
                          n++;
                        }
                      });
                      return Text('$n models',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: Theme.of(context).hintColor));
                    },
                  ),
                ),
              ]),
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
                      builder: (_, q, __) => ValueListenableBuilder<bool>(
                        valueListenable: freeOnly,
                        builder: (_, fo, __) => ListView(
                          controller: scrollCtrl,
                          padding:
                              const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          children: [
                            if (c.loadedLocalName.isNotEmpty &&
                                !fo &&
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
                                  sheetCtx, pid, groups[pid]!, q, fo),
                          ],
                        ),
                      ),
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  List<Widget> _pickerGroup(BuildContext sheetCtx, String providerId,
      List<String> models, String q, bool freeOnly) {
    final name = c.providerName(providerId);
    bool freeOf(String m) {
      try {
        return Get.find<CloudModelController>().isFreeModel(providerId, m);
      } catch (_) {
        return false;
      }
    }

    final filtered = models.where((m) {
      if (q.isNotEmpty &&
          !m.toLowerCase().contains(q) &&
          !name.toLowerCase().contains(q)) {
        return false;
      }
      if (freeOnly && !freeOf(m)) return false;
      return true;
    }).toList();
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
              title: Row(children: [
                Expanded(
                  child: Text(m,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(fontSize: 13)),
                ),
                if (freeOf(m))
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color:
                          AppColors.success.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('FREE',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: AppColors.success)),
                  ),
              ]),
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
      final ttft = e.firstTokenMs == null
          ? ''
          : ' · TTFT ${(e.firstTokenMs! / 1000).toStringAsFixed(1)}s';
      final detail = st == 'error'
          ? (e.error ?? 'error')
          : st == 'running'
              ? '$secs s · ${e.tokensPerSec.toStringAsFixed(1)} tok/s · ${e.chars} chars$ttft'
              : '$secs s · ${e.tokensPerSec.toStringAsFixed(1)} tok/s · ${e.chars} chars$ttft';
      // Normalize bars against the best finished contender.
      final best = _bestMetrics();
      return Padding(
        padding: const EdgeInsets.only(top: 10),
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
                  if (st != 'error') ...[
                    const SizedBox(height: 5),
                    _metricBar(
                        'SPD',
                        best.speed <= 0
                            ? 0
                            : (e.tokensPerSec / best.speed)
                                .clamp(0.0, 1.0),
                        Dt.accent),
                    const SizedBox(height: 3),
                    _metricBar(
                        'INFO',
                        best.chars <= 0
                            ? 0
                            : (e.chars / best.chars).clamp(0.0, 1.0),
                        AppColors.success),
                  ],
                ]),
          ),
        ]),
      );
    });
  }

  ({double speed, int chars}) _bestMetrics() {
    var speed = 0.0;
    var chars = 0;
    for (final e in c.entries) {
      if (e.status.value == 'error') continue;
      if (e.tokensPerSec > speed) speed = e.tokensPerSec;
      if (e.chars > chars) chars = e.chars;
    }
    return (speed: speed, chars: chars);
  }

  Widget _metricBar(String tag, double ratio, Color color) {
    return Row(children: [
      SizedBox(
        width: 30,
        child: Text(tag,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: color)),
      ),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            minHeight: 5,
            value: ratio,
            backgroundColor: color.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ),
    ]);
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
        Builder(builder: (_) {
          final worst = v.rows.values.fold<double>(
              0, (a, r) => r.score > a ? r.score : a);
          return Column(children: [
            for (final id in v.order)
              Builder(builder: (_) {
                final row = v.rows[id]!;
                final entry =
                    c.entries.firstWhere((e) => e.pick.id == id,
                        orElse: () => c.entries.first);
                final secs =
                    ((entry.doneMs ?? entry.elapsedMs.value) / 1000)
                        .toStringAsFixed(1);
                // Lower score = better → invert for bar length.
                final ratio = worst <= 0
                    ? 1.0
                    : (1 - (row.score - 1) / (worst <= 1 ? 1 : worst - 1))
                        .clamp(0.0, 1.0);
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(
                              '#${v.order.indexOf(id) + 1} ${entry.pick.label}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800),
                            ),
                          ),
                          Text('${row.score.toStringAsFixed(2)} pts',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Dt.accent)),
                        ]),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            minHeight: 7,
                            value: ratio,
                            backgroundColor:
                                Dt.accent.withValues(alpha: 0.12),
                            valueColor:
                                const AlwaysStoppedAnimation<Color>(
                                    Dt.accent),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'finish #${row.finishRank} · speed #${row.speedRank} '
                          '(${entry.tokensPerSec.toStringAsFixed(1)} tok/s) · '
                          'length #${row.lengthRank} (${entry.chars} chars, ${secs}s)',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11, height: 1.4,
                              color: Theme.of(context).hintColor),
                        ),
                      ]),
                );
              }),
          ]);
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
    return Obx(() {
      // Chat-page parity: render markdown (code blocks get copy/share +
      // HTML live preview via CodeBlockBuilder), think tags stripped.
      final answer = splitThoughtTags(e.text.value).answer.trim();
      final shown = answer.isNotEmpty ? answer : e.text.value;
      return Card(
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
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Read aloud',
                icon: const Icon(LucideIcons.volume2, size: 16),
                onPressed: e.text.value.isEmpty
                    ? null
                    : () => _speak(e.text.value),
              ),
              IconButton(
                tooltip: 'Export .md',
                icon: const Icon(LucideIcons.download, size: 16),
                onPressed: e.text.value.isEmpty
                    ? null
                    : () => PromptExport.shareAsMarkdown(
                        shown, baseName: 'battle'),
              ),
              IconButton(
                tooltip: 'Copy response',
                icon: const Icon(LucideIcons.copy, size: 16),
                onPressed: e.text.value.isEmpty
                    ? null
                    : () => Clipboard.setData(
                        ClipboardData(text: e.text.value)),
              ),
            ],
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
              child: shown.isEmpty
                  ? Text('(no output)',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: Theme.of(context).hintColor))
                  : MarkdownBody(
                      data: shown,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet.fromTheme(
                              Theme.of(context))
                          .copyWith(
                        p: GoogleFonts.plusJakartaSans(
                            fontSize: 13, height: 1.5),
                      ),
                      builders: {
                        'code': CodeBlockBuilder(context),
                        'pre': CodeBlockBuilder(context),
                      },
                    ),
            ),
          ],
        ),
      );
    });
  }

  void _speak(String text) {
    try {
      if (Get.isRegistered<TtsService>()) {
        Get.find<TtsService>().speak(text);
      }
    } catch (_) {}
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
