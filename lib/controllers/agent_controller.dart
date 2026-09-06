import 'dart:io';

import 'package:archive/archive.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../controllers/settings_controller.dart';
import '../services/agent_workspace.dart';
import '../services/app_log_service.dart';
import '../services/cloud_service.dart';
import '../services/inference_service.dart';
import '../services/preview_server.dart';
import '../utils/app_snackbar.dart';
import '../utils/web_project.dart';

/// Agent-IDE orchestrator (MVP): prompt → files → local preview →
/// console-error repair loop (changed files only, max rounds).
class AgentController extends GetxController {
  static const maxRepairRounds = 3;
  static const maxContextChars = 60000;

  final topic = ''.obs;
  final framework = 'Single HTML'.obs;
  final project = Rxn<AgentProject>();
  final files = <String>[].obs;
  final generating = false.obs;
  final fixing = false.obs;
  final autoFix = true.obs;
  final previewUrl = RxnString();
  final consoleError = RxnString();
  final lastError = RxnString();
  final revision = 0.obs;

  int _autoRounds = 0;

  AgentWorkspaceService get _ws => Get.find<AgentWorkspaceService>();
  PreviewServerService get _preview => Get.find<PreviewServerService>();

  void _touch() => revision.value++;

  Future<void> refreshFiles() async {
    final p = project.value;
    if (p == null) {
      files.clear();
      return;
    }
    files.assignAll(await _ws.listFiles(p.id));
  }

  Future<String?> readFile(String path) async {
    final p = project.value;
    if (p == null) return null;
    return _ws.readFile(p.id, path);
  }

  Future<void> newProject() async {
    final t = topic.value.trim();
    if (t.isEmpty || generating.value) return;
    generating.value = true;
    lastError.value = null;
    consoleError.value = null;
    _autoRounds = 0;
    try {
      final name = t.length > 40 ? '${t.substring(0, 40)}…' : t;
      final p = await _ws.createProject(name, framework.value);
      project.value = p;
      final raw = await _ask(
        prompt: 'Build this website with ${framework.value}: $t',
        system: webSystemPrompt(framework: framework.value),
      );
      final parsed = parseFiles(raw);
      final err = await _ws.importFiles(
          p.id, {for (final f in parsed) f.path: f.content});
      if (err != null) {
        lastError.value = 'Some files failed: $err';
      }
      await refreshFiles();
      await _serve();
      _touch();
    } catch (e) {
      lastError.value = '$e';
      _log('Project build failed', e);
    } finally {
      generating.value = false;
    }
  }

  /// Follow-up change ("make navbar blue"): model returns ONLY
  /// changed/new files, merged over the workspace.
  Future<void> modifyProject() async {
    final p = project.value;
    final t = topic.value.trim();
    if (p == null || t.isEmpty || generating.value || fixing.value) return;
    generating.value = true;
    lastError.value = null;
    try {
      final projContext = await _projectContext(p.id);
      final raw = await _ask(
        prompt: 'Modify the "${p.name}" ${p.framework} project: $t\n\n'
            'CURRENT FILES:\n$projContext\n\n'
            'Return a files-JSON object with ONLY new or fully-rewritten changed files.',
        system:
            '${webSystemPrompt(framework: p.framework)}\nSTRICT: output only files that change (plus any brand-new files).',
      );
      final parsed = parseFiles(raw);
      var applied = 0;
      for (final f in parsed) {
        final err = await _ws.writeFile(p.id, f.path, f.content);
        if (err == null) applied++;
      }
      await _ws.touch(p.id);
      await refreshFiles();
      _touch();
      AppSnackbar.showTop(
        'Updated',
        '$applied file${applied == 1 ? '' : 's'} changed — preview reloaded.',
        logHistory: false,
      );
    } catch (e) {
      lastError.value = '$e';
      _log('Project modify failed', e);
    } finally {
      generating.value = false;
    }
  }

  /// Called by the view's WebView console hook. Auto-repairs (bounded),
  /// otherwise surfaces with a manual Fix button.
  Future<void> onConsoleError(String message) async {
    final p = project.value;
    consoleError.value = message;
    if (p == null || fixing.value || generating.value) return;
    if (!autoFix.value || _autoRounds >= maxRepairRounds) return;
    _autoRounds++;
    await repairFromError();
  }

  Future<void> repairFromError() async {
    final p = project.value;
    final err = consoleError.value;
    if (p == null || err == null || err.isEmpty || fixing.value) return;
    fixing.value = true;
    lastError.value = null;
    try {
      final projContext = await _projectContext(p.id);
      final raw = await _ask(
        prompt: 'Fix this runtime error in the "${p.name}" '
            '${p.framework} project:\n\nERROR:\n$err\n\n'
            'CURRENT FILES:\n$projContext\n\n'
            'Return a files-JSON object with ONLY the corrected files '
            '(complete new contents).',
        system:
            '${webSystemPrompt(framework: p.framework)}\nSTRICT: output only files that change.',
      );
      final parsed = parseFiles(raw);
      var applied = 0;
      for (final f in parsed) {
        final werr = await _ws.writeFile(p.id, f.path, f.content);
        if (werr == null) applied++;
      }
      await _ws.touch(p.id);
      await refreshFiles();
      consoleError.value = null;
      _touch();
      AppSnackbar.showTop(
        'Auto-fix applied',
        '$applied file${applied == 1 ? '' : 's'} rewritten — reloaded.',
        logHistory: false,
      );
    } catch (e) {
      lastError.value = '$e';
      _log('Auto-fix failed', e);
    } finally {
      fixing.value = false;
    }
  }

  /// Small-file contexts for repair/modify prompts (capped).
  Future<String> _projectContext(String projectId) async {
    final buf = StringBuffer();
    var used = 0;
    for (final path in await _ws.listFiles(projectId)) {
      final content = await _ws.readFile(projectId, path) ?? '';
      if (content.length > 8000) {
        buf.writeln('--- $path (first 2KB of ${content.length}) ---');
        final head = content.substring(0, 2000);
        if (used + head.length > maxContextChars) break;
        buf.writeln(head);
        used += head.length;
      } else {
        if (used + content.length > maxContextChars) break;
        buf.writeln('--- $path ---');
        buf.writeln(content);
        used += content.length;
      }
    }
    return buf.toString();
  }

  Future<void> openProject(AgentProject p) async {
    project.value = p;
    consoleError.value = null;
    lastError.value = null;
    _autoRounds = 0;
    await refreshFiles();
    await _serve();
    _touch();
  }

  Future<void> _serve() async {
    final p = project.value;
    if (p == null) return;
    try {
      final dir = await _ws.dirFor(p.id);
      previewUrl.value = await _preview.start(p.id, dir.path);
    } catch (_) {
      previewUrl.value = null;
    }
  }

  Future<void> deleteProject(String id) async {
    if (project.value?.id == id) {
      project.value = null;
      files.clear();
      previewUrl.value = null;
      await _preview.stop();
    }
    await _ws.deleteProject(id);
  }

  Future<void> exportZip() async {
    final p = project.value;
    if (p == null) return;
    try {
      final dir = await _ws.dirFor(p.id);
      final archive = Archive();
      for (final path in await _ws.listFiles(p.id)) {
        final bytes = await File('${dir.path}/$path').readAsBytes();
        archive.addFile(ArchiveFile(path, bytes.length, bytes));
      }
      final out = ZipEncoder().encode(archive);
      if (out.isEmpty) throw Exception('ZIP encoder returned nothing.');
      final tmp = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${tmp.path}/cubicagent_$stamp.zip');
      await file.writeAsBytes(out, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/zip')],
        subject: p.name,
      );
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
      source: 'agent',
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

  @override
  void onClose() {
    try {
      Get.find<PreviewServerService>().stop();
    } catch (_) {}
    super.onClose();
  }
}
