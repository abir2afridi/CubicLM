import 'dart:io';

import 'package:get/get.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../controllers/settings_controller.dart';
import '../services/app_log_service.dart';
import '../services/cloud_service.dart';
import '../services/inference_service.dart';
import '../services/local_image_service.dart';
import '../utils/app_snackbar.dart';
import '../utils/prompt_export.dart';
import '../utils/slide_deck.dart';

/// Slide Maker: AI generates a structured deck from a topic.
/// Same engine rules as chat (local resident model or active cloud
/// setup). Image-capable setups can render per-slide visuals; otherwise
/// every visual slide keeps a proper placeholder box with its prompt.
class SlideDeckController extends GetxController {
  static const styles = [
    'Professional',
    'Playful',
    'Minimal',
    'Story-like',
  ];
  static const minSlides = 3;
  static const maxSlides = 12;

  final topic = ''.obs;
  final style = 'Professional'.obs;
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
            count: slideCount.value, style: style.value),
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
        ),
        system: slideSystemPrompt(
            count: slides.length, style: style.value),
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

  // ── Manual editing ──

  void applyEdit(int index,
      {required String title,
      required String pointsText,
      required String imagePrompt,
      required String notes,
      required String layout}) {
    if (index < 0 || index >= slides.length) return;
    final s = slides[index];
    s.title = title.trim().isEmpty ? 'Untitled' : title.trim();
    s.points = pointsText
        .split('\n')
        .map((e) => e.trim().replaceFirst(RegExp(r'^[-*•]\s+'), ''))
        .where((e) => e.isNotEmpty)
        .toList();
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
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/cubiclm_slides_$stamp.html');
      await file.writeAsString(html, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/html')],
        subject: _deckTitle,
      );
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
        AppSnackbar.showTop(
            'Cannot open', result.message.isNotEmpty ? result.message : 'No browser found.');
      }
    } catch (e) {
      AppSnackbar.showTop('prompt_export_failed'.tr, '$e');
    }
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
        maxTokens: settings.autoTuneParams.value
            ? null
            : settings.maxTokens.value,
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
