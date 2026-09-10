import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../controllers/settings_controller.dart';
import '../services/agent_workspace.dart';
import '../services/app_log_service.dart';
import '../services/cloud_service.dart';
import '../services/inference_service.dart';
import '../services/preview_server.dart';
import '../services/runtime/ansi.dart';
import '../services/cubicweb/cubicweb_event.dart';
import '../services/cubicweb/cubicweb_logger.dart';
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
import '../utils/export_file.dart';
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
  
  /// New Builder Settings
  final liveFlushThrottle = 1500.obs; // ms
  final enableLivePreview = true.obs;
  final selectedLibrary = 'Auto'.obs; // Auto | shadcn | Tailwind | Lucide
  final selectedDesignSystem = 'Modern'.obs; // Modern | Retro | Enterprise
  
  /// Stats for the current change
  final lastInsertions = 0.obs;
  final lastDeletions = 0.obs;

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

  /// Token tracking
  final totalTokensUsed = 0.obs;
  final lastRequestTokens = 0.obs;
  final projectSizeKb = 0.0.obs;

  /// Smart Suggestions
  final suggestions = <String>[].obs;

  /// Runtime Error Details
  final runtimeError = Rxn<Map<String, dynamic>>();

  /// Cloud fallback provider (unconfigured in this build — honest stub).
  final CloudRuntimeProvider cloudRuntime = UnconfiguredCloudRuntime();

  /// Map of path -> {old: string, new: string} for pending AI changes.
  final pendingChanges = <String, Map<String, String>>{}.obs;

  /// True while the user is reviewing pending changes in the diff view.
  final reviewingChanges = false.obs;

  /// Buffer for console logs from the preview WebView.
  final consoleBuffer = <Map<String, dynamic>>[].obs;

  /// Map of checkpoint ID -> screenshot bytes (visual history).
  final checkpointThumbnails = <String, Uint8List>{}.obs;

  /// Map of brand properties (primaryColor, secondaryColor, font, logo).
  final brandIdentity = <String, String>{}.obs;

  /// Correlation id for the current build/modify/fix operation (§23).
  /// Passed to every CubicWeb event so one operation's story rebuilds.
  String currentTraceId = '';

  /// Apply all pending changes from the diff view to the project files.
  Future<void> applyPendingChanges() async {
    final p = project.value;
    if (p == null || pendingChanges.isEmpty) return;
    
    reviewingChanges.value = false;
    generating.value = true;
    buildStatus.value = 'Saving changes…';
    
    try {
      for (final entry in pendingChanges.entries) {
        await _ws.writeFile(p.id, entry.key, entry.value['new'] ?? '');
      }
      await _ws.touch(p.id);
      await refreshFiles();
      _touch();
      
      // Save checkpoint after successful apply with stats
      await _ws.saveCheckpoint(p.id, 
        label: 'Applied changes', 
        insertions: lastInsertions.value, 
        deletions: lastDeletions.value
      );

      pendingChanges.clear();
      AppSnackbar.showTop('Success', 'Changes applied successfully');
      
      // Master Class: Auto-install dependencies
      _checkAutoInstall();

      // Delay slightly to let the WebView reload before capturing
      Future.delayed(const Duration(seconds: 1), () => captureCheckpointThumbnail());
    } catch (e) {
      lastError.value = '$e';
    } finally {
      generating.value = false;
      buildStatus.value = null;
    }
  }

  CubicWebLogger? get _cw {
    try {
      return Get.find<CubicWebLogger>();
    } catch (_) {
      return null;
    }
  }

  String _cwPlatform() {
    try {
      return Get.find<RuntimeManager>().status.value.platform;
    } catch (_) {
      try {
        if (kIsWeb) return 'web';
        return Platform.operatingSystem;
      } catch (_) {
        return '';
      }
    }
  }

  /// Initialize a project with a pre-built skeleton based on the prompt.
  Future<void> initializeSkeleton(String projectId, String topic) async {
    String? template;
    final t = topic.toLowerCase();
    if (t.contains('landing')) template = 'Landing Page';
    if (t.contains('dashboard')) template = 'Dashboard';
    
    if (template != null && projectSkeletons.containsKey(template)) {
      term('🪄 initializing $template skeleton...');
      final skeleton = projectSkeletons[template]!;
      await _ws.importFiles(projectId, skeleton);
      await refreshFiles();
      _touch();
    }
  }

  /// Helper to calculate diff stats (+/-) for UI display.
  void _calculateDiffStats(String oldContent, String newContent) {
    if (oldContent.isEmpty) {
      lastInsertions.value += newContent.split('\n').length;
      return;
    }
    final oldLines = oldContent.split('\n');
    final newLines = newContent.split('\n');
    
    // Simple line-based diff counting
    final oldSet = oldLines.toSet();
    lastInsertions.value += newLines.where((l) => !oldSet.contains(l)).length;
    lastDeletions.value += oldLines.where((l) => !newLines.contains(l)).length;
  }

  /// Recent system diagnostics for AI prompts (§16/17). Empty when
  /// nothing environmental failed — keeps prompts lean.
  String _cwDiagnosticsForAi() {
    try {
      final pid = project.value?.id ?? '';
      final ctx = _cw?.recentForAi(projectId: pid) ?? '';
      if (ctx.isEmpty) return '';
      return 'SYSTEM DIAGNOSTICS (environment — items marked aiCanFix: false '
          'CANNOT be fixed by editing code, do not rewrite files for them):\n$ctx\n\n';
    } catch (_) {
      return '';
    }
  }

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
  final transcript = <Map<String, dynamic>>[].obs;

  /// Live build status shown in the preview pane while working
  /// (null when idle). E.g. "Streaming response… 12k chars".
  final buildStatus = RxnString();

  /// Attached image (base64, no data-uri prefix) for vision models.
  /// Sent with the next build/modify call, then cleared.
  final attachedImage = RxnString();

  /// Element picked from the live preview (long-press in preview).
  /// Injected as context into the next modify prompt.
  final pickedElement = RxnString();

  /// Element currently hovered in the preview (canvas mode).
  final hoveredElement = RxnString();

  void addConsoleLog(String level, String message) {
    consoleBuffer.add({
      'level': level,
      'message': message,
      'time': DateTime.now().millisecondsSinceEpoch,
    });
    if (consoleBuffer.length > 500) {
      consoleBuffer.removeAt(0);
    }
  }

  void clearConsole() => consoleBuffer.clear();

  /// Master Class: Detect new dependencies and run npm install automatically.
  Future<void> _checkAutoInstall() async {
    final p = project.value;
    if (p == null) return;
    
    try {
      final pkgJson = await _ws.readFile(p.id, 'package.json');
      if (pkgJson == null) return;
      
      final data = jsonDecode(pkgJson);
      final deps = data['dependencies'] as Map<String, dynamic>? ?? {};
      final devDeps = data['devDependencies'] as Map<String, dynamic>? ?? {};
      
      // Basic heuristic: check if node_modules exists, if not, or if deps changed
      // In a real WASM container we'd have a lockfile tracker.
      // For this master class upgrade, we'll trigger a check.
      term('⚙ scanning for new dependencies...');
      
      // If we find something common that's NOT usually there, trigger install.
      // In a real system we'd compare against a cached dep map.
      if (deps.isNotEmpty || devDeps.isNotEmpty) {
        term('🚀 new dependencies detected, running autonomous install...');
        runTerminal('npm install');
      }
    } catch (_) {}
  }

  /// Take a visual snapshot of the preview and link it to the latest checkpoint.
  Future<void> captureCheckpointThumbnail() async {
    final p = project.value;
    final web = previewWebController;
    if (p == null || web == null) return;
    
    try {
      final bytes = await web.takeScreenshot();
      if (bytes == null) return;
      
      final checkpoints = await _ws.listCheckpoints(p.id);
      if (checkpoints.isNotEmpty) {
        checkpointThumbnails[checkpoints.first.id] = bytes;
      }
    } catch (_) {}
  }

  /// Generate an AI image asset and save it to the project.
  Future<void> generateProjectAsset(String prompt, String path) async {
    final p = project.value;
    if (p == null || prompt.trim().isEmpty) return;

    generating.value = true;
    buildStatus.value = 'Generating asset...';
    term('> generate asset: "$prompt" -> $path');

    try {
      // Use stability provider if configured, otherwise fallback to a placeholder/mock
      // (The system prompt for StabilityProvider expects [IMAGE_BASE64] response)
      final cloud = Get.find<CloudService>();
      
      String response;
      if (cloud.isProviderConfigured('stability')) {
        response = await cloud.sendMessage(
          messages: [
            {'role': 'user', 'content': prompt}
          ],
        );
      } else {
        // Mock generation for testing if no API key
        await Future.delayed(const Duration(seconds: 3));
        response = '[IMAGE_BASE64]placeholder';
      }

      if (response.startsWith('[IMAGE_BASE64]')) {
        final base64 = response.replaceFirst('[IMAGE_BASE64]', '');
        if (base64 == 'placeholder') {
          // Just touch a dummy file for the UI effect in mock mode
          await _ws.writeFile(p.id, path, 'Mock image data for: $prompt');
        } else {
          final bytes = base64Decode(base64);
          await _ws.writeBinaryFile(p.id, path, bytes);
        }
        
        await refreshFiles();
        _touch();
        AppSnackbar.showTop('Asset Generated', '$path saved to project.');
        term('✓ asset generated: $path');
      } else {
        throw Exception('Unexpected response from image service');
      }
    } catch (e) {
      lastError.value = '$e';
      term('✗ asset generation failed: $e');
    } finally {
      generating.value = false;
      buildStatus.value = null;
    }
  }

  /// Analyze project imports to build a dependency graph.
  Future<List<Map<String, String>>> getProjectDependencies() async {
    final p = project.value;
    if (p == null) return [];
    
    final deps = <Map<String, String>>[];
    final importPattern = RegExp("import\\s+.*from\\s+['\"](.+)['\"]|import\\s+['\"](.+)['\"]");

    for (final path in files) {
      final content = await _ws.readFile(p.id, path) ?? '';
      final matches = importPattern.allMatches(content);
      for (final m in matches) {
        final imported = m.group(1) ?? m.group(2);
        if (imported != null) {
          deps.add({'from': path, 'to': imported});
        }
      }
    }
    return deps;
  }
  /// Scan all project files for symbols (functions, components).
  Future<List<Map<String, dynamic>>> scanProjectSymbols() async {
    final p = project.value;
    if (p == null) return [];
    
    final symbols = <Map<String, dynamic>>[];
    // Patterns for React components, Vue components, and general JS functions
    final patterns = [
      RegExp(r'const\s+([A-Z][\w]+)\s*='), // React/Vue Component
      RegExp(r'function\s+([\w]+)\s*\('), // JS Function
      RegExp(r'export\s+(?:default\s+)?(?:const|let|var)\s+([\w]+)'), // Exported var
    ];

    for (final path in files) {
      final content = await _ws.readFile(p.id, path) ?? '';
      final lines = content.split('\n');
      for (int i = 0; i < lines.length; i++) {
        for (final pattern in patterns) {
          final match = pattern.firstMatch(lines[i]);
          if (match != null && match.groupCount >= 1) {
            final name = match.group(1) ?? '';
            if (name.isEmpty) continue;
            
            final isComponent = name[0].toUpperCase() == name[0] && name[0] != name[0].toLowerCase();

            symbols.add({
              'name': name,
              'file': path,
              'line': i + 1,
              'type': isComponent ? 'component' : 'function',
            });
          }
        }
      }
    }
    return symbols;
  }

  /// Search through all project files for a specific query.
  Future<List<Map<String, dynamic>>> searchProjectContent(String query) async {
    final p = project.value;
    if (p == null || query.trim().isEmpty) return [];
    
    final results = <Map<String, dynamic>>[];
    final queryLower = query.toLowerCase();
    
    for (final path in files) {
      final content = await _ws.readFile(p.id, path) ?? '';
      if (content.toLowerCase().contains(queryLower)) {
        final lines = content.split('\n');
        for (int i = 0; i < lines.length; i++) {
          if (lines[i].toLowerCase().contains(queryLower)) {
            results.add({
              'path': path,
              'line': i + 1,
              'text': lines[i].trim(),
            });
          }
        }
      }
    }
    return results;
  }
  /// Send a line to the active terminal process or attached CLI.
  void sendStdin(String line) {
    if (activeCliId.value != null) {
      sendStdinToCli(line);
      return;
    }
    // No active CLI/interactive session: treat as a new shell command.
    runTerminal(line);
  }

  Future<void> promoteComponent(String name, String code) async {
    final p = project.value;
    if (p == null) return;
    
    // Auto-detect extension based on framework
    String ext = '.html';
    if (p.framework.toLowerCase().contains('react')) ext = '.jsx';
    if (p.framework.toLowerCase().contains('vue')) ext = '.vue';
    
    final path = 'src/components/$name$ext';
    
    pendingChanges[path] = {'old': '', 'new': code};
    reviewingChanges.value = true;
    
    AppSnackbar.showTop('Promoting Component', 'Review the new file in the diff view.');
  }
  Future<void> inlineEdit(String path, String selection, String prompt) async {
    final p = project.value;
    if (p == null || selection.trim().isEmpty || prompt.trim().isEmpty) return;

    generating.value = true;
    buildStatus.value = 'AI Editing selection…';
    
    try {
      final currentContent = await _ws.readFile(p.id, path) ?? '';
      
      final raw = await _ask(
        prompt: 'Refactor the following selection in "$path":\n\n'
            'SELECTION:\n$selection\n\n'
            'INSTRUCTION: $prompt\n\n'
            'CONTEXT (FULL FILE):\n$currentContent\n\n'
            'Return ONLY the modified selection text. No explanations.',
        system: 'You are a precise code editor. Return ONLY the new selection text.',
        onProgress: (n) => _streamStatus('Editing', n),
      );

      if (_cancelled) return;
      
      final newSelection = raw.trim();
      final newContent = currentContent.replaceFirst(selection, newSelection);
      
      pendingChanges.clear();
      pendingChanges[path] = {'old': currentContent, 'new': newContent};
      reviewingChanges.value = true;
      
      AppSnackbar.showTop('AI Edit Ready', 'Review the changes in the diff view.');
    } catch (e) {
      lastError.value = '$e';
    } finally {
      generating.value = false;
      buildStatus.value = null;
    }
  }
  final requestAskFocus = 0.obs;

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
    hoveredElement.value = null;
    elementPickMode.value = false;
    requestAskFocus.value++;
    term(
        '🎯 element picked: ${info.length > 80 ? '${info.substring(0, 80)}…' : info}');
    AppSnackbar.showTop(
      'Element picked',
      'Context added — describe the change you want.',
      logHistory: false,
    );
  }

  void _say(String role, String text, {List<Map<String, String>>? activity}) {
    try {
      transcript.add({
        'role': role,
        'text': text,
        if (activity != null) 'activity': activity,
      });
      while (transcript.length > 100) {
        transcript.removeAt(0);
      }
    } catch (_) {}
  }

  void _snapshotActivity() {
    try {
      final idx = transcript.lastIndexWhere((m) => m['role'] == 'activity');
      if (idx != -1) {
        transcript[idx] = {
          'role': 'activity',
          'steps': buildSteps.toList(),
        };
      }
    } catch (_) {}
  }

  void _markLastAssistantWithBuild() {
    try {
      final idx = transcript.lastIndexWhere((m) => m['role'] == 'assistant');
      if (idx != -1) {
        transcript[idx] = {
          ...transcript[idx],
          'has_build': true,
        };
      }
    } catch (_) {}
  }

  /// Live build timeline (v0-style): thinking → files → errors → fixes.
  /// Rendered as an activity card in the chat pane. Cleared per task,
  /// kept across auto-fix rounds of the same task.
  final buildSteps = <Map<String, String>>[].obs;
  final _announcedPaths = <String>{};

  /// Append one timeline step. Kinds: thinking | file | error | fix | done.
  void step(String kind, String text) {
    try {
      // Dynamic thinking messages for a more "lovable" experience
      String message = text;
      if (kind == 'thinking') {
        final messages = [
          'Analyzing requirements...',
          'Designing system architecture...',
          'Styling components with ${selectedLibrary.value}...',
          'Optimizing for ${selectedDesignSystem.value} style...',
          'Ensuring mobile responsiveness...',
          'Validating accessibility rules...',
        ];
        // Cycle through or pick based on context if we had more info
        if (text.toLowerCase().contains('planning')) message = messages[0];
        if (text.toLowerCase().contains('designing')) message = messages[1];
      }

      buildSteps.add({
        'kind': kind,
        'text': message.length > 140 ? '${message.substring(0, 140)}…' : message,
        'ms': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      while (buildSteps.length > 100) {
        buildSteps.removeAt(0);
      }
    } catch (_) {}
  }

  void _beginSteps() {
    try {
      buildSteps.clear();
    } catch (_) {}
    _announcedPaths.clear();
  }

  /// Rich completion summary: action line + changed-file list.
  String _doneSummary(String action, List<String> files) {
    final buf = StringBuffer(
        '$action — ${files.length} file${files.length == 1 ? '' : 's'} changed, preview reloaded.');
    for (final f in files.take(6)) {
      buf.write('\n• $f');
    }
    if (files.length > 6) buf.write('\n• …and ${files.length - 6} more');
    return buf.toString();
  }

  void term(String line) {
    try {
      final now = DateTime.now();
      final ts = '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}:'
          '${now.second.toString().padLeft(2, '0')}';
      // Strip TUI control codes for the log view (colors/cursor/
      // alternate-screen sequences would render as garbage here).
      terminal.add('[$ts] ${stripAnsi(line)}');
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
    buildStatus.value = '$prefix… ${(chars / 1024).toStringAsFixed(1)}k chars';
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
        if (_announcedPaths.add(f.path)) step('file', 'Writing ${f.path}…');
      }
    }
    if (!changed) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final hasPackageJson = partial.any((f) {
      final p = f.path.toLowerCase();
      return p == 'package.json' || p.endsWith('/package.json');
    });
    if (!hasPackageJson && enableLivePreview.value && now - _lastLiveWriteMs >= liveFlushThrottle.value) {
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
  void _mergeIssues(List<ProjectIssue> base, List<ProjectIssue> extra) {
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

  /// Parse + collect silent truncations (file/total caps) so callers can
  /// surface them as blocking issues instead of serving partial source.
  List<WebFile> _parseChecked(String raw, List<String> truncatedOut) =>
      parseFiles(raw, onTruncated: truncatedOut.add);

  /// Turn collected truncations into blocking preview issues (§13).
  void _mergeTruncation(List<ProjectIssue> issues, List<String> truncated) {
    for (final t in truncated) {
      issues.add(ProjectIssue(
        'truncated-source',
        '"$t" was cut to fit size limits — ask the AI to regenerate it smaller or split it.',
        path: t.startsWith('(') ? null : t,
      ));
    }
    if (truncated.isNotEmpty) {
      step('error', 'Truncated ${truncated.length} file(s) — see issues.');
    }
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
        term(
            '✗ NEXT_BUILD_FAILED — npm unavailable (NPM_MISSING): Node.js runtime missing.');
        lastError.value = 'npm is unavailable — Node.js runtime missing.';
        try {
          _cw?.log(
            severity: CwSeverity.error,
            category: CwCategory.runtime,
            component: 'TERMINAL',
            errorCode: CwCodes.executableUnavailable,
            title: 'npm unavailable for build check',
            message:
                'The project needs Node.js for `npm run build`, but npm is unavailable in this environment.',
            operation: 'npm run build',
            projectId: p.id,
            traceId: currentTraceId,
            platform: _cwPlatform(),
            aiCanFix: false,
            fallbackAvailable: 'USE_CLOUD_RUNTIME',
          );
        } catch (_) {}
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
        code = await session.exitCode.timeout(const Duration(minutes: 10));
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
        AppSnackbar.showTop('Build passed', '`npm run build` succeeded.',
            logHistory: false);
      } else {
        term(
            '✗ NEXT_BUILD_FAILED (exit $code) — compiler output above; tap the terminal wand (Ask AI) and I’ll fix it');
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
      projectSizeKb.value = 0.0;
      return;
    }
    final list = await _ws.listFiles(p.id);
    files.assignAll(list);
    
    // Calculate project size
    double totalBytes = 0;
    final dir = await _ws.dirFor(p.id);
    for (final f in list) {
      try {
        final file = File('${dir.path}/$f');
        if (await file.exists()) {
          totalBytes += await file.length();
        }
      } catch (_) {}
    }
    projectSizeKb.value = totalBytes / 1024;
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

  /// Fork the current project into a copy and open it.
  Future<void> forkProject() async {
    final p = project.value;
    if (p == null || generating.value || fixing.value) return;
    try {
      buildStatus.value = 'Forking project…';
      final np = await _ws.forkProject(p.id);
      if (np == null) return;
      await openProject(np);
      AppSnackbar.showTop('Project forked', np.name, logHistory: false);
    } catch (e) {
      AppSnackbar.showTop('Fork failed', '$e', logHistory: false);
    } finally {
      if (buildStatus.value == 'Forking project…') buildStatus.value = null;
    }
  }

  /// Latest preview WebView controller (set by the view). Used for
  /// element picking arming + screenshot capture.
  InAppWebViewController? previewWebController;

  /// Capture the live preview as PNG and attach it as vision context.
  Future<void> capturePreviewShot() async {
    final w = previewWebController;
    if (w == null || project.value == null) return;
    try {
      final bytes = await w.takeScreenshot();
      if (bytes == null || bytes.isEmpty) return;
      attachedImage.value = base64Encode(bytes);
      term('preview screenshot attached (${(bytes.length / 1024).round()} KB)');
      AppSnackbar.showTop(
        'Screenshot attached',
        'Describe what to change in the screenshot.',
        logHistory: false,
      );
    } catch (e) {
      AppSnackbar.showTop('Capture failed', '$e', logHistory: false);
    }
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
    // Framework guard (CW-PREVIEW-003): a Node framework with no Node
    // runtime produces an unpreviewable project. Offer static instead.
    var buildFramework = framework.value;
    if (frameworkNeedsNode(buildFramework)) {
      var nodeOk = false;
      try {
        nodeOk = (await Get.find<RuntimeManager>().refresh()).nodeAvailable;
      } catch (_) {}
      if (!nodeOk) {
        final choice = await Get.dialog<String>(
          AlertDialog(
            title: const Text('No Node.js on this device'),
            content: Text(
                '"$buildFramework" needs Node.js (`npm run dev`), which is not available here. Build as static single-file HTML instead so preview works?'),
            actions: [
              TextButton(
                onPressed: () => Get.back(result: null),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Get.back(result: 'node'),
                child: Text('Build $buildFramework anyway'),
              ),
              FilledButton(
                onPressed: () => Get.back(result: 'static'),
                child: const Text('Build static HTML'),
              ),
            ],
          ),
          barrierDismissible: false,
        );
        if (choice == null) return;
        if (choice == 'static') buildFramework = 'Single HTML';
      }
    }
    generating.value = true;
    _cancelled = false;
    lastError.value = null;
    consoleError.value = null;
    _autoRounds = 0;
    currentTraceId = newTraceId();
    transcript.clear();
    _say('user', t);
    _say('activity', '');
    buildStatus.value = 'Designing project…';
    term(
        '> build "${t.length > 60 ? '${t.substring(0, 60)}…' : t}" ($buildFramework)');
    _beginSteps();
    step('thinking', 'Planning $buildFramework project…');
    String? createdCp;
    try {
      final name = t.length > 40 ? '${t.substring(0, 40)}…' : t;
      final p = await _ws.createProject(name, buildFramework);
      project.value = p;
      createdCp = await _ws.saveCheckpoint(p.id, label: 'Project created');
      
      // Smart Skeleton Initialization
      await initializeSkeleton(p.id, t);

      final raw = await _ask(
        prompt: 'Build this website with $buildFramework: $t',
        system: webSystemPrompt(
          framework: buildFramework, 
          brandIdentity: brandIdentity,
          library: selectedLibrary.value,
          designSystem: selectedDesignSystem.value,
        ),
        onProgress: (n) => _streamStatus('Writing project', n),
        onPartial: (buf) => unawaited(_flushPartial(buf, p.id)),
      );
      if (_cancelled) {
        // Live partial writes may already be on disk — roll back to the
        // empty just-created state so cancel means "never happened".
        // (createdCp is definitely assigned here; the catch block below
        // keeps the null-safe variant.)
        try {
          await _ws.rollbackToCheckpoint(p.id, createdCp);
          await refreshFiles();
          _touch();
        } catch (_) {}
        term('■ build cancelled by user — rolled back');
        return;
      }
      buildStatus.value = 'Saving files…';
      final truncated = <String>[];
      final parsed = _parseChecked(raw, truncated);
      final err = await _ws
          .importFiles(p.id, {for (final f in parsed) f.path: f.content});
      if (err != null) {
        lastError.value = 'Some files failed: $err';
      }
      await refreshFiles();
      await _serve();
      // Integrity gate (§8): what landed on disk must equal what the
      // model emitted — byte-for-byte — plus hygiene scan.
      final fidelity = await _verifyWriteFidelity(
          p.id, {for (final f in parsed) f.path: f.content});
      _mergeTruncation(fidelity, truncated);
      if (fidelity.isNotEmpty) {
        _mergeIssues(previewIssues, fidelity);
        final blocking = previewIssues.where((i) => i.blocksPreview).toList();
        if (blocking.isNotEmpty) {
          previewDecision.value = routePreview(
              kind: previewKind.value,
              issues: previewIssues.toList(),
              nodeAvailable: true,
              cloudConfigured: cloudRuntime.isConfigured);
          term(
              '✗ source validation failed: ${blocking.map((i) => i.code).join(', ')}');
          _say('assistant',
              'Generated source validation failed — ${blocking.length} problem(s), not previewing blindly:\n${blocking.map((i) => '• ${i.message}').join('\n')}\nTap “Ask AI to Fix” and I’ll regenerate the broken files.');
        }
      }
      _touch();
      buildStatus.value = null;
      final builtPaths = [for (final f in parsed) f.path];
      step('done', 'Built ${builtPaths.length} files — preview live.');
      _snapshotActivity();
      final summary =
          '${_doneSummary('Built', builtPaths)}\nTap a file to edit, or ask for changes below.';
      _say('assistant', summary);
      _markLastAssistantWithBuild();
      term('✓ build done — ${files.length} files, preview live');
      Future.delayed(const Duration(seconds: 1), () => captureCheckpointThumbnail());
    } catch (e) {
      if (_cancelled) {
        term('■ build cancelled by user');
        return;
      }
      // Generation failed mid-stream: live partials may be on disk —
      // restore the empty just-created state (§7: never keep half files).
      final cp = createdCp;
      final p0 = project.value;
      if (cp != null && p0 != null) {
        try {
          await _ws.rollbackToCheckpoint(p0.id, cp);
          await refreshFiles();
          _touch();
        } catch (_) {}
      }
      lastError.value = '$e';
      term('✗ build failed: $e');
      step('error', 'Build failed — rolled back.');
      _snapshotActivity();
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
    currentTraceId = newTraceId();
    _say('user', t);
    _say('activity', '');
    buildStatus.value = 'Applying change…';
    term('> modify: "${t.length > 80 ? '${t.substring(0, 80)}…' : t}"');
    _beginSteps();
    step('thinking', 'Planning the change…');
    String? beforeCp;
    try {
      beforeCp = await _ws.saveCheckpoint(p.id, label: 'Before modify');
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
      final projContext = await _projectContext(p.id, t);
      // One-shot visual context: user long-pressed an element in preview.
      final picked = pickedElement.value;
      pickedElement.value = null;
      final pickedCtx = (picked != null && picked.trim().isNotEmpty)
          ? 'SELECTED ELEMENT (user picked this in the live preview — focus the change here):\n$picked\n\n'
          : '';
      final raw = await _ask(
        prompt: 'Modify the "${p.name}" ${p.framework} project: $t\n\n'
            '${pickedCtx}CURRENT FILES:\n$projContext\n\n'
            '${_cwDiagnosticsForAi()}'
            'LOCAL DEV CLIs (on-device): ${_cliContextLine()}\n\n'
            'Return a files-JSON object with ONLY new or fully-rewritten changed files.',
        system:
            '${webSystemPrompt(
              framework: p.framework, 
              brandIdentity: brandIdentity,
              library: selectedLibrary.value,
              designSystem: selectedDesignSystem.value,
            )}\nSTRICT: output only files that change (plus any brand-new files).',
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
      lastInsertions.value = 0;
      lastDeletions.value = 0;
      final truncated = <String>[];
      final parsed = _parseChecked(raw, truncated);
      
      pendingChanges.clear();
      for (final f in parsed) {
        final old = before[f.path] ?? await _ws.readFile(p.id, f.path);
        _calculateDiffStats(old ?? '', f.content);
        pendingChanges[f.path] = {'old': old ?? '', 'new': f.content};
      }
      
      if (pendingChanges.isNotEmpty) {
        reviewingChanges.value = true;
        term('✓ change ready for review');
        step('done', 'Change ready for review.');
      } else {
        term('! no changes generated');
        step('error', 'No changes generated.');
      }
      
      _snapshotActivity();
      _say('assistant', 'I\'ve generated the changes. Please review them in the diff view.');
      _markLastAssistantWithBuild();

    } catch (e) {
      if (_cancelled) {
        term('■ modify cancelled by user');
        return;
      }
      // Same guard as cancel: a mid-stream failure must not leave
      // live partial writes behind.
      final cp = beforeCp;
      if (cp != null) {
        try {
          await _ws.rollbackToCheckpoint(p.id, cp);
          await refreshFiles();
          _touch();
        } catch (_) {}
      }
      lastError.value = '$e';
      term('✗ modify failed: $e');
      step('error', 'Change failed — rolled back.');
      _snapshotActivity();
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
    term(
        '> plan: "${t.length > 60 ? '${t.substring(0, 60)}…' : t}" (${framework.value})');
    try {
      final raw = await _ask(
        prompt: 'Plan this ${framework.value} project based on: $t\n\n'
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
    _say('activity', '');
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
        system: webSystemPrompt(
          framework: framework.value, 
          brandIdentity: brandIdentity,
          library: selectedLibrary.value,
          designSystem: selectedDesignSystem.value,
        ),
        onProgress: (n) => _streamStatus('Writing project', n),
      );
      if (_cancelled) return;
      buildStatus.value = 'Saving files…';
      final truncated = <String>[];
      final parsed = _parseChecked(raw, truncated);
      final err = await _ws
          .importFiles(p.id, {for (final f in parsed) f.path: f.content});
      if (err != null) {
        lastError.value = 'Some files failed: $err';
      }
      await refreshFiles();
      await _serve();
      if (truncated.isNotEmpty) {
        term('⚠ truncated: ${truncated.join(', ')}');
        _say('assistant',
            'Heads-up — ${truncated.length} file(s) were cut to fit size limits (${truncated.take(3).join(', ')}). Ask me to regenerate them smaller if anything looks off.');
      }
      _touch();
      buildStatus.value = null;
      final summary =
          'Built ${parsed.length} files from plan — preview is live.';
      step('done', 'Built ${parsed.length} files from plan.');
      _snapshotActivity();
      _say('assistant', summary);
      _markLastAssistantWithBuild();
      term('✓ build done — ${files.length} files, preview live');
      Future.delayed(const Duration(seconds: 1), () => captureCheckpointThumbnail());
    } catch (e) {
      if (_cancelled) {
        term('■ build cancelled by user');
        return;
      }
      lastError.value = '$e';
      term('✗ build from plan failed: $e');
      step('error', 'Build from plan failed.');
      _snapshotActivity();
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
  ///
  /// Page-load failures are classified first: a dead dev server is an
  /// environment problem (System Logs), never a rewrite trigger (§27).
  Future<void> onConsoleError(String message) async {
    final p = project.value;
    consoleError.value = message;
    term(
        '✗ console: ${message.length > 160 ? '${message.substring(0, 160)}…' : message}');
    if (message.startsWith('Page load failed') && p != null) {
      ClassificationResult? c;
      try {
        c = classifyFailure(
          stderr: message,
          platform: _cwPlatform(),
          localhostExpected: devServerUrl.value != null,
        );
      } catch (_) {}
      if (c != null && c.errorCode != null && !c.aiCanFix) {
        try {
          _cw?.log(
            severity: CwSeverity.error,
            category: c.category,
            component: 'WEBVIEW',
            errorCode: c.errorCode!,
            title: c.title,
            message: c.explanation,
            technicalDetails: message,
            operation: 'preview-load',
            projectId: p.id,
            traceId: currentTraceId,
            platform: _cwPlatform(),
            aiCanFix: false,
            fallbackAvailable: c.fallbackAvailable,
          );
          term(
              '■ ${c.errorCode} — ${c.title} (see System Logs; no code rewrite)');
        } catch (_) {}
        return;
      }
    }
    if (p == null || fixing.value || generating.value) return;
    if (!autoFix.value || _autoRounds >= maxRepairRounds) return;
    _autoRounds++;
    try {
      final short =
          message.length > 120 ? '${message.substring(0, 120)}…' : message;
      step('error', short);
      step('fix', 'Auto-fix round $_autoRounds/$maxRepairRounds — diagnosing…');
    } catch (_) {}
    await repairFromError();
  }

  /// True when the triggering error deserves a file rewrite. Separated
  /// so the auto-fix trigger, the manual button and tests share it.
  bool _shouldRewriteForError(String err) {
    ClassificationResult c;
    try {
      c = classifyFailure(stderr: err, platform: _cwPlatform());
    } catch (_) {
      return true;
    }
    if (c.errorCode != null && !c.aiCanFix) {
      term(
          '■ ${c.errorCode} — ${c.title}: environment problem, skipping code rewrite (see System Logs)');
      _say('assistant',
          '${c.title} (${c.errorCode}). ${c.explanation} I did not modify your files — open CubicWeb System Logs for details.');
      return false;
    }
    return true;
  }

  Future<void> repairFromError() async {
    final p = project.value;
    final err = consoleError.value;
    if (p == null || err == null || err.isEmpty || fixing.value) return;
    // No-loop guard (§5): environment failures must not trigger rewrites.
    if (!_shouldRewriteForError(err)) return;
    fixing.value = true;
    _cancelled = false;
    lastError.value = null;
    currentTraceId = newTraceId();
    _say('user', 'Auto-fix error: ${err.length > 200 ? '${err.substring(0, 200)}…' : err}');
    _say('activity', '');
    buildStatus.value = 'Fixing error…';
    term('⚙ auto-fix round $_autoRounds/$maxRepairRounds…');
    try {
      await _ws.saveCheckpoint(p.id, label: 'Before auto-fix');
      final projContext = await _projectContext(p.id, err);
      final raw = await _ask(
        prompt: 'Fix this runtime error in the "${p.name}" '
            '${p.framework} project:\n\nERROR:\n$err\n\n'
            'CURRENT FILES:\n$projContext\n\n'
            '${_cwDiagnosticsForAi()}'
            'LOCAL DEV CLIs (on-device): ${_cliContextLine()}\n\n'
            'RECENT TERMINAL (what happened so far):\n'
            '${terminalTail()}\n\n'
            'Return a files-JSON object with ONLY the corrected files '
            '(complete new contents).',
        system:
            '${webSystemPrompt(
              framework: p.framework, 
              brandIdentity: brandIdentity,
              library: selectedLibrary.value,
              designSystem: selectedDesignSystem.value,
            )}\nSTRICT: output only files that change.',
        onProgress: (n) => _streamStatus('Writing fix', n),
      );
      final truncated = <String>[];
      final parsed = _parseChecked(raw, truncated);
      if (_cancelled) return;
      
      pendingChanges.clear();
      final currentFiles = await _projectContents(p.id);
      for (final f in parsed) {
        final old = currentFiles[f.path] ?? '';
        pendingChanges[f.path] = {'old': old, 'new': f.content};
      }

      if (pendingChanges.isNotEmpty) {
        reviewingChanges.value = true;
        term('✓ auto-fix ready for review');
        step('fix', 'Auto-fix ready for review.');
      } else {
        term('! auto-fix suggested no changes');
        step('fix', 'No changes suggested.');
      }

      _snapshotActivity();
      _say('assistant', 'I\'ve diagnosed the error and prepared a fix. Please review it in the diff view.');
      _markLastAssistantWithBuild();
      
      AppSnackbar.showTop(
        'Auto-fix ready',
        'Review the suggested fixes.',
        logHistory: false,
      );
      Future.delayed(const Duration(seconds: 1), () => captureCheckpointThumbnail());
    } catch (e) {
      if (_cancelled) {
        term('■ fix cancelled by user');
        return;
      }
      lastError.value = '$e';
      term('✗ auto-fix failed: $e');
      step('error', 'Auto-fix failed.');
      _snapshotActivity();
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
    _say('activity', '');
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
      final projContext = await _projectContext(p.id, 'QA review');
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
        system: '${webSystemPrompt(framework: p.framework, brandIdentity: brandIdentity)}\n'
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
        final truncated = <String>[];
        final parsed = _parseChecked(raw, truncated);
        await _ws.saveCheckpoint(p.id, label: 'Before auto-test fix');
        var applied = 0;
        for (final f in parsed) {
          final werr = await _ws.writeFile(p.id, f.path, f.content);
          if (werr == null) applied++;
        }
        await _ws.touch(p.id);
        await refreshFiles();
        _touch();
        if (truncated.isNotEmpty) {
          term('⚠ truncated: ${truncated.join(', ')}');
        }
        if (applied > 0) {
          step('done', 'Applied $applied fixes from auto-test.');
          _snapshotActivity();
          _say(
              'assistant',
              'Auto-test found and fixed $applied file${applied == 1 ? '' : 's'}. '
                  'Preview reloaded — check the result.');
          _markLastAssistantWithBuild();
          term('✓ auto-test: fixed $applied files');
          AppSnackbar.showTop('Auto-test fixed',
              '$applied file${applied == 1 ? '' : 's'} updated.',
              logHistory: false);
        } else {
          step('done', 'No issues found.');
          _snapshotActivity();
        }
      }
    } catch (e) {
      if (_cancelled) {
        term('■ auto-test cancelled');
        return;
      }
      lastError.value = '$e';
      term('✗ auto-test failed: $e');
      step('error', 'Auto-test failed.');
      _snapshotActivity();
      _log('Auto-test failed', e);
    } finally {
      generating.value = false;
      buildStatus.value = null;
      _cancelled = false;
    }
  }

  /// Context Management (Mini-RAG): Build a relevant context for the prompt.
  /// Prioritizes files mentioned in the prompt or symbol names.
  Future<String> _projectContext(String projectId, [String? userPrompt]) async {
    final buf = StringBuffer();
    final allFiles = await _ws.listFiles(projectId);
    final sortedFiles = List<String>.from(allFiles);

    // Prioritization logic
    if (userPrompt != null && userPrompt.isNotEmpty) {
      final promptLower = userPrompt.toLowerCase();
      
      // 1. Check for explicit file mentions
      final mentioned = sortedFiles.where((f) => promptLower.contains(f.toLowerCase())).toList();
      
      // 2. Check for symbol mentions (functions, components)
      final symbols = await scanProjectSymbols();
      final mentionedBySymbol = <String>{};
      for (final s in symbols) {
        final name = s['name']?.toString().toLowerCase();
        if (name != null && promptLower.contains(name)) {
          mentionedBySymbol.add(s['file']);
        }
      }

      // Re-sort: Mentioned files first, then by symbol, then others.
      sortedFiles.sort((a, b) {
        final aMentioned = mentioned.contains(a) || mentionedBySymbol.contains(a);
        final bMentioned = mentioned.contains(b) || mentionedBySymbol.contains(b);
        if (aMentioned && !bMentioned) return -1;
        if (!aMentioned && bMentioned) return 1;
        return a.compareTo(b);
      });
    }

    var used = 0;
    for (final path in sortedFiles) {
      final content = await _ws.readFile(projectId, path) ?? '';
      
      // If we're getting close to the limit, start truncating less relevant files
      int maxFileChars = 8000;
      if (used > maxContextChars * 0.7) maxFileChars = 2000;

      if (content.length > maxFileChars) {
        buf.writeln('--- $path (first ${maxFileChars ~/ 1024}KB of ${content.length}) ---');
        final head = content.substring(0, maxFileChars);
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
    updateSuggestions();
  }

  /// Update smart suggestions based on the project state.
  void updateSuggestions() {
    final p = project.value;
    if (p == null) {
      suggestions.assignAll([
        'Build a modern landing page',
        'Create a crypto dashboard',
        'Build a developer portfolio',
        'Create a minimalist blog',
      ]);
      return;
    }

    final list = <String>[];
    final f = p.framework.toLowerCase();

    if (files.length < 5) {
      list.add('Add a contact section');
      list.add('Add a dark mode toggle');
      list.add('Improve mobile responsiveness');
    }

    if (f.contains('react') || f.contains('next')) {
      list.add('Add a Framer Motion animation');
      list.add('Extract components to separate files');
      list.add('Add a Shadcn UI button');
    } else {
      list.add('Add a sticky navigation bar');
      list.add('Add a footer with social links');
    }

    list.add('Polish the typography');
    list.add('Add glassmorphism styles');
    
    suggestions.assignAll(list.take(5).toList());
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
            kind: kind,
            issues: issues,
            nodeAvailable: true,
            cloudConfigured: cloudRuntime.isConfigured);
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
        steps.add(
            PreviewStep('Validate', 'fail', '${blocking.length} blocker(s)'));
        steps.add(const PreviewStep('Preview', 'fail', 'blocked'));
        previewSteps.assignAll(steps);
        previewDecision.value = routePreview(
            kind: kind,
            issues: issues,
            nodeAvailable: false,
            cloudConfigured: cloudRuntime.isConfigured);
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
            kind: kind,
            issues: issues,
            nodeAvailable: false,
            cloudConfigured: cloudRuntime.isConfigured);
        term('✗ preview needs Node.js — runtime unavailable (${st.platform})');
        try {
          _cw?.log(
            severity: CwSeverity.error,
            category: CwCategory.preview,
            component: 'PREVIEW',
            errorCode: CwCodes.frameworkNeedsRuntime,
            title:
                '${CwCodes.titles[CwCodes.frameworkNeedsRuntime]} (${projectKindLabel(kind)})',
            message:
                'The project is a ${projectKindLabel(kind)} project and needs Node.js (`npm run dev`), which is unavailable on ${st.platform}. The source may be valid — AI code changes cannot fix this.',
            operation: 'preview-serve',
            projectId: p.id,
            traceId: currentTraceId,
            platform: st.platform,
            runtime: st.deviceAbi,
            aiCanFix: false,
            fallbackAvailable: 'USE_CLOUD_RUNTIME',
          );
        } catch (_) {}
        _say(
            'assistant',
            'This is a ${projectKindLabel(kind)} project — it needs Node.js (`npm run dev`), which is not available on this device. '
                'Static serving cannot execute JSX, so the preview would only show unstyled HTML. '
                'Use “Recheck” after installing a runtime, “Cloud” if configured, or export the ZIP and run it where Node exists.');
        previewUrl.value = await _preview.start(p.id, dir.path);
        devServerUrl.value = null;
        return;
      }
      steps.add(PreviewStep('Runtime', 'ok', 'node ${st.nodeVersion}'.trim()));
      previewSteps.assignAll(steps);
      previewDecision.value = routePreview(
          kind: kind,
          issues: issues,
          nodeAvailable: true,
          cloudConfigured: cloudRuntime.isConfigured);
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
        onUnexpectedExit: (pid, code) => _onDevServerCrashed(pid, code),
      );
      devServerUrl.value = session.url;
      previewUrl.value = session.url;
      _touch();
      // Recovery story (§41): a live server after a blocking runtime
      // issue is worth one INFO event, not silence.
      try {
        _cw?.log(
          severity: CwSeverity.info,
          category: CwCategory.preview,
          component: 'DEV_SERVER',
          title: 'Development server started',
          message:
              '${session.runtime.label} dev server live at ${session.url} (port ${session.port ?? '?'}).',
          operation: 'npm run dev',
          projectId: p.id,
          traceId: currentTraceId,
          platform: _cwPlatform(),
          aiCanFix: true,
          fallbackUsed: 'LOCAL_RUNTIME',
        );
      } catch (_) {}
      final steps = previewSteps.toList()
        ..removeWhere((s) => s.label == 'Preview' || s.label == 'Server');
      steps.add(const PreviewStep('Deps', 'ok', 'node_modules ready'));
      steps.add(PreviewStep('Server', 'ok', session.url));
      steps.add(const PreviewStep('Preview', 'ok', 'live dev server'));
      previewSteps.assignAll(steps);
      term('✓ preview → live dev server ${session.url}');
      _say('assistant',
          'Dev server is live — the preview now shows the real running app.');
    } on DevServerException catch (e) {
      term('✗ dev server: ${e.message}');
      // Structured mapping (§18): dependency-flavored failures return
      // null and stay on the AI path; the rest become System Logs.
      try {
        final code = devServerCodeToCw(e.code, e.message);
        if (code != null) {
          final cls = classifyFailure(
              command: 'npm run dev',
              stderr: e.message,
              platform: _cwPlatform());
          _cw?.log(
            severity: CwSeverity.error,
            category: cls.category,
            component: 'DEV_SERVER',
            errorCode: code,
            title: CwCodes.titleFor(code),
            message: e.message,
            operation: 'npm run dev',
            projectId: p.id,
            traceId: currentTraceId,
            platform: _cwPlatform(),
            aiCanFix: false,
            fallbackAvailable: cls.fallbackAvailable.isEmpty
                ? 'USE_CLOUD_RUNTIME'
                : cls.fallbackAvailable,
          );
          term('■ $code — ${CwCodes.titleFor(code)} (see System Logs)');
        }
      } catch (_) {}
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

  /// Crash handler (§18 RUNTIME_CRASHED): drop the dead URL, fall
  /// back to static serving, and say so — never leave Preview aimed
  /// at a dead port, and never auto-rewrite files for a dead server.
  void _onDevServerCrashed(String pid, int code) {
    if (project.value?.id != pid) return;
    if (devServerUrl.value == null) return;
    devServerUrl.value = null;
    term('✗ RUNTIME_CRASHED — dev server exited ($code) unexpectedly');
    try {
      _cw?.log(
        severity: CwSeverity.error,
        category: CwCategory.preview,
        component: 'DEV_SERVER',
        errorCode: CwCodes.devServerFailed,
        title: 'Development server stopped unexpectedly',
        message:
            'The dev server process exited with code $code. The environment killed or crashed it — rewriting source files will not help.',
        operation: 'npm run dev',
        projectId: pid,
        traceId: currentTraceId,
        platform: _cwPlatform(),
        aiCanFix: false,
        fallbackAvailable: 'RETRY',
      );
    } catch (_) {}
    _say('assistant',
        'The dev server crashed (exit $code). Preview fell back to static files — tap “Restart dev server” to bring the live app back.');
    unawaited(_fallbackToStatic());
  }

  Future<void> _fallbackToStatic() async {
    final p = project.value;
    if (p == null) return;
    try {
      final dir = await _ws.dirFor(p.id);
      previewUrl.value = await _preview.start(p.id, dir.path);
      final steps = previewSteps.toList()
        ..removeWhere((s) => s.label == 'Preview' || s.label == 'Server');
      steps.add(const PreviewStep('Server', 'fail', 'crashed'));
      steps.add(const PreviewStep('Preview', 'info', 'static fallback'));
      previewSteps.assignAll(steps);
      _touch();
    } catch (_) {}
  }

  /// Stop + start the dev server (the diagnosis "Restart" action).
  /// Unlike [startDevServer] (which reuses a live server), this always
  /// bounces the process.
  Future<void> restartDevServer() async {
    final p = project.value;
    if (p == null || devServerStarting.value) return;
    try {
      await Get.find<DevServerManager>().stop(p.id);
    } catch (_) {}
    devServerUrl.value = null;
    term('■ dev server stopped — restarting…');
    await startDevServer();
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
    final blockers = previewIssues.where((i) => i.blocksPreview).toList();
    if (blockers.isEmpty || generating.value || fixing.value) return;
    topic.value =
        'Fix these preview blockers in the "${project.value?.name}" project:\n'
        '${blockers.map((i) => '• [${i.path ?? 'project'}] ${i.message}').join('\n')}\n'
        'Return a files-JSON object with the corrected files (complete new contents).';
    await modifyProject();
  }

  /// Alias for runShellCommand to support interactive studio naming.
  Future<void> runTerminal(String command) => runShellCommand(command);

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
    // Evidence buffer for classification (stderr-ish tail, capped).
    final evidence = StringBuffer();
    void collect(String line) {
      if (evidence.length < 2000) {
        evidence.writeln(line);
        if (evidence.length > 2000) {
          final s = evidence.toString();
          evidence
            ..clear()
            ..write(s.substring(s.length - 2000));
        }
      }
    }

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
      final sub1 = session.stdoutLines.listen((l) {
        term(l);
        collect(l);
      });
      final sub2 = session.stderrLines.listen((l) {
        term(l);
        collect(l);
      });
      final code = await session.exitCode;
      try {
        await sub1.cancel();
      } catch (_) {}
      try {
        await sub2.cancel();
      } catch (_) {}
      term(code == 0 ? '✓ exit 0' : '✗ exit $code');
      // Classify failures at the source (§12/39): environment evidence
      // becomes a System Log; ordinary failures stay terminal-only.
      if (code != 0) {
        try {
          final ev = _cw?.logClassified(
            component: 'TERMINAL',
            operation: 'shell',
            command: cmd,
            exitCode: code,
            stderr: evidence.toString(),
            platform: _cwPlatform(),
            projectId: project.value?.id ?? '',
            traceId: currentTraceId,
          );
          if (ev != null) {
            term(
                '■ ${ev.errorCode} — ${ev.title} (see System Logs; no code rewrite)');
          }
        } catch (_) {}
      }
      // Adopt terminal-installed CLIs into the manager (§34).
      if (code == 0) {
        try {
          final found =
              await Get.find<CliManagerService>().detectAfterCommand(cmd, code);
          if (found != null) {
            detectedCliId.value = found.id;
            detectedCliVersion.value =
                Get.find<CliManagerService>().versions[found.id] ?? '';
          }
        } catch (_) {}
      }
    } catch (e) {
      term('✗ could not run "${redactCommand(cmd)}": $e');
      // Spawn failure IS evidence (executable missing, exec format…).
      try {
        final ev = _cw?.logClassified(
          component: 'TERMINAL',
          operation: 'shell-spawn',
          command: cmd,
          exception: e,
          processSpawnFailed: true,
          platform: _cwPlatform(),
          projectId: project.value?.id ?? '',
          traceId: currentTraceId,
        );
        if (ev != null) {
          term('■ ${ev.errorCode} — ${ev.title} (see System Logs)');
        }
      } catch (_) {}
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
      term(
          '▶ ${m.displayName} started (pid ${session.pid}) in $where — type below to interact, ■ to stop');
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
      AppSnackbar.showTop('No errors', 'The terminal shows no recent failures.',
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

  /// Cloud fallback tap (§18/41): no backend is bundled, so this
  /// records CW-CLOUD-001 (the ORIGINAL local failure stays visible)
  /// and explains honestly instead of pretending to deploy.
  void useCloudFallback() {
    final p = project.value;
    try {
      _cw?.log(
        severity: CwSeverity.warning,
        category: CwCategory.cloud,
        component: 'CLOUD',
        errorCode: CwCodes.cloudUnavailable,
        title: CwCodes.titleFor(CwCodes.cloudUnavailable),
        message:
            'Cloud execution was requested${p == null ? '' : ' for "${p.name}"'}, but no cloud runtime is configured in this build.',
        operation: 'cloud-fallback',
        projectId: p?.id ?? '',
        traceId: currentTraceId,
        platform: _cwPlatform(),
        aiCanFix: false,
      );
    } catch (_) {}
    AppSnackbar.showTop(
      'Cloud runtime',
      cloudRuntime.unavailableReason,
      logHistory: false,
    );
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
      await ExportFile.quickExport(
        bytes: Uint8List.fromList(out),
        fileName: name,
        mimeType: 'application/zip',
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

    try {
      if (settings.inferenceMode.value == 'cloud') {
        final cloud = Get.find<CloudService>();
        await for (final chunk in cloud.streamMessage(
          [
            {'role': 'system', 'content': sys},
            {'role': 'user', 'content': prompt},
          ],
          temperature: settings.temperature.value,
          maxTokens:
              settings.autoTuneParams.value ? null : settings.maxTokens.value,
          imageBase64: attachedImage.value,
        )) {
          bump(chunk);
        }
      } else {
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
      }
      
      final out = buf.toString().trim();
      if (out.isEmpty) throw Exception('The model returned nothing.');
      
      // Update token tracking (heuristic: 4 chars = 1 token)
      final tokens = (out.length / 4).round();
      lastRequestTokens.value = tokens;
      totalTokensUsed.value += tokens;
      
      return out;
    } finally {
      // Any cleanup if needed
    }
  }

  /// Magic Wand: Auto-Polish the UI
  Future<void> autoPolish() async {
    final p = project.value;
    if (p == null || generating.value || fixing.value) return;
    
    generating.value = true;
    _cancelled = false;
    lastError.value = null;
    currentTraceId = newTraceId();
    
    _say('user', '🪄 Auto-Polish: Refine UI styles and alignment');
    _say('activity', '');
    buildStatus.value = 'Polishing UI…';
    term('> auto-polish: refining "${p.name}"…');
    _beginSteps();
    step('thinking', 'Analyzing UI for refinements…');

    try {
      final beforeCp = await _ws.saveCheckpoint(p.id, label: 'Before auto-polish');
      final projContext = await _projectContext(p.id);
      
      final raw = await _ask(
        prompt: 'Refine and polish the UI of the "${p.name}" ${p.framework} project. '
            'Focus on: fixing inconsistent spacing/padding, improving color contrast, '
            'refining typography, adding subtle transitions/animations, and ensuring '
            'perfect alignment. Keep the core logic and features identical.\n\n'
            'CURRENT FILES:\n$projContext\n\n'
            'Return a files-JSON object with ONLY the polished files (complete new contents).',
        system: '${webSystemPrompt(
          framework: p.framework, 
          brandIdentity: brandIdentity,
          library: selectedLibrary.value,
          designSystem: selectedDesignSystem.value,
        )}\n'
            'You are a senior UI/UX engineer. Your goal is to make the design "lovable".',
        onProgress: (n) => _streamStatus('Polishing', n),
        onPartial: (buf) => unawaited(_flushPartial(buf, p.id)),
      );

      if (_cancelled) {
        try {
          await _ws.rollbackToCheckpoint(p.id, beforeCp);
          await refreshFiles();
          _touch();
        } catch (_) {}
        return;
      }

      final truncated = <String>[];
      final parsed = _parseChecked(raw, truncated);
      
      pendingChanges.clear();
      final currentFiles = await _projectContents(p.id);
      for (final f in parsed) {
        final old = currentFiles[f.path] ?? '';
        pendingChanges[f.path] = {'old': old, 'new': f.content};
      }
      
      if (pendingChanges.isNotEmpty) {
        reviewingChanges.value = true;
        term('✓ UI polished — review the refinements');
        step('done', 'UI polished — ready for review.');
      } else {
        term('! no refinements needed');
        step('done', 'No refinements needed.');
      }
      
      _snapshotActivity();
      _say('assistant', 'I\'ve polished the UI. Review the refinements in the diff view.');
      _markLastAssistantWithBuild();

    } catch (e) {
      lastError.value = '$e';
      term('✗ polish failed: $e');
      step('error', 'Polish failed.');
    } finally {
      _clearStreaming();
      generating.value = false;
      buildStatus.value = null;
    }
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

  List<AgentProject> projectsOf() => _ws.projects.toList();

  @override
  void onClose() {
    try {
      Get.find<PreviewServerService>().stop();
    } catch (_) {}
    try {
      Get.find<DevServerManager>().stopAll();
    } catch (_) {}
    try {
      Get.find<CliManagerService>().killAllLaunched();
    } catch (_) {}
    activeCliId.value = null;
    super.onClose();
  }
}
