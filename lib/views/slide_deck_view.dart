import 'dart:io';
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
import '../utils/slide_palette.dart';
import '../services/app_log_service.dart';
import '../widgets/slide_source_selector.dart';
import 'slides/slide_charts.dart';
import 'slides/slide_canvas.dart';
import 'slides/slide_dialogs.dart';
import 'slides/slide_outline_view.dart';
import 'slides/slide_present_view.dart';
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
    AppLogService.trackScreen('Slide Maker');
    c = Get.isRegistered<SlideDeckController>()
        ? Get.find<SlideDeckController>()
        : Get.put(SlideDeckController());
    _topicCtrl.text = c.topic.value;
  }

  @override
  void dispose() {
    AppLogService.untrackScreen('Slide Maker');
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
              ? Row(
                  children: [
                    // Adaptive Content: Resize
                    _miniBtn(context, LucideIcons.scaling, 'Resize deck',
                        () => _showResizeDialog(context)),
                    const SizedBox(width: 4),
                    // TOC generation
                    _miniBtn(context, LucideIcons.list, 'Generate TOC',
                        c.generateTOC),
                    const SizedBox(width: 4),
                    // One-click restyle button
                    PopupMenuButton<String>(
                      tooltip: 'Restyle deck',
                      enabled: !c.generating.value,
                      onSelected: (v) => c.restyleDeck(v),
                      icon: const Icon(LucideIcons.palette, size: 20),
                      itemBuilder: (_) => [
                        for (final s in SlideDeckController.styles)
                          PopupMenuItem(
                            value: s,
                            child: Text(s,
                                style: GoogleFonts.plusJakartaSans(fontSize: 13)),
                          ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Theme settings',
                      icon: const Icon(LucideIcons.settings2, size: 20),
                      onPressed: () => _showThemePicker(context),
                    ),
                    const SizedBox(width: 4),
                    PopupMenuButton<String>(
                      tooltip: 'AI Tools',
                      icon: const Icon(LucideIcons.sparkles, size: 20),
                      onSelected: (v) {
                        if (v == 'polish') c.polishDesign();
                        if (v == 'translate') _showTranslateDialog(context);
                        if (v == 'live') _showLiveDataDialog(context);
                        if (v == 'url') _showUrlDialog(context);
                        if (v == 'audit') c.auditDeck();
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'polish', child: Text('Polish Design')),
                        const PopupMenuItem(
                            value: 'translate', child: Text('Translate Deck')),
                        const PopupMenuItem(
                            value: 'live', child: Text('Inject Live Data')),
                        const PopupMenuItem(
                            value: 'url', child: Text('Generate from URL')),
                        const PopupMenuItem(
                            value: 'audit', child: Text('Audit Deck')),
                      ],
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Clear deck',
                      icon: Icon(LucideIcons.trash2,
                          size: 20,
                          color: AppColors.error.withValues(alpha: 0.8)),
                      onPressed: c.clearDeck,
                    ),
                    const SizedBox(width: 4),
                    PopupMenuButton<String>(
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
                    ),
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
              Flexible(child: Obx(() => _visualStylePill(context, isDark))),
              const SizedBox(width: 6),
              Flexible(child: Obx(() => _countStepper(context, isDark))),
              const Spacer(),
              Flexible(child: Obx(() => _audiencePill(context, isDark))),
            ],
          ),
          const SizedBox(height: 6),
          // Vision input
          Obx(() => _visionPill(context, isDark)),
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

  Widget _visualStylePill(BuildContext context, bool isDark) {
    return PopupMenuButton<String>(
      enabled: !c.generating.value,
      tooltip: 'Visual style',
      initialValue: c.visualStyle.value,
      onSelected: (v) => c.visualStyle.value = v,
      itemBuilder: (_) => [
        for (final s in SlideDeckController.visualStyles)
          PopupMenuItem(
            value: s,
            child: Text(s, style: GoogleFonts.plusJakartaSans(fontSize: 13)),
          ),
      ],
      child: Container(
        height: Dt.pillHeight,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: c.visualStyle.value != 'Professional'
              ? Dt.accent.withValues(alpha: 0.12)
              : Dt.pillMuted,
          borderRadius: BorderRadius.circular(Dt.pillHeight),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.palette,
                size: 13,
                color: c.visualStyle.value != 'Professional' ? Dt.accent : Dt.textSecondary),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                c.visualStyle.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: c.visualStyle.value != 'Professional' ? Dt.accent : Dt.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _visionPill(BuildContext context, bool isDark) {
    final hasImg = c.inputImage.value != null;
    return InkWell(
      onTap: c.generating.value ? null : _pickInputImage,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: hasImg ? Dt.accent.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: hasImg ? Border.all(color: Dt.accent.withValues(alpha: 0.3)) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(hasImg ? LucideIcons.badgeCheck : LucideIcons.imagePlus,
                size: 14, color: hasImg ? Dt.accent : Dt.textSecondary),
            const SizedBox(width: 6),
            Text(
              hasImg ? 'Sketch/Photo attached' : 'Attach Sketch for Vision',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: hasImg ? Dt.accent : Dt.textSecondary),
            ),
            if (hasImg) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => c.inputImage.value = null,
                child: const Icon(LucideIcons.x, size: 14, color: AppColors.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickInputImage() async {
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
      final file = await ImagePicker().pickImage(source: source);
      if (file != null) {
        c.inputImage.value = File(file.path);
      }
    } catch (_) {}
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
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Slide Deck Theme',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Instant — no AI re-generate, content untouched.',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5, color: Theme.of(context).hintColor)),
            const SizedBox(height: 12),
            Obx(() => Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final t in SlideThemePresets.all)
                      _themePresetCard(ctx, t,
                          selected: c.theme.value.name == t.name),
                  ],
                )),
            const Divider(height: 24),
            Text('Brand Kit',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Obx(() => Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Dt.pillMuted,
                    borderRadius: BorderRadius.circular(8),
                    image: c.theme.value.logoBytes != null
                        ? DecorationImage(image: MemoryImage(Uint8List.fromList(c.theme.value.logoBytes!)))
                        : null,
                  ),
                  child: c.theme.value.logoBytes == null
                      ? const Icon(LucideIcons.image, size: 20)
                      : null,
                )),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: _pickLogo,
                  icon: const Icon(LucideIcons.upload, size: 16),
                  label: const Text('Upload Logo'),
                ),
                if (c.theme.value.logoBytes != null)
                  IconButton(
                    onPressed: () => _updateTheme(logo: []),
                    icon: const Icon(LucideIcons.trash2, size: 16, color: AppColors.error),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _pickLogo() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file != null) {
        final bytes = await file.readAsBytes();
        _updateTheme(logo: bytes.toList());
      }
    } catch (_) {}
  }

  void _showTranslateDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Translate Deck'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'Target language (e.g. Spanish, Bengali)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (ctrl.text.isNotEmpty) {
                c.translateDeck(ctrl.text);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Translate'),
          ),
        ],
      ),
    );
  }

  void _showLiveDataDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Inject Live Data'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'What to find? (e.g. Apple stock price)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (ctrl.text.isNotEmpty) {
                c.injectLiveData(ctrl.text);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Inject'),
          ),
        ],
      ),
    );
  }

  void _showUrlDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Generate from URL'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'https://example.com/article'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (ctrl.text.isNotEmpty) {
                c.generateFromUrl(ctrl.text);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Generate'),
          ),
        ],
      ),
    );
  }

  void _updateTheme({List<int>? logo}) {
    final old = c.theme.value;
    c.theme.value = SlideDeckTheme(
      name: old.name,
      primaryColor: old.primaryColor,
      secondaryColor: old.secondaryColor,
      backgroundColor: old.backgroundColor,
      textColor: old.textColor,
      accentColor: old.accentColor,
      fontHeading: old.fontHeading,
      fontBody: old.fontBody,
      logoBytes: logo ?? old.logoBytes,
    );
  }

  void _showResizeDialog(BuildContext context) {
    final ctrl = TextEditingController(text: '${c.slides.length}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resize Deck'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter target slide count (AI will merge/split slides):'),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'e.g. 5'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final count = int.tryParse(ctrl.text);
              if (count != null && count >= 3 && count <= 20) {
                c.resizeDeck(count);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Resize'),
          ),
        ],
      ),
    );
  }

  Widget _themePresetCard(
      BuildContext sheetCtx, SlideDeckTheme t, {required bool selected}) {
    final pal = SlidePalette.fromTheme(t);
    return InkWell(
      onTap: () {
        c.applyThemePreset(t.name);
        Navigator.pop(sheetCtx);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 96,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? Dt.accent : Theme.of(context).dividerColor,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 44,
              decoration: BoxDecoration(
                color: pal.bg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: pal.accent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(t.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 10.5, fontWeight: FontWeight.w700)),
          ],
        ),
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
      IconButton(
        tooltip: 'Present fullscreen',
        icon: const Icon(LucideIcons.play, size: 18),
        onPressed: () => Get.to(() => SlidePresentView(
              slides: c.slides.toList(),
              theme: c.theme.value,
              initialIndex: _page.clamp(0, c.slides.length - 1),
            )),
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
              PopupMenuButton<String>(
                tooltip: 'Transform layout',
                icon: const Icon(LucideIcons.layout, size: 16, color: Dt.textSecondary),
                onSelected: (v) => c.transformLayout(index, v),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'cards', child: Text('Feature Cards')),
                  const PopupMenuItem(value: 'gallery', child: Text('Image Gallery')),
                  const PopupMenuItem(value: 'stats', child: Text('Key Stats')),
                  const PopupMenuItem(value: 'timeline', child: Text('Timeline')),
                ],
              ),
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
    // Touch the observable so one-click theme presets rebuild the canvas.
    final pal = SlidePalette.fromTheme(c.theme.value);
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: SlideCanvas(
        slide: s,
        index: index,
        pal: pal,
        logoBytes: c.theme.value.logoBytes,
      ),
    );
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
                      builder: (_, cons) => SlideCanvas.freeStack(
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
    final hasImage = (s.imageBytes != null && s.imageBytes!.isNotEmpty) || (s.imageUrl != null && s.imageUrl!.isNotEmpty);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (s.wantsImage || hasImage) ...[
          _chipButton(
            context,
            icon: hasImage ? LucideIcons.refreshCw : LucideIcons.sparkles,
            label: hasImage
                ? 'Regenerate AI image'
                : (c.canGenerateImages
                    ? 'Generate AI image'
                    : 'No AI image engine'),
            busy: c.imageBusyIndex.value == index,
            onTap: c.imageBusyIndex.value == index
                ? null
                : () => c.generateSlideImage(index),
          ),
          _chipButton(
            context,
            icon: LucideIcons.search,
            label: 'Find Stock Photo',
            busy: c.stockImageBusyIndex.value == index,
            onTap: c.stockImageBusyIndex.value == index
                ? null
                : () => c.findStockImage(index),
          ),
        ],
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
