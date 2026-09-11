import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../controllers/slide_deck_controller.dart';
import '../../core/colors.dart';
import '../../theme/design_tokens.dart';
import '../../utils/slide_deck.dart';

/// Slide edit + AI refine dialogs.
/// Extracted from views/slide_deck_view.dart.

SlideDeckController get _c => Get.find<SlideDeckController>();

// ── Manual edit dialog ──

void showEditDialog(BuildContext context, bool isDark, int index, Slide s) {
  final titleCtrl = TextEditingController(text: s.title);
  final subtitleCtrl = TextEditingController(text: s.subtitle);
  final authorCtrl = TextEditingController(text: s.quoteAuthor);
  final pointsCtrl =
      TextEditingController(text: s.points.map((p) => '- $p').join('\n'));
  final imgCtrl = TextEditingController(text: s.imagePrompt);
  final notesCtrl = TextEditingController(text: s.notes);
  var layout = s.layout;
  var chartType = s.chartData['type']?.toString() ?? 'bar';
  final chartItemsCtrl = TextEditingController(
      text: s.chartData['items'] is List
          ? (s.chartData['items'] as List)
              .map((e) => '${e['label']}: ${e['value']}')
              .join('\n')
          : '');
  showDialog(
    context: context,
    builder: (dlgCtx) => StatefulBuilder(
      builder: (ctx, setDlg) => AlertDialog(
        backgroundColor: isDark ? AppColors.surface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Edit slide ${index + 1}',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: titleCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration:
                  const InputDecoration(labelText: 'Title', isDense: true),
            ),
            const SizedBox(height: 10),
            if (layout == 'title') ...[
              TextField(
                controller: subtitleCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration:
                    const InputDecoration(labelText: 'Subtitle', isDense: true),
              ),
              const SizedBox(height: 10),
            ],
            if (layout == 'quote') ...[
              TextField(
                controller: authorCtrl,
                decoration: const InputDecoration(
                    labelText: 'Quote Author / Source', isDense: true),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: pointsCtrl,
              maxLines: 5,
              decoration: InputDecoration(
                  labelText: layout == 'comparison'
                      ? 'Points (first half vs second half)'
                      : 'Points (one per line, - optional)',
                  alignLabelWithHint: true,
                  isDense: true),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: [
                'title',
                'bullets',
                'image',
                'quote',
                'comparison',
                'stats',
                'timeline',
                'summary',
                'chart'
              ].contains(layout)
                  ? layout
                  : 'bullets',
              items: const [
                DropdownMenuItem(
                    value: 'title', child: Text('Title & Subtitle')),
                DropdownMenuItem(
                    value: 'bullets', child: Text('Bullet Points')),
                DropdownMenuItem(value: 'image', child: Text('Image + Text')),
                DropdownMenuItem(
                    value: 'quote', child: Text('Quote / Key Insight')),
                DropdownMenuItem(
                    value: 'comparison', child: Text('Comparison (2 Columns)')),
                DropdownMenuItem(value: 'stats', child: Text('Key Statistics')),
                DropdownMenuItem(
                    value: 'timeline', child: Text('Timeline / Steps')),
                DropdownMenuItem(
                    value: 'summary', child: Text('Summary / Takeaways')),
                DropdownMenuItem(
                    value: 'chart', child: Text('Chart (Bar / Donut / Line)')),
              ],
              onChanged: (v) {
                if (v != null) setDlg(() => layout = v);
              },
              decoration:
                  const InputDecoration(labelText: 'Layout', isDense: true),
            ),
            if (layout == 'chart') ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: ['bar', 'donut', 'line'].contains(chartType)
                    ? chartType
                    : 'bar',
                items: const [
                  DropdownMenuItem(value: 'bar', child: Text('Bar Chart')),
                  DropdownMenuItem(value: 'donut', child: Text('Donut Chart')),
                  DropdownMenuItem(value: 'line', child: Text('Line Chart')),
                ],
                onChanged: (v) {
                  if (v != null) setDlg(() => chartType = v);
                },
                decoration: const InputDecoration(
                    labelText: 'Chart type', isDense: true),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: chartItemsCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                    labelText: 'Data (one per line: Label: Value)',
                    hintText: 'Revenue: 12\nProfit: 5\nCost: 3',
                    alignLabelWithHint: true,
                    isDense: true),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: imgCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Image prompt (reserves the box)',
                  alignLabelWithHint: true,
                  isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Speaker notes',
                  alignLabelWithHint: true,
                  isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: TextEditingController(text: s.speakerNotes),
              maxLines: 3,
              onChanged: (v) => s.speakerNotes = v,
              decoration: const InputDecoration(
                  labelText: 'Full Presenter Script',
                  alignLabelWithHint: true,
                  isDense: true),
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Map<String, dynamic>? cd;
              if (layout == 'chart' && chartItemsCtrl.text.isNotEmpty) {
                cd = {
                  'type': chartType,
                  'items': chartItemsCtrl.text
                      .split('\n')
                      .where((l) => l.contains(':'))
                      .map((l) {
                    final parts = l.split(':');
                    return {
                      'label': parts[0].trim(),
                      'value': parts.sublist(1).join(':').trim(),
                    };
                  }).toList(),
                };
              }
              _c.applyEdit(index,
                  title: titleCtrl.text,
                  subtitle: subtitleCtrl.text,
                  quoteAuthor: authorCtrl.text,
                  pointsText: pointsCtrl.text,
                  imagePrompt: imgCtrl.text,
                  notes: notesCtrl.text,
                  layout: layout,
                  chartData: cd);
              Navigator.pop(dlgCtx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

/// AI refine dialog: user types a natural-language instruction, AI
/// rewrites that single slide to match while keeping deck context.
void showRefineDialog(BuildContext context, bool isDark, int index) {
  final ctrl = TextEditingController();
  final isLoading = ValueNotifier<bool>(false);
  showDialog(
    context: context,
    builder: (dlgCtx) => ValueListenableBuilder<bool>(
      valueListenable: isLoading,
      builder: (ctx, loading, _) => AlertDialog(
        backgroundColor: isDark ? AppColors.surface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Refine slide ${index + 1}',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        content: loading
            ? const SizedBox(
                height: 48, child: Center(child: CircularProgressIndicator()))
            : TextField(
                controller: ctrl,
                maxLines: 3,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText:
                      'e.g. "make it more data-driven" or "add a comparison chart"',
                  hintStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 13, color: Dt.textPlaceholder),
                  isDense: true,
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            icon: loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(LucideIcons.sparkles, size: 16),
            label: const Text('Refine'),
            style: FilledButton.styleFrom(backgroundColor: Dt.accent),
            onPressed: loading
                ? null
                : () {
                    final instruction = ctrl.text.trim();
                    if (instruction.isEmpty) return;
                    isLoading.value = true;
                    final nav = Navigator.of(dlgCtx);
                    _c.refineSlide(index, instruction).whenComplete(() {
                      if (nav.mounted) nav.pop();
                    });
                  },
          ),
        ],
      ),
    ),
  );
}
