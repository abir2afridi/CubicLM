import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:get/get.dart';
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
  static const minSlides = 3;
  static const maxSlides = 20;

  final topic = ''.obs;
  final style = 'Professional'.obs;
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
            audience: audience.value),
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
            audience: audience.value),
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

  Future<String> _ask({required String prompt, required String system}) async {
    final settings = Get.find<SettingsController>();
    final buf = StringBuffer();
    if (settings.inferenceMode.value == 'cloud') {
      final cloud = Get.find<CloudService>();
      await for (final chunk in cloud.streamMessage(
        [
          {'role': 'system', 'content': system},
          {'role': 'user', 'content': prompt},
        ],
        temperature: settings.temperature.value,
        maxTokens:
            settings.autoTuneParams.value ? null : settings.maxTokens.value,
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
