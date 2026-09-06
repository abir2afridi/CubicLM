import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/slide_deck_controller.dart';
import '../core/colors.dart';
import '../theme/design_tokens.dart';
import '../utils/slide_deck.dart';

/// Slide Maker (chat ⋮ menu): AI builds a structured deck from a topic.
/// Text-only models reserve proper image boxes; image-capable setups can
/// render them. Any slide can be regenerated solo or edited by hand.
/// Exports: Markdown, PDF, standalone HTML.
class SlideDeckView extends StatefulWidget {
  const SlideDeckView({super.key});

  @override
  State<SlideDeckView> createState() => _SlideDeckViewState();
}

class _SlideDeckViewState extends State<SlideDeckView> {
  late final SlideDeckController c;
  final _topicCtrl = TextEditingController();
  final _pageCtrl = PageController();
  int _page = 0;

  @override
  void initState() {
    super.initState();
    c = Get.isRegistered<SlideDeckController>()
        ? Get.find<SlideDeckController>()
        : Get.put(SlideDeckController());
    _topicCtrl.text = c.topic.value;
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _topicCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text('Slide Maker',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        actions: [
          Obx(() => c.hasDeck
              ? PopupMenuButton<String>(
                  tooltip: 'Export deck',
                  icon: Icon(LucideIcons.share2,
                      color: isDark
                          ? AppColors.textPrimary
                          : Dt.iconDefault),
                  onSelected: (v) {
                    if (v == 'md') c.exportMarkdown();
                    if (v == 'pdf') c.exportPdf();
                    if (v == 'html') c.exportHtml();
                  },
                  itemBuilder: (_) => [
                    _exportItem('md', 'Markdown (.md)'),
                    _exportItem('pdf', 'PDF document'),
                    _exportItem('html', 'Web slides (.html)'),
                  ],
                )
              : const SizedBox.shrink()),
          const SizedBox(width: 4),
        ],
      ),
      body: Obx(() {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _composerCard(context, isDark),
            if (c.lastError.value != null) ...[
              const SizedBox(height: 10),
              _errorBox(context, isDark),
            ],
            if (c.hasDeck) ...[
              const SizedBox(height: 12),
              _deckBar(context, isDark),
              const SizedBox(height: 10),
              _carousel(context, isDark),
            ] else if (c.generating.value) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 12),
              Center(
                child: Text('Designing your slides…',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: Theme.of(context).hintColor)),
              ),
            ] else ...[
              const SizedBox(height: 24),
              Center(
                child: Text(
                  'Describe a topic above — the AI designs every slide.\n'
                  'Visual slides always reserve an image box, even when '
                  'the model can only write text.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      height: 1.5,
                      color: Theme.of(context).hintColor),
                ),
              ),
            ],
          ],
        );
      }),
    );
  }

  PopupMenuItem<String> _exportItem(String value, String label) {
    return PopupMenuItem(
      value: value,
      child: Text(label,
          style: GoogleFonts.plusJakartaSans(fontSize: 14)),
    );
  }

  // ── Composer ──

  Widget _composerCard(BuildContext context, bool isDark) {
    return _card(isDark, [
      TextField(
        controller: _topicCtrl,
        enabled: !c.generating.value,
        maxLines: 3,
        minLines: 1,
        onChanged: (v) => c.topic.value = v,
        style: GoogleFonts.plusJakartaSans(fontSize: 14, height: 1.45),
        decoration: InputDecoration(
          hintText: 'e.g. How photosynthesis works (class 8)',
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.all(12),
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: c.style.value,
            items: [
              for (final s in SlideDeckController.styles)
                DropdownMenuItem(value: s, child: Text(s)),
            ],
            onChanged: c.generating.value
                ? null
                : (v) {
                    if (v != null) c.style.value = v;
                  },
            decoration: InputDecoration(
              labelText: 'Style',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          decoration: BoxDecoration(
            border: Border.all(
                color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              tooltip: 'Fewer slides',
              icon: const Icon(Icons.remove, size: 18),
              onPressed: c.generating.value
                  ? null
                  : () => c.setCount(c.slideCount.value - 1),
            ),
            Text('${c.slideCount.value}',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 15, fontWeight: FontWeight.w800)),
            IconButton(
              tooltip: 'More slides',
              icon: const Icon(Icons.add, size: 18),
              onPressed: c.generating.value
                  ? null
                  : () => c.setCount(c.slideCount.value + 1),
            ),
          ]),
        ),
      ]),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: c.generating.value ||
                  _topicCtrl.text.trim().isEmpty
              ? null
              : () async {
                  c.topic.value = _topicCtrl.text;
                  await c.generate();
                  _page = 0;
                  if (_pageCtrl.hasClients) {
                    _pageCtrl.jumpToPage(0);
                  }
                },
          icon: const Icon(LucideIcons.presentation, size: 18),
          label: Text(c.hasDeck ? 'Regenerate deck' : 'Make slides'),
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

  Widget _errorBox(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(c.lastError.value!,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5, color: AppColors.error, height: 1.4)),
    );
  }

  // ── Deck bar + carousel ──

  Widget _deckBar(BuildContext context, bool isDark) {
    return Row(children: [
      Text('${c.slides.length} slides',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).hintColor)),
      const Spacer(),
      IconButton(
        tooltip: 'Add blank slide',
        icon: const Icon(LucideIcons.plus, size: 18),
        onPressed: () {
          c.addBlank();
          _page = c.slides.length - 1;
          if (_pageCtrl.hasClients) _pageCtrl.jumpToPage(_page);
        },
      ),
      IconButton(
        tooltip: 'Clear deck',
        icon: Icon(LucideIcons.trash2,
            size: 18, color: AppColors.error.withValues(alpha: 0.8)),
        onPressed: c.clearDeck,
      ),
    ]);
  }

  Widget _carousel(BuildContext context, bool isDark) {
    return Column(children: [
      SizedBox(
        height: 460,
        child: PageView.builder(
          controller: _pageCtrl,
          itemCount: c.slides.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _slideCard(context, isDark, i, c.slides[i]),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text('${(_page + 1).clamp(1, c.slides.length)} / ${c.slides.length}',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).hintColor)),
    ]);
  }

  Widget _slideCard(
      BuildContext context, bool isDark, int index, Slide s) {
    final busy =
        c.generating.value && c.regenIndex.value == index;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.07)
                : Dt.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('SLIDE ${index + 1}',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: Dt.accent)),
          const Spacer(),
          if (busy)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else ...[
            _miniBtn(context, LucideIcons.pencil, 'Edit slide',
                () => _showEditDialog(context, isDark, index, s)),
            _miniBtn(context, LucideIcons.refreshCw, 'Regenerate this slide',
                () => c.regenerateSlide(index)),
            _miniBtn(context, LucideIcons.arrowUp, 'Move up',
                index == 0 ? null : () => c.moveSlide(index, -1)),
            _miniBtn(context, LucideIcons.arrowDown, 'Move down',
                index == c.slides.length - 1
                    ? null
                    : () => c.moveSlide(index, 1)),
            _miniBtn(context, LucideIcons.trash2, 'Delete slide',
                () => c.deleteSlide(index),
                color: AppColors.error.withValues(alpha: 0.8)),
          ],
        ]),
        const SizedBox(height: 10),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.title.isEmpty ? 'Untitled' : s.title,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 21, fontWeight: FontWeight.w800, height: 1.25),
                  ),
                  if (s.points.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    for (final p in s.points)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              const Text('▸  ',
                                  style: TextStyle(
                                      color: Dt.accent,
                                      fontWeight: FontWeight.w800)),
                              Expanded(
                                child: Text(p,
                                    style:
                                        GoogleFonts.plusJakartaSans(
                                            fontSize: 14, height: 1.45)),
                              ),
                            ]),
                      ),
                  ],
                  const SizedBox(height: 12),
                  _imageArea(context, isDark, index, s),
                  if (s.notes.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('Notes: ${s.notes.trim()}',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: Theme.of(context).hintColor)),
                  ],
                ]),
          ),
        ),
      ]),
    );
  }

  Widget _miniBtn(BuildContext context, IconData icon, String tip,
      VoidCallback? onTap,
      {Color? color}) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon,
              size: 16,
              color: onTap == null
                  ? Theme.of(context).disabledColor
                  : (color ?? Theme.of(context).hintColor)),
        ),
      ),
    );
  }

  /// Image area: generated bytes → image; otherwise a proper reserved
  /// placeholder box with the visual prompt + one-tap generate.
  Widget _imageArea(
      BuildContext context, bool isDark, int index, Slide s) {
    if (s.imageBytes != null && s.imageBytes!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(children: [
          Image.memory(
            Uint8List.fromList(s.imageBytes!),
            width: double.infinity,
            height: 170,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const SizedBox(height: 120),
          ),
          Positioned(
            right: 8,
            top: 8,
            child: _chipButton(
              context,
              icon: LucideIcons.refreshCw,
              label: 'Retry',
              busy: c.imageBusyIndex.value == index,
              onTap: c.imageBusyIndex.value == index
                  ? null
                  : () => c.generateSlideImage(index),
            ),
          ),
        ]),
      );
    }
    if (!s.wantsImage) return const SizedBox.shrink();
    final prompt =
        s.imagePrompt.trim().isEmpty ? '(visual forthcoming)' : s.imagePrompt.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Dt.accent.withValues(alpha: 0.45),
          width: 1.2,
        ),
        color: Dt.accent.withValues(alpha: 0.05),
      ),
      child: Column(children: [
        const Icon(LucideIcons.imagePlus, size: 26, color: Dt.accent),
        const SizedBox(height: 6),
        Text('IMAGE SPACE',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
                color: Dt.accent)),
        const SizedBox(height: 6),
        Text(prompt,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                height: 1.45,
                color: Theme.of(context).hintColor)),
        const SizedBox(height: 10),
        _chipButton(
          context,
          icon: LucideIcons.sparkles,
          label: c.canGenerateImages ? 'Generate image' : 'No image engine',
          busy: c.imageBusyIndex.value == index,
          onTap: c.imageBusyIndex.value == index
              ? null
              : () => c.generateSlideImage(index),
        ),
      ]),
    );
  }

  Widget _chipButton(BuildContext context,
      {required IconData icon,
      required String label,
      required bool busy,
      required VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Dt.accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (busy)
            const SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(icon, size: 13, color: Dt.accent),
          const SizedBox(width: 6),
          Text(label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }

  // ── Manual edit dialog ──

  void _showEditDialog(
      BuildContext context, bool isDark, int index, Slide s) {
    final titleCtrl = TextEditingController(text: s.title);
    final pointsCtrl =
        TextEditingController(text: s.points.map((p) => '- $p').join('\n'));
    final imgCtrl = TextEditingController(text: s.imagePrompt);
    final notesCtrl = TextEditingController(text: s.notes);
    var layout = s.layout;
    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: isDark ? AppColors.surface : Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: Text('Edit slide ${index + 1}',
              style:
                  GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: titleCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Title', isDense: true),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: pointsCtrl,
                maxLines: 5,
                decoration: const InputDecoration(
                    labelText: 'Points (one per line, - optional)',
                    alignLabelWithHint: true,
                    isDense: true),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: ['title', 'bullets', 'image'].contains(layout)
                    ? layout
                    : 'bullets',
                items: const [
                  DropdownMenuItem(
                      value: 'title', child: Text('Title')),
                  DropdownMenuItem(
                      value: 'bullets', child: Text('Bullets')),
                  DropdownMenuItem(
                      value: 'image', child: Text('Image + text')),
                ],
                onChanged: (v) {
                  if (v != null) setDlg(() => layout = v);
                },
                decoration: const InputDecoration(
                    labelText: 'Layout', isDense: true),
              ),
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
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                c.applyEdit(index,
                    title: titleCtrl.text,
                    pointsText: pointsCtrl.text,
                    imagePrompt: imgCtrl.text,
                    notes: notesCtrl.text,
                    layout: layout);
                Navigator.pop(dlgCtx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children),
    );
  }
}
