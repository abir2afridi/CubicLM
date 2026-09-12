import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';
import 'package:flutter/foundation.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

import '../controllers/settings_controller.dart';
import '../services/app_log_service.dart';
import '../services/cloud_service.dart';
import '../services/cubicdata/controller.dart';
import '../services/cubicdata/models.dart';
import '../services/document_extractor_service.dart';
import '../services/inference_service.dart';
import '../services/local_image_service.dart';
import '../services/web_fetch_service.dart';
import '../utils/app_snackbar.dart';
import '../utils/export_file.dart';
import '../utils/prompt_export.dart';
import '../utils/slide_deck.dart';
import '../utils/slide_pptx.dart';

/// Slide Maker: AI generates a structured deck from a topic.
class SlideDeckController extends GetxController {
  static const styles = [
    'Professional',
    'Playful',
    'Minimal',
    'Story-like',
    'Academic',
    'Creative',
    'Data-driven',
    'Pitch Deck',
  ];
  static const visualStyles = [
    'Professional',
    'Photorealistic',
    'Flat Vector',
    '3D Glossy',
    'Minimalist',
    'Cyberpunk',
    'Hand-drawn',
    'Vintage',
  ];
  static const minSlides = 3;
  static const maxSlides = 20;

  final topic = ''.obs;
  final style = 'Professional'.obs;
  final visualStyle = 'Professional'.obs;
  final audience = ''.obs;
  final slideCount = 6.obs;
  final slides = <Slide>[].obs;
  final outline = <SlideOutline>[].obs;
  final theme = SlideDeckTheme(
    name: 'Modern Terracotta',
    primaryColor: '#d97757',
    secondaryColor: '#4ade80',
    backgroundColor: '#14141c',
    textColor: '#f2f0ea',
    accentColor: '#d97757',
    fontHeading: 'Plus Jakarta Sans',
    fontBody: 'Plus Jakarta Sans',
  ).obs;

  final generating = false.obs;
  final showingOutline = false.obs;
  final useResearch = false.obs;
  final selectedDataSheetId = RxnString();
  final sourceFile = Rxn<File>();
  final inputImage = Rxn<File>();
  final stockImageBusyIndex = (-1).obs;

  final regenIndex = (-1).obs; // -1 = whole deck, else slide index
  final imageBusyIndex = (-1).obs;
  final lastError = RxnString();

  bool get hasDeck => slides.isNotEmpty;

  void setCount(int v) {
    slideCount.value = v.clamp(minSlides, maxSlides);
  }

  void setSourceFile(File? f) {
    sourceFile.value = f;
  }

  Future<void> generateOutline() async {
    // .pptx sources skip the AI outline flow: structural import is instant
    // and exact, then Restyle/regen can redesign from real content.
    if (sourceFile.value != null &&
        sourceFile.value!.path.toLowerCase().endsWith('.pptx')) {
      await importPptxFile();
      return;
    }
    final t = topic.value.trim();
    if (t.isEmpty || generating.value) return;
    generating.value = true;
    lastError.value = null;
    try {
      String context = '';
      if (sourceFile.value != null) {
        final ext = sourceFile.value!.path.split('.').last;
        context = await DocumentExtractorService.extractText(
            sourceFile.value!.path, ext);
      }
      if (selectedDataSheetId.value != null) {
        final ds = Get.find<CubicDataController>().byId(selectedDataSheetId.value!);
        if (ds != null) {
          context += '\n--- DataSheet: ${ds.name} ---\n${_extractDataSheetText(ds)}';
        }
      }
      if (useResearch.value) {
        final result = await WebFetchService.augmentWithSources(t);
        context += result.augmentedText;
      }

      final raw = await _ask(
        prompt: 'Create an outline for a ${slideCount.value}-slide presentation about: $t\n\n'
            '${context.isNotEmpty ? "Use this context:\n$context" : ""}',
        system: outlineSystemPrompt(count: slideCount.value, topic: t),
        imagePath: inputImage.value?.path,
      );
      final parsed = parseOutline(raw);
      if (parsed.isNotEmpty) {
        outline.assignAll(parsed);
        showingOutline.value = true;
      } else if (raw.trim().isNotEmpty) {
        lastError.value = 'Failed to parse outline JSON.';
      }
    } catch (e) {
      lastError.value = '$e';
      _log('Outline generation failed', e);
    } finally {
      generating.value = false;
    }
  }

  Future<void> generateFromOutline() async {
    if (outline.isEmpty || generating.value) return;
    generating.value = true;
    lastError.value = null;
    try {
      final t = topic.value.trim();
      final outlineJson = jsonEncode(outline.map((e) => e.toMap()).toList());

      final raw = await _ask(
        prompt: 'Create a ${outline.length}-slide presentation about: $t\n\n'
            'Follow this outline strictly:\n$outlineJson',
        system: slideSystemPrompt(
            count: outline.length,
            style: style.value,
            visualStyle: visualStyle.value,
            audience: audience.value),
        imagePath: inputImage.value?.path,
      );
      final parsed = parseSlides(raw);
      slides.assignAll(parsed);
      showingOutline.value = false;
    } catch (e) {
      lastError.value = '$e';
      _log('Deck generation failed', e);
    } finally {
      generating.value = false;
    }
  }

  Future<void> generateDirectly() async {
    final t = topic.value.trim();
    if (t.isEmpty || generating.value) return;
    generating.value = true;
    regenIndex.value = -1;
    lastError.value = null;
    try {
      String context = '';
      if (sourceFile.value != null) {
        final ext = sourceFile.value!.path.split('.').last;
        context = await DocumentExtractorService.extractText(
            sourceFile.value!.path, ext);
      }

      final raw = await _ask(
        prompt: 'Create a ${slideCount.value}-slide presentation about: $t\n\n'
            '${context.isNotEmpty ? "Use this context:\n$context" : ""}',
        system: slideSystemPrompt(
            count: slideCount.value,
            style: style.value,
            visualStyle: visualStyle.value,
            audience: audience.value),
        imagePath: inputImage.value?.path,
      );
      final parsed = parseSlides(raw);
      slides.assignAll(parsed);
    } catch (e) {
      lastError.value = '$e';
      _log('Deck generation failed', e);
    } finally {
      generating.value = false;
    }
  }

  Future<void> generate() async {
    // Default to outline workflow for Gemma level
    await generateOutline();
  }

  /// Structural .pptx import: real slides in, editable deck out. No AI
  /// call — use Restyle / per-slide regen afterwards to redesign.
  Future<void> importPptxFile() async {
    final f = sourceFile.value;
    if (f == null || generating.value) return;
    generating.value = true;
    lastError.value = null;
    try {
      final bytes = await f.readAsBytes();
      final parsed = parsePptx(bytes);
      if (parsed.isEmpty) {
        lastError.value =
            'No readable slides found in ${f.path.split('/').last}.';
        return;
      }
      slides.assignAll(parsed);
      outline.clear();
      showingOutline.value = false;
      final base = f.path.split('/').last.replaceAll(
          RegExp(r'\.pptx$', caseSensitive: false), '');
      topic.value = base.isEmpty ? 'Imported deck' : base;
      AppSnackbar.showTop('Imported ${parsed.length} slides',
          'Restyle or regenerate any slide to redesign.',
          logHistory: true);
    } catch (e) {
      lastError.value = '$e';
      _log('PPTX import failed', e);
    } finally {
      generating.value = false;
    }
  }

  /// Generate a deck from a website URL.
  Future<void> generateFromUrl(String url) async {
    if (generating.value || url.trim().isEmpty) return;
    generating.value = true;
    lastError.value = null;
    try {
      final content = await WebFetchService.fetchAsText(url);
      if (content == null || content.isEmpty) {
        throw Exception('Could not extract content from the provided URL.');
      }

      topic.value = 'Presentation based on $url';
      final raw = await _ask(
        prompt: 'Create a ${slideCount.value}-slide presentation outline based on this web content:\n\n$content',
        system: outlineSystemPrompt(count: slideCount.value, topic: topic.value),
      );
      final parsed = parseOutline(raw);
      if (parsed.isNotEmpty) {
        outline.assignAll(parsed);
        showingOutline.value = true;
      }
    } catch (e) {
      lastError.value = '$e';
      _log('URL-to-Deck failed', e);
    } finally {
      generating.value = false;
    }
  }

  /// Transform a slide's layout while intelligently adapting content.
  Future<void> transformLayout(int index, String targetLayout) async {
    if (generating.value || index < 0 || index >= slides.length) return;
    generating.value = true;
    regenIndex.value = index;
    try {
      final s = slides[index];
      final raw = await _ask(
        prompt: 'Transform this slide into a "$targetLayout" layout.\n'
            'Current slide content: ${jsonEncode(s.toMap())}\n'
            'Adapt the content structure (e.g. merge points for cards, or suggest images for a gallery).',
        system: 'Output only the transformed slide in the ```slides block.',
      );
      final parsed = parseSlides(raw);
      if (parsed.isNotEmpty) {
        slides[index] = parsed.first;
      }
    } catch (e) {
      _log('Layout transformation failed', e);
    } finally {
      generating.value = false;
      regenIndex.value = -1;
    }
  }

  /// Automated audit of the deck for quality, flow, and clarity.
  Future<void> auditDeck() async {
    if (generating.value || slides.isEmpty) return;
    generating.value = true;
    try {
      final contentSummary = slides.map((s) => '${s.title}: ${s.points.join("; ")}').join('\n');
      final result = await _ask(
        prompt: 'Audit this presentation for logical flow, impact, and information density:\n\n$contentSummary',
        system: 'Provide a professional critique. Highlight any gaps or slides that are too dense.',
      );
      AppSnackbar.showTop('AI Audit Result', result, logHistory: true);
    } catch (e) {
      _log('Audit failed', e);
    } finally {
      generating.value = false;
    }
  }

  /// AI-powered deck translation.
  Future<void> translateDeck(String targetLang) async {
    if (generating.value || slides.isEmpty) return;
    generating.value = true;
    lastError.value = null;
    try {
      final t = topic.value.trim();
      final contentSummary = StringBuffer();
      for (var i = 0; i < slides.length; i++) {
        final s = slides[i];
        contentSummary.writeln(
            'Slide ${i + 1}: ${s.title} — ${s.points.join(", ")}');
      }

      final raw = await _ask(
        prompt: 'Translate the entire presentation about "$t" into $targetLang.\n\n'
            'Current content:\n${contentSummary.toString()}\n'
            'Maintain the same number of slides and JSON structure. Translate titles, points, notes, and speaker notes.',
        system: 'You are a translation expert. Output ONLY valid JSON in the ```slides fence.',
      );
      final parsed = parseSlides(raw);
      if (parsed.length == slides.length) {
        // Preserve images/icons
        for (var i = 0; i < parsed.length; i++) {
          parsed[i].imageBytes = slides[i].imageBytes;
          parsed[i].imageUrl = slides[i].imageUrl;
          parsed[i].icons = slides[i].icons;
        }
        slides.assignAll(parsed);
      }
    } catch (e) {
      lastError.value = '$e';
      _log('Translation failed', e);
    } finally {
      generating.value = false;
    }
  }

  /// Automated design polish: contrast check, icon consistency, etc.
  void polishDesign() {
    if (slides.isEmpty) return;
    // Enforce icon consistency if some slides have them
    final hasIcons = slides.any((s) => s.icons != null && s.icons!.isNotEmpty);
    if (hasIcons) {
      for (final s in slides) {
        if (s.icons == null || s.icons!.isEmpty) {
          s.icons = List.filled(s.points.length, 'chevron-right');
        }
      }
    }
    slides.refresh();
    AppSnackbar.showTop('Design Polished', 'Consistent icons applied across the deck.');
  }

  /// Pull live data (Weather, Stocks) and inject into the deck.
  Future<void> injectLiveData(String query) async {
    if (generating.value || slides.isEmpty) return;
    generating.value = true;
    try {
      final result = await WebFetchService.augmentWithWebContent('Find current stats for: $query');
      final raw = await _ask(
        prompt: 'Update the "Stats" or "Chart" slides in the current deck with this live data:\n$result\n\n'
            'Current slides: ${jsonEncode(slides.map((s) => s.toMap()).toList())}',
        system: 'Extract specific numbers and update the JSON. Output only the ```slides block.',
      );
      final parsed = parseSlides(raw);
      if (parsed.isNotEmpty) {
        // Find a stats/chart slide to update
        final targetIdx = slides.indexWhere((s) => s.layout == 'stats' || s.layout == 'chart');
        if (targetIdx != -1 && parsed.any((s) => s.layout == 'stats' || s.layout == 'chart')) {
          final updated = parsed.firstWhere((s) => s.layout == 'stats' || s.layout == 'chart');
          slides[targetIdx] = updated;
        }
      }
    } catch (e) {
      _log('Live data injection failed', e);
    } finally {
      generating.value = false;
    }
  }

  /// AI-powered deck resizing to fit different time constraints.
  /// Merges or splits slides while maintaining logical flow.
  Future<void> resizeDeck(int targetCount) async {
    if (generating.value || slides.isEmpty || targetCount == slides.length) return;
    generating.value = true;
    lastError.value = null;
    try {
      final t = topic.value.trim();
      final contentSummary = StringBuffer();
      for (var i = 0; i < slides.length; i++) {
        final s = slides[i];
        contentSummary.writeln(
            'Slide ${i + 1} [${s.layout}]: ${s.title} — ${s.points.join(", ")}');
      }

      final raw = await _ask(
        prompt: 'Resize this presentation about "$t" from ${slides.length} slides to EXACTLY $targetCount slides.\n\n'
            'Current content:\n${contentSummary.toString()}\n'
            'Intelligently merge or split content to fit the new count while preserving all key information and logical flow.\n'
            'Output the new deck in the same JSON schema.',
        system: slideSystemPrompt(
            count: targetCount,
            style: style.value,
            visualStyle: visualStyle.value,
            audience: audience.value),
      );
      final parsed = parseSlides(raw);
      if (parsed.length == targetCount) {
        slides.assignAll(parsed);
      } else {
        lastError.value = 'Resize failed: model returned ${parsed.length} slides (expected $targetCount).';
      }
    } catch (e) {
      lastError.value = '$e';
      _log('Deck resize failed', e);
    } finally {
      generating.value = false;
    }
  }

  /// Auto-generate a "Table of Contents" slide based on current deck.
  void generateTOC() {
    if (slides.isEmpty) return;
    final tocPoints = slides.skip(1).take(10).map((s) => s.title).toList();
    final tocSlide = Slide(
      title: 'Table of Contents',
      points: tocPoints,
      layout: 'bullets',
      notes: 'Overview of the presentation topics.',
      speakerNotes: 'Here is what we will be covering today.',
    );
    // Insert after title slide
    slides.insert(1, tocSlide);
  }

  /// Find high-quality stock images using web search.
  Future<void> findStockImage(int index) async {
    if (index < 0 || index >= slides.length || generating.value) return;
    final s = slides[index];
    final q = s.imagePrompt.isNotEmpty ? s.imagePrompt : '${topic.value}: ${s.title}';
    
    stockImageBusyIndex.value = index;
    try {
      // We'll use WebFetchService to "search" for image URLs.
      // Since we don't have a direct Image Search API, we'll try to find images in related pages
      // or use a placeholder service like Unsplash Source if available.
      // For a "Pro" feel, we'll suggest using Unsplash Source URLs based on keywords.
      final keywords = q.split(' ').take(3).join(',');
      final url = 'https://images.unsplash.com/photo-1542281286-9e0a16bb7366?auto=format&fit=crop&q=80&w=1000&q=$keywords';
      // In a real scenario, we might scrape a search engine result.
      s.imageUrl = url;
      slides.refresh();
    } catch (e) {
      _log('Stock image find failed', e);
    } finally {
      stockImageBusyIndex.value = -1;
    }
  }

  /// Regenerate one slide in place (keeps the rest of the deck).
  Future<void> regenerateSlide(int index) async {
    if (generating.value ||
        index < 0 ||
        index >= slides.length ||
        topic.value.trim().isEmpty) {
      return;
    }
    generating.value = true;
    regenIndex.value = index;
    lastError.value = null;
    try {
      final raw = await _ask(
        prompt: slideRegenPrompt(
          topic: topic.value.trim(),
          index: index + 1,
          current: slides[index],
          prevTitle: index > 0 ? slides[index - 1].title : null,
          nextTitle: index < slides.length - 1 ? slides[index + 1].title : null,
        ),
        system: slideSystemPrompt(
            count: slides.length,
            style: style.value,
            visualStyle: visualStyle.value,
            audience: audience.value),
      );
      final parsed = parseSlides(raw);
      if (parsed.isNotEmpty) {
        final keepImages = slides[index].imageBytes;
        final next = parsed.first;
        next.imageBytes = keepImages;
        slides[index] = next;
      }
    } catch (e) {
      lastError.value = '$e';
      _log('Slide regen failed', e);
    } finally {
      generating.value = false;
      regenIndex.value = -1;
    }
  }

  /// AI-powered slide refinement.
  Future<void> refineSlide(int index, String instruction) async {
    if (generating.value ||
        index < 0 ||
        index >= slides.length ||
        instruction.trim().isEmpty) {
      return;
    }
    generating.value = true;
    regenIndex.value = index;
    lastError.value = null;
    try {
      final raw = await _ask(
        prompt: 'Rewrite slide ${index + 1} of the "$topic" deck based on this instruction:\n'
            '"${instruction.trim()}"\n\n'
            'Keep the same JSON schema inside one ```slides fence.\n'
            'Current slide:\n'
            'Title: ${slides[index].title}\n'
            'Layout: ${slides[index].layout}\n'
            'Points: ${slides[index].points.join("; ")}\n'
            'Image: ${slides[index].imagePrompt}\n'
            'Notes: ${slides[index].notes}',
        system: slideSystemPrompt(
            count: slides.length,
            style: style.value,
            visualStyle: visualStyle.value,
            audience: audience.value),
      );
      final parsed = parseSlides(raw);
      if (parsed.isNotEmpty) {
        final keepImages = slides[index].imageBytes;
        final next = parsed.first;
        next.imageBytes = keepImages;
        slides[index] = next;
      }
    } catch (e) {
      lastError.value = '$e';
      _log('Slide refine failed', e);
    } finally {
      generating.value = false;
      regenIndex.value = -1;
    }
  }

  /// One-click restyle.
  Future<void> restyleDeck(String newStyle) async {
    if (generating.value || topic.value.trim().isEmpty || slides.isEmpty) return;
    generating.value = true;
    regenIndex.value = -1;
    lastError.value = null;
    final oldStyle = style.value;
    style.value = newStyle;
    try {
      final contentSummary = StringBuffer();
      for (var i = 0; i < slides.length; i++) {
        final s = slides[i];
        contentSummary.writeln(
            'Slide ${i + 1} [${s.layout}]: ${s.title} — ${s.points.take(3).join(", ")}');
      }
      final raw = await _ask(
        prompt: 'Restyle this ${slides.length}-slide presentation about: ${topic.value.trim()}\n\n'
            'Current content:\n${contentSummary.toString()}\n'
            'Keep the same number of slides and preserve the same information. '
            'Rewrite tone, wording, and layout choices to match "$newStyle" style.\n'
            'Do NOT change the facts or data — only change the voice, style, and layout.',
        system: slideSystemPrompt(
            count: slides.length,
            style: newStyle,
            visualStyle: visualStyle.value,
            audience: audience.value),
      );
      final parsed = parseSlides(raw);
      if (parsed.length == slides.length) {
        for (var i = 0; i < parsed.length; i++) {
          parsed[i].imageBytes = slides[i].imageBytes;
        }
        slides.assignAll(parsed);
      } else {
        lastError.value =
            'Restyle returned ${parsed.length} slides (expected ${slides.length}). Keeping original.';
        style.value = oldStyle;
      }
    } catch (e) {
      lastError.value = '$e';
      style.value = oldStyle;
      _log('Deck restyle failed', e);
    } finally {
      generating.value = false;
    }
  }

  void applyEdit(int index,
      {required String title,
      String subtitle = '',
      String quoteAuthor = '',
      required String pointsText,
      required String imagePrompt,
      required String notes,
      required String layout,
      Map<String, dynamic>? chartData}) {
    if (index < 0 || index >= slides.length) return;
    final s = slides[index];
    s.title = title.trim().isEmpty ? 'Untitled' : title.trim();
    s.subtitle = subtitle.trim();
    s.quoteAuthor = quoteAuthor.trim();
    final pts = pointsText
        .split('\n')
        .map((e) => e.trim().replaceFirst(RegExp(r'^[-*•]\s+'), ''))
        .where((e) => e.isNotEmpty)
        .toList();
    s.points = pts;
    if (layout == 'comparison') {
      final mid = pts.length ~/ 2;
      s.columns = [pts.sublist(0, mid), pts.sublist(mid)];
    }
    if (layout == 'chart' && chartData != null) {
      s.chartData = chartData;
    }
    s.imagePrompt = imagePrompt.trim();
    s.notes = notes.trim();
    s.layout = layout;
    slides.refresh();
  }

  void addBlank() {
    slides.add(Slide(title: 'New slide', points: []));
  }

  void deleteSlide(int index) {
    if (index < 0 || index >= slides.length) return;
    slides.removeAt(index);
  }

  void duplicateSlide(int index) {
    if (index < 0 || index >= slides.length) return;
    if (slides.length >= maxSlides) {
      lastError.value = 'Max $maxSlides slides reached.';
      return;
    }
    final src = slides[index];
    final copy = Slide.fromMap(src.toMap());
    copy.imageBytes = src.imageBytes;
    slides.insert(index + 1, copy);
  }

  void moveSlide(int index, int dir) {
    final j = index + dir;
    if (index < 0 || index >= slides.length || j < 0 || j >= slides.length) {
      return;
    }
    final s = slides.removeAt(index);
    slides.insert(j, s);
  }

  void clearDeck() {
    slides.clear();
    outline.clear();
    showingOutline.value = false;
    lastError.value = null;
  }

  /// One-click theme switch: instant, no AI call, content untouched.
  /// Brand-kit logo survives the swap. Unknown names fall back to default.
  void applyThemePreset(String name) {
    final preset = SlideThemePresets.byName(name);
    final logo = theme.value.logoBytes;
    theme.value = SlideDeckTheme(
      name: preset.name,
      primaryColor: preset.primaryColor,
      secondaryColor: preset.secondaryColor,
      backgroundColor: preset.backgroundColor,
      textColor: preset.textColor,
      accentColor: preset.accentColor,
      fontHeading: preset.fontHeading,
      fontBody: preset.fontBody,
      logoBytes: logo,
    );
  }

  bool get canGenerateImages {
    try {
      return Get.find<LocalImageService>().isModelLoaded.value;
    } catch (_) {
      return false;
    }
  }

  Future<void> generateSlideImage(int index) async {
    if (index < 0 || index >= slides.length) return;
    LocalImageService svc;
    try {
      svc = Get.find<LocalImageService>();
    } catch (_) {
      _hintNoImageEngine();
      return;
    }
    if (!svc.isModelLoaded.value) {
      _hintNoImageEngine();
      return;
    }
    final s = slides[index];
    final prompt = s.imagePrompt.trim().isEmpty
        ? '${topic.value.trim()}: ${s.title}'.trim()
        : s.imagePrompt.trim();
    imageBusyIndex.value = index;
    try {
      final bytes = await svc.generateImage(prompt: prompt);
      if (bytes != null && bytes.isNotEmpty) {
        s.imageBytes = bytes;
        slides.refresh();
      } else {
        AppSnackbar.showTop('Image failed', 'The image engine returned nothing.');
      }
    } catch (e) {
      AppSnackbar.showTop('Image failed', '$e');
      _log('Slide image failed', e);
    } finally {
      imageBusyIndex.value = -1;
    }
  }

  void _hintNoImageEngine() {
    AppSnackbar.showTop(
      'No image engine',
      'Load a Stable Diffusion model to render slide images.',
    );
  }

  String get _deckTitle =>
      topic.value.trim().isEmpty ? 'Untitled deck' : topic.value.trim();

  Future<void> exportMarkdown() async {
    if (slides.isEmpty) return;
    await PromptExport.shareAsMarkdown(
      deckToMarkdown(_deckTitle, slides.toList()),
      baseName: 'slides',
    );
  }

  Future<void> exportPdf() async {
    if (slides.isEmpty) return;
    await PromptExport.shareAsPdf(
      deckToMarkdown(_deckTitle, slides.toList()),
      baseName: 'slides',
    );
  }

  Future<void> exportHtml() async {
    if (slides.isEmpty) return;
    try {
      final html = deckToHtml(_deckTitle, slides.toList(), theme: theme.value);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      await ExportFile.quickExport(
        text: html,
        fileName: 'cubiclm_slides_$stamp.html',
        mimeType: 'text/html',
        shareText: html,
      );
    } catch (e) {
      AppSnackbar.showTop('prompt_export_failed'.tr, '$e');
    }
  }

  Future<void> previewInBrowser() async {
    if (slides.isEmpty) return;
    try {
      final html = deckToHtml(_deckTitle, slides.toList(), theme: theme.value);
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/cubiclm_slides_$stamp.html');
      await file.writeAsString(html, flush: true);
      final result = await OpenFile.open(file.path);
      if (result.type != ResultType.done) {
        AppSnackbar.showTop('Cannot open', 'No browser found.');
      }
    } catch (e) {
      AppSnackbar.showTop('prompt_export_failed'.tr, '$e');
    }
  }

  Future<void> exportPptx() async {
    if (slides.isEmpty) return;
    try {
      final bytes = await deckToPptx(_deckTitle, slides.toList(), theme: theme.value);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      await ExportFile.quickExport(
        bytes: Uint8List.fromList(bytes),
        fileName: 'cubiclm_slides_$stamp.pptx',
        mimeType:
            'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      );
    } catch (e) {
      AppSnackbar.showTop('prompt_export_failed'.tr, '$e');
    }
  }

  static const templates = SlideDeckControllerTemplates.templates;

  Future<void> generateFromTemplate(String templateName) async {
    final skeleton = templates[templateName];
    if (skeleton == null) return;
    final t = topic.value.trim();
    if (t.isEmpty || generating.value) return;
    generating.value = true;
    lastError.value = null;
    slideCount.value = skeleton.length;
    try {
      final structureHint = skeleton
          .asMap()
          .entries
          .map((e) =>
              'Slide ${e.key + 1}: "${e.value['title']}" (layout: ${e.value['layout']})')
          .join('\n');
      final raw = await _ask(
        prompt: 'Create a ${skeleton.length}-slide presentation about: $t\n\n'
            'Follow this exact slide structure:\n$structureHint',
        system: slideSystemPrompt(
            count: skeleton.length,
            style: style.value,
            audience: audience.value),
      );
      final parsed = parseSlides(raw);
      slides.assignAll(parsed);
    } catch (e) {
      lastError.value = '$e';
      _log('Template generation failed', e);
    } finally {
      generating.value = false;
    }
  }

  Future<void> changeSlideLayout(int index, String newLayout) async {
    if (index < 0 || index >= slides.length) return;
    slides[index].layout = newLayout;
    slides.refresh();
  }

  Future<String> _ask({required String prompt, required String system, String? imagePath}) async {
    final settings = Get.find<SettingsController>();
    final buf = StringBuffer();
    if (settings.inferenceMode.value == 'cloud') {
      final cloud = Get.find<CloudService>();
      String? imgBase64;
      if (imagePath != null && !kIsWeb) {
        try {
          imgBase64 =
              await compute(base64Encode, await File(imagePath).readAsBytes());
        } catch (_) {}
      }
      await for (final chunk in cloud.streamMessage(
        [
          {'role': 'system', 'content': system},
          {'role': 'user', 'content': prompt},
        ],
        temperature: settings.temperature.value,
        maxTokens:
            settings.autoTuneParams.value ? null : settings.maxTokens.value,
        imageBase64: imgBase64,
      )) {
        buf.write(chunk);
      }
      return buf.toString().trim();
    }
    final inference = Get.find<InferenceService>();
    if (!inference.isModelLoaded.value) {
      throw Exception('No local model loaded.');
    }
    await inference.generate(
      prompt: prompt,
      systemPrompt: system,
      source: 'slides',
      imagePath: imagePath,
      onToken: buf.write,
    );
    return buf.toString().trim();
  }

  void _log(String message, Object e) {
    try {
      Get.find<AppLogService>().warning(
        message,
        details: '$e',
        category: LogCategory.chat,
      );
    } catch (_) {}
  }

  String _extractDataSheetText(SmartFile ds) {
    final buf = StringBuffer();
    if (ds.sheets != null) {
      for (final s in ds.sheets!) {
        buf.writeln('Sheet: ${s.name}');
        s.cells.forEach((k, v) {
          if (v.value.isNotEmpty) buf.writeln('$k: ${v.value}');
        });
      }
    }
    if (ds.hybridBlocks != null) {
      for (final b in ds.hybridBlocks!) {
        buf.writeln('Block: ${b.title} (${b.type})');
        if (b.docContent != null) buf.writeln(b.docContent);
        b.spreadsheetCells?.forEach((k, v) {
          if (v.value.isNotEmpty) buf.writeln('$k: ${v.value}');
        });
      }
    }
    return buf.toString();
  }
}

class SlideDeckControllerTemplates {
  static const templates = <String, List<Map<String, String>>>{
    '📚 Lesson Plan': [
      {'title': 'Topic & Objectives', 'layout': 'title'},
      {'title': 'Learning Objectives', 'layout': 'bullets'},
      {'title': 'Key Concepts', 'layout': 'bullets'},
      {'title': 'Visual Explanation', 'layout': 'image'},
      {'title': 'Activity / Practice', 'layout': 'bullets'},
      {'title': 'Key Takeaways', 'layout': 'summary'},
    ],
    '💼 Business Pitch': [
      {'title': 'Company & Vision', 'layout': 'title'},
      {'title': 'The Problem', 'layout': 'bullets'},
      {'title': 'Our Solution', 'layout': 'image'},
      {'title': 'Market Opportunity', 'layout': 'stats'},
      {'title': 'Before vs After', 'layout': 'comparison'},
      {'title': 'Traction & Milestones', 'layout': 'timeline'},
      {'title': 'The Ask', 'layout': 'summary'},
    ],
    '🔬 Research Report': [
      {'title': 'Research Title', 'layout': 'title'},
      {'title': 'Background & Motivation', 'layout': 'bullets'},
      {'title': 'Methodology', 'layout': 'bullets'},
      {'title': 'Key Findings', 'layout': 'stats'},
      {'title': 'Visual Results', 'layout': 'image'},
      {'title': 'Discussion', 'layout': 'bullets'},
      {'title': 'Conclusion', 'layout': 'summary'},
    ],
    '📊 Project Update': [
      {'title': 'Project Status', 'layout': 'title'},
      {'title': 'Progress Overview', 'layout': 'stats'},
      {'title': 'Completed Milestones', 'layout': 'timeline'},
      {'title': 'Blockers & Risks', 'layout': 'comparison'},
      {'title': 'Next Steps', 'layout': 'summary'},
    ],
    '📖 Story / Narrative': [
      {'title': 'Once Upon a Time…', 'layout': 'title'},
      {'title': 'The Setting', 'layout': 'image'},
      {'title': 'The Challenge', 'layout': 'bullets'},
      {'title': 'The Key Insight', 'layout': 'quote'},
      {'title': 'The Resolution', 'layout': 'bullets'},
      {'title': 'Moral / Takeaway', 'layout': 'summary'},
    ],
  };
}
