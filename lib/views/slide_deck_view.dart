import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
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

  /// Viewer mode: ppt (dark 4:3 stage) · docs (light paper flow) ·
  /// pdf (light A4 portrait page). View-only; exports unchanged.
  String _viewMode = 'ppt';

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
                    if (v == 'preview') c.previewInBrowser();
                  },
                  itemBuilder: (_) => [
                    _exportItem('preview', 'Preview in browser'),
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
      // Viewer mode switch (Docs / PowerPoint / PDF look).
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'docs',
              icon: Icon(LucideIcons.fileText, size: 14),
              label: Text('Docs'),
            ),
            ButtonSegment(
              value: 'ppt',
              icon: Icon(LucideIcons.presentation, size: 14),
              label: Text('Slides'),
            ),
            ButtonSegment(
              value: 'pdf',
              icon: Icon(LucideIcons.fileDown, size: 14),
              label: Text('PDF'),
            ),
          ],
          selected: {_viewMode},
          onSelectionChanged: (s) =>
              setState(() => _viewMode = s.first),
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.compact,
          ),
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: _viewMode == 'ppt' ? 470 : 560,
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
      padding: const EdgeInsets.all(14),
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
            _miniBtn(context, LucideIcons.move, 'Free layout',
                () => _toggleFreeLayout(index, s),
                color: s.freeLayout ? Dt.accent : null),
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
        // WYSIWYG canvas — how the slide actually looks (4:3 stage).
        _slideCanvas(context, index, s, _viewMode),
        if (s.notes.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Notes: ${s.notes.trim()}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Theme.of(context).hintColor)),
        ],
        const SizedBox(height: 8),
        _imageControls(context, index, s),
      ]),
    );
  }

  /// PowerPoint-like 4:3 stage: gradient backdrop, image banner or
  /// reserved placeholder, compact title + bullets. Overflow-safe by
  /// construction (fixed line budgets + ellipsis).
  /// [mode]: ppt (dark 4:3 stage) · docs (light paper flow) ·
  /// pdf (light A4 portrait page).
  Widget _slideCanvas(
      BuildContext context, int index, Slide s, String mode) {
    if (mode == 'docs') return _docsCanvas(context, index, s);
    if (mode == 'pdf') return _pdfCanvas(context, index, s);
    return _pptCanvas(context, index, s);
  }

  Widget _pptCanvas(BuildContext context, int index, Slide s) {
    final hasImage = s.imageBytes != null && s.imageBytes!.isNotEmpty;
    final showPoints = s.points.take(4).toList();
    final hidden = s.points.length - showPoints.length;
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF23232f), Color(0xFF101016)],
          ),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.08)),
        ),
        clipBehavior: Clip.antiAlias,
        child: s.freeLayout
            ? LayoutBuilder(
                builder: (_, cons) => _freeStack(
                  context,
                  s,
                  cons.maxWidth,
                  cons.maxHeight,
                  titleColor: Colors.white,
                  bodyColor: const Color(0xFFD8D5CF),
                  titleBase: 17,
                  bodyBase: 11.5,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              if (hasImage)
                SizedBox(
                  height: 110,
                  child: Image.memory(
                    Uint8List.fromList(s.imageBytes!),
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const SizedBox(height: 110),
                  ),
                )
              else if (s.wantsImage)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Dt.accent.withValues(alpha: 0.12),
                    border: const Border(
                      bottom: BorderSide(
                          color: Dt.accent, width: 1),
                    ),
                  ),
                  child: Row(children: [
                    const Icon(LucideIcons.imagePlus,
                        size: 13, color: Dt.accent),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        s.imagePrompt.trim().isEmpty
                            ? 'IMAGE SPACE'
                            : s.imagePrompt.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFE8B4A0)),
                      ),
                    ),
                  ]),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                  child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.title.isEmpty ? 'Untitled' : s.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                              color: Colors.white),
                        ),
                        const SizedBox(height: 6),
                        for (final p in showPoints)
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: 3),
                            child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  const Text('▸ ',
                                      style: TextStyle(
                                          color: Dt.accent,
                                          fontWeight:
                                              FontWeight.w800,
                                          fontSize: 11)),
                                  Expanded(
                                    child: Text(p,
                                        maxLines: 2,
                                        overflow:
                                            TextOverflow.ellipsis,
                                        style: GoogleFonts
                                            .plusJakartaSans(
                                                fontSize: 11.5,
                                                height: 1.35,
                                                color: const Color(
                                                    0xFFD8D5CF))),
                                  ),
                                ]),
                          ),
                        if (hidden > 0)
                          Text('+$hidden more',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF8E8B85))),
                        const Spacer(),
                        Align(
                          alignment: Alignment.bottomRight,
                          child: Text('${index + 1}',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF6E6B65))),
                        ),
                      ]),
                ),
              ),
            ]),
      ),
    );
  }

  /// Docs mode: light paper, continuous flow (all content visible).
  Widget _docsCanvas(BuildContext context, int index, Slide s) {
    final hasImage = s.imageBytes != null && s.imageBytes!.isNotEmpty;
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.title.isEmpty ? 'Untitled' : s.title,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                      color: const Color(0xFF1A1A1A)),
                ),
                Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    height: 3,
                    width: 44,
                    decoration: BoxDecoration(
                        color: Dt.accent,
                        borderRadius: BorderRadius.circular(2))),
                for (final p in s.points)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const Text('•  ',
                              style: TextStyle(
                                  color: Dt.accent,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13)),
                          Expanded(
                            child: Text(p,
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    height: 1.5,
                                    color: const Color(0xFF2A2A2A))),
                          ),
                        ]),
                  ),
                if (hasImage) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      Uint8List.fromList(s.imageBytes!),
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const SizedBox.shrink(),
                    ),
                  ),
                ] else if (s.wantsImage) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F1EA),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color:
                              Dt.accent.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      s.imagePrompt.trim().isEmpty
                          ? '[ image ]'
                          : '[ image: ${s.imagePrompt.trim()} ]',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic,
                          color: const Color(0xFF8A7F72)),
                    ),
                  ),
                ],
                if (s.notes.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(s.notes.trim(),
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic,
                          color: const Color(0xFF8A8A8A))),
                ],
              ]),
        ),
      ),
    );
  }

  /// PDF mode: light A4 portrait page with margins + page number.
  Widget _pdfCanvas(BuildContext context, int index, Slide s) {
    final hasImage = s.imageBytes != null && s.imageBytes!.isNotEmpty;
    final total = c.slides.length;
    return AspectRatio(
      aspectRatio: 1 / 1.4142,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.title.isEmpty ? 'Untitled' : s.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                      color: const Color(0xFF111111)),
                ),
                const SizedBox(height: 4),
                Text('Slide ${index + 1} of $total',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF9A9A9A))),
                const Divider(height: 20),
                Expanded(
                  child: s.freeLayout
                      ? LayoutBuilder(
                          builder: (_, cons) => _freeStack(
                            context,
                            s,
                            cons.maxWidth,
                            cons.maxHeight,
                            titleColor:
                                const Color(0xFF111111),
                            bodyColor:
                                const Color(0xFF333333),
                            titleBase: 16,
                            bodyBase: 11,
                          ),
                        )
                      : SingleChildScrollView(
                    child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          for (final p in s.points)
                            Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 6),
                              child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Text('– ',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color:
                                                Color(0xFF555555))),
                                    Expanded(
                                      child: Text(p,
                                          style: GoogleFonts
                                              .plusJakartaSans(
                                                  fontSize: 12,
                                                  height: 1.5,
                                                  color: const Color(
                                                      0xFF222222))),
                                    ),
                                  ]),
                            ),
                          if (hasImage) ...[
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(6),
                              child: Image.memory(
                                Uint8List.fromList(
                                    s.imageBytes!),
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                          ] else if (s.wantsImage) ...[
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding:
                                  const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color: const Color(0xFFCCCCCC)),
                                borderRadius:
                                    BorderRadius.circular(6),
                              ),
                              child: Text(
                                s.imagePrompt.trim().isEmpty
                                    ? '[ image ]'
                                    : '[ image: ${s.imagePrompt.trim()} ]',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                    color:
                                        const Color(0xFF999999)),
                              ),
                            ),
                          ],
                        ]),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Text('${index + 1} / $total',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          color: const Color(0xFFAAAAAA))),
                ),
              ]),
        ),
      ),
    );
  }

  /// Image generate/retry row under the canvas (full editor lives here;
  /// the canvas only previews).
  Widget _imageControls(
      BuildContext context, int index, Slide s) {
    final hasImage = s.imageBytes != null && s.imageBytes!.isNotEmpty;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (s.wantsImage || hasImage)
          _chipButton(
            context,
            icon: hasImage ? LucideIcons.refreshCw : LucideIcons.sparkles,
            label: hasImage
                ? 'Regenerate image'
                : (c.canGenerateImages
                    ? 'Generate image'
                    : 'No image engine — load SD model'),
            busy: c.imageBusyIndex.value == index,
            onTap: c.imageBusyIndex.value == index
                ? null
                : () => c.generateSlideImage(index),
          ),
        _chipButton(
          context,
          icon: LucideIcons.imagePlus,
          label: hasImage ? 'Replace photo' : 'Add photo',
          busy: false,
          onTap: () => _addManualImage(index, s),
        ),
      ],
    );
  }

  /// Toggle freehand layout. First enable seeds non-overlapping
  /// defaults; disabling keeps values (re-enable restores them).
  void _toggleFreeLayout(int index, Slide s) {
    if (!s.freeLayout &&
        s.tDx == 0 &&
        s.tDy == 0 &&
        s.bDx == 0 &&
        s.bDy == 0 &&
        s.iDx == 0 &&
        s.iDy == 0) {
      s.tDx = 0.07;
      s.tDy = 0.05;
      s.bDx = 0.07;
      s.bDy = 0.34;
      s.iDx = 0.07;
      s.iDy = 0.64;
    }
    s.freeLayout = !s.freeLayout;
    c.slides.refresh();
  }

  /// Manual image: gallery or camera into the slide (works even when the
  /// model couldn't generate one — the reserved box gets filled by hand).
  Future<void> _addManualImage(int index, Slide s) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(LucideIcons.image),
            title: const Text('Gallery'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(LucideIcons.camera),
            title: const Text('Camera'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
        ]),
      ),
    );
    if (source == null) return;
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return;
      s.imageBytes = bytes.toList();
      c.slides.refresh();
    } catch (_) {}
  }

  /// Free-layout stack shared by PPT + PDF canvas: title / body / image
  /// boxes positioned by fractional offsets, draggable + scalable.
  Widget _freeStack(
    BuildContext context,
    Slide s,
    double w,
    double h, {
    required Color titleColor,
    required Color bodyColor,
    required double titleBase,
    required double bodyBase,
  }) {
    final hasImage = s.imageBytes != null && s.imageBytes!.isNotEmpty;
    return Stack(children: [
      _FreeBox(
        dx: s.tDx,
        dy: s.tDy,
        scale: s.tS,
        canvasW: w,
        canvasH: h,
        onCommit: (dx, dy, sc) {
          s.tDx = dx;
          s.tDy = dy;
          s.tS = sc;
        },
        builder: (_, sc) => Text(
          s.title.isEmpty ? 'Untitled' : s.title,
          style: GoogleFonts.plusJakartaSans(
              fontSize: titleBase * sc,
              fontWeight: FontWeight.w800,
              height: 1.2,
              color: titleColor),
        ),
      ),
      _FreeBox(
        dx: s.bDx,
        dy: s.bDy,
        scale: s.bS,
        canvasW: w,
        canvasH: h,
        onCommit: (dx, dy, sc) {
          s.bDx = dx;
          s.bDy = dy;
          s.bS = sc;
        },
        builder: (_, sc) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final p in s.points.take(6))
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text('▸ $p',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: bodyBase * sc,
                          height: 1.35,
                          color: bodyColor)),
                ),
            ]),
      ),
      if (hasImage || s.wantsImage)
        _FreeBox(
          dx: s.iDx,
          dy: s.iDy,
          scale: s.iS,
          canvasW: w,
          canvasH: h,
          boxH: 84,
          onCommit: (dx, dy, sc) {
            s.iDx = dx;
            s.iDy = dy;
            s.iS = sc;
          },
          builder: (_, sc) => hasImage
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    Uint8List.fromList(s.imageBytes!),
                    height: 84 * sc,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const SizedBox.shrink(),
                  ),
                )
              : Container(
                  height: 52 * sc,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Dt.accent, width: 1),
                    color: Dt.accent.withValues(alpha: 0.1),
                  ),
                  child: Text('IMAGE',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 10 * sc,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: Dt.accent)),
                ),
        ),
    ]);
  }

  Widget _miniBtn(BuildContext context, IconData icon, String tip,      VoidCallback? onTap,
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

/// Draggable + scalable overlay box for freehand slide layout.
///
/// - Drag anywhere on the box to move (fractional canvas offsets).
/// - Drag the corner handle to scale content.
/// - State lives locally during the gesture; [onCommit] persists to the
///   slide on every change (plain field writes — no list rebuild, so the
///   drag stays smooth).
class _FreeBox extends StatefulWidget {
  final double dx;
  final double dy;
  final double scale;
  final double canvasW;
  final double canvasH;
  final double boxH;
  final Widget Function(BuildContext, double scale) builder;
  final void Function(double dx, double dy, double scale) onCommit;

  const _FreeBox({
    required this.dx,
    required this.dy,
    required this.scale,
    required this.canvasW,
    required this.canvasH,
    required this.builder,
    required this.onCommit,
    this.boxH = 0,
  });

  @override
  State<_FreeBox> createState() => _FreeBoxState();
}

class _FreeBoxState extends State<_FreeBox> {
  late double _dx;
  late double _dy;
  late double _scale;

  @override
  void initState() {
    super.initState();
    _dx = widget.dx;
    _dy = widget.dy;
    _scale = widget.scale.clamp(0.5, 2.5);
  }

  void _commit() => widget.onCommit(_dx, _dy, _scale);

  @override
  Widget build(BuildContext context) {
    const widthFrac = 0.86;
    final w = widget.canvasW * widthFrac;
    final left = (_dx * widget.canvasW).clamp(0.0, widget.canvasW - w);
    final top = (_dy * widget.canvasH).clamp(0.0, widget.canvasH - 30);
    return Positioned(
      left: left,
      top: top,
      width: w,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanUpdate: (d) {
          setState(() {
            _dx = ((_dx * widget.canvasW + d.delta.dx) / widget.canvasW)
                .clamp(0.0, 1.0 - widthFrac);
            _dy = ((_dy * widget.canvasH + d.delta.dy) / widget.canvasH)
                .clamp(0.0, 0.95);
          });
          _commit();
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: Dt.accent.withValues(alpha: 0.55),
              width: 1,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: const EdgeInsets.all(5),
                child: widget.boxH > 0
                    ? SizedBox(
                        height: widget.boxH * _scale,
                        width: double.infinity,
                        child: widget.builder(context, _scale),
                      )
                    : widget.builder(context, _scale),
              ),
              Positioned(
                right: -11,
                bottom: -11,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (d) {
                    setState(() {
                      _scale = (_scale + d.delta.dx / 120)
                          .clamp(0.5, 2.5);
                    });
                    _commit();
                  },
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: Dt.accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.open_in_full_rounded,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
