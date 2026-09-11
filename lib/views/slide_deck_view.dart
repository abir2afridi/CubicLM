import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../controllers/slide_deck_controller.dart';
import '../controllers/settings_controller.dart';
import '../core/colors.dart';
import '../services/inference_service.dart';
import '../services/local_image_service.dart';
import '../theme/design_tokens.dart';
import '../utils/slide_deck.dart';
import '../widgets/slide_source_selector.dart';
import 'slides/slide_charts.dart';
import 'slides/slide_dialogs.dart';
import 'slides/slide_outline_view.dart';
import 'slides/slide_painters.dart';
import '../widgets/app_ui.dart';
import '../widgets/model_switcher_sheet.dart';

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

  final _stt = stt.SpeechToText();
  bool _isListening = false;

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
                      color: isDark ? AppColors.textPrimary : Dt.iconDefault),
                  onSelected: (v) {
                    if (v == 'md') c.exportMarkdown();
                    if (v == 'pdf') c.exportPdf();
                    if (v == 'html') c.exportHtml();
                    if (v == 'pptx') c.exportPptx();
                    if (v == 'preview') c.previewInBrowser();
                  },
                  itemBuilder: (_) => [
                    _exportItem('preview', 'Preview in browser'),
                    _exportItem('pptx', 'PowerPoint (.pptx)'),
                    _exportItem('pdf', 'PDF document'),
                    _exportItem('html', 'Web slides (.html)'),
                    _exportItem('md', 'Markdown (.md)'),
                  ],
                )
              : const SizedBox.shrink()),
          const SizedBox(width: 4),
        ],
      ),
      body: Obx(() {
        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                children: [
                  if (c.lastError.value != null) ...[
                    _errorBox(context, isDark),
                    const SizedBox(height: 10),
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
                        'Describe a topic below — the AI designs every slide.\n'
                        'Visual slides always reserve an image box, even when '
                        'the model can only write text.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            height: 1.5,
                            color: Theme.of(context).hintColor),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: Text(
                        'Or start with a structured template:',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).hintColor),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tName in SlideDeckController.templates.keys)
                          ActionChip(
                            backgroundColor:
                                isDark ? AppColors.surface : Dt.pillMuted,
                            side: BorderSide(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Dt.hairline),
                            label: Text(
                              tName,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      isDark ? Colors.white : Dt.textPrimary),
                            ),
                            onPressed: () => _pickTemplate(tName),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            // ── Composer pinned at the bottom (chat-style) ──
            Padding(
              padding: EdgeInsets.fromLTRB(
                  16, 4, 16, 16 + MediaQuery.of(context).padding.bottom),
              child: _composerCard(context, isDark),
            ),
          ],
        );
      }),
      // Outline Sheet
      bottomSheet: Obx(() => c.showingOutline.value
          ? SlideOutlineView()
          : const SizedBox.shrink()),
    );
  }

  PopupMenuItem<String> _exportItem(String value, String label) {
    return PopupMenuItem(
      value: value,
      child: Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 14)),
    );
  }

  // ── Composer ──

  /// Chat-style composer: borderless field on top, controls row below
  /// (model pill → style → slide count … generate CTA).
  Widget _composerCard(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Dt.card,
        borderRadius: BorderRadius.circular(Dt.rComposer),
        border: isDark
            ? Border.all(color: Colors.white.withValues(alpha: 0.08))
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _topicCtrl,
                    enabled: !c.generating.value,
                    maxLines: 4,
                    minLines: 1,
                    onChanged: (v) => c.topic.value = v,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 16, height: 1.35, fontWeight: FontWeight.w500),
                    decoration: InputDecoration(
                      hintText: 'e.g. How photosynthesis works (class 8)',
                      hintStyle: GoogleFonts.plusJakartaSans(
                          fontSize: 16, color: Dt.textPlaceholder),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                      isDense: true,
                      fillColor: Colors.transparent,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(_isListening ? LucideIcons.mic : LucideIcons.micOff,
                      color: _isListening ? Dt.accent : Dt.textSecondary),
                  onPressed: _toggleSpeech,
                ),
              ],
            ),
          ),
          // Source Selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Obx(() => SlideSourceSelector(
                  selectedFile: c.sourceFile.value,
                  useResearch: c.useResearch.value,
                  onFileSelected: c.setSourceFile,
                  onResearchToggled: (v) => c.useResearch.value = v,
                )),
          ),
          const SizedBox(height: 4),
          // Row 1: model pill … generate CTA (always fits 360dp).
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 125,
                child: Obx(() => AppModelPill(
                      label: _engineLabel(),
                      onTap: () => showModelSwitcherSheet(context),
                    )),
              ),
              const Spacer(),
              AppCtaButton(
                icon: c.generating.value
                    ? Icons.hourglass_top_rounded
                    : LucideIcons.presentation,
                onTap: c.generating.value || _topicCtrl.text.trim().isEmpty
                    ? null
                    : () async {
                        c.topic.value = _topicCtrl.text;
                        await c.generate();
                        _page = 0;
                        if (_pageCtrl.hasClients) {
                          _pageCtrl.jumpToPage(0);
                        }
                      },
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Row 2: style + slide count.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(child: Obx(() => _stylePill(context, isDark))),
              const SizedBox(width: 6),
              Flexible(child: Obx(() => _countStepper(context, isDark))),
              const Spacer(),
              Flexible(child: Obx(() => _audiencePill(context, isDark))),
            ],
          ),
        ],
      ),
    );
  }

  /// Engine label for the model pill (same rules as chat).
  String _engineLabel() {
    final s = Get.find<SettingsController>();
    if (s.inferenceMode.value == 'cloud') {
      final m = s.selectedCloudModelName;
      if (m.isEmpty) return 'Cloud';
      final short = m.contains('/') ? m.split('/').last : m;
      return short.length > 14 ? '${short.substring(0, 14)}…' : short;
    }
    String name = '';
    try {
      final inf = Get.find<InferenceService>();
      if (inf.isModelLoaded.value) name = inf.loadedModelName.value;
    } catch (_) {}
    if (name.isEmpty) {
      try {
        final img = Get.find<LocalImageService>();
        if (img.isModelLoaded.value) name = img.loadedModelName.value;
      } catch (_) {}
    }
    if (name.isEmpty) return 'Local';
    final stripped = name.replaceAll(
        RegExp(r'\.(gguf|litertlm|safetensors)$', caseSensitive: false), '');
    return stripped.length > 14 ? '${stripped.substring(0, 14)}…' : stripped;
  }

  /// Compact style picker pill.
  Widget _stylePill(BuildContext context, bool isDark) {
    return PopupMenuButton<String>(
      enabled: !c.generating.value,
      tooltip: 'Slide style',
      initialValue: c.style.value,
      onSelected: (v) => c.style.value = v,
      itemBuilder: (_) => [
        for (final s in SlideDeckController.styles)
          PopupMenuItem(
            value: s,
            child: Text(s, style: GoogleFonts.plusJakartaSans(fontSize: 14)),
          ),
      ],
      child: Container(
        height: Dt.pillHeight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Dt.pillMuted,
          borderRadius: BorderRadius.circular(Dt.pillHeight),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                c.style.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Dt.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.expand_more_rounded,
                size: 16, color: Dt.textSecondary),
          ],
        ),
      ),
    );
  }

  /// Compact slide-count stepper.
  Widget _countStepper(BuildContext context, bool isDark) {
    final disabled = c.generating.value;
    return Container(
      height: Dt.pillHeight,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Dt.pillMuted,
        borderRadius: BorderRadius.circular(Dt.pillHeight),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: disabled ? null : () => c.setCount(c.slideCount.value - 1),
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.remove,
                  size: 15,
                  color: disabled ? Dt.textPlaceholder : Dt.textPrimary),
            ),
          ),
          Text('${c.slideCount.value}',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5, fontWeight: FontWeight.w800)),
          InkWell(
            onTap: disabled ? null : () => c.setCount(c.slideCount.value + 1),
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.add,
                  size: 15,
                  color: disabled ? Dt.textPlaceholder : Dt.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  /// Compact audience-targeting pill with common presets.
  static const _audiences = [
    'General',
    'Investors',
    'Students',
    'Executives',
    'Engineers',
    'Marketing',
    'Clients',
    'Team',
  ];

  Widget _audiencePill(BuildContext context, bool isDark) {
    final current = c.audience.value;
    final label = current.isEmpty ? 'Audience' : current;
    return PopupMenuButton<String>(
      enabled: !c.generating.value,
      tooltip: 'Target audience',
      initialValue: current.isEmpty ? null : current,
      onSelected: (v) => c.audience.value = v == 'General' ? '' : v,
      itemBuilder: (_) => [
        for (final a in _audiences)
          PopupMenuItem(
            value: a,
            child: Text(a, style: GoogleFonts.plusJakartaSans(fontSize: 13)),
          ),
      ],
      child: Container(
        height: Dt.pillHeight,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: current.isNotEmpty
              ? Dt.accent.withValues(alpha: 0.12)
              : Dt.pillMuted,
          borderRadius: BorderRadius.circular(Dt.pillHeight),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.users,
                size: 13,
                color: current.isNotEmpty ? Dt.accent : Dt.textSecondary),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: current.isNotEmpty ? Dt.accent : Dt.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleSpeech() async {
    if (!_isListening) {
      bool available = await _stt.initialize();
      if (available) {
        setState(() => _isListening = true);
        _stt.listen(onResult: (val) {
          setState(() {
            _topicCtrl.text = val.recognizedWords;
            c.topic.value = val.recognizedWords;
          });
        });
      }
    } else {
      setState(() => _isListening = false);
      _stt.stop();
    }
  }

  void _showThemePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Slide Deck Theme',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              children: [
                _themeColorPill('Modern', '#d97757'),
                _themeColorPill('Forest', '#4ade80'),
                _themeColorPill('Ocean', '#60a5fa'),
                _themeColorPill('Royal', '#a78bfa'),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _themeColorPill(String name, String color) {
    final hex = int.parse(color.replaceAll('#', '0xFF'));
    return InkWell(
      onTap: () {
        c.theme.value = SlideDeckTheme(
          name: name,
          primaryColor: color,
          secondaryColor: '#ffffff',
          backgroundColor: '#14141c',
          textColor: '#f2f0ea',
          accentColor: color,
          fontHeading: 'Plus Jakarta Sans',
          fontBody: 'Plus Jakarta Sans',
        );
        Navigator.pop(context);
      },
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Color(hex),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
          const SizedBox(height: 4),
          Text(name, style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }

  Future<void> _pickTemplate(String templateName) async {
    if (_topicCtrl.text.trim().isEmpty) {
      _topicCtrl.text =
          templateName.replaceFirst(RegExp(r'^[^\w\s]+\s*'), '').trim();
      c.topic.value = _topicCtrl.text;
    }
    await c.generateFromTemplate(templateName);
    _page = 0;
    if (_pageCtrl.hasClients) {
      _pageCtrl.jumpToPage(0);
    }
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
      // One-click restyle button
      PopupMenuButton<String>(
        tooltip: 'Restyle deck',
        enabled: !c.generating.value,
        onSelected: (v) => c.restyleDeck(v),
        itemBuilder: (_) => [
          for (final s in SlideDeckController.styles)
            PopupMenuItem(
              value: s,
              child: Text(s, style: GoogleFonts.plusJakartaSans(fontSize: 13)),
            ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Dt.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(LucideIcons.palette, size: 14, color: Dt.accent),
            const SizedBox(width: 4),
            Text('Restyle',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Dt.accent)),
          ]),
        ),
      ),
      const SizedBox(width: 6),
      IconButton(
        tooltip: 'Theme settings',
        icon: const Icon(LucideIcons.settings2, size: 18),
        onPressed: () => _showThemePicker(context),
      ),
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
          onSelectionChanged: (s) => setState(() => _viewMode = s.first),
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.compact,
          ),
        ),
      ),
      const SizedBox(height: 10),
      // Thumbnail strip for quick navigation
      if (c.slides.length > 1)
        SizedBox(
          height: 48,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: c.slides.length,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemBuilder: (_, i) {
              final ts = c.slides[i];
              final active = i == _page;
              return GestureDetector(
                onTap: () {
                  setState(() => _page = i);
                  _pageCtrl.jumpToPage(i);
                },
                child: Container(
                  width: 64,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surface : Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: active
                          ? Dt.accent
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Dt.hairline),
                      width: active ? 2 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('${i + 1}',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: active ? Dt.accent : Dt.textSecondary)),
                      const SizedBox(height: 2),
                      Text(ts.layout.substring(0, 4),
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 8, color: Dt.textPlaceholder)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      const SizedBox(height: 8),
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

  Widget _slideCard(BuildContext context, bool isDark, int index, Slide s) {
    final busy = c.generating.value && c.regenIndex.value == index;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.07) : Dt.hairline),
      ),
      // Scrollable: notes + image controls can exceed the fixed
      // PageView viewport on small screens — scroll instead of overflow.
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('SLIDE ${index + 1}',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: Dt.accent)),
            if (s.speakerNotes.isNotEmpty) ...[
              const SizedBox(width: 6),
              const Tooltip(
                message: 'Has speaker notes',
                child: Icon(LucideIcons.mic, size: 12, color: Dt.accent),
              ),
            ],
            if (s.citations.isNotEmpty) ...[
              const SizedBox(width: 6),
              const Tooltip(
                message: 'Has citations',
                child: Icon(LucideIcons.scroll, size: 12, color: Dt.accent),
              ),
            ],
            const Spacer(),
            if (busy)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else ...[
              _miniBtn(context, LucideIcons.pencil, 'Edit slide',
                  () => showEditDialog(context, isDark, index, s)),
              _miniBtn(context, LucideIcons.move, 'Free layout',
                  () => _toggleFreeLayout(index, s),
                  color: s.freeLayout ? Dt.accent : null),
              _miniBtn(context, LucideIcons.refreshCw, 'Regenerate this slide',
                  () => c.regenerateSlide(index)),
              _miniBtn(context, LucideIcons.sparkles, 'AI refine',
                  () => showRefineDialog(context, isDark, index)),
              _miniBtn(
                  context,
                  LucideIcons.copy,
                  'Duplicate slide',
                  c.slides.length >= SlideDeckController.maxSlides
                      ? null
                      : () => c.duplicateSlide(index)),
              _miniBtn(context, LucideIcons.arrowUp, 'Move up',
                  index == 0 ? null : () => c.moveSlide(index, -1)),
              _miniBtn(
                  context,
                  LucideIcons.arrowDown,
                  'Move down',
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
          if (s.citations.isNotEmpty) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: s.citations
                    .map((c) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ActionChip(
                            label: Text(c.source, style: const TextStyle(fontSize: 10)),
                            padding: EdgeInsets.zero,
                            onPressed: () {},
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
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
      ),
    );
  }

  /// PowerPoint-like 4:3 stage: gradient backdrop, image banner or
  /// reserved placeholder, compact title + bullets. Overflow-safe by
  /// construction (fixed line budgets + ellipsis).
  /// [mode]: ppt (dark 4:3 stage) · docs (light paper flow) ·
  /// pdf (light A4 portrait page).
  Widget _slideCanvas(BuildContext context, int index, Slide s, String mode) {
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
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (hasImage)
                  SizedBox(
                    height: 110,
                    child: Image.memory(
                      Uint8List.fromList(s.imageBytes!),
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(height: 110),
                    ),
                  )
                else if (s.wantsImage)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: Dt.accent.withValues(alpha: 0.12),
                      border: const Border(
                        bottom: BorderSide(color: Dt.accent, width: 1),
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
                    child: Stack(
                      children: [
                        _pptContentByLayout(s, index, showPoints, hidden),
                        Align(
                          alignment: Alignment.bottomRight,
                          child: Text('${index + 1}',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF6E6B65))),
                        ),
                      ],
                    ),
                  ),
                ),
              ]),
      ),
    );
  }

  Widget _pptContentByLayout(
      Slide s, int index, List<String> showPoints, int hidden) {
    switch (s.layout) {
      case 'title':
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                s.title.isEmpty ? 'Untitled' : s.title,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                    color: Colors.white),
              ),
              if (s.subtitle.isNotEmpty || showPoints.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                    width: 36,
                    height: 2.5,
                    decoration: BoxDecoration(
                        color: Dt.accent,
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 8),
                Text(
                  s.subtitle.isNotEmpty ? s.subtitle : showPoints.first,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFFD8D5CF)),
                ),
              ],
            ],
          ),
        );

      case 'quote':
        final quoteText = s.points.isNotEmpty ? s.points.first : s.title;
        final author = s.quoteAuthor.isNotEmpty
            ? s.quoteAuthor
            : (s.points.length > 1 ? s.points[1] : '');
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(LucideIcons.quote, size: 24, color: Dt.accent),
              const SizedBox(height: 8),
              Text(
                '"$quoteText"',
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14.5,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                    color: Colors.white),
              ),
              if (author.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '— $author',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Dt.accent),
                ),
              ],
            ],
          ),
        );

      case 'stats':
        final statsItems = s.stats.isNotEmpty
            ? s.stats
            : s.points.take(3).map((p) {
                final match =
                    RegExp(r'^([\d%+\$\.\s\w]+)[:\-–]\s*(.+)$').firstMatch(p);
                if (match != null) {
                  return {
                    'value': match.group(1)!.trim(),
                    'label': match.group(2)!.trim()
                  };
                }
                return {'value': '•', 'label': p};
              }).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.title.isEmpty ? 'Key Statistics' : s.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.white),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Row(
                children: [
                  for (final item in statsItems.take(3))
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2.5),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Dt.accent.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              item['value'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: Dt.accent),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              item['label'] ?? '',
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 9.5,
                                  color: const Color(0xFFD8D5CF)),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );

      case 'comparison':
        final col1 = s.columns.isNotEmpty
            ? s.columns[0]
            : s.points.take((s.points.length / 2).ceil()).toList();
        final col2 = s.columns.length > 1
            ? s.columns[1]
            : s.points.skip((s.points.length / 2).ceil()).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.title.isEmpty ? 'Comparison' : s.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.white),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final p in col1.take(3))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text('• $p',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 10,
                                      color: const Color(0xFFD8D5CF))),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Dt.accent.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: Dt.accent.withValues(alpha: 0.25)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final p in col2.take(3))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text('✓ $p',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 10,
                                      color: const Color(0xFFE8B4A0))),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

      case 'timeline':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.title.isEmpty ? 'Timeline' : s.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.white),
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < showPoints.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Dt.accent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${i + 1}',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        showPoints[i],
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 10.5, color: const Color(0xFFD8D5CF)),
                      ),
                    ),
                  ],
                ),
              ),
            if (hidden > 0)
              Text('+$hidden more steps',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF8E8B85))),
          ],
        );

      case 'summary':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.checkCircle2,
                    size: 15, color: Dt.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    s.title.isEmpty ? 'Key Takeaways' : s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final p in showPoints)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('✓ ',
                        style: TextStyle(
                            color: Dt.accent,
                            fontWeight: FontWeight.w900,
                            fontSize: 10.5)),
                    Expanded(
                      child: Text(p,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 10.5,
                              height: 1.35,
                              color: const Color(0xFFD8D5CF))),
                    ),
                  ],
                ),
              ),
            if (hidden > 0)
              Text('+$hidden more',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF8E8B85))),
          ],
        );

      case 'chart':
        return chartContent(s);

      case 'diagram':
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                s.title.isEmpty ? 'Process Flow' : s.title,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: CustomPaint(
                  painter: DiagramPainter(s.diagram ?? '', true),
                  size: Size.infinite,
                ),
              ),
            ],
          ),
        );

      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.title.isEmpty ? 'Untitled' : s.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  color: Colors.white),
            ),
            const SizedBox(height: 6),
            for (final p in showPoints)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('▸ ',
                        style: TextStyle(
                            color: Dt.accent,
                            fontWeight: FontWeight.w800,
                            fontSize: 11)),
                    Expanded(
                      child: Text(p,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              height: 1.35,
                              color: const Color(0xFFD8D5CF))),
                    ),
                  ],
                ),
              ),
            if (hidden > 0)
              Text('+$hidden more',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF8E8B85))),
          ],
        );
    }
  }

  /// Pure-Flutter chart renderer: bar, donut, or line from chartData.

  /// Docs mode: light paper, continuous flow (all content visible).
  Widget _docsCanvas(BuildContext context, int index, Slide s) {
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
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                    color: Dt.accent, borderRadius: BorderRadius.circular(2))),
            ...layoutBodyWidgets(s, s.wantsImage),
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
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                        titleColor: const Color(0xFF111111),
                        bodyColor: const Color(0xFF333333),
                        titleBase: 16,
                        bodyBase: 11,
                      ),
                    )
                  : SingleChildScrollView(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ...layoutBodyWidgets(s, s.wantsImage,
                                fontSize: 12,
                                bulletColor: const Color(0xFF555555),
                                textColor: const Color(0xFF222222)),
                          ]),
                    ),
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: Text('${index + 1} / $total',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 10, color: const Color(0xFFAAAAAA))),
            ),
          ]),
        ),
      ),
    );
  }

  /// Image generate/retry row under the canvas (full editor lives here;
  /// the canvas only previews).
  Widget _imageControls(BuildContext context, int index, Slide s) {
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
      FreeBox(
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
      FreeBox(
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
        FreeBox(
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
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
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

  Widget _miniBtn(
      BuildContext context, IconData icon, String tip, VoidCallback? onTap,
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
}
