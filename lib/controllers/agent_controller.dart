import 'dart:async';
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
import '../services/runtime/cli_manager.dart';
import '../services/runtime/cli_manifest.dart';
import '../services/runtime/cloud_runtime.dart';
import '../services/runtime/dev_server_manager.dart';
import '../services/runtime/preview_router.dart';
import '../services/runtime/process_runner.dart';
import '../services/runtime/project_detector.dart';
import '../services/runtime/project_validator.dart';
import '../services/runtime/runtime_manager.dart';
import '../utils/app_snackbar.dart';
import '../utils/web_download.dart';
import '../utils/web_project.dart';

/// One preview-pipeline step for the status checklist UI.
class PreviewStep {
  /// Short label, e.g. 'Detect project'.
  final String label;

  /// 'pending' | 'ok' | 'fail' | 'info'.
  final String state;

  /// Detail line, e.g. 'Vite project' or 'node v22.1.0'.
  final String detail;

  const PreviewStep(this.label, this.state, [this.detail = '']);
}

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

  /// Live-streamed files mid-generation (path → partial content).
  /// Shown in the Files tab + streaming editor while the AI writes;
  /// cleared once final files land on disk.
  final streamingFiles = <String, String>{}.obs;

  /// True while partial output is being flushed (drives live UI).
  final streamingActive = false.obs;

  /// True once partial files hit disk at least once (live preview on).
  final livePreviewReady = false.obs;

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

  /// Runtime-aware preview routing (see services/runtime/).
  final previewKind = ProjectKind.staticSite.obs;
  final previewIssues = <ProjectIssue>[].obs;
  final previewSteps = <PreviewStep>[].obs;
  final previewDecision = Rxn<PreviewDecision>();

  /// Live dev-server URL when the pipeline runs one (null otherwise).
  final devServerUrl = RxnString();
  final devServerStarting = false.obs;

  /// True while `npm run build` validation runs.
  final validatingBuild = false.obs;

  /// Cloud fallback provider (unconfigured in this build — honest stub).
  final CloudRuntimeProvider cloudRuntime = UnconfiguredCloudRuntime();

  /// Manifest id of the CLI currently attached to the terminal input
  /// (null = input runs one-shot shell commands).
  final activeCliId = RxnString();

  /// Terminal-detected CLI awaiting the user's Add/Ignore choice.
  final detectedCliId = RxnString();
  final detectedCliVersion = RxnString();

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

  int _lastLiveWriteMs = 0;

  /// Merge one streamed buffer into live file state.
  ///
  /// - Updates [streamingFiles] so the Files tab + streaming editor
  ///   show code AS the AI writes it (v0/Replit-style).
  /// - For previewable output (no package.json in the partial set) the
  ///   partial files are ALSO written to disk (throttled) so the
  ///   preview WebView reloads live. npm/framework output skips disk
  ///   writes — it cannot execute until installed/built anyway.
  /// - Never throws; streaming must not break generation.
  Future<void> _flushPartial(String buf, String projectId) async {
    List<PartialWebFile> partial;
    try {
      partial = parsePartialFiles(buf);
    } catch (_) {
      return;
    }
    if (partial.isEmpty || _cancelled) return;
    streamingActive.value = true;
    var changed = false;
    for (final f in partial) {
      if (streamingFiles[f.path] != f.content) {
        streamingFiles[f.path] = f.content;
        changed = true;
      }
    }
    if (!changed) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final hasPackageJson = partial.any((f) {
      final p = f.path.toLowerCase();
      return p == 'package.json' || p.endsWith('/package.json');
    });
    if (!hasPackageJson && now - _lastLiveWriteMs >= 1500) {
      _lastLiveWriteMs = now;
      try {
        var wrote = false;
        for (final f in partial) {
          final err = await _ws.writeFile(projectId, f.path, f.content);
          if (err == null) wrote = true;
        }
        if (wrote && !_cancelled) {
          await refreshFiles();
          livePreviewReady.value = true;
          _touch(); // reload the preview WebView
        }
      } catch (_) {}
    }
  }

  /// Merge issue lists without code+path duplicates (disk validation
  /// and write-fidelity often flag the same file twice).
  void _mergeIssues(
      List<ProjectIssue> base, List<ProjectIssue> extra) {
    final have = base.map((i) => '${i.code}:${i.path}').toSet();
    for (final i in extra) {
      if (have.add('${i.code}:${i.path}')) base.add(i);
    }
  }

  /// Generation integrity (§8): read back what was just written and
  /// compare byte-for-byte, plus hygiene-scan the generated source.
  /// Catches truncation/corruption between model output and disk —
  /// surfaced as blockers, never silently previewed.
  Future<List<ProjectIssue>> _verifyWriteFidelity(
      String projectId, Map<String, String> expected) async {
    final issues = <ProjectIssue>[];
    for (final e in expected.entries) {
      String? actual;
      try {
        actual = await _ws.readFile(projectId, e.key);
      } catch (_) {}
      if (actual == null) {
        issues.add(ProjectIssue('write-missing',
            '"${e.key}" is missing on disk after writing — the write failed.',
            path: e.key));
      } else if (actual.length != e.value.length) {
        issues.add(ProjectIssue('write-truncated',
            '"${e.key}" on disk (${actual.length} chars) differs from generated source (${e.value.length} chars) — truncated or corrupted in transit.',
            path: e.key));
      } else if (actual != e.value) {
        issues.add(ProjectIssue('write-corrupted',
            '"${e.key}" on disk differs from generated source — serialization corrupted it.',
            path: e.key));
      }
      issues.addAll(sourceHygieneIssues(e.key, e.value));
    }
    return issues;
  }

  /// Production build validation (`npm run build`) for Node projects.
  /// Streams real compiler output to the terminal; failures flow into
  /// the existing Ask-AI loop via the terminal wand button.
  Future<void> validateBuild() async {
    final p = project.value;
    if (p == null ||
        validatingBuild.value ||
        generating.value ||
        fixing.value) {
      return;
    }
    if (!projectNeedsNode(previewKind.value)) {
      AppSnackbar.showTop('Build check',
          'Only Node projects need `npm run build` — this one previews statically.',
          logHistory: false);
      return;
    }
    validatingBuild.value = true;
    buildStatus.value = 'Running npm run build…';
    term('> npm run build  (production validation)');
    try {
      String? npm;
      try {
        npm = (await Get.find<RuntimeManager>().refresh()).npmPath;
      } catch (_) {}
      if (npm == null || npm.isEmpty) {
        term('✗ NEXT_BUILD_FAILED — npm unavailable (NPM_MISSING): Node.js runtime missing.');
        lastError.value = 'npm is unavailable — Node.js runtime missing.';
        return;
      }
      final dir = await _ws.dirFor(p.id);
      final session = await ProcessRunner.startSession(
        npm,
        const ['run', 'build'],
        workingDirectory: dir.path,
        commandLabel: 'npm run build',
      );
      final sub1 = session.stdoutLines.listen(term);
      final sub2 = session.stderrLines.listen(term);
      int code;
      try {
        code = await session.exitCode
            .timeout(const Duration(minutes: 10));
      } on TimeoutException {
        code = -1;
        try {
          await session.kill(true);
        } catch (_) {}
      }
      try {
        await sub1.cancel();
      } catch (_) {}
      try {
        await sub2.cancel();
      } catch (_) {}
      if (code == 0) {
        term('✓ npm run build passed');
        _say('assistant',
            'Production build passed (`npm run build` ✅). Preview keeps running the dev server.');
        AppSnackbar.showTop(
            'Build passed', '`npm run build` succeeded.',
            logHistory: false);
      } else {
        term('✗ NEXT_BUILD_FAILED (exit $code) — compiler output above; tap the terminal wand (Ask AI) and I’ll fix it');
        lastError.value =
            '`npm run build` failed (exit $code) — see Terminal, then Ask AI to Fix.';
        _say('assistant',
            'The production build failed (exit $code) — full compiler output is in the Terminal. Tap the wand button there (Ask AI to Fix) and I’ll repair the source.');
      }
    } catch (e) {
      term('✗ build check failed: $e');
      lastError.value = '$e';
    } finally {
      validatingBuild.value = false;
      buildStatus.value = null;
    }
  }

  /// Clear all live-streaming state (call when generation settles).
  void _clearStreaming() {
    try {
      streamingFiles.clear();
    } catch (_) {}
    streamingActive.value = false;
    livePreviewReady.value = false;
    _lastLiveWriteMs = 0;
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
      final createdCp =
          await _ws.saveCheckpoint(p.id, label: 'Project created');
      final raw = await _ask(
        prompt: 'Build this website with ${framework.value}: $t',
        system: webSystemPrompt(framework: framework.value),
        onProgress: (n) => _streamStatus('Writing project', n),
        onPartial: (buf) => unawaited(_flushPartial(buf, p.id)),
      );
      if (_cancelled) {
        // Live partial writes may already be on disk — roll back to the
        // empty just-created state so cancel means "never happened".
        try {
          await _ws.rollbackToCheckpoint(p.id, createdCp);
          await refreshFiles();
          _touch();
        } catch (_) {}
        term('■ build cancelled by user — rolled back');
        return;
      }
      buildStatus.value = 'Saving files…';
      final parsed = parseFiles(raw);
      final err = await _ws.importFiles(
          p.id, {for (final f in parsed) f.path: f.content});
      if (err != null) {
        lastError.value = 'Some files failed: $err';
      }
      await refreshFiles();
      await _serve();
      // Integrity gate (§8): what landed on disk must equal what the
      // model emitted — byte-for-byte — plus hygiene scan.
      final fidelity = await _verifyWriteFidelity(
          p.id, {for (final f in parsed) f.path: f.content});
      if (fidelity.isNotEmpty) {
        _mergeIssues(previewIssues, fidelity);
        final blocking =
            previewIssues.where((i) => i.blocksPreview).toList();
        if (blocking.isNotEmpty) {
          previewDecision.value = routePreview(
              kind: previewKind.value,
              issues: previewIssues.toList(),
              nodeAvailable: true);
          term('✗ source validation failed: ${blocking.map((i) => i.code).join(', ')}');
          _say('assistant',
              'Generated source validation failed — ${blocking.length} problem(s), not previewing blindly:\n${blocking.map((i) => '• ${i.message}').join('\n')}\nTap “Ask AI to Fix” and I’ll regenerate the broken files.');
        }
      }
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
      _clearStreaming();
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
      final beforeCp = await _ws.saveCheckpoint(p.id, label: 'Before modify');
      // Snapshot pre-modify contents for the diff view. Live partial
      // writes land on disk mid-stream, so "old" must come from BEFORE
      // generation — never from post-stream disk reads.
      Map<String, String> before = {};
      try {
        before = await _projectContents(p.id);
        var total = 0;
        for (final v in before.values) {
          total += v.length;
        }
        if (total > 1000000) before = {};
      } catch (_) {}
      final projContext = await _projectContext(p.id);
      final raw = await _ask(
        prompt: 'Modify the "${p.name}" ${p.framework} project: $t\n\n'
            'CURRENT FILES:\n$projContext\n\n'
            'LOCAL DEV CLIs (on-device): ${_cliContextLine()}\n\n'
            'Return a files-JSON object with ONLY new or fully-rewritten changed files.',
        system:
            '${webSystemPrompt(framework: p.framework)}\nSTRICT: output only files that change (plus any brand-new files).',
        onProgress: (n) => _streamStatus('Writing change', n),
        onPartial: (buf) => unawaited(_flushPartial(buf, p.id)),
      );
      if (_cancelled) {
        // Live partial writes may already be on disk — restore the
        // pre-modify snapshot so cancel is lossless.
        try {
          await _ws.rollbackToCheckpoint(p.id, beforeCp);
          await refreshFiles();
          _touch();
        } catch (_) {}
        term('■ modify cancelled by user — rolled back');
        return;
      }
      final parsed = parseFiles(raw);
      // Diff against the pre-modify snapshot (not live-written disk).
      lastDiffs.clear();
      for (final f in parsed) {
        final old = before[f.path] ?? await _ws.readFile(p.id, f.path);
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
      // Re-route preview diagnosis from current disk state (cheap and
      // pure — no server auto-start here; _serve owns that on open).
      final contentsNow = await _projectContents(p.id);
      final kindNow = detectProject(contentsNow);
      previewKind.value = kindNow;
      final fidelityNow = await _verifyWriteFidelity(
          p.id, {for (final f in parsed) f.path: f.content});
      for (final f in parsed) {
        fidelityNow.addAll(sourceHygieneIssues(f.path, f.content));
      }
      final mergedNow = validateProject(kindNow, contentsNow);
      _mergeIssues(mergedNow, fidelityNow);
      previewIssues.assignAll(mergedNow);
      var nodeOk = false;
      try {
        nodeOk =
            (await Get.find<RuntimeManager>().refresh()).nodeAvailable;
      } catch (_) {}
      previewDecision.value = routePreview(
          kind: kindNow,
          issues: previewIssues.toList(),
          nodeAvailable: nodeOk);
      final fidelityBlocking =
          fidelityNow.where((i) => i.blocksPreview).toList();
      if (fidelityBlocking.isNotEmpty) {
        term('✗ source validation failed: ${fidelityBlocking.map((i) => i.code).join(', ')}');
        _say('assistant',
            'Change applied, but source validation failed:\n${fidelityBlocking.map((i) => '• ${i.message}').join('\n')}\nTap “Ask AI to Fix” and I’ll regenerate the broken files.');
      }
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
      _clearStreaming();
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
            'LOCAL DEV CLIs (on-device): ${_cliContextLine()}\n\n'
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

  /// Read every project file into a path → content map (shared
  /// workspace: the SAME files the AI wrote, the terminal sees, and
  /// the preview serves — never a separate copy).
  Future<Map<String, String>> _projectContents(String projectId) async {
    final out = <String, String>{};
    for (final path in await _ws.listFiles(projectId)) {
      out[path] = await _ws.readFile(projectId, path) ?? '';
    }
    return out;
  }

  /// Route the project to its preview strategy, then serve.
  ///
  /// Static sites keep the exact previous behavior. Framework projects
  /// get a diagnosis + dev-server pipeline instead of being silently
  /// mis-served as static HTML (JSX never executes statically — that
  /// was the "unstyled HTML" preview bug).
  Future<void> _serve() async {
    final p = project.value;
    if (p == null) return;
    try {
      final dir = await _ws.dirFor(p.id);
      final contents = await _projectContents(p.id);
      final kind = detectProject(contents);
      previewKind.value = kind;
      final issues = validateProject(kind, contents);
      previewIssues.assignAll(issues);

      if (!projectNeedsNode(kind)) {
        previewSteps.assignAll([
          PreviewStep('Detect project', 'ok', projectKindLabel(kind)),
          const PreviewStep('Validate', 'ok', 'entry present'),
          const PreviewStep('Preview', 'ok', 'static server'),
        ]);
        previewDecision.value = routePreview(
            kind: kind, issues: issues, nodeAvailable: true);
        previewUrl.value = await _preview.start(p.id, dir.path);
        devServerUrl.value = null;
        return;
      }

      // Framework path: validate first, then runtime.
      final steps = <PreviewStep>[
        PreviewStep('Detect project', 'ok', projectKindLabel(kind)),
      ];
      final blocking = issues.where((i) => i.blocksPreview).toList();
      if (blocking.isNotEmpty) {
        steps.add(PreviewStep(
            'Validate', 'fail', '${blocking.length} blocker(s)'));
        steps.add(const PreviewStep('Preview', 'fail', 'blocked'));
        previewSteps.assignAll(steps);
        previewDecision.value = routePreview(
            kind: kind, issues: issues, nodeAvailable: false);
        term('✗ preview blocked: ${blocking.map((i) => i.code).join(', ')}');
        _say('assistant',
            'I generated a ${projectKindLabel(kind)} project, but ${blocking.length} structural problem(s) block preview:\n${blocking.map((i) => '• ${i.message}').join('\n')}\nTap “Ask AI to Fix” in the preview pane and I’ll repair them.');
        // Keep the static fallback servable for file inspection, but the
        // UI flags it as non-running (see previewDecision).
        previewUrl.value = await _preview.start(p.id, dir.path);
        devServerUrl.value = null;
        return;
      }
      steps.add(const PreviewStep('Validate', 'ok', 'structure clean'));

      final rt = Get.find<RuntimeManager>();
      final st = await rt.refresh();
      if (!st.nodeAvailable) {
        steps.add(const PreviewStep('Runtime', 'fail', 'Node.js missing'));
        steps.add(const PreviewStep('Preview', 'fail', 'needs runtime'));
        previewSteps.assignAll(steps);
        previewDecision.value = routePreview(
            kind: kind, issues: issues, nodeAvailable: false);
        term('✗ preview needs Node.js — runtime unavailable (${st.platform})');
        _say('assistant',
            'This is a ${projectKindLabel(kind)} project — it needs Node.js (`npm run dev`), which is not available on this device. '
            'Static serving cannot execute JSX, so the preview would only show unstyled HTML. '
            'Use “Recheck” after installing a runtime, “Cloud” if configured, or export the ZIP and run it where Node exists.');
        previewUrl.value = await _preview.start(p.id, dir.path);
        devServerUrl.value = null;
        return;
      }
      steps.add(PreviewStep(
          'Runtime', 'ok', 'node ${st.nodeVersion}'.trim()));
      previewSteps.assignAll(steps);
      previewDecision.value = routePreview(
          kind: kind, issues: issues, nodeAvailable: true);
      // Auto-start the dev server and point preview at the REAL url.
      await startDevServer();
    } catch (_) {
      previewUrl.value = null;
    }
  }

  /// Start (or reuse) the dev server and point the preview at it.
  /// Surfaces specific errors — never a generic dead preview.
  Future<void> startDevServer() async {
    final p = project.value;
    if (p == null || devServerStarting.value) return;
    devServerStarting.value = true;
    buildStatus.value = 'Starting dev server…';
    try {
      final dir = await _ws.dirFor(p.id);
      final mgr = Get.find<DevServerManager>();
      final session = await mgr.start(
        projectId: p.id,
        workDir: dir.path,
        kind: previewKind.value,
        onLog: term,
      );
      devServerUrl.value = session.url;
      previewUrl.value = session.url;
      _touch();
      final steps = previewSteps.toList()
        ..removeWhere((s) => s.label == 'Preview' || s.label == 'Server');
      steps.add(const PreviewStep('Deps', 'ok', 'node_modules ready'));
      steps.add(PreviewStep('Server', 'ok', session.url));
      steps.add(const PreviewStep('Preview', 'ok', 'live dev server'));
      previewSteps.assignAll(steps);
      term('✓ preview → live dev server ${session.url}');
      _say('assistant', 'Dev server is live — the preview now shows the real running app.');
    } on DevServerException catch (e) {
      term('✗ dev server: ${e.message}');
      final steps = previewSteps.toList()
        ..removeWhere((s) => s.label == 'Preview' || s.label == 'Server');
      steps.add(PreviewStep('Server', 'fail', e.code));
      steps.add(const PreviewStep('Preview', 'fail', 'server did not start'));
      previewSteps.assignAll(steps);
      lastError.value = e.message;
      _say('assistant', 'The dev server could not start: ${e.message}');
    } catch (e) {
      term('✗ dev server failed: $e');
      lastError.value = '$e';
    } finally {
      devServerStarting.value = false;
      buildStatus.value = null;
    }
  }

  /// Stop this project's dev server (if any). Never throws.
  Future<void> stopDevServer() async {
    final p = project.value;
    try {
      if (p != null) await Get.find<DevServerManager>().stop(p.id);
    } catch (_) {}
    devServerUrl.value = null;
    term('■ dev server stopped');
  }

  /// Re-probe the runtime and re-route preview (UI "Recheck" action).
  Future<void> recheckRuntimeAndServe() async {
    try {
      await Get.find<RuntimeManager>().refresh(force: true);
    } catch (_) {}
    final st = Get.find<RuntimeManager>().status.value;
    term(st.nodeAvailable
        ? '✓ runtime ready — node ${st.nodeVersion}, npm ${st.npmVersion}'
        : '✗ runtime still unavailable — ${st.lastError ?? 'no Node found'}');
    await _serve();
  }

  /// One-tap repair for structural preview blockers: feeds the issues
  /// back into the normal modify flow so the AI fixes them.
  Future<void> fixPreviewIssues() async {
    final blockers =
        previewIssues.where((i) => i.blocksPreview).toList();
    if (blockers.isEmpty || generating.value || fixing.value) return;
    topic.value = 'Fix these preview blockers in the "${project.value?.name}" project:\n'
        '${blockers.map((i) => '• [${i.path ?? 'project'}] ${i.message}').join('\n')}\n'
        'Return a files-JSON object with the corrected files (complete new contents).';
    await modifyProject();
  }

  /// Run a real shell command in the project dir (or app docs when no
  /// project). Output streams into the terminal buffer with exit code.
  /// `node --version`, `npm install`, `ls` etc. produce ACTUAL output.
  Future<void> runShellCommand(String command) async {
    final cmd = command.trim();
    if (cmd.isEmpty) return;
    if (!ProcessRunner.isSupported) {
      term('✗ shell unavailable on Web builds.');
      return;
    }
    // Secrets never hit the log or the persisted history.
    term('> ${redactCommand(cmd)}');
    try {
      Get.find<CliManagerService>().recordCommand(cmd);
    } catch (_) {}
    final parts = _splitCommand(cmd);
    if (parts.isEmpty) return;
    String workDir;
    try {
      final p = project.value;
      if (p == null) {
        // No project: run in the app's private docs dir (never a fake
        // project dir, never outside the sandbox).
        workDir = (await getApplicationDocumentsDirectory()).path;
      } else {
        workDir = (await _ws.dirFor(p.id)).path;
      }
    } catch (_) {
      workDir = '';
    }
    Map<String, String>? env;
    try {
      env = await Get.find<CliManagerService>().managedEnv();
    } catch (_) {}
    try {
      final exe =
          await ProcessRunner.resolveExecutable(parts.first) ?? parts.first;
      final session = await ProcessRunner.startSession(
        exe,
        parts.sublist(1),
        workingDirectory: workDir.isEmpty ? null : workDir,
        environment: env,
        commandLabel: cmd,
      );
      final sub1 = session.stdoutLines.listen(term);
      final sub2 = session.stderrLines.listen(term);
      final code = await session.exitCode;
      try {
        await sub1.cancel();
      } catch (_) {}
      try {
        await sub2.cancel();
      } catch (_) {}
      term(code == 0 ? '✓ exit 0' : '✗ exit $code');
      // Adopt terminal-installed CLIs into the manager (§34).
      if (code == 0) {
        try {
          final found = await Get.find<CliManagerService>()
              .detectAfterCommand(cmd, code);
          if (found != null) {
            detectedCliId.value = found.id;
            detectedCliVersion.value =
                Get.find<CliManagerService>().versions[found.id] ?? '';
          }
        } catch (_) {}
      }
    } catch (e) {
      term('✗ could not run "${redactCommand(cmd)}": $e');
    }
  }

  // ── Interactive CLI sessions ──

  /// Launch a managed CLI's real executable inside the current project
  /// (shared workspace) and attach the terminal input to its stdin.
  Future<void> openCli(String manifestId) async {
    CliManagerService mgr;
    try {
      mgr = Get.find<CliManagerService>();
    } catch (_) {
      term('✗ CLI manager unavailable.');
      return;
    }
    final m = mgr.manifestById(manifestId);
    if (m == null) return;
    await stopActiveCli(silent: true);
    String workDir;
    try {
      final p = project.value;
      workDir = p == null
          ? (await getApplicationDocumentsDirectory()).path
          : (await _ws.dirFor(p.id)).path;
    } catch (_) {
      term('✗ could not resolve working directory.');
      return;
    }
    try {
      final session = await mgr.launchInProject(m, workDir);
      activeCliId.value = m.id;
      final where = project.value?.name ?? 'sandbox';
      term('▶ ${m.displayName} started in $where — type below to interact, ■ to stop');
      session.stdoutLines.listen(term);
      session.stderrLines.listen(term);
      unawaited(session.exitCode.then((code) {
        if (activeCliId.value == m.id) activeCliId.value = null;
        term(code == 0
            ? '■ ${m.displayName} exited (0)'
            : '■ ${m.displayName} exited ($code)');
      }));
    } catch (e) {
      term('✗ could not start ${m.displayName}: $e');
      AppSnackbar.showTop(
        '${m.displayName} could not start',
        '$e',
        logHistory: false,
      );
    }
  }

  /// Send a line to the attached CLI's stdin (redacted in logs).
  void sendStdinToCli(String line) {
    final id = activeCliId.value;
    if (id == null) return;
    try {
      final s = Get.find<CliManagerService>().launchedSession(id);
      if (s == null) {
        activeCliId.value = null;
        term('■ session already ended');
        return;
      }
      term('› ${redactCommand(line)}');
      s.writeStdin('$line\n');
    } catch (_) {
      activeCliId.value = null;
    }
  }

  /// Stop the attached CLI: Ctrl+C (SIGINT) first, SIGTERM fallback.
  Future<void> stopActiveCli({bool silent = false}) async {
    final id = activeCliId.value;
    if (id == null) return;
    activeCliId.value = null;
    CliManagerService? mgr;
    try {
      mgr = Get.find<CliManagerService>();
    } catch (_) {}
    final s = mgr?.launchedSession(id);
    if (s == null) {
      if (!silent) term('■ session already ended');
      return;
    }
    if (!silent) term('■ stopping (Ctrl+C)…');
    try {
      await s.interrupt();
      await s.exitCode.timeout(const Duration(seconds: 3));
      if (!silent) term('■ stopped');
    } catch (_) {
      try {
        await mgr?.killLaunched(id);
        if (!silent) term('■ stopped');
      } catch (_) {}
    }
  }

  /// "Ask AI to Fix": send the latest terminal failure to the builder
  /// agent with command + error + project context (info only, the agent
  /// edits files through its normal confirmed flow).
  Future<void> askAiToFixTerminalError() async {
    if (generating.value || fixing.value) return;
    final p = project.value;
    if (p == null) {
      AppSnackbar.showTop('No project open',
          'Open or build a project first, then ask AI to fix.',
          logHistory: false);
      return;
    }
    final lines = terminal.toList();
    String lastCmd = '';
    final errs = <String>[];
    for (var i = lines.length - 1;
        i >= 0 && errs.length < 15 && (lines.length - i) < 60;
        i--) {
      final l = lines[i];
      final stripped = l.replaceFirst(RegExp(r'^\[\d{2}:\d{2}:\d{2}\] '), '');
      if (stripped.startsWith('> ') && lastCmd.isEmpty) {
        lastCmd = stripped.substring(2);
      }
      if (RegExp(r'✗|error|Error|ERR|failed|FAIL|Exception|EACCES|ENOENT')
          .hasMatch(l)) {
        errs.insert(0, l);
      }
    }
    if (errs.isEmpty) {
      AppSnackbar.showTop(
          'No errors', 'The terminal shows no recent failures.',
          logHistory: false);
      return;
    }
    topic.value = 'Fix this terminal failure in the "${p.name}" project'
        '${lastCmd.isEmpty ? '' : ' (command: $lastCmd)'}:\n'
        '${errs.join('\n')}\n\n'
        'LOCAL DEV CLIs (on-device): ${_cliContextLine()}\n'
        'Return a files-JSON object with the corrected files (complete new contents).';
    await modifyProject();
  }

  /// First-run welcome lines (§61). Shown once ever.
  Future<void> ensureTerminalWelcome() async {
    try {
      final mgr = Get.find<CliManagerService>();
      if (await mgr.consumeWelcome()) {
        term('Welcome to CubicLM Terminal');
        term('• Run real commands: node --version · npm install · ls');
        term('• Tap the package icon to install AI coding CLIs');
        term('• Launched CLIs run inside the current project');
      }
    } catch (_) {}
  }

  /// One info line for AI prompts so the agent knows local CLIs (§33).
  String _cliContextLine() {
    try {
      return Get.find<CliManagerService>().cliContextLine();
    } catch (_) {
      return 'none installed';
    }
  }

  /// Minimal shell-like split (handles single/double quotes).
  List<String> _splitCommand(String cmd) {
    final out = <String>[];
    final buf = StringBuffer();
    String? quote;
    for (var i = 0; i < cmd.length; i++) {
      final ch = cmd[i];
      if (quote != null) {
        if (ch == quote) {
          quote = null;
        } else {
          buf.write(ch);
        }
      } else if (ch == '"' || ch == "'") {
        quote = ch;
      } else if (ch == ' ' || ch == '\t') {
        if (buf.isNotEmpty) {
          out.add(buf.toString());
          buf.clear();
        }
      } else {
        buf.write(ch);
      }
    }
    if (buf.isNotEmpty) out.add(buf.toString());
    return out;
  }

  Future<void> deleteProject(String id) async {
    try {
      await Get.find<DevServerManager>().stop(id);
    } catch (_) {}
    if (project.value?.id == id) {
      project.value = null;
      files.clear();
      previewUrl.value = null;
      devServerUrl.value = null;
      previewIssues.clear();
      previewSteps.clear();
      previewDecision.value = null;
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
      void Function(int chars)? onProgress,
      void Function(String partial)? onPartial}) async {
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
    var lastPartialMs = 0;
    void bump(String chunk) {
      buf.write(chunk);
      count += chunk.length;
      try {
        onProgress?.call(count);
      } catch (_) {}
      // Throttled live-flush hook for streaming file preview (~2/sec).
      if (onPartial != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastPartialMs >= 500) {
          lastPartialMs = now;
          try {
            onPartial(buf.toString());
          } catch (_) {}
        }
      }
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
    try {
      Get.find<DevServerManager>().stopAll();
    } catch (_) {}
    super.onClose();
  }
}
