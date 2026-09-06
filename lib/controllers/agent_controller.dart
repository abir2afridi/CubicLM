import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../controllers/settings_controller.dart';
import '../services/agent_workspace.dart';
import '../services/app_log_service.dart';
import '../services/cloud_service.dart';
import '../services/inference_service.dart';
import '../services/preview_server.dart';
import '../utils/app_snackbar.dart';
import '../utils/web_download.dart';
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
  final planMode = false.obs;
  final extendedThinking = false.obs;
  final webSearch = false.obs;

  /// Pending plan awaiting user approval (null when no plan pending).
  final pendingPlan = RxnString();

  /// Last modify diffs — file path → (old content, new content).
  final lastDiffs = <String, Map<String, String>>{}.obs;

  /// Set by Stop — in-flight awaits can't be aborted, but their results
  /// are discarded and flags reset.
  bool _cancelled = false;

  void cancelWork() {
    _cancelled = true;
  }
  final previewUrl = RxnString();
  final consoleError = RxnString();
  final lastError = RxnString();
  final revision = 0.obs;

  /// Terminal buffer: timestamped agent activity (builds, fixes, file
  /// ops, console errors). The AI reads the tail in repair prompts, so
  /// it "sees" what happened — capped at 200 lines.
  final terminal = <String>[].obs;

  /// Chat transcript with the builder AI (user prompts + agent replies).
  /// Mirrors other builders: conversation is visible, not hidden.
  final transcript = <Map<String, String>>[].obs;

  /// Live build status shown in the preview pane while working
  /// (null when idle). E.g. "Streaming response… 12k chars".
  final buildStatus = RxnString();

  /// Attached image (base64, no data-uri prefix) for vision models.
  /// Sent with the next build/modify call, then cleared.
  final attachedImage = RxnString();

  /// Element picked from the live preview (long-press in preview).
  /// Injected as context into the next modify prompt.
  final pickedElement = RxnString();

  /// When true, long-press on any preview element captures it as context.
  final elementPickMode = false.obs;

  /// Attach an image (from gallery/camera) for vision models.
  Future<void> attachImage() async {
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        imageQuality: 82,
      );
      if (xfile == null) return;
      final bytes = await xfile.readAsBytes();
      attachedImage.value = base64Encode(bytes);
      term('📷 image attached (${(bytes.length / 1024).round()} KB)');
    } catch (e) {
      AppSnackbar.showTop('Attach failed', '$e', logHistory: false);
    }
  }

  void clearAttachment() => attachedImage.value = null;
  void clearPickedElement() => pickedElement.value = null;
  void toggleElementPick() => elementPickMode.value = !elementPickMode.value;

  /// Called by the preview's JS bridge when the user long-presses an element.
  void onElementPicked(String info) {
    pickedElement.value = info;
    elementPickMode.value = false;
    term('🎯 element picked: ${info.length > 80 ? '${info.substring(0, 80)}…' : info}');
    AppSnackbar.showTop(
      'Element picked',
      'Context added — describe the change you want.',
      logHistory: false,
    );
  }

  void _say(String role, String text) {
    try {
      transcript.add({'role': role, 'text': text});
      while (transcript.length > 100) {
        transcript.removeAt(0);
      }
    } catch (_) {}
  }

  void term(String line) {
    try {
      final now = DateTime.now();
      final ts = '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}:'
          '${now.second.toString().padLeft(2, '0')}';
      terminal.add('[$ts] $line');
      while (terminal.length > 200) {
        terminal.removeAt(0);
      }
    } catch (_) {}
  }

  void clearTerminal() {
    try {
      terminal.clear();
    } catch (_) {}
  }

  /// Last N terminal lines for prompts (AI context).
  String terminalTail([int n = 30]) {
    try {
      final lines = terminal.toList();
      return lines.skip(lines.length > n ? lines.length - n : 0).join('\n');
    } catch (_) {
      return '';
    }
  }

  int _autoRounds = 0;

  AgentWorkspaceService get _ws => Get.find<AgentWorkspaceService>();
  PreviewServerService get _preview => Get.find<PreviewServerService>();

  void _touch() => revision.value++;

  int _lastStatusMs = 0;

  void _streamStatus(String prefix, int chars) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastStatusMs < 300) return;
    _lastStatusMs = now;
    buildStatus.value =
        '$prefix… ${(chars / 1024).toStringAsFixed(1)}k chars';
  }

  Future<void> refreshFiles() async {
    final p = project.value;
    if (p == null) {
      files.clear();
      return;
    }
    files.assignAll(await _ws.listFiles(p.id));
  }

  /// Call after manual file ops (save/rename/add/delete) so the explorer
  /// list AND the preview both refresh. Clears a stale console error —
  /// a hand fix likely resolved it.
  Future<void> notifyFilesChanged() async {
    await refreshFiles();
    consoleError.value = null;
    _touch();
  }

  Future<void> renameProject(String name) async {
    final p = project.value;
    if (p == null || name.trim().isEmpty) return;
    await _ws.renameProject(p.id, name);
    p.name = name.trim();
    project.refresh();
  }

  Future<String?> readFile(String path) async {
    final p = project.value;
    if (p == null) return null;
    return _ws.readFile(p.id, path);
  }

  Future<void> newProject() async {
    final t = topic.value.trim();
    if (t.isEmpty || generating.value) return;
    // If plan mode is on, generate plan first instead of building directly.
    if (planMode.value) {
      await generatePlan();
      return;
    }
    generating.value = true;
    _cancelled = false;
    lastError.value = null;
    consoleError.value = null;
    _autoRounds = 0;
    transcript.clear();
    _say('user', t);
    buildStatus.value = 'Designing project…';
    term('> build "${t.length > 60 ? '${t.substring(0, 60)}…' : t}" (${framework.value})');
    try {
      final name = t.length > 40 ? '${t.substring(0, 40)}…' : t;
      final p = await _ws.createProject(name, framework.value);
      project.value = p;
      await _ws.saveCheckpoint(p.id, label: 'Project created');
      final raw = await _ask(
        prompt: 'Build this website with ${framework.value}: $t',
        system: webSystemPrompt(framework: framework.value),
        onProgress: (n) => _streamStatus('Writing project', n),
      );
      if (_cancelled) return;
      buildStatus.value = 'Saving files…';
      final parsed = parseFiles(raw);
      final err = await _ws.importFiles(
          p.id, {for (final f in parsed) f.path: f.content});
      if (err != null) {
        lastError.value = 'Some files failed: $err';
      }
      await refreshFiles();
      await _serve();
      _touch();
      buildStatus.value = null;
      final summary =
          'Built ${parsed.length} files — preview is live. Tap a file to edit, or ask for changes below.';
      _say('assistant', summary);
      term('✓ build done — ${files.length} files, preview live');
    } catch (e) {
      if (_cancelled) {
        term('■ build cancelled by user');
        return;
      }
      lastError.value = '$e';
      term('✗ build failed: $e');
      _log('Project build failed', e);
    } finally {
      generating.value = false;
      buildStatus.value = null;
      _cancelled = false;
    }
  }

  /// Follow-up change ("make navbar blue"): model returns ONLY
  /// changed/new files, merged over the workspace.
  Future<void> modifyProject() async {
    final p = project.value;
    final t = topic.value.trim();
    if (p == null || t.isEmpty || generating.value || fixing.value) return;
    generating.value = true;
    _cancelled = false;
    lastError.value = null;
    _say('user', t);
    buildStatus.value = 'Applying change…';
    term('> modify: "${t.length > 80 ? '${t.substring(0, 80)}…' : t}"');
    try {
      await _ws.saveCheckpoint(p.id, label: 'Before modify');
      final projContext = await _projectContext(p.id);
      final raw = await _ask(
        prompt: 'Modify the "${p.name}" ${p.framework} project: $t\n\n'
            'CURRENT FILES:\n$projContext\n\n'
            'Return a files-JSON object with ONLY new or fully-rewritten changed files.',
        system:
            '${webSystemPrompt(framework: p.framework)}\nSTRICT: output only files that change (plus any brand-new files).',
        onProgress: (n) => _streamStatus('Writing change', n),
      );
      if (_cancelled) return;
      final parsed = parseFiles(raw);
      // Capture old contents for diff view.
      lastDiffs.clear();
      for (final f in parsed) {
        final old = await _ws.readFile(p.id, f.path);
        if (old != null && old != f.content) {
          lastDiffs[f.path] = {'old': old, 'new': f.content};
        } else if (old == null) {
          lastDiffs[f.path] = {'old': '', 'new': f.content};
        }
      }
      var applied = 0;
      for (final f in parsed) {
        final err = await _ws.writeFile(p.id, f.path, f.content);
        if (err == null) applied++;
      }
      await _ws.touch(p.id);
      await refreshFiles();
      _touch();
      buildStatus.value = null;
      term('✓ modify applied ($applied files)');
      _say('assistant',
          'Done — $applied file${applied == 1 ? '' : 's'} changed, preview reloaded.');
      AppSnackbar.showTop(
        'Updated',
        '$applied file${applied == 1 ? '' : 's'} changed — preview reloaded.',
        logHistory: false,
      );
    } catch (e) {
      if (_cancelled) {
        term('■ modify cancelled by user');
        return;
      }
      lastError.value = '$e';
      term('✗ modify failed: $e');
      _log('Project modify failed', e);
    } finally {
      generating.value = false;
      buildStatus.value = null;
      _cancelled = false;
    }
  }

  // ── Plan Mode ──

  /// Generate a structured plan (no code yet). User reviews, then approves.
  Future<void> generatePlan() async {
    final t = topic.value.trim();
    if (t.isEmpty || generating.value) return;
    generating.value = true;
    _cancelled = false;
    lastError.value = null;
    transcript.clear();
    _say('user', t);
    buildStatus.value = 'Thinking through the plan…';
    term('> plan: "${t.length > 60 ? '${t.substring(0, 60)}…' : t}" (${framework.value})');
    try {
      final raw = await _ask(
        prompt:
            'Plan this ${framework.value} project based on: $t\n\n'
            'Output a structured plan in this EXACT format inside a ```plan fenced block:\n\n'
            '```plan\n'
            'PROJECT: <short project name>\n'
            'FRAMEWORK: ${framework.value}\n'
            'DESCRIPTION: <1-2 sentence description>\n'
            'FILES:\n'
            '- index.html: <what this file does>\n'
            '- styles.css: <what this file does>\n'
            '- app.js: <what this file does>\n'
            'FEATURES:\n'
            '- <feature 1>\n'
            '- <feature 2>\n'
            'DESIGN:\n'
            '- <color scheme, layout style, typography>\n'
            '```\n\n'
            'Be specific about each file\'s purpose and the design decisions. '
            'Do NOT write any code yet — just the plan.',
        system: _planSystemPrompt(),
        onProgress: (n) => _streamStatus('Planning', n),
      );
      if (_cancelled) return;
      // Extract plan text from response
      final planText = _extractPlan(raw);
      pendingPlan.value = planText;
      _say('assistant', 'Here\'s my plan:\n\n$planText');
      term('✓ plan ready — review and tap Build to proceed');
      buildStatus.value = null;
    } catch (e) {
      if (_cancelled) {
        term('■ plan cancelled by user');
        return;
      }
      lastError.value = '$e';
      term('✗ plan failed: $e');
      _log('Plan generation failed', e);
    } finally {
      generating.value = false;
      buildStatus.value = null;
      _cancelled = false;
    }
  }

  /// Build from an approved plan (plan must be in pendingPlan).
  Future<void> buildFromPlan() async {
    final plan = pendingPlan.value;
    final t = topic.value.trim();
    if (plan == null || t.isEmpty || generating.value) return;
    pendingPlan.value = null; // consume the plan
    generating.value = true;
    _cancelled = false;
    lastError.value = null;
    consoleError.value = null;
    _autoRounds = 0;
    _say('user', '✓ Build it');
    buildStatus.value = 'Building from plan…';
    term('> build from plan (${framework.value})');
    try {
      final name = t.length > 40 ? '${t.substring(0, 40)}…' : t;
      final p = await _ws.createProject(name, framework.value);
      project.value = p;
      final raw = await _ask(
        prompt:
            'Build this ${framework.value} project NOW based on this APPROVED plan:\n\n'
            '$plan\n\n'
            'ORIGINAL REQUEST: $t\n\n'
            'Output EXACTLY one ```files fenced block with ALL the code. '
            'Every file listed in the plan MUST be included with complete, '
            'working code. No placeholders.',
        system: webSystemPrompt(framework: framework.value),
        onProgress: (n) => _streamStatus('Writing project', n),
      );
      if (_cancelled) return;
      buildStatus.value = 'Saving files…';
      final parsed = parseFiles(raw);
      final err = await _ws.importFiles(
          p.id, {for (final f in parsed) f.path: f.content});
      if (err != null) {
        lastError.value = 'Some files failed: $err';
      }
      await refreshFiles();
      await _serve();
      _touch();
      buildStatus.value = null;
      final summary =
          'Built ${parsed.length} files from plan — preview is live.';
      _say('assistant', summary);
      term('✓ build done — ${files.length} files, preview live');
    } catch (e) {
      if (_cancelled) {
        term('■ build cancelled by user');
        return;
      }
      lastError.value = '$e';
      term('✗ build from plan failed: $e');
      _log('Build from plan failed', e);
    } finally {
      generating.value = false;
      buildStatus.value = null;
      _cancelled = false;
    }
  }

  String _planSystemPrompt() {
    return 'You are a senior web architect. When asked to plan a project, '
        'output a structured plan — NOT code. Use the exact format requested. '
        'Be specific about file purposes, features, and design decisions. '
        'Keep the plan concise but actionable.';
  }

  String _extractPlan(String raw) {
    final planFence = RegExp(r'```plan\n([\s\S]*?)```');
    final m = planFence.firstMatch(raw);
    if (m != null) return m.group(1)!.trim();
    // Fallback: return everything after "PLAN:" or the full response
    final planIdx = raw.indexOf('PLAN:');
    if (planIdx >= 0) return raw.substring(planIdx).trim();
    return raw.trim();
  }

  /// Called by the view's WebView console hook. Auto-repairs (bounded),
  /// otherwise surfaces with a manual Fix button.
  Future<void> onConsoleError(String message) async {
    final p = project.value;
    consoleError.value = message;
    term('✗ console: ${message.length > 160 ? '${message.substring(0, 160)}…' : message}');
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
    _cancelled = false;
    lastError.value = null;
    buildStatus.value = 'Fixing error…';
    term('⚙ auto-fix round $_autoRounds/$maxRepairRounds…');
    try {
      await _ws.saveCheckpoint(p.id, label: 'Before auto-fix');
      final projContext = await _projectContext(p.id);
      final raw = await _ask(
        prompt: 'Fix this runtime error in the "${p.name}" '
            '${p.framework} project:\n\nERROR:\n$err\n\n'
            'CURRENT FILES:\n$projContext\n\n'
            'RECENT TERMINAL (what happened so far):\n'
            '${terminalTail()}\n\n'
            'Return a files-JSON object with ONLY the corrected files '
            '(complete new contents).',
        system:
            '${webSystemPrompt(framework: p.framework)}\nSTRICT: output only files that change.',
        onProgress: (n) => _streamStatus('Writing fix', n),
      );
      final parsed = parseFiles(raw);
      if (_cancelled) return;
      var applied = 0;
      for (final f in parsed) {
        final werr = await _ws.writeFile(p.id, f.path, f.content);
        if (werr == null) applied++;
      }
      await _ws.touch(p.id);
      await refreshFiles();
      consoleError.value = null;
      _touch();
      buildStatus.value = null;
      term('✓ auto-fix applied ($applied files)');
      _say('assistant',
          'Fixed — $applied file${applied == 1 ? '' : 's'} rewritten, preview reloaded.');
      AppSnackbar.showTop(
        'Auto-fix applied',
        '$applied file${applied == 1 ? '' : 's'} rewritten — reloaded.',
        logHistory: false,
      );
    } catch (e) {
      if (_cancelled) {
        term('■ fix cancelled by user');
        return;
      }
      lastError.value = '$e';
      term('✗ auto-fix failed: $e');
      _log('Auto-fix failed', e);
    } finally {
      fixing.value = false;
      buildStatus.value = null;
      _cancelled = false;
    }
  }

  // ── Browser Auto-Test ──

  /// Manual test button: checks console errors + asks AI to review code,
  /// then auto-fixes any issues found.
  Future<void> runAutoTest() async {
    final p = project.value;
    if (p == null || generating.value || fixing.value) return;
    generating.value = true;
    _cancelled = false;
    lastError.value = null;
    _say('user', '🔍 Auto-test: review project for bugs and improvements');
    buildStatus.value = 'Running auto-test…';
    term('> auto-test: reviewing "${p.name}"…');
    try {
      // 1) Check existing console errors.
      final consoleErr = consoleError.value;
      if (consoleErr != null && consoleErr.isNotEmpty) {
        term('✗ console error detected: $consoleErr');
        await repairFromError();
        if (generating.value) return; // already fixing
      }
      // 2) Ask AI to review all files for issues.
      final projContext = await _projectContext(p.id);
      final raw = await _ask(
        prompt: 'Auto-test the "${p.name}" ${p.framework} project. '
            'Review all files for: broken links, missing images, '
            'accessibility issues (alt text, contrast), responsive bugs, '
            'SEO problems (missing title/meta), performance issues, '
            'and any other bugs.\n\n'
            'CURRENT FILES:\n$projContext\n\n'
            'If you find issues, return a files-JSON object with the '
            'corrected files (complete new contents). If everything looks '
            'good, respond with just: OK',
        system:
            '${webSystemPrompt(framework: p.framework)}\n'
            'You are a QA engineer. Be thorough but practical.',
        onProgress: (n) => _streamStatus('Testing', n),
      );
      if (_cancelled) return;
      if (raw.trim() == 'OK') {
        _say('assistant',
            'All checks passed! No issues found. The project looks good.');
        term('✓ auto-test: all checks passed');
        AppSnackbar.showTop('Auto-test passed', 'No issues found.',
            logHistory: false);
      } else {
        final parsed = parseFiles(raw);
        await _ws.saveCheckpoint(p.id, label: 'Before auto-test fix');
        var applied = 0;
        for (final f in parsed) {
          final werr = await _ws.writeFile(p.id, f.path, f.content);
          if (werr == null) applied++;
        }
        await _ws.touch(p.id);
        await refreshFiles();
        _touch();
        _say('assistant',
            'Auto-test found and fixed $applied file${applied == 1 ? '' : 's'}. '
            'Preview reloaded — check the result.');
        term('✓ auto-test: fixed $applied files');
        AppSnackbar.showTop('Auto-test fixed',
            '$applied file${applied == 1 ? '' : 's'} updated.',
            logHistory: false);
      }
    } catch (e) {
      if (_cancelled) {
        term('■ auto-test cancelled');
        return;
      }
      lastError.value = '$e';
      term('✗ auto-test failed: $e');
      _log('Auto-test failed', e);
    } finally {
      generating.value = false;
      buildStatus.value = null;
      _cancelled = false;
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
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final name = 'cubicagent_$stamp.zip';
      if (kIsWeb) {
        try {
          if (await downloadWebFile(out, name, 'application/zip')) return;
        } catch (_) {}
      }
      final tmp = await getTemporaryDirectory();
      final file = File('${tmp.path}/$name');
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

  Future<String> _ask(
      {required String prompt,
      required String system,
      void Function(int chars)? onProgress}) async {
    final settings = Get.find<SettingsController>();
    // Inject extended thinking instructions.
    var sys = system;
    if (extendedThinking.value) {
      sys += '\n\nTHINKING MODE: Before writing any code, think step-by-step. '
          'Analyze requirements, consider edge cases, plan the structure, '
          'then write clean, well-organized code.';
    }
    if (webSearch.value) {
      sys += '\n\nWEB SEARCH: If you need current library versions, CDN URLs, '
          'or best practices, include them. Use well-known, stable CDN '
          'links (unpkg, cdnjs, jsdelivr) for external libraries.';
    }
    final buf = StringBuffer();
    var count = 0;
    void bump(String chunk) {
      buf.write(chunk);
      count += chunk.length;
      try {
        onProgress?.call(count);
      } catch (_) {}
    }

    if (settings.inferenceMode.value == 'cloud') {
      final cloud = Get.find<CloudService>();
      await for (final chunk in cloud.streamMessage(
        [
          {'role': 'system', 'content': sys},
          {'role': 'user', 'content': prompt},
        ],
        temperature: settings.temperature.value,
        maxTokens: settings.autoTuneParams.value
            ? null
            : settings.maxTokens.value,
        imageBase64: attachedImage.value,
      )) {
        bump(chunk);
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
      onToken: bump,
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
