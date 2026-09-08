import 'dart:io';
import 'dart:typed_data';

import 'package:get/get.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

import '../controllers/settings_controller.dart';
import '../services/app_log_service.dart';
import '../services/cloud_service.dart';
import '../services/inference_service.dart';
import '../services/local_image_service.dart';
import '../utils/app_snackbar.dart';
import '../utils/export_file.dart';
import '../utils/prompt_export.dart';
import '../utils/slide_deck.dart';
import '../utils/slide_pptx.dart';

/// Slide Maker: AI generates a structured deck from a topic.
/// Same engine rules as chat (local resident model or active cloud
/// setup). Image-capable setups can render per-slide visuals; otherwise
/// every visual slide keeps a proper placeholder box with its prompt.
///
/// Supports 8 presentation styles, 8 slide layout types, pre-built
/// templates, smart single-slide regeneration, and export to Markdown,
/// PDF, HTML, and PowerPoint (.pptx).
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
  final generating = false.obs;
  final regenIndex = (-1).obs; // -1 = whole deck, else slide index
  final imageBusyIndex = (-1).obs;
  final lastError = RxnString();

  bool get hasDeck => slides.isNotEmpty;

  void setCount(int v) {
    slideCount.value = v.clamp(minSlides, maxSlides);
  }

  Future<void> generate() async {
    final t = topic.value.trim();
    if (t.isEmpty || generating.value) return;
    generating.value = true;
    regenIndex.value = -1;
    lastError.value = null;
    try {
      final raw = await _ask(
        prompt: 'Create a ${slideCount.value}-slide presentation about: $t',
        system: slideSystemPrompt(
            count: slideCount.value,
            style: style.value,
            audience: audience.value),
      );
      final parsed = parseSlides(raw);
      slides.assignAll(parsed);
      if (parsed.length == 1 &&
          parsed.first.title == 'Untitled' &&
          raw.trim().isNotEmpty) {
        lastError.value =
            'The model did not follow the slide format — showing raw text as one slide. Try Regenerate.';
      }
    } catch (e) {
      lastError.value = '$e';
      _log('Deck generation failed', e);
    } finally {
      generating.value = false;
    }
  }

  /// Regenerate one slide in place (keeps the rest of the deck).
  /// Passes adjacent slide context so the replacement fits the flow.
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

  /// AI-powered slide refinement: user describes a change, AI rewrites
  /// that single slide to match the request while keeping deck context.
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

  /// One-click restyle: regenerate all slides with a new [newStyle] while
  /// keeping the same topic and slide count. Content is rewritten to match
  /// the new tone; layouts may change for better fit.
  Future<void> restyleDeck(String newStyle) async {
    if (generating.value || topic.value.trim().isEmpty || slides.isEmpty) return;
    generating.value = true;
    regenIndex.value = -1;
    lastError.value = null;
    final oldStyle = style.value;
    style.value = newStyle;
    try {
      // Build a compact summary of current content for the AI to preserve
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
        // Preserve images from the old deck
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

  // ── Manual editing ──

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
    lastError.value = null;
  }

  // ── Slide images (local SD when loaded) ──

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
        AppSnackbar.showTop(
          'Image failed',
          'The image engine returned nothing. Try again.',
          logHistory: false,
        );
      }
    } catch (e) {
      AppSnackbar.showTop('Image failed', '$e', logHistory: false);
      _log('Slide image failed', e);
    } finally {
      imageBusyIndex.value = -1;
    }
  }

  void _hintNoImageEngine() {
    AppSnackbar.showTop(
      'No image engine',
      'Load a Stable Diffusion model (Explore → Local) to render slide images. Text + placeholders work meanwhile.',
      logHistory: false,
    );
  }

  // ── Export ──

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
      final html = deckToHtml(_deckTitle, slides.toList());
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final saved = await ExportFile.saveText(
        text: html,
        fileName: 'cubiclm_slides_$stamp.html',
        dialogTitle: 'Save slides (.html)',
        mimeType: 'text/html',
      );
      if (saved != null) {
        AppSnackbar.showTop('Slides saved', saved, logHistory: false);
      }
    } catch (e) {
      AppSnackbar.showTop('prompt_export_failed'.tr, '$e');
    }
  }

  /// Write the deck HTML and open it in the system browser — the exact
  /// exported render ( closest to a Docs/Slides preview without leaving
  /// the share flow).
  Future<void> previewInBrowser() async {
    if (slides.isEmpty) return;
    try {
      final html = deckToHtml(_deckTitle, slides.toList());
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/cubiclm_slides_$stamp.html');
      await file.writeAsString(html, flush: true);
      final result = await OpenFile.open(file.path);
      if (result.type != ResultType.done) {
        AppSnackbar.showTop('Cannot open',
            result.message.isNotEmpty ? result.message : 'No browser found.');
      }
    } catch (e) {
      AppSnackbar.showTop('prompt_export_failed'.tr, '$e');
    }
  }

  /// Export as PowerPoint (.pptx) — builds an OpenXML zip archive.
  Future<void> exportPptx() async {
    if (slides.isEmpty) return;
    try {
      final bytes = await deckToPptx(_deckTitle, slides.toList());
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final saved = await ExportFile.saveBytes(
        bytes: Uint8List.fromList(bytes),
        fileName: 'cubiclm_slides_$stamp.pptx',
        dialogTitle: 'Save slides (.pptx)',
        mimeType:
            'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      );
      if (saved != null) {
        AppSnackbar.showTop('Slides saved', saved, logHistory: false);
      }
    } catch (e) {
      AppSnackbar.showTop('prompt_export_failed'.tr, '$e');
    }
  }

  // ── Slide Templates ──

  /// Pre-built deck skeletons the user can pick before AI generation.
  /// Each template defines the skeleton slides (title + layout) that
  /// the AI then fills with content for the user's topic.
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

  /// Generate a deck from a pre-built template. The template defines
  /// slide structure; AI fills content for the user's topic.
  Future<void> generateFromTemplate(String templateName) async {
    final skeleton = templates[templateName];
    if (skeleton == null) return;
    final t = topic.value.trim();
    if (t.isEmpty || generating.value) return;
    generating.value = true;
    regenIndex.value = -1;
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
      if (parsed.length == 1 &&
          parsed.first.title == 'Untitled' &&
          raw.trim().isNotEmpty) {
        lastError.value =
            'The model did not follow the slide format — showing raw text as one slide. Try Regenerate.';
      }
    } catch (e) {
      lastError.value = '$e';
      _log('Template generation failed', e);
    } finally {
      generating.value = false;
    }
  }

  /// Quick-action: change a slide's layout and optionally regenerate
  /// its content to fit the new layout.
  Future<void> changeSlideLayout(int index, String newLayout) async {
    if (index < 0 || index >= slides.length) return;
    slides[index].layout = newLayout;
    slides.refresh();
  }

  // ── Engine (same rules as chat) ──

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
      final out = buf.toString().trim();
      if (out.isEmpty) throw Exception('The model returned nothing.');
      return out;
    }
    final inference = Get.find<InferenceService>();
    if (!inference.isModelLoaded.value) {
      throw Exception(
          'No local model loaded — load one in Explore → Local, or switch to Cloud mode.');
    }
    await inference.generate(
      prompt: prompt,
      systemPrompt: system,
      source: 'slides',
      onToken: buf.write,
    );
    final out = buf.toString().trim();
    if (out.isEmpty) throw Exception('The model returned nothing.');
    return out;
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
}
