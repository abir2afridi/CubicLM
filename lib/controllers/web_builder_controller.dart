import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../controllers/settings_controller.dart';
import '../services/app_log_service.dart';
import '../services/cloud_service.dart';
import '../services/inference_service.dart';
import '../utils/app_snackbar.dart';
import '../utils/web_project.dart';

/// CubicWeb Build: AI builds a complete website from a prompt —
/// any framework (Single HTML → React/Next/Vue). Preview runs browser
/// files instantly; everything exports as one ZIP.
class WebBuilderController extends GetxController {
  final topic = ''.obs;
  final framework = 'Single HTML'.obs;
  final files = <WebFile>[].obs;
  final generating = false.obs;
  final regenIndex = (-1).obs;
  final lastError = RxnString();

  /// Bumps on every project mutation — views key the preview on it.
  final revision = 0.obs;
  void _touch() => revision.value++;

  bool get hasProject => files.isNotEmpty;

  /// Frameworks that run directly in a browser (preview supported).
  bool get previewSupported =>
      framework.value == 'Single HTML' ||
      framework.value == 'HTML + CSS + JS';

  Future<void> generate() async {
    final t = topic.value.trim();
    if (t.isEmpty || generating.value) return;
    generating.value = true;
    regenIndex.value = -1;
    lastError.value = null;
    try {
      final raw = await _ask(
        prompt: 'Build this website with ${framework.value}: $t',
        system: webSystemPrompt(framework: framework.value),
      );
      final parsed = parseFiles(raw);
      files.assignAll(parsed);
      _touch();
    } catch (e) {
      lastError.value = '$e';
      _log('Website generation failed', e);
    } finally {
      generating.value = false;
    }
  }

  /// Regenerate one file in place (keeps siblings compatible).
  Future<void> regenerateFile(int index) async {
    if (generating.value ||
        index < 0 ||
        index >= files.length ||
        topic.value.trim().isEmpty) {
      return;
    }
    generating.value = true;
    regenIndex.value = index;
    lastError.value = null;
    try {
      final raw = await _ask(
        prompt: webRegenFilePrompt(
          topic: topic.value.trim(),
          framework: framework.value,
          path: files[index].path,
          current: files[index].content,
          siblings: [
            for (var i = 0; i < files.length; i++)
              if (i != index) files[i].path,
          ],
        ),
        system: webSystemPrompt(framework: framework.value),
      );
      final parsed = parseFiles(raw);
      if (parsed.isNotEmpty) {
        // Keep the original path (model may rename); take new content.
        files[index] =
            WebFile(path: files[index].path, content: parsed.first.content);
        _touch();
      }
    } catch (e) {
      lastError.value = '$e';
      _log('File regen failed', e);
    } finally {
      generating.value = false;
      regenIndex.value = -1;
    }
  }

  // ── Manual editing ──

  void applyEdit(int index, String path, String content) {
    if (index < 0 || index >= files.length) return;
    final clean = sanitizePath(path);
    if (clean.isEmpty || content.length > maxFileChars) return;
    files[index] = WebFile(path: clean, content: content);
    _touch();
  }

  void addFile(String path) {
    if (files.length >= maxFiles) return;
    final clean = sanitizePath(path);
    if (clean.isEmpty) return;
    if (files.any((f) => f.path == clean)) return;
    files.add(WebFile(path: clean, content: ''));
    _touch();
  }

  void deleteFile(int index) {
    if (index < 0 || index >= files.length) return;
    files.removeAt(index);
    _touch();
  }

  void clearProject() {
    files.clear();
    lastError.value = null;
    _touch();
  }

  // ── Preview + export ──

  /// Write all files under a temp dir, return the entry HTML abs path
  /// (or null when nothing browser-runnable exists).
  Future<String?> preparePreview() async {
    final entry = entryHtmlPath(files.toList());
    if (entry == null) return null;
    try {
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final root = Directory('${dir.path}/cubicweb_$stamp');
      await root.create(recursive: true);
      for (final f in files) {
        final out = File('${root.path}/${f.path}');
        await out.parent.create(recursive: true);
        await out.writeAsString(f.content, flush: true);
      }
      return '${root.path}/$entry';
    } catch (e) {
      _log('Preview prep failed', e);
      return null;
    }
  }

  /// ZIP the whole project and share it.
  Future<void> exportZip() async {
    if (files.isEmpty) return;
    try {
      final archive = Archive();
      for (final f in files) {
        final data = utf8.encode(f.content);
        archive.addFile(ArchiveFile(f.path, data.length, data));
      }
      final bytes = ZipEncoder().encode(archive);
      if (bytes.isEmpty) {
        throw Exception('ZIP encoder returned nothing.');
      }
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final name =
          'cubicweb_${topic.value.trim().isEmpty ? 'site' : _safeName(topic.value.trim())}_$stamp.zip';
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/zip')],
        subject: topic.value.trim().isEmpty
            ? 'Website project'
            : topic.value.trim(),
      );
    } catch (e) {
      AppSnackbar.showTop('prompt_export_failed'.tr, '$e');
    }
  }

  String _safeName(String s) {
    final clean = s.replaceAll(RegExp(r'[^\w\-. ]'), '').trim();
    final flat = clean.replaceAll(RegExp(r'\s+'), '_');
    return flat.isEmpty
        ? 'site'
        : flat.substring(0, flat.length > 40 ? 40 : flat.length);
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
      source: 'cubicweb',
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
