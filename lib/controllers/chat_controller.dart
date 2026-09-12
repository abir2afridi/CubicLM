import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart'
    show compute, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:uuid/uuid.dart';
import '../controllers/settings_controller.dart';
import '../controllers/model_controller.dart';
import '../controllers/cloud_model_controller.dart';
import '../controllers/home_controller.dart';
import '../core/constants.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../models/project_model.dart';
import '../models/folder_model.dart';
import '../ffi/sd_ffi_bindings.dart';
import '../services/hive_service.dart';
import '../services/chat_backup.dart';
import '../services/web_fetch_service.dart';
import '../services/inference_service.dart';
import '../services/cloud_service.dart';
import '../services/local_image_service.dart';
import '../services/tts_service.dart';
import '../services/app_log_service.dart';
import '../services/image_generation_notification_service.dart';
import '../services/document_extractor_service.dart';
import '../services/skills/skill_injector.dart';
import '../models/web_source.dart';
import '../utils/thought_parser.dart';
import '../utils/history_budget.dart';
import '../services/stats_service.dart';
import '../services/memory_service.dart';
import '../services/vector_service.dart';
import '../utils/artifact_parser.dart';

const int _visionImageMaxSide = 768;
const int _visionImageJpegQuality = 72;

class ChatController extends GetxController {
  final HiveService _hive = Get.find<HiveService>();
  final _uuid = const Uuid();

  // State
  final sessions = <ChatSession>[].obs;
  final messages = <ChatMessage>[].obs;
  final projects = <ChatProject>[].obs;
  final folders = <ChatFolder>[].obs;
  final currentSessionId = ''.obs;
  final currentProjectId = Rxn<String>();
  final isLoading = false.obs;
  final inputText = ''.obs;
  final selectedImagePath = Rxn<String>();
  final selectedImageBase64 = Rxn<String>();
  final selectedFileName = Rxn<String>();
  final selectedFileContent = Rxn<String>();
  final selectedFilePath = Rxn<String>();
  final selectedFileType = Rxn<String>();
  final selectedFileSize = 0.obs;
  final selectedFileChunks = <String>[].obs;

  // Real-time streaming state — the AI response as it's being generated
  final streamingResponse = ''.obs;
  final streamingThought = ''.obs;
  final streamingAnswer = ''.obs;
  final streamingIsThinking = false.obs;
  final isStreaming = false.obs;
  final streamingAttachmentType = Rxn<String>();
  final generationStartTime = Rxn<DateTime>();
  final generationLiveDurationSecs = 0.obs;
  Timer? _generationTimer;

  // Image generation progress (lightweight, replaces text-heavy updates)
  final imageGenStep = 0.obs;
  final imageGenTotal = 0.obs;
  final imageGenEstimatedSecs = 0.obs;
  final imageGenStartTime = Rxn<DateTime>();
  final imageGenDecoding = false.obs;

  // UI state
  final showScrollToBottom = false.obs;

  // Artifacts (Claude-style side panel)
  final activeArtifactId = Rxn<String>();
  final artifacts = <String, List<Map<String, String>>>{}
      .obs; // id -> [{title, type, content, timestamp}]
  final showArtifactPanel = false.obs;

  // Search Mode (Perplexity-style)
  final isSearchMode = false.obs;

  // Prompt templates
  static const _kTemplatesKey = 'prompt_templates_v1';
  final promptTemplates = <Map<String, String>>[].obs;
  bool _templatesLoaded = false;
  final templateSearchQuery = ''.obs;

  List<Map<String, String>> get filteredTemplates {
    final query = templateSearchQuery.value.toLowerCase();
    if (query.isEmpty) return promptTemplates;
    return promptTemplates.where((t) {
      final name = (t['name'] ?? '').toLowerCase();
      final body = (t['body'] ?? '').toLowerCase();
      return name.contains(query) || body.contains(query);
    }).toList();
  }

  // Multi-select
  final selectionMode = false.obs;
  final selectedIds = <String>{}.obs;

  // Side-by-side compare
  Map<String, String>? _compareRef;
  final compareLabel = ''.obs;

  // Streaming draft
  String? _draftMsgId;

  void openArtifact(String id, String content, {String? title, String? type}) {
    final version = {
      'title': title ?? 'Artifact',
      'type': type ?? 'code',
      'content': content,
      'timestamp': DateTime.now().toIso8601String(),
    };

    if (artifacts.containsKey(id)) {
      if (artifacts[id]!.last['content'] != content) {
        artifacts[id]!.add(version);
      }
    } else {
      artifacts[id] = [version];
    }

    activeArtifactId.value = id;
    showArtifactPanel.value = true;
  }

  void updateArtifact(String id, String content) {
    if (!artifacts.containsKey(id)) return;
    final last = artifacts[id]!.last;
    final version = {
      'title': last['title'] ?? 'Artifact',
      'type': last['type'] ?? 'code',
      'content': content,
      'timestamp': DateTime.now().toIso8601String(),
    };
    artifacts[id]!.add(version);
    artifacts.refresh();
  }

  void closeArtifact() {
    showArtifactPanel.value = false;
  }

  // Speech-to-text
  final isListening = false.obs;
  final sttAvailable = false.obs;
  final _speech = stt.SpeechToText();

  final voiceMode = false.obs;
  bool _voiceSpeaking = false;
  bool _voiceSendArmed = true;
  bool _wasLoading = false;
  bool _voiceStopQuiet = false;
  final _voiceWorkers = <Worker>[];

  TtsService? _tts() {
    try {
      return Get.isRegistered<TtsService>() ? Get.find<TtsService>() : null;
    } catch (_) {
      return null;
    }
  }

  void setVoiceMode(bool on) {
    voiceMode.value = on;
    if (on) {
      _voiceStopQuiet = false;
      _voiceSpeaking = false;
      _voiceSendArmed = true;
      _attachVoiceWorkers();
      Get.snackbar(
        'Hands-free on',
        'Speak, and CubicLM replies aloud. Tap the headset icon to stop.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 4),
      );
      unawaited(toggleListening());
    } else {
      _detachVoiceWorkers();
      _voiceSpeaking = false;
      try {
        _speech.stop();
      } catch (_) {}
      try {
        _tts()?.stop();
      } catch (_) {}
      isListening.value = false;
    }
  }

  void _attachVoiceWorkers() {
    _detachVoiceWorkers();
    final tts = _tts();
    if (tts != null) {
      _voiceWorkers.add(ever<bool>(tts.isSpeaking, (speaking) {
        if (!voiceMode.value) return;
        if (_voiceSpeaking && !speaking) {
          _voiceSpeaking = false;
          _voiceSendArmed = true;
          unawaited(toggleListening());
        }
      }));
    }
    _voiceWorkers.add(ever<bool>(isLoading, (loading) {
      if (_wasLoading && !loading) unawaited(_onVoiceReplyReady());
      _wasLoading = loading;
    }));

    _voiceWorkers.add(ever<bool>(isListening, (listening) {
      if (voiceMode.value && listening && tts != null && tts.isSpeaking.value) {
        unawaited(tts.stop());
      }
    }));
  }

  void _detachVoiceWorkers() {
    for (final w in _voiceWorkers) {
      try {
        w.dispose();
      } catch (_) {}
    }
    _voiceWorkers.clear();
  }

  Future<void> _onVoiceReplyReady() async {
    if (!voiceMode.value) return;
    if (_voiceStopQuiet) {
      _voiceStopQuiet = false;
      return;
    }
    if (currentSessionId.value.isEmpty) return;
    ChatMessage? last;
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      if (m.chatId == currentSessionId.value &&
          m.role == 'assistant' &&
          m.content.trim().isNotEmpty) {
        last = m;
        break;
      }
    }
    if (last == null) return;
    final tts = _tts();
    if (tts == null) {
      _voiceSendArmed = true;
      unawaited(toggleListening());
      return;
    }
    _voiceSpeaking = true;
    _voiceSendArmed = true;
    await tts.speak(last.content);
  }

  final textController = TextEditingController();
  final scrollController = ScrollController();
  final composerFocusNode = FocusNode();
  final composerKeyboardFocusNode = FocusNode();

  final findActive = false.obs;
  final findQuery = ''.obs;
  final findMatches = <String>[].obs;
  final findIndex = 0.obs;
  final findController = TextEditingController();
  final _findKeys = <String, GlobalKey>{};

  GlobalKey findKeyFor(String id) => _findKeys.putIfAbsent(id, GlobalKey.new);

  void toggleFind(bool open) {
    findActive.value = open;
    if (!open) {
      findQuery.value = '';
      findMatches.clear();
      findIndex.value = 0;
      findController.clear();
    }
  }

  void updateFind(String q) {
    unawaited(_updateFindAsync(q));
  }

  int _findGen = 0;

  Future<void> _updateFindAsync(String q) async {
    final gen = ++_findGen;
    final needle = q.trim().toLowerCase();
    findQuery.value = needle;
    if (needle.isEmpty) {
      findMatches.clear();
      findIndex.value = 0;
      return;
    }
    List<String> scan() => messages
        .where((m) =>
            '${m.content} ${m.fileName ?? ''}'.toLowerCase().contains(needle))
        .map((m) => m.id)
        .toList();
    findMatches.value = scan();
    var pages = 0;
    while (findMatches.isEmpty &&
        hasOlderMessages.value &&
        pages < 5 &&
        gen == _findGen) {
      pages++;
      await loadOlderMessages();
      if (gen != _findGen) return;
      findMatches.value = scan();
    }
    if (gen != _findGen) return;
    findIndex.value = 0;
    if (findMatches.isNotEmpty) jumpToFindMatch(0);
  }

  void stepFind(int dir) {
    if (findMatches.isEmpty) return;
    findIndex.value =
        (findIndex.value + dir + findMatches.length) % findMatches.length;
    jumpToFindMatch(findIndex.value);
  }

  void jumpToFindMatch(int i) {
    if (i < 0 || i >= findMatches.length) return;
    final ctx = _findKeys[findMatches[i]]?.currentContext;
    if (ctx == null) return;
    try {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: 0.3,
      );
    } catch (_) {}
  }

  final chatScaffoldKey = GlobalKey<ScaffoldState>();
  final historySearchFocus = FocusNode();

  void openHistorySearch() {
    try {
      chatScaffoldKey.currentState?.openDrawer();
    } catch (_) {}
    Future.delayed(const Duration(milliseconds: 350), () {
      try {
        historySearchFocus.requestFocus();
      } catch (_) {}
    });
  }

  Timer? _scrollTimer;
  bool _followStreaming = true;
  bool _scrollListenerAttached = false;
  int _generationSerial = 0;

  @override
  void onInit() {
    super.onInit();
    scrollController.addListener(_handleUserScroll);
    _scrollListenerAttached = true;
    loadSessions();
    loadProjects();
    loadFolders();
    _initSpeech();
    _loadAutoBackupPrefs();
    unawaited(checkSharedText());
    if (!_autoBackupChecked) {
      _autoBackupChecked = true;
      unawaited(Future.delayed(
          const Duration(seconds: 10), () => maybeAutoBackup(_hive)));
    }
  }

  static bool _autoBackupChecked = false;

  Future<void> checkSharedText() async {
    if (kIsWeb) return;
    try {
      if (defaultTargetPlatform != TargetPlatform.android) return;
      final text = await const MethodChannel('com.cubiclm.app/model_import')
          .invokeMethod<String>('getSharedText');
      if (text == null || text.trim().isEmpty) return;
      if (currentSessionId.value.isEmpty) createNewChat();
      final cur = textController.text;
      textController.text = cur.isEmpty ? text : '$cur\n$text';
      try {
        textController.selection =
            TextSelection.collapsed(offset: textController.text.length);
      } catch (_) {}
      inputText.value = textController.text;
      try {
        if (Get.isRegistered<HomeController>()) {
          Get.find<HomeController>().changeTab(0);
        }
      } catch (_) {}
      Get.snackbar('Shared text added', 'Review and tap send when ready.',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 3));
    } catch (_) {}
  }

  /// Insert browser-extracted page text into the composer for review.
  /// Same pattern as [checkSharedText]: never auto-sends, jumps to Chat.
  void insertBrowserExtract(String title, String url, String text) {
    final clean = text.trim();
    if (clean.isEmpty) return;
    if (currentSessionId.value.isEmpty) createNewChat();
    final header = title.trim().isEmpty ? url : '${title.trim()} ($url)';
    final block = '[Web page: $header]\n$clean';
    final cur = textController.text;
    textController.text = cur.isEmpty ? block : '$cur\n\n$block';
    try {
      textController.selection =
          TextSelection.collapsed(offset: textController.text.length);
    } catch (_) {}
    inputText.value = textController.text;
    try {
      if (Get.isRegistered<HomeController>()) {
        Get.find<HomeController>().changeTab(0);
      }
    } catch (_) {}
  }

  final autoBackupEnabled = false.obs;
  final autoBackupDays = 7.obs;
  static const List<int> autoBackupDayOptions = [1, 3, 7, 14, 30];

  void _loadAutoBackupPrefs() {
    try {
      autoBackupEnabled.value = _hive.getSetting<bool>(
              AppConstants.keyAutoBackupEnabled,
              defaultValue: false) ??
          false;
      autoBackupDays.value = _hive.getSetting<int>(
              AppConstants.keyAutoBackupDays,
              defaultValue: 7) ??
          7;
    } catch (_) {}
  }

  Future<void> _initSpeech() async {
    try {
      sttAvailable.value = await _speech.initialize(
        onError: (_) => isListening.value = false,
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            isListening.value = false;
          }
        },
      );
    } catch (_) {
      sttAvailable.value = false;
    }
  }

  Future<void> toggleListening() async {
    try {
      if (isListening.value) {
        await _speech.stop();
        isListening.value = false;
        return;
      }
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        var mic = await Permission.microphone.status;
        if (!mic.isGranted) {
          mic = await Permission.microphone.request();
        }
        if (mic.isPermanentlyDenied) {
          Get.snackbar(
            'Microphone blocked',
            'Allow microphone access in system settings to use voice input.',
            snackPosition: SnackPosition.BOTTOM,
            duration: const Duration(seconds: 5),
            mainButton: const TextButton(
              onPressed: openAppSettings,
              child: Text('Open settings'),
            ),
          );
          return;
        }
        if (!mic.isGranted) return;
      }
      if (!sttAvailable.value) {
        try {
          final ok = await _speech.initialize();
          sttAvailable.value = ok;
        } catch (_) {
          sttAvailable.value = false;
        }
        if (!sttAvailable.value) {
          Get.snackbar('Voice Input Unavailable',
              'Speech recognition is not available on this device.',
              snackPosition: SnackPosition.BOTTOM);
          return;
        }
      }
      await _speech.listen(
        onResult: (result) {
          textController.text = result.recognizedWords;
          inputText.value = result.recognizedWords;
          if (voiceMode.value && result.finalResult) {
            final said = result.recognizedWords.trim();
            if (said.isNotEmpty && _voiceSendArmed && !isLoading.value) {
              _voiceSendArmed = false;
              sendMessage();
            }
          }
        },
        listenOptions: stt.SpeechListenOptions(
          listenFor: const Duration(seconds: 60),
          pauseFor: const Duration(seconds: 4),
          localeId: _sttLocaleId(),
        ),
      );
      isListening.value = true;
      _voiceSendArmed = true;
    } catch (_) {
      isListening.value = false;
    }
  }

  String _sttLocaleId() {
    var code = 'en';
    try {
      if (Get.isRegistered<SettingsController>()) {
        code = Get.find<SettingsController>().locale.value.code;
      } else if (Get.locale != null) {
        code = Get.locale!.languageCode;
      }
    } catch (_) {}
    switch (code) {
      case 'bn':
        return 'bn-BD';
      case 'hi':
        return 'hi-IN';
      case 'ar':
        return 'ar-SA';
      case 'zh':
        return 'zh-CN';
      case 'es':
        return 'es-ES';
      case 'fr':
        return 'fr-FR';
      case 'ja':
        return 'ja-JP';
      case 'ko':
        return 'ko-KR';
      case 'pt':
        return 'pt-BR';
      case 'de':
        return 'de-DE';
      case 'tr':
        return 'tr-TR';
      case 'id':
        return 'id-ID';
      case 'ru':
        return 'ru-RU';
      case 'ur':
        return 'ur-PK';
      case 'en':
      default:
        return 'en-US';
    }
  }

  @override
  void onClose() {
    _detachVoiceWorkers();
    _scrollTimer?.cancel();
    if (_scrollListenerAttached) {
      scrollController.removeListener(_handleUserScroll);
    }
    textController.dispose();
    findController.dispose();
    composerFocusNode.dispose();
    composerKeyboardFocusNode.dispose();
    historySearchFocus.dispose();
    scrollController.dispose();
    super.onClose();
  }

  // ─── Session Management ─────────────────────────

  void loadSessions() {
    final raw = _hive.getAllSessions();
    sessions.value = raw.map((m) => ChatSession.fromMap(m)).toList()
      ..sort(_sessionSort);
  }

  void loadProjects() {
    final raw = _hive.getAllProjects();
    projects.value = raw.map((m) => ChatProject.fromMap(m)).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  void loadFolders() {
    final raw = _hive.getAllFolders();
    folders.value = raw.map((m) => ChatFolder.fromMap(m)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  void createFolder(String name, {String? parentId}) {
    final id = _uuid.v4();
    final folder = ChatFolder(id: id, name: name, parentId: parentId);
    _hive.saveFolder(id, folder.toMap());
    folders.add(folder);
  }

  void deleteFolder(String id) {
    _hive.deleteFolder(id);
    folders.removeWhere((f) => f.id == id);
    for (var i = 0; i < sessions.length; i++) {
      if (sessions[i].folderId == id) {
        final updated = sessions[i].copyWith(folderId: null);
        sessions[i] = updated;
        _hive.saveSession(updated.id, updated.toMap());
      }
    }
  }

  void addChatToFolder(String chatId, String? folderId) {
    final sIdx = sessions.indexWhere((s) => s.id == chatId);
    if (sIdx >= 0) {
      final updated = sessions[sIdx].copyWith(folderId: folderId);
      sessions[sIdx] = updated;
      _hive.saveSession(updated.id, updated.toMap());
    }
  }

  void createProject(String name) {
    final id = _uuid.v4();
    final project = ChatProject(id: id, name: name);
    _hive.saveProject(id, project.toMap());
    projects.insert(0, project);
  }

  void deleteProject(String id) {
    _hive.deleteProject(id);
    projects.removeWhere((p) => p.id == id);
    for (var i = 0; i < sessions.length; i++) {
      if (sessions[i].projectId == id) {
        final updated = sessions[i].copyWith(projectId: null);
        sessions[i] = updated;
        _hive.saveSession(updated.id, updated.toMap());
      }
    }
  }

  void addChatToProject(String chatId, String projectId) {
    final sIdx = sessions.indexWhere((s) => s.id == chatId);
    if (sIdx >= 0) {
      final updated = sessions[sIdx].copyWith(projectId: projectId);
      sessions[sIdx] = updated;
      _hive.saveSession(updated.id, updated.toMap());
    }
  }

  int _sessionSort(ChatSession a, ChatSession b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    return b.updatedAt.compareTo(a.updatedAt);
  }

  void togglePin(String sessionId) {
    final session = sessions.firstWhereOrNull((s) => s.id == sessionId);
    if (session == null) return;
    final updated = session.copyWith(pinned: !session.pinned);
    _hive.saveSession(updated.id, updated.toMap());
    final idx = sessions.indexWhere((s) => s.id == updated.id);
    if (idx >= 0) sessions[idx] = updated;
    sessions.sort(_sessionSort);
  }

  void toggleArchive(String sessionId) {
    final session = sessions.firstWhereOrNull((s) => s.id == sessionId);
    if (session == null) return;
    final updated = session.copyWith(archived: !session.archived);
    _hive.saveSession(updated.id, updated.toMap());
    final idx = sessions.indexWhere((s) => s.id == updated.id);
    if (idx >= 0) sessions[idx] = updated;
    sessions.sort(_sessionSort);
    Get.snackbar(
      updated.archived ? 'Chat archived' : 'Chat unarchived',
      updated.archived
          ? 'Hidden from history. Use "Show archived" to reveal.'
          : 'Back in your history.',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 3),
    );
  }

  final showArchived = false.obs;
  int get archivedCount => sessions.where((s) => s.archived).length;

  void toggleHidden(String sessionId) {
    final session = sessions.firstWhereOrNull((s) => s.id == sessionId);
    if (session == null) return;
    final updated = session.copyWith(hidden: !session.hidden);
    _hive.saveSession(updated.id, updated.toMap());
    final idx = sessions.indexWhere((s) => s.id == updated.id);
    if (idx >= 0) sessions[idx] = updated;
    sessions.sort(_sessionSort);
    Get.snackbar(
      updated.hidden ? 'Chat hidden' : 'Chat unhidden',
      updated.hidden
          ? 'Out of history and search. Use "Show hidden" to reveal.'
          : 'Back in your history.',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 3),
    );
  }

  final showHidden = false.obs;
  int get hiddenCount => sessions.where((s) => s.hidden).length;

  final labelFilter = ''.obs;
  List<String> get chatLabels {
    final set = <String>{};
    for (final s in sessions) {
      final l = s.label.trim();
      if (l.isNotEmpty) set.add(l);
    }
    final out = set.toList()..sort();
    return out;
  }

  void setLabel(String sessionId, String label) {
    final session = sessions.firstWhereOrNull((s) => s.id == sessionId);
    if (session == null) return;
    final updated = session.copyWith(label: label.trim());
    _hive.saveSession(updated.id, updated.toMap());
    final idx = sessions.indexWhere((s) => s.id == updated.id);
    if (idx >= 0) sessions[idx] = updated;
    sessions.sort(_sessionSort);
  }

  void setPersona(String sessionId, String persona) {
    final session = sessions.firstWhereOrNull((s) => s.id == sessionId);
    if (session == null) return;
    final updated = session.copyWith(persona: persona.trim());
    _hive.saveSession(updated.id, updated.toMap());
    final idx = sessions.indexWhere((s) => s.id == updated.id);
    if (idx >= 0) sessions[idx] = updated;
  }

  String get currentPersona {
    if (currentSessionId.value.isEmpty) return '';
    return sessions
            .firstWhereOrNull((s) => s.id == currentSessionId.value)
            ?.persona ??
        '';
  }

  void createNewChat() {
    final id = _uuid.v4();
    final session = ChatSession(id: id, title: 'New Chat');
    _hive.saveSession(id, session.toMap());
    sessions.add(session);
    sessions.sort(_sessionSort);
    openChat(id);
  }

  void _resetInferenceContext() {
    final inference = Get.find<InferenceService>();
    if (inference.isModelLoaded.value) {
      unawaited(inference.resetConversation());
    }
  }

  void openChat(String sessionId, {bool unlocked = false}) {
    final target = sessions.firstWhereOrNull((s) => s.id == sessionId);
    if (target != null && target.locked && !unlocked) {
      unawaited(_authThenOpen(sessionId));
      return;
    }
    stopGenerating();
    currentSessionId.value = sessionId;
    hasOlderMessages.value = false;
    isLoadingOlder.value = false;
    toggleFind(false);
    _findKeys.clear();
    final raw = _hive.getMessagesForChatPaged(
      sessionId,
      limit: _chatPageSize,
    );
    messages.value = raw.map((m) => ChatMessage.fromMap(m)).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    hasOlderMessages.value = raw.length >= _chatPageSize;
    unawaited(_preloadChatImages(sessionId, messages.toList()));
    final inference = Get.find<InferenceService>();
    if (inference.isModelLoaded.value) {
      inference.refreshContextInfo();
    }
    _resetInferenceContext();
    final opened = sessions.firstWhereOrNull((s) => s.id == sessionId);
    if (opened != null) {
      currentProjectId.value = opened.projectId;
      unawaited(_applySessionModel(opened));
    }
    unawaited(_flushOutbox());
    _scrollToBottom(force: true);
  }

  Future<void> _authThenOpen(String sessionId) async {
    try {
      final ok = await Get.find<SettingsController>()
          .authenticate(reason: 'Unlock this chat');
      if (!ok) {
        Get.snackbar('Locked', 'Authentication failed — chat stays closed.',
            snackPosition: SnackPosition.BOTTOM);
        return;
      }
      if (currentSessionId.value != sessionId) {
        openChat(sessionId, unlocked: true);
      }
    } catch (_) {}
  }

  void toggleLocked(String sessionId) {
    final session = sessions.firstWhereOrNull((s) => s.id == sessionId);
    if (session == null) return;
    final updated = session.copyWith(locked: !session.locked);
    _hive.saveSession(updated.id, updated.toMap());
    final idx = sessions.indexWhere((s) => s.id == updated.id);
    if (idx >= 0) sessions[idx] = updated;
    sessions.sort(_sessionSort);
    Get.snackbar(
      updated.locked ? 'Chat locked' : 'Chat unlocked',
      updated.locked
          ? 'Device auth is required to open it.'
          : 'Opens without authentication.',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
  }

  static const int _chatPageSize = 100;
  final hasOlderMessages = false.obs;
  final isLoadingOlder = false.obs;

  Future<void> loadOlderMessages() async {
    if (isLoadingOlder.value || !hasOlderMessages.value) return;
    if (currentSessionId.value.isEmpty) return;
    if (!scrollController.hasClients) return;
    isLoadingOlder.value = true;
    try {
      final sessionId = currentSessionId.value;
      if (messages.isEmpty) {
        hasOlderMessages.value = false;
        return;
      }
      final oldestMs = messages.first.timestamp.millisecondsSinceEpoch;
      final raw = _hive.getMessagesForChatPaged(
        sessionId,
        limit: _chatPageSize,
        beforeTimestampMs: oldestMs,
      );
      if (currentSessionId.value != sessionId) return;
      if (raw.isEmpty) {
        hasOlderMessages.value = false;
        return;
      }
      final older = raw.map((m) => ChatMessage.fromMap(m)).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final knownIds = messages.map((m) => m.id).toSet();
      older.removeWhere((m) => knownIds.contains(m.id));
      if (older.isEmpty) {
        hasOlderMessages.value = false;
        return;
      }
      final pos = scrollController.position;
      final oldMax = pos.maxScrollExtent;
      final oldPixels = pos.pixels;
      messages.insertAll(0, older);
      unawaited(_preloadChatImages(sessionId, older));
      hasOlderMessages.value = raw.length >= _chatPageSize;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!scrollController.hasClients) return;
        try {
          final newMax = scrollController.position.maxScrollExtent;
          scrollController.jumpTo(
            (oldPixels + (newMax - oldMax)).clamp(0.0, newMax.toDouble()),
          );
        } catch (_) {}
      });
    } finally {
      isLoadingOlder.value = false;
    }
  }

  Future<void> _preloadChatImages(
      String sessionId, List<ChatMessage> msgs) async {
    for (final m in msgs) {
      if (currentSessionId.value != sessionId) return;
      if (m.imageBase64 == null && m.imagePath == null) continue;
      try {
        await m.preloadImageBytes();
      } catch (_) {}
    }
  }

  ChatSession? _trashSession;
  List<Map<String, dynamic>> _trashMessages = [];

  void deleteChat(String sessionId) {
    if (currentSessionId.value == sessionId && isLoading.value) {
      stopGenerating();
    }
    final session = sessions.firstWhereOrNull((s) => s.id == sessionId);
    _trashSession = session;
    _trashMessages = session == null
        ? []
        : _hive
            .getMessagesForChat(sessionId)
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
    _hive.deleteSession(sessionId);
    sessions.removeWhere((s) => s.id == sessionId);
    if (currentSessionId.value == sessionId) {
      currentSessionId.value = '';
      messages.clear();
      hasOlderMessages.value = false;
    }
    if (session != null) {
      Get.snackbar(
        'Chat deleted',
        session.title,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 5),
        mainButton: TextButton(
          onPressed: () {
            try {
              Get.back();
            } catch (_) {}
            undoDeleteChat();
          },
          child: const Text('UNDO'),
        ),
      );
    }
  }

  Future<void> undoDeleteChat() async {
    final s = _trashSession;
    if (s == null) return;
    _trashSession = null;
    try {
      await _hive.saveSession(s.id, s.toMap());
      for (final m in _trashMessages) {
        try {
          final id = m['id']?.toString() ?? '';
          if (id.isNotEmpty) await _hive.saveMessage(id, m);
        } catch (_) {}
      }
    } catch (_) {}
    _trashMessages = [];
    if (!sessions.any((e) => e.id == s.id)) {
      sessions.add(s);
      sessions.sort(_sessionSort);
    }
    if (currentSessionId.value.isEmpty) openChat(s.id);
  }

  void renameChat(String sessionId, String newTitle) {
    if (newTitle.trim().isEmpty) return;
    final session = sessions.firstWhereOrNull((s) => s.id == sessionId);
    if (session == null) return;
    final updated = session.copyWith(title: newTitle.trim());
    _hive.saveSession(updated.id, updated.toMap());
    final idx = sessions.indexWhere((s) => s.id == updated.id);
    if (idx >= 0) sessions[idx] = updated;
  }

  // ─── Backup & Restore ───────────────────────────

  Future<void> setAutoBackup(bool enabled, [int? days]) async {
    autoBackupEnabled.value = enabled;
    await _hive.setSetting(AppConstants.keyAutoBackupEnabled, enabled);
    if (days != null) {
      autoBackupDays.value = days;
      await _hive.setSetting(AppConstants.keyAutoBackupDays, days);
    }
  }

  Future<String?> importChats({String? passphrase}) async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      final files = picked?.files;
      if (files == null || files.isEmpty) return 'cancelled';
      final platformFile = files.first;

      String? raw;
      if (platformFile.bytes != null && platformFile.bytes!.isNotEmpty) {
        try {
          raw = utf8.decode(platformFile.bytes!);
        } on FormatException {
          raw = null;
        }
      }
      raw ??= platformFile.path != null
          ? await File(platformFile.path!).readAsString()
          : null;
      if (raw == null || raw.isEmpty) return 'invalid';

      final dynamic decoded;
      try {
        decoded = jsonDecode(raw);
      } on FormatException {
        return 'invalid';
      }
      var body = decoded;
      if (decoded is Map<String, dynamic> &&
          decoded['type'] == 'chat_backup_encrypted') {
        final algo = decoded['algo']?.toString() ?? 'aes256cbc-sha256';
        if (algo != 'aes256cbc-sha256') return 'invalid';
        final pass = (passphrase ?? '').trim();
        if (pass.isEmpty) return 'locked';
        try {
          final packed = base64Decode(decoded['data']?.toString() ?? '');
          final plain = await _hive.decryptBackupBytes(packed, pass);
          final text = utf8.decode(plain);
          if (!text.startsWith(HiveService.backupMagic)) return 'invalid';
          body = jsonDecode(text.substring(HiveService.backupMagic.length));
        } catch (_) {
          return 'invalid';
        }
      }
      if (body is! Map<String, dynamic>) return 'invalid';
      final t = body['type'];
      final hasData = body['sessions'] is List || body['messages'] is List;
      if (t != 'chat_backup' && !(t == null && hasData)) return 'invalid';

      final existingIds = sessions.map((s) => s.id).toSet();
      var importedSessions = 0;
      var importedMessages = 0;

      final rawSessions = body['sessions'];
      if (rawSessions is List) {
        for (final item in rawSessions) {
          if (item is! Map) continue;
          final session = ChatSession.fromMap(Map<dynamic, dynamic>.from(item));
          if (session.id.isEmpty || existingIds.contains(session.id)) continue;
          await _hive.saveSession(session.id, session.toMap());
          existingIds.add(session.id);
          importedSessions++;
        }
      }

      final existingMessageKeys = _hive
          .getAllMessagesRaw()
          .map((m) => _messageKey(
              m['chatId']?.toString() ?? '', m['id']?.toString() ?? ''))
          .toSet();

      final rawMessages = body['messages'];
      if (rawMessages is List) {
        for (final item in rawMessages) {
          if (item is! Map) continue;
          final msg = Map<String, dynamic>.from(item);
          final id = msg['id']?.toString() ?? '';
          final chatId = msg['chatId']?.toString() ?? '';
          if (id.isEmpty) continue;
          final key = _messageKey(chatId, id);
          if (existingMessageKeys.contains(key)) continue;
          await _hive.saveMessage(id, msg);
          existingMessageKeys.add(key);
          importedMessages++;
        }
      }

      if (importedSessions > 0) loadSessions();

      if (importedSessions == 0 && importedMessages == 0) return 'nothing';
      return 'ok:$importedSessions:$importedMessages';
    } catch (e) {
      Get.find<AppLogService>().error('Backup import failed',
          details: e, category: LogCategory.chat);
      return 'error';
    }
  }

  String _messageKey(String chatId, String id) =>
      chatId.isNotEmpty ? '$chatId/$id' : id;

  // ─── Image Handling ─────────────────────────────

  Future<void> pickImage() async {
    try {
      if (!kIsWeb &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        await _pickImageDesktop();
        return;
      }
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: _visionImageMaxSide.toDouble(),
        maxHeight: _visionImageMaxSide.toDouble(),
        imageQuality: _visionImageJpegQuality,
      );
      if (file != null) {
        selectedImagePath.value = file.path;
        selectedImageBase64.value = null;
        selectedFileName.value = file.name;
        selectedFilePath.value = file.path;
        selectedFileType.value = 'image';
        selectedFileSize.value = await file.length();
        selectedFileContent.value = null;
        _checkVisionSupport();
      }
    } catch (e) {
      Get.find<AppLogService>()
          .error('Image pick failed', details: e, category: LogCategory.chat);
      Get.snackbar(
          'Image Pick Failed', 'Could not pick an image on this device.',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _pickImageDesktop() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.image,
      withData: false,
    );
    final files = picked?.files;
    if (files == null || files.isEmpty) return;
    final path = files.first.path;
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (!await file.exists()) return;
    selectedImagePath.value = path;
    selectedImageBase64.value = null;
    selectedFileName.value = path.split(Platform.pathSeparator).last;
    selectedFilePath.value = path;
    selectedFileType.value = 'image';
    selectedFileSize.value = await file.length();
    selectedFileContent.value = null;
    _checkVisionSupport();
  }

  Future<void> takePhoto() async {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      Get.snackbar('Camera Unavailable',
          'Photo capture needs the Android app — pick an image instead.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: _visionImageMaxSide.toDouble(),
        maxHeight: _visionImageMaxSide.toDouble(),
        imageQuality: _visionImageJpegQuality,
      );
      if (file != null) {
        selectedImagePath.value = file.path;
        selectedImageBase64.value = null;
        selectedFileName.value = file.name;
        selectedFilePath.value = file.path;
        selectedFileType.value = 'image';
        selectedFileSize.value = await file.length();
        selectedFileContent.value = null;
        _checkVisionSupport();
      }
    } catch (e) {
      Get.find<AppLogService>().error('Photo capture failed',
          details: e, category: LogCategory.chat);
      Get.snackbar('Camera Failed', 'Could not capture a photo.',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  void clearImage({bool deleteFile = true}) {
    final path = selectedImagePath.value;
    selectedImagePath.value = null;
    selectedImageBase64.value = null;
    if (deleteFile && path != null && path.isNotEmpty) {
      try {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    if (selectedFileType.value == 'image') {
      clearFile();
    }
  }

  void _checkVisionSupport() {
    final s = Get.find<SettingsController>();
    if (s.inferenceMode.value != 'cloud') {
      _checkLocalVisionSupport();
      return;
    }

    final provider = s.cloudProvider.value;
    String modelName = '';
    switch (provider) {
      case 'anthropic':
        modelName = s.anthropicModel.value;
        break;
      case 'google':
        modelName = s.googleModel.value;
        break;
      case 'kimi':
        modelName = s.kimiModel.value;
        break;
      case 'stability':
        modelName = s.stabilityModel.value;
        break;
      case 'nvidia':
        modelName = s.nvidiaModel.value;
        break;
      case 'openrouter':
        modelName = s.openRouterModel.value;
        break;
      case 'deepseek':
        modelName = s.deepSeekModel.value;
        break;
      case 'custom':
        modelName = s.customCloudModel.value;
        break;
      default:
        modelName = s.openaiModel.value;
        break;
    }

    final model = modelName.toLowerCase();

    final isVision = model.contains('vision') ||
        model.contains('-vl') ||
        model.contains('gpt-4o') ||
        model.contains('claude-3') ||
        model.contains('gemini') ||
        model.contains('pixtral') ||
        model.contains('llava') ||
        model.contains('omni');

    if (!isVision) {
      Get.snackbar(
        'Warning: Text-Only Model',
        'The selected model ($modelName) might not support images. If you get an error, switch to a vision model (like Gemini, GPT-4o, or Claude 3).',
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 6),
        backgroundColor:
            const Color(0xFFFF9500).withValues(alpha: 0.95),
        colorText: Colors.white,
        margin: const EdgeInsets.all(12),
      );
    }
  }

  void _checkLocalVisionSupport() {
    var ok = false;
    try {
      final inference = Get.find<InferenceService>();
      final runtime = inference.loadedModelRuntime.value.toLowerCase();
      ok = inference.isModelLoaded.value &&
          runtime.contains('litert') &&
          inference.isVisionLoaded.value;
    } catch (_) {
      ok = false;
    }
    if (ok) return;
    Get.snackbar(
      'Warning: Text-Only Engine',
      'On-device vision needs a LiteRT vision model — GGUF models are text-only here. Switch to Cloud for vision.',
      snackPosition: SnackPosition.TOP,
      duration: const Duration(seconds: 6),
      backgroundColor: const Color(0xFFFF9500).withValues(alpha: 0.95),
      colorText: Colors.white,
      margin: const EdgeInsets.all(12),
    );
  }

  Future<void> pickFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'png', 'jpg', 'jpeg', 'webp', 'gif', 'heic',
          'pdf', 'docx',
          'mp3', 'm4a', 'wav', 'aac', 'ogg', 'flac',
          'txt', 'md', 'json', 'csv', 'log', 'yaml', 'yml', 'xml',
          'dart', 'kt', 'java', 'js', 'ts', 'py',
          'zip', 'c', 'cpp', 'h', 'hpp', 'go', 'rs', 'rb', 'php'
        ],
        withData: kIsWeb,
      );
      if (result == null) return;
      final file = result.files.single;
      await handleFile(file.path!, file.name,
          size: file.size, bytes: file.bytes);
    } catch (e) {
      Get.find<AppLogService>().error('File pick failed',
          details: e, category: LogCategory.chat);
    }
  }

  Future<void> handleFile(String path, String name,
      {int? size, Uint8List? bytes}) async {
    try {
      final extension = name.split('.').last.toLowerCase();
      final fileType = _attachmentTypeForExtension(extension);

      if (extension.isEmpty || (fileType == 'file' && extension != 'zip')) {
        Get.snackbar(
          'Unsupported file',
          'Only images, audio, PDF, DOCX, ZIP and text/code files are supported.',
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }

      if (fileType == 'image') {
        selectedImagePath.value = path;
        selectedImageBase64.value =
            (kIsWeb && bytes != null) ? base64Encode(bytes) : null;
        selectedFileName.value = name;
        selectedFilePath.value = path;
        selectedFileType.value = 'image';
        selectedFileSize.value = size ?? await File(path).length();
        selectedFileContent.value = null;
        _checkVisionSupport();
        return;
      }

      selectedFileName.value = name;
      selectedFileType.value = extension;
      selectedFileSize.value = size ?? await File(path).length();
      selectedFilePath.value = path;
      selectedFileContent.value = 'chat_extracting_text'.tr;

      if (extension == 'zip') {
        final chunks = await DocumentExtractorService.extractZip(path);
        final structure = _generateProjectStructure(chunks);
        final content =
            chunks.map((c) => '--- ${c.source} ---\n${c.text}').join('\n\n');
        selectedFileContent.value = '$structure\n\n$content';
      } else {
        final text = await DocumentExtractorService.extractText(path, extension);
        selectedFileContent.value = text;
      }

      if (selectedFileContent.value != null && selectedFileContent.value!.length > 2000) {
        final vs = Get.find<VectorService>();
        selectedFileChunks.assignAll(vs.chunkText(selectedFileContent.value!));
      } else {
        selectedFileChunks.clear();
      }
    } catch (e) {
      Get.find<AppLogService>().error('File handle failed',
          details: e, category: LogCategory.chat);
    }
  }

  String _generateProjectStructure(List<DocumentChunk> chunks) {
    final buffer = StringBuffer();
    buffer.writeln('Project Structure Overview:');
    
    final tree = <String, Set<String>>{};
    for (final c in chunks) {
      final parts = c.source.split('/');
      if (parts.length > 1) {
        final root = parts[0];
        tree.putIfAbsent(root, () => {}).add(parts.sublist(0, parts.length - 1).join('/'));
      }
    }

    if (tree.isNotEmpty) {
      buffer.writeln('Root Folders: ${tree.keys.join(', ')}');
      if (tree.values.fold(0, (sum, set) => sum + set.length) < 20) {
        buffer.writeln('Subfolders: ${tree.values.expand((e) => e).join(', ')}');
      }
    }
    
    buffer.writeln('Total files: ${chunks.length}');
    buffer.writeln('---');
    return buffer.toString();
  }

  void clearFile() {
    selectedFileName.value = null;
    selectedFileContent.value = null;
    selectedFilePath.value = null;
    selectedFileType.value = null;
    selectedFileSize.value = 0;
    selectedFileChunks.clear();
  }

  // ─── Send Message ───────────────────────────────

  Future<void> sendMessage() async {
    if (isLoading.value || isStreaming.value) return;

    final text = textController.text.trim();
    final hasAttachment =
        selectedImagePath.value != null || selectedFileName.value != null;
    if (text.isEmpty && !hasAttachment) return;

    unawaited(HapticFeedback.lightImpact());

    final fileName = selectedFileName.value;
    final fileContent = selectedFileContent.value;
    final filePath = selectedFilePath.value;
    final fileType = selectedFileType.value;
    final fileSize = selectedFileSize.value;
    final imagePath = selectedImagePath.value;
    final imageBase64 = selectedImageBase64.value;
    final visibleText =
        text.isEmpty ? _defaultAttachmentPrompt(fileType) : text;
    final effectiveText = (fileContent != null && fileContent.trim().isNotEmpty)
        ? '$visibleText\n\nAttached file: $fileName\n```text\n$fileContent\n```'
        : visibleText;

    if (currentSessionId.value.isEmpty) {
      createNewChat();
    }

    String? imgBase64 = imageBase64;
    if (imgBase64 == null && imagePath != null && !kIsWeb) {
      try {
        imgBase64 =
            await compute(base64Encode, await File(imagePath).readAsBytes());
      } catch (_) {}
    }

    final userMsgId = _uuid.v4();
    String? persistedImagePath = imagePath;
    if (imagePath != null && !kIsWeb) {
      persistedImagePath = await _persistImageFile(imagePath, userMsgId);
    }

    final userMsg = ChatMessage(
      id: userMsgId,
      chatId: currentSessionId.value,
      role: 'user',
      content: effectiveText,
      imageBase64: null,
      imagePath: persistedImagePath,
      fileName: fileName,
      fileContent: fileContent,
      filePath: filePath,
      fileType: fileType,
      fileSize: fileSize > 0 ? fileSize : null,
    );
    messages.add(userMsg);
    _hive.saveMessage(userMsg.id, userMsg.toMap());

    textController.clear();
    inputText.value = '';
    clearImage(deleteFile: false);
    clearFile();
    _scrollToBottom(force: true);

    if (messages.where((m) => m.role == 'user').length == 1) {
      final title = visibleText.length > 40
          ? '${visibleText.substring(0, 40)}...'
          : visibleText;
      final session =
          sessions.firstWhere((s) => s.id == currentSessionId.value);
      final updated = session.copyWith(title: title, lastMessage: visibleText);
      _hive.saveSession(updated.id, updated.toMap());
      final idx = sessions.indexWhere((s) => s.id == updated.id);
      if (idx >= 0) sessions[idx] = updated;
    }

    await _flushOutbox();
    StatsService.tap(StatsService.eventChatSent);

    await _generateAIResponse(
      prompt: effectiveText,
      imagePath: imagePath,
      imgBase64: imgBase64,
      fileType: fileType,
      filePath: filePath,
    );
  }

  int _historyCharBudget() {
    var ctx = AppConstants.defaultContextSize;
    try {
      if (Get.isRegistered<SettingsController>()) {
        ctx = Get.find<SettingsController>().contextSize.value;
      }
    } catch (_) {}
    if (ctx <= 0) ctx = AppConstants.defaultContextSize;
    return (ctx * 0.6 * 4).toInt();
  }

  Future<bool> _generateAIResponse({
    required String prompt,
    String? imagePath,
    String? imgBase64,
    String? fileType,
    String? filePath,
    int? insertAt,
  }) async {
    final generationId = ++_generationSerial;
    isLoading.value = true;
    isStreaming.value = true;
    streamingAttachmentType.value =
        (imagePath != null || fileType == 'audio') ? fileType : null;
    streamingResponse.value = '';
    streamingThought.value = '';
    streamingAnswer.value = '';
    streamingIsThinking.value = false;
    generationStartTime.value = DateTime.now();
    
    unawaited(HapticFeedback.mediumImpact());
    generationLiveDurationSecs.value = 0;
    _generationTimer?.cancel();
    _generationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (generationStartTime.value != null) {
        generationLiveDurationSecs.value =
            DateTime.now().difference(generationStartTime.value!).inSeconds;
      }
    });
    _followStreaming = true;
    _scrollToBottom(force: true);

    final List<String> displayQueue = [];
    String fullResponse = '';
    Timer? fluidTimer;
    bool generationDone = false;
    bool hasSeenThoughtTag = false;
    DateTime? thoughtStartedAt;
    int? thoughtDurationSeconds;

    void trackThoughtTiming() {
      final current = streamingResponse.value;
      if (!hasSeenThoughtTag) {
        if (current.contains('<think')) {
          hasSeenThoughtTag = true;
        } else {
          streamingAnswer.value = current;
          return;
        }
      }
      
      final parts = splitThoughtTags(current);
      streamingThought.value = parts.thought;
      streamingAnswer.value = parts.answer;
      streamingIsThinking.value = parts.isThinking;

      if (thoughtDurationSeconds != null) return;
      
      if (parts.hasThought && parts.isThinking && thoughtStartedAt == null) {
        thoughtStartedAt = DateTime.now();
      }
      if (parts.hasThought &&
          !parts.isThinking &&
          thoughtStartedAt != null) {
        thoughtDurationSeconds =
            DateTime.now().difference(thoughtStartedAt!).inSeconds;
      }
    }

    Future<void> finalizeMessage({
      required String rawResponse,
      required List<WebSource> webSources,
      required List<String> usedSkillNames,
      required int? tps,
      required int? thoughtDurationSeconds,
      required List<Map<String, String>> history,
      required String systemPrompt,
    }) async {
      if (generationId != _generationSerial) return;

      final totalDurationMs = generationStartTime.value != null
          ? DateTime.now().difference(generationStartTime.value!).inMilliseconds
          : null;

      final imageDurationMs = imageGenStartTime.value != null
          ? DateTime.now().difference(imageGenStartTime.value!).inMilliseconds
          : null;

      _generationTimer?.cancel();
      _generationTimer = null;
      fluidTimer?.cancel();
      
      isStreaming.value = false;
      streamingAttachmentType.value = null;
      streamingResponse.value = '';
      streamingThought.value = '';
      streamingAnswer.value = '';
      streamingIsThinking.value = false;
      generationStartTime.value = null;
      generationLiveDurationSecs.value = 0;
      imageGenStep.value = 0;
      imageGenTotal.value = 0;
      imageGenDecoding.value = false;

      String? outImageBase64;
      String? outImagePath;
      if (rawResponse.startsWith('[IMAGE_BASE64]')) {
        outImageBase64 = rawResponse.substring('[IMAGE_BASE64]'.length);
        rawResponse = 'Here is your generated image:';
      }

      final aiMsgId = _uuid.v4();
      if (outImageBase64 != null && outImageBase64.isNotEmpty && !kIsWeb) {
        try {
          final bytes = base64Decode(outImageBase64);
          outImagePath = await _persistImageBytes(bytes, aiMsgId);
          if (outImagePath != null) outImageBase64 = null;
        } catch (_) {}
      }

      final artifactsDetected = parseArtifacts(rawResponse);
      final cleanContent = removeArtifacts(rawResponse);

      final aiMsg = ChatMessage(
        id: aiMsgId,
        chatId: currentSessionId.value,
        role: 'assistant',
        content: cleanContent,
        imageBase64: outImageBase64,
        imagePath: outImagePath,
        tokensPerSec: (tps != null && tps > 0) ? tps.toDouble() : null,
        thoughtDurationSeconds: thoughtDurationSeconds,
        imageGenDurationMs: imageDurationMs,
        generationDurationMs: totalDurationMs,
        webSources: webSources.isEmpty ? null : webSources,
        usedSkills: usedSkillNames.isEmpty ? null : usedSkillNames,
        artifacts: artifactsDetected.isEmpty ? null : artifactsDetected.map((e) => {
          'id': e.id ?? _uuid.v4(),
          'type': e.type ?? 'code',
          'title': e.title ?? 'Artifact',
          'content': e.content,
        }).toList(),
      );

      if (insertAt != null && insertAt >= 0 && insertAt <= messages.length) {
        messages.insert(insertAt, aiMsg);
      } else {
        messages.add(aiMsg);
      }
      _hive.saveMessage(aiMsg.id, aiMsg.toMap());
      imageGenStartTime.value = null;

      final session = sessions.firstWhereOrNull((s) => s.id == currentSessionId.value);
      if (session != null) {
        final updated = session.copyWith(lastMessage: aiMsg.content);
        _hive.saveSession(updated.id, updated.toMap());
        final idx = sessions.indexWhere((s) => s.id == updated.id);
        if (idx >= 0) sessions[idx] = updated;
      }
      
      unawaited(HapticFeedback.mediumImpact());
      _dropStreamingDraft();

      // One-shot compare: challenger answers the same prompt
      if (_compareRef != null && outImageBase64 == null) {
        await _runComparison(
          prompt: prompt,
          systemPrompt: systemPrompt,
          history: history,
        );
      }

      // ── Long-term Memory Extraction ──
      unawaited(_extractMemories(prompt, rawResponse));
      
      isLoading.value = false;
      _scrollToBottom();
    }

    void startFluidEngine({
      required List<WebSource> webSources,
      required List<String> usedSkillNames,
      required List<Map<String, String>> history,
      required String systemPrompt,
    }) {
      fluidTimer = Timer.periodic(const Duration(milliseconds: 25), (timer) {
        if (displayQueue.isEmpty && generationDone) {
          timer.cancel();
          final inferenceMode = _hive.getSetting(AppConstants.keyInferenceMode, defaultValue: 'local') ?? 'local';
          final tps = inferenceMode == 'local' ? Get.find<InferenceService>().tokensPerSecond.value.toInt() : null;
          finalizeMessage(
            rawResponse: fullResponse, // Uses outer scope fullResponse
            webSources: webSources,
            usedSkillNames: usedSkillNames,
            tps: tps,
            thoughtDurationSeconds: thoughtDurationSeconds,
            history: history,
            systemPrompt: systemPrompt,
          );
          return;
        }

        if (displayQueue.isNotEmpty) {
          int burst = 1;
          final qLen = displayQueue.length;
          if (qLen > 400) {
            burst = 15;
          } else if (qLen > 150) {
            burst = 8;
          } else if (qLen > 50) {
            burst = 4;
          } else if (qLen > 15) {
            burst = 2;
          }

          final toAdd = displayQueue.take(burst).join();
          displayQueue.removeRange(0, min(burst, displayQueue.length));
          
          streamingResponse.value += toAdd;
          trackThoughtTiming();
          _scrollToBottom();
        }
      });
    }

    void bufferToken(String t) {
      for (var i = 0; i < t.length; i++) {
        displayQueue.add(t[i]);
      }
    }

    try {
      final inferenceMode = _hive.getSetting(
            AppConstants.keyInferenceMode,
            defaultValue: 'local',
          ) ??
          'local';

      final storedForHistory = _hive.getMessagesForChatPaged(
        currentSessionId.value,
        limit: 40,
      );
      var history = storedForHistory
          .map((m) {
            final role = m['role']?.toString() ?? '';
            var content = m['content']?.toString() ?? '';
            if (role == 'assistant') {
              content = splitThoughtTags(content).answer;
            }
            return {'role': role, 'content': content};
          })
          .where((e) => e['role'] == 'user' || e['role'] == 'assistant')
          .toList();

      try {
        final vs = Get.find<VectorService>();
        if (prompt.contains('Attached file:') && prompt.length > 3000) {
          final contentMatch = RegExp(r'```text\n([\s\S]*?)\n```').firstMatch(prompt);
          if (contentMatch != null) {
            final full = contentMatch.group(1) ?? '';
            final hits = await compute((String text) => vs.retrieve(prompt.split('\n\n').first, vs.chunkText(text)), full);
            if (hits.isNotEmpty) {
              prompt = prompt.replaceFirst(
                RegExp(r'Attached file:.*?\n```text\n[\s\S]*?\n```'),
                '[Relevant snippets from attachment]:\n${hits.map((h) => "> $h").join("\n\n")}'
              );
            }
          }
        }
        
        for (var i = 0; i < history.length; i++) {
          final turn = history[i];
          final content = turn['content'] ?? '';
          if (turn['role'] == 'user' && content.contains('Attached file:') && content.length > 3000) {
            final contentMatch = RegExp(r'```text\n([\s\S]*?)\n```').firstMatch(content);
            if (contentMatch != null) {
              final full = contentMatch.group(1) ?? '';
              final hits = await compute((String text) => vs.retrieve(prompt, vs.chunkText(text)), full);
              if (hits.isNotEmpty) {
                history[i] = {
                  'role': 'user',
                  'content': content.replaceFirst(
                    RegExp(r'Attached file:.*?\n```text\n[\s\S]*?\n```'),
                    '[Relevant snippets from file]:\n${hits.map((h) => "> $h").join("\n\n")}'
                  )
                };
              }
            }
          }
        }
      } catch (_) {}

      final uiTurns = messages
          .where((m) => m.role == 'user' || m.role == 'assistant')
          .length;
      if (history.isEmpty && uiTurns > 0) {
        Get.find<AppLogService>().warning(
          'History empty despite $uiTurns UI turns — using visible list',
          category: LogCategory.chat,
        );
        history = messages
            .where((m) => m.role == 'user' || m.role == 'assistant')
            .map((m) {
          var content = m.content;
          if (m.role == 'assistant') {
            content = splitThoughtTags(content).answer;
          }
          return {'role': m.role, 'content': content};
        }).toList();
      }

      final preTrimTurns = history.length;
      final historyBudget =
          inferenceMode == 'local' ? _historyCharBudget() : 48000;
      
      history = await compute((Map<String, dynamic> p) => fitHistoryToBudget(p['h'] as List<Map<String, String>>, p['b'] as int), {'h': history, 'b': historyBudget});

      try {
        final chars =
            history.fold<int>(0, (s, m) => s + (m['content'] ?? '').length);
        final roles = history.isEmpty
            ? 'none'
            : '${history.first['role']}…${history.last['role']}';
        final trimmed = preTrimTurns > history.length
            ? ', trimmed ${preTrimTurns - history.length}'
            : '';
        Get.find<AppLogService>().info(
          'Chat context: ${history.length} turns, ~${chars ~/ 4} tokens ($roles$trimmed)',
          category: LogCategory.chat,
        );
      } catch (_) {}

      final settingsForPrompt = Get.find<SettingsController>();
      final modelNameForPrompt = inferenceMode == 'local'
          ? Get.find<InferenceService>().loadedModelName.value
          : settingsForPrompt.selectedCloudModelName;
      final relevantSkills = SkillInjector.selectRelevantSkills(prompt);
      final List<String> usedSkillNames =
          relevantSkills.map((s) => s.name).toList();
      var basePrompt =
          settingsForPrompt.baseSystemPromptForModel(modelNameForPrompt);
      final persona = currentPersona;
      if (persona.isNotEmpty) {
        basePrompt = '$basePrompt\n\n[Chat persona]\n$persona';
      }
      final String systemPromptForThisTurn = Get.find<MemoryService>().injectMemories(
      relevantSkills.isEmpty
          ? basePrompt
          : '$basePrompt${SkillInjector.buildForSkills(relevantSkills)}',
    );

      List<WebSource> webSources = [];
      try {
        final s = Get.find<SettingsController>();
        if (s.webFetchEnabled.value) {
          final pagesRead = WebFetchService.countUrls(prompt);
          if (pagesRead > 0) {
            Get.snackbar(
              'Web Access',
              'Reading $pagesRead link${pagesRead > 1 ? 's' : ''} into context…',
              snackPosition: SnackPosition.BOTTOM,
              duration: const Duration(seconds: 2),
            );
          }
          final result = await WebFetchService.augmentWithSources(prompt);
          if (result.augmentedText != prompt) {
            prompt = result.augmentedText;
            if (history.isNotEmpty && history.last['role'] == 'user') {
              history[history.length - 1] = {
                'role': 'user',
                'content': prompt,
              };
            }
          }
          webSources = result.sources.where((w) => w.success).toList();
        }
      } catch (_) {}

      final cloud = Get.find<CloudService>();
      fullResponse = '';

      if (isSearchMode.value && cloud.isProviderConfigured('perplexity')) {
        final apiMessages = [
          {
            'role': 'system',
            'content':
                'You are a helpful assistant with real-time web search capabilities. Provide comprehensive answers with citations where possible.'
          },
          ...history,
          {'role': 'user', 'content': prompt},
        ];

        startFluidEngine(
          webSources: webSources,
          usedSkillNames: usedSkillNames,
          history: history,
          systemPrompt: systemPromptForThisTurn,
        );
        final buffer = StringBuffer();
        try {
          await for (final chunk in cloud.streamMessageAs(
            providerId: 'perplexity',
            model: 'sonar-pro',
            messages: apiMessages,
          )) {
            buffer.write(chunk);
            bufferToken(chunk);
          }
          fullResponse = buffer.toString();
        } catch (e) {
          fullResponse = 'Search failed: $e';
        }
      } else if (inferenceMode == 'local') {
        final localImage = Get.find<LocalImageService>();

        if (localImage.isModelLoaded.value &&
            _isImageGenerationPrompt(prompt)) {
          final settings = Get.find<SettingsController>();
          final imageNotifications =
              Get.find<ImageGenerationNotificationService>();
          final steps = _hive.getSetting<int>(AppConstants.keyImageSteps,
                  defaultValue: AppConstants.defaultImageSteps) ??
              AppConstants.defaultImageSteps;
          final sizeSetting = settings.imageGenSize.value;
          final sizeLabel =
              sizeSetting == 0 ? 'Auto size' : '${sizeSetting}x$sizeSetting';
          final backendLabel = localImage.currentBackend.value == Backend.cpu
              ? 'CPU'
              : localImage.currentBackend.value.displayName
                  .split(' ')
                  .first
                  .toUpperCase();
          imageGenStep.value = 0;
          imageGenTotal.value = steps;
          imageGenEstimatedSecs.value = 0;
          imageGenStartTime.value = DateTime.now();
          imageGenDecoding.value = false;
          await imageNotifications.start(
            modelName: localImage.loadedModelName.value,
            backend: backendLabel,
            steps: steps,
            sizeLabel: sizeLabel,
          );

          final pngBytes = await localImage.generateImage(
            prompt: prompt,
            onProgress: (step, total) {
              imageGenStep.value = step;
              imageGenTotal.value = total;
              if (step >= total && total > 0) {
                imageGenDecoding.value = true;
                imageNotifications.decoding();
              }
              if (step > 0 && total > 0 && step < total) {
                final start = imageGenStartTime.value;
                if (start != null) {
                  final elapsed =
                      DateTime.now().difference(start).inMilliseconds;
                  final avgMsPerStep = elapsed / step;
                  final remainingSteps = total - step;
                  imageGenEstimatedSecs.value =
                      (avgMsPerStep * remainingSteps / 1000).ceil();
                }
              }
              imageNotifications.update(
                step: step,
                total: total,
                etaSeconds: imageGenEstimatedSecs.value,
                elapsedSeconds: imageGenStartTime.value == null
                    ? 0
                    : DateTime.now()
                        .difference(imageGenStartTime.value!)
                        .inSeconds,
              );
              _scrollToBottom();
            },
          );

          if (pngBytes != null) {
            fullResponse = '[IMAGE_BASE64]${await compute(base64Encode, pngBytes)}';
          } else {
            fullResponse = '❌ Local image generation failed.';
          }
          generationDone = true;
          startFluidEngine(
            webSources: webSources,
            usedSkillNames: usedSkillNames,
            history: history,
            systemPrompt: systemPromptForThisTurn,
          );
        } else {
          startFluidEngine(
          webSources: webSources,
          usedSkillNames: usedSkillNames,
          history: history,
          systemPrompt: systemPromptForThisTurn,
        );
          final inference = Get.find<InferenceService>();
          fullResponse = await inference.generate(
            prompt: prompt,
            systemPrompt: systemPromptForThisTurn,
            conversationHistory: history,
            source: 'chat',
            imagePath: imagePath,
            audioPath: fileType == 'audio' ? filePath : null,
            onToken: bufferToken,
          );
        }
      } else {
        final cloud = Get.find<CloudService>();
        final settings = Get.find<SettingsController>();
        final apiMessages = [
          {'role': 'system', 'content': systemPromptForThisTurn},
          ...history,
        ];
        
        startFluidEngine(
          webSources: webSources,
          usedSkillNames: usedSkillNames,
          history: history,
          systemPrompt: systemPromptForThisTurn,
        );
        fullResponse = await cloud.sendMessage(
          messages: apiMessages,
          imageBase64: imgBase64,
          temperature: settings.temperature.value,
          maxTokens:
              settings.autoTuneParams.value ? null : settings.maxTokens.value,
          onToken: bufferToken,
        );
      }

      generationDone = true;
      return true;
    } catch (e) {
      generationDone = true;
      if (generationId != _generationSerial) {
        fluidTimer?.cancel();
        return true;
      }
      fluidTimer?.cancel();
      isStreaming.value = false;
      streamingAttachmentType.value = null;
      streamingResponse.value = '';
      streamingThought.value = '';
      streamingAnswer.value = '';
      streamingIsThinking.value = false;
      imageGenStep.value = 0;
      imageGenTotal.value = 0;
      imageGenDecoding.value = false;
      if (imageGenStartTime.value != null) {
        await Get.find<ImageGenerationNotificationService>().failed();
      }
      imageGenStartTime.value = null;
      Get.find<AppLogService>().error('Chat response failed',
          details: e, category: LogCategory.chat);
      final errorMsg = ChatMessage(
        id: _uuid.v4(),
        chatId: currentSessionId.value,
        role: 'assistant',
        content: _friendlyGenerationError(e),
      );
      messages.add(errorMsg);
      _hive.saveMessage(errorMsg.id, errorMsg.toMap());
      unawaited(HapticFeedback.heavyImpact());
      final queued = _isNetworkError(e) &&
          await _enqueueOutbox(
            prompt: prompt,
            imagePath: null,
            fileType: fileType,
            filePath: filePath,
          );
      if (queued) {
        Get.snackbar(
            'Queued — offline', 'Will auto-send when you are back online.',
            snackPosition: SnackPosition.BOTTOM,
            duration: const Duration(seconds: 3));
      }
      return false;
    }
  }

  Future<void> _extractMemories(String userMsg, String aiMsg) async {
    final personalKeywords = [
      'my name is',
      'i live in',
      'i like',
      'i work as',
      'my birthday is',
      'i am interested in',
      'i prefer',
      'i use',
      'my favorite',
      'i want to learn',
      'i am a'
    ];
    final lowerUser = userMsg.toLowerCase();
    for (final kw in personalKeywords) {
      if (lowerUser.contains(kw)) {
        final startIdx = lowerUser.indexOf(kw);
        var fact = userMsg.substring(startIdx).trim();
        final endIdx = fact.indexOf(RegExp(r'[.!?\n]'));
        if (endIdx != -1) {
          fact = fact.substring(0, endIdx).trim();
        }
        
        if (fact.length > kw.length + 2) {
          final existing = Get.find<MemoryService>().getAllMemories();
          if (!existing.any((m) => m.toLowerCase() == fact.toLowerCase())) {
            await Get.find<MemoryService>().addMemory(fact);
          }
        }
      }
    }
  }

  bool _flushingOutbox = false;
  DateTime? _outboxBackoffUntil;

  Future<bool> _enqueueOutbox({
    required String prompt,
    String? imagePath,
    String? fileType,
    String? filePath,
  }) async {
    try {
      if (imagePath != null && imagePath.isNotEmpty) return false;
      final raw = _hive
              .getSetting<List>(AppConstants.keyChatOutbox, defaultValue: []) ??
          [];
      final list = raw
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      list.add({
        'chatId': currentSessionId.value,
        'prompt': prompt,
        'fileType': fileType,
        'filePath': filePath,
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
      while (list.length > 20) {
        list.removeAt(0);
      }
      await _hive.setSetting(AppConstants.keyChatOutbox, list);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _flushOutbox() async {
    if (_flushingOutbox) return;
    final backoff = _outboxBackoffUntil;
    if (backoff != null && DateTime.now().isBefore(backoff)) return;
    _flushingOutbox = true;
    try {
      final raw = _hive
              .getSetting<List>(AppConstants.keyChatOutbox, defaultValue: []) ??
          [];
      var list = raw
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      final mine =
          list.where((e) => e['chatId'] == currentSessionId.value).toList();
      for (final e in mine) {
        list.remove(e);
        await _hive.setSetting(AppConstants.keyChatOutbox, list);
        final ok = await _generateAIResponse(
          prompt: (e['prompt'] ?? '').toString(),
          fileType: e['fileType']?.toString(),
          filePath: e['filePath']?.toString(),
        );
        if (!ok) {
          _outboxBackoffUntil = DateTime.now().add(const Duration(minutes: 2));
          return;
        }
      }
    } catch (_) {
    } finally {
      _flushingOutbox = false;
    }
  }

  void stopGenerating() {
    if (!isLoading.value && !isStreaming.value) return;
    _voiceStopQuiet = true;
    _voiceSpeaking = false;
    try {
      if (Get.isRegistered<TtsService>()) Get.find<TtsService>().stop();
    } catch (_) {}
    final partialResponse = streamingResponse.value.trim();

    final genDurationMs = generationStartTime.value != null
        ? DateTime.now().difference(generationStartTime.value!).inMilliseconds
        : null;

    if (partialResponse.isNotEmpty) {
      final tps = Get.find<InferenceService>().tokensPerSecond.value;
      _dropStreamingDraft();
      _saveAssistantMessage(
        content: partialResponse,
        tokensPerSec: tps > 0 ? tps : null,
        generationDurationMs: genDurationMs,
      );
    }
    _generationSerial++;
    _generationTimer?.cancel();
    _generationTimer = null;
    isLoading.value = false;
    isStreaming.value = false;
    streamingAttachmentType.value = null;
    streamingResponse.value = '';
    generationStartTime.value = null;
    generationLiveDurationSecs.value = 0;
    Get.find<ImageGenerationNotificationService>().cancel();
    imageGenStep.value = 0;
    imageGenTotal.value = 0;
    imageGenEstimatedSecs.value = 0;
    imageGenStartTime.value = null;
    imageGenDecoding.value = false;
    unawaited(Get.find<InferenceService>().stopGeneration());
    Get.find<LocalImageService>().cancelGeneration();
  }

  void ensureTemplatesLoaded() {
    if (_templatesLoaded) return;
    _templatesLoaded = true;
    try {
      final raw = _hive.getSetting<String>(_kTemplatesKey);
      if (raw == null || raw.isEmpty) {
        promptTemplates.assignAll(_defaultTemplates());
        unawaited(
            _hive.setSetting(_kTemplatesKey, jsonEncode(promptTemplates)));
      } else {
        final list = (jsonDecode(raw) as List)
            .whereType<Map>()
            .map((m) => {
                  'id': m['id']?.toString() ?? '',
                  'name': m['name']?.toString() ?? '',
                  'body': m['body']?.toString() ?? '',
                  'builtin': m['builtin']?.toString() ?? '',
                })
            .where((m) => (m['name'] ?? '').isNotEmpty)
            .toList();
        promptTemplates.assignAll(list.isEmpty ? _defaultTemplates() : list);
      }
    } catch (_) {
      promptTemplates.assignAll(_defaultTemplates());
    }
  }

  static List<Map<String, String>> _defaultTemplates() => const [
        {
          'id': 'builtin-explain-code',
          'name': 'Explain code',
          'body': 'Explain what this code does, step by step:\n\n',
          'builtin': '1',
        },
        {
          'id': 'builtin-fix-bug',
          'name': 'Fix a bug',
          'body':
              'Find the bug in this code and fix it. Explain the cause first:\n\n',
          'builtin': '1',
        },
        {
          'id': 'builtin-summarize',
          'name': 'Summarize',
          'body': 'Summarize this in 5 short bullet points:\n\n',
          'builtin': '1',
        },
        {
          'id': 'builtin-eli12',
          'name': 'Explain simply (ELI12)',
          'body':
              'Explain this like I am 12, with one everyday analogy and one example:\n\n',
          'builtin': '1',
        },
        {
          'id': 'builtin-translate',
          'name': 'Translate BN↔EN',
          'body':
              'Translate this between Bangla and English. Keep it natural:\n\n',
          'builtin': '1',
        },
        {
          'id': 'builtin-mail',
          'name': 'Write a mail',
          'body': 'Write a short polite email about this:\n\n',
          'builtin': '1',
        },
      ];

  void insertTemplate(String body) {
    final cur = textController.text;
    textController.text = cur.isEmpty ? body : '$cur\n$body';
    try {
      textController.selection =
          TextSelection.collapsed(offset: textController.text.length);
    } catch (_) {}
    inputText.value = textController.text;
    try {
      composerFocusNode.requestFocus();
    } catch (_) {}
  }

  Future<void> addPromptTemplate(String name, String body) async {
    ensureTemplatesLoaded();
    promptTemplates.add({
      'id': _uuid.v4(),
      'name': name.trim(),
      'body': body,
      'builtin': '',
    });
    await _hive.setSetting(
        _kTemplatesKey, jsonEncode(promptTemplates.toList()));
  }

  Future<void> deletePromptTemplate(String id) async {
    ensureTemplatesLoaded();
    promptTemplates
        .removeWhere((t) => t['id'] == id && (t['builtin'] ?? '').isEmpty);
    await _hive.setSetting(
        _kTemplatesKey, jsonEncode(promptTemplates.toList()));
  }

  void toggleSelectionMode([bool? on]) {
    final next = on ?? !selectionMode.value;
    selectionMode.value = next;
    if (!next) selectedIds.clear();
  }

  void toggleSelected(String id) {
    if (selectedIds.contains(id)) {
      selectedIds.remove(id);
    } else {
      selectedIds.add(id);
    }
    if (selectedIds.isEmpty) selectionMode.value = false;
  }

  Future<void> deleteSelected() async {
    final ids = selectedIds.toSet();
    if (ids.isEmpty) return;
    messages.removeWhere((m) => ids.contains(m.id));
    for (final id in ids) {
      try {
        await _hive.deleteMessage(id);
      } catch (_) {}
    }
    toggleSelectionMode(false);
  }

  String selectedAsMarkdown() {
    final sel = messages.where((m) => selectedIds.contains(m.id)).toList();
    final buf = StringBuffer();
    for (final m in sel) {
      buf.writeln(m.role == 'user' ? '## You' : '## AI');
      buf.writeln(m.content.trim());
      buf.writeln();
    }
    return buf.toString().trim();
  }

  bool get chatHasModelPin {
    final sid = currentSessionId.value;
    if (sid.isEmpty) return false;
    final s = sessions.firstWhereOrNull((e) => e.id == sid);
    return s != null && s.modelMode.isNotEmpty;
  }

  String get chatPinnedModelLabel {
    final sid = currentSessionId.value;
    if (sid.isEmpty) return '';
    final s = sessions.firstWhereOrNull((e) => e.id == sid);
    if (s == null || s.modelMode.isEmpty) return '';
    var label = s.modelId;
    if (s.modelMode == 'cloud' && s.modelProvider.isNotEmpty) {
      label = '${s.modelProvider}: $label';
    }
    label = label
        .replaceAll('.gguf', '')
        .replaceAll('.GGUF', '')
        .replaceAll('custom-profile:', 'custom #');
    if (label.length > 20) label = '${label.substring(0, 20)}…';
    return label;
  }

  Future<void> pinModelToChat() async {
    final sid = currentSessionId.value;
    if (sid.isEmpty) {
      Get.snackbar('No open chat', 'Open a chat first, then pin a model.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    final settings = Get.find<SettingsController>();
    final mode = settings.inferenceMode.value == 'cloud' ? 'cloud' : 'local';
    String modelId = '';
    String provider = '';
    if (mode == 'cloud') {
      provider = settings.cloudProvider.value;
      if (provider == 'custom') {
        modelId = 'custom-profile:${settings.customCloudProfileIndex.value}';
      } else {
        modelId = settings.selectedCloudModelName;
      }
      if (modelId.isEmpty) {
        Get.snackbar('Nothing to pin', 'Pick a cloud model first.',
            snackPosition: SnackPosition.BOTTOM);
        return;
      }
    } else {
      modelId = Get.find<InferenceService>().loadedModelName.value;
      if (modelId.isEmpty) {
        modelId =
            _hive.getSetting<String>(AppConstants.keyLocalModelName) ?? '';
      }
      if (modelId.isEmpty) {
        Get.snackbar('Nothing to pin', 'Load a local model first.',
            snackPosition: SnackPosition.BOTTOM);
        return;
      }
    }
    final idx = sessions.indexWhere((e) => e.id == sid);
    if (idx < 0) return;
    final updated = sessions[idx].copyWith(
      modelMode: mode,
      modelId: modelId,
      modelProvider: provider,
    );
    sessions[idx] = updated;
    await _hive.saveSession(updated.id, updated.toMap());
    Get.snackbar('Pinned to this chat', chatPinnedModelLabel,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2));
  }

  Future<void> clearChatModelPin() async {
    final sid = currentSessionId.value;
    if (sid.isEmpty) return;
    final idx = sessions.indexWhere((e) => e.id == sid);
    if (idx < 0) return;
    final updated =
        sessions[idx].copyWith(modelMode: '', modelId: '', modelProvider: '');
    sessions[idx] = updated;
    await _hive.saveSession(updated.id, updated.toMap());
  }

  Future<void> _applySessionModel(ChatSession s) async {
    if (s.modelMode.isEmpty) return;
    try {
      final settings = Get.find<SettingsController>();
      if (s.modelMode == 'cloud') {
        final cmc = Get.find<CloudModelController>();
        if (s.modelProvider == 'custom') {
          final idx =
              int.tryParse(s.modelId.replaceFirst('custom-profile:', '')) ?? 0;
          await cmc.selectCustomProfile(idx);
          await settings.setCloudProvider('custom');
          await settings.setInferenceMode('cloud');
        } else if (s.modelId.isNotEmpty) {
          await cmc.selectModel(s.modelProvider, s.modelId,
              showSnackbar: false);
        }
      } else if (s.modelId.isNotEmpty) {
        await settings.setInferenceMode('local');
        final inference = Get.find<InferenceService>();
        if (inference.loadedModelName.value != s.modelId) {
          await Get.find<ModelController>().loadModel(s.modelId);
        }
      }
    } catch (_) {}
  }

  void setCompareChallenger(String mode, String provider, String model) {
    _compareRef = {'mode': mode, 'provider': provider, 'model': model};
    compareLabel.value = mode == 'cloud'
        ? '$provider: $model'
        : model.replaceAll('.gguf', '').replaceAll('.GGUF', '');
  }

  void clearCompareChallenger() {
    _compareRef = null;
    compareLabel.value = '';
  }

  Future<void> _runComparison({
    required String prompt,
    required String systemPrompt,
    required List<Map<String, String>> history,
  }) async {
    final ref = _compareRef;
    _compareRef = null;
    compareLabel.value = '';
    if (ref == null) return;
    final chatId = currentSessionId.value;
    final settings = Get.find<SettingsController>();
    final primaryMode = settings.inferenceMode.value;
    final primaryProvider = settings.cloudProvider.value;
    final primaryCloudModel = settings.selectedCloudModelName;
    final primaryCustomIdx = settings.customCloudProfileIndex.value;
    final primaryLocal = Get.find<InferenceService>().loadedModelName.value;
    final label = ref['mode'] == 'cloud'
        ? '${ref['provider']}: ${ref['model']}'
        : (ref['model'] ?? '').replaceAll('.gguf', '').replaceAll('.GGUF', '');
    Get.snackbar('Comparing…', 'Asking $label too',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2));
    try {
      String answer;
      if (ref['mode'] == 'cloud') {
        await Get.find<CloudModelController>().selectModel(
            ref['provider'] ?? '', ref['model'] ?? '',
            showSnackbar: false);
        answer = await Get.find<CloudService>().sendMessage(
          messages: [
            {'role': 'system', 'content': systemPrompt},
            ...history,
          ],
          temperature: settings.temperature.value,
          maxTokens:
              settings.autoTuneParams.value ? null : settings.maxTokens.value,
        );
      } else {
        await settings.setInferenceMode('local');
        await Get.find<ModelController>().loadModel(ref['model'] ?? '');
        final inference = Get.find<InferenceService>();
        if (inference.loadedModelName.value != (ref['model'] ?? '')) {
          throw Exception('challenger model not loaded');
        }
        answer = await inference.generate(
          prompt: prompt,
          systemPrompt: systemPrompt,
          conversationHistory: history,
          source: 'chat-compare',
        );
      }
      if (answer.trim().isEmpty) throw Exception('empty challenger answer');
      if (currentSessionId.value != chatId) return;
      final msg = ChatMessage(
        id: _uuid.v4(),
        chatId: chatId,
        role: 'assistant',
        content: '⚖️ $label\n\n${answer.trim()}',
      );
      messages.add(msg);
      _hive.saveMessage(msg.id, msg.toMap());
    } catch (e) {
      Get.find<AppLogService>()
          .warning('Compare failed: $e', category: LogCategory.chat);
      Get.snackbar('Compare failed', e.toString(),
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      try {
        if (primaryMode == 'cloud') {
          final cmc = Get.find<CloudModelController>();
          if (primaryProvider == 'custom') {
            await cmc.selectCustomProfile(primaryCustomIdx);
            await settings.setCloudProvider('custom');
            await settings.setInferenceMode('cloud');
          } else {
            await cmc.selectModel(primaryProvider, primaryCloudModel,
                showSnackbar: false);
          }
        } else {
          await settings.setInferenceMode('local');
          if (primaryLocal.isNotEmpty &&
              Get.find<InferenceService>().loadedModelName.value !=
                  primaryLocal) {
            await Get.find<ModelController>().loadModel(primaryLocal);
          }
        }
      } catch (_) {}
    }
  }

  bool _isNetworkError(Object e) {
    final lower = e.toString().toLowerCase();
    return lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection refused') ||
        lower.contains('network is unreachable') ||
        lower.contains('timed out') ||
        lower.contains('timeoutexception');
  }

  String _friendlyGenerationError(Object e) {
    final s = e.toString();
    final lower = s.toLowerCase();
    if (lower.contains('no endpoints found that support image input') ||
        lower.contains('does not support image') ||
        lower.contains('vision is not supported')) {
      return '🖼️ This model doesn\'t support image input.\n\n'
          '• Switch to a vision model (e.g. GPT-4o, Claude, Gemini)\n'
          '• Or remove the image and resend as text';
    }
    final rateLimited = lower.contains('429') ||
        lower.contains('rate_limit') ||
        lower.contains('rate-limit') ||
        lower.contains('rate limited');
    if (rateLimited) {
      var wait = '';
      final m = RegExp(r'retry_after_seconds"?\s*:\s*(\d+)').firstMatch(s);
      if (m != null) wait = ' (~${m.group(1)}s)';
      return '⏳ The provider rate-limited this request$wait '
          '(free shared pool).\n\n• Wait a bit and retry\n'
          '• Or add your own API key: Explore → provider card → Add API Key';
    }
    if (_isNetworkError(e)) {
      return '🌐 Network error — check your connection and retry.';
    }
    if (s.length > 300) {
      return '❌ Error: ${s.substring(0, 300)}…\n'
          '(Full details in System Logs → Chat)';
    }
    return '❌ Error: $s';
  }

  void editMessage(ChatMessage msg, String newContent) {
    if (isLoading.value || isStreaming.value) return;
    if (msg.role != 'user') return;
    final idx = messages.indexWhere((m) => m.id == msg.id);
    if (idx < 0) return;

    textController.clear();
    inputText.value = '';

    String? currentAssistantResponse;
    if (idx + 1 < messages.length && messages[idx + 1].role == 'assistant') {
      currentAssistantResponse = messages[idx + 1].content;
    }

    final allRevisions = List<Map<String, dynamic>>.from(msg.revisions ?? []);

    if (allRevisions.isEmpty) {
      allRevisions.add({
        'content': msg.content,
        'response': currentAssistantResponse,
      });
    } else {
      allRevisions[msg.revisionIndex] = {
        'content': msg.content,
        'response': currentAssistantResponse,
      };
    }

    allRevisions.add({
      'content': newContent,
      'response': null,
    });

    if (idx + 1 < messages.length && messages[idx + 1].role == 'assistant') {
      _hive.deleteMessage(messages[idx + 1].id);
      messages.removeAt(idx + 1);
    }

    final updated = ChatMessage(
      id: msg.id,
      chatId: msg.chatId,
      role: msg.role,
      content: newContent,
      imageBase64: msg.imageBase64,
      imagePath: msg.imagePath,
      fileName: msg.fileName,
      fileContent: msg.fileContent,
      filePath: msg.filePath,
      fileType: msg.fileType,
      fileSize: msg.fileSize,
      timestamp: msg.timestamp,
      revisions: allRevisions,
      revisionIndex: allRevisions.length - 1,
    );
    messages[idx] = updated;
    _hive.saveMessage(updated.id, updated.toMap());

    _generateAIResponse(
      prompt: newContent,
      imagePath: msg.imagePath,
      imgBase64: msg.imageBase64,
      fileType: msg.fileType,
      filePath: msg.filePath,
      insertAt: idx + 1,
    );
  }

  void navigateRevision(ChatMessage msg, int direction) {
    final revisions = msg.revisions;
    if (revisions == null || revisions.isEmpty) return;

    final targetIdx = msg.revisionIndex + direction;
    if (targetIdx < 0 || targetIdx >= revisions.length) return;

    var msgIdx = messages.indexWhere((m) => m.id == msg.id);
    if (msgIdx < 0) return;
    if (msgIdx == 0 && hasOlderMessages.value) {
      unawaited(loadOlderMessages().then((_) {
        navigateRevision(msg, direction);
      }));
      return;
    }

    String? currentResponse;
    if (msgIdx + 1 < messages.length &&
        messages[msgIdx + 1].role == 'assistant') {
      currentResponse = messages[msgIdx + 1].content;
    }

    final updatedRevisions = List<Map<String, dynamic>>.from(revisions);
    updatedRevisions[msg.revisionIndex] = {
      'content': msg.content,
      'response': currentResponse,
    };

    final targetRevision = updatedRevisions[targetIdx];
    final targetContent = targetRevision['content'] as String;
    final targetResponse = targetRevision['response'] as String?;

    final updatedUser = ChatMessage(
      id: msg.id,
      chatId: msg.chatId,
      role: msg.role,
      content: targetContent,
      imageBase64: msg.imageBase64,
      imagePath: msg.imagePath,
      fileName: msg.fileName,
      fileContent: msg.fileContent,
      filePath: msg.filePath,
      fileType: msg.fileType,
      fileSize: msg.fileSize,
      timestamp: msg.timestamp,
      revisions: updatedRevisions,
      revisionIndex: targetIdx,
    );
    messages[msgIdx] = updatedUser;
    _hive.saveMessage(updatedUser.id, updatedUser.toMap());

    if (msgIdx + 1 < messages.length &&
        messages[msgIdx + 1].role == 'assistant') {
      if (targetResponse != null) {
        final oldAssistant = messages[msgIdx + 1];
        final updatedAssistant = ChatMessage(
          id: oldAssistant.id,
          chatId: oldAssistant.chatId,
          role: oldAssistant.role,
          content: targetResponse,
          imageBase64: oldAssistant.imageBase64,
          imagePath: oldAssistant.imagePath,
          tokensPerSec: oldAssistant.tokensPerSec,
          thoughtDurationSeconds: oldAssistant.thoughtDurationSeconds,
          timestamp: oldAssistant.timestamp,
        );
        messages[msgIdx + 1] = updatedAssistant;
        _hive.saveMessage(updatedAssistant.id, updatedAssistant.toMap());
      } else {
        _hive.deleteMessage(messages[msgIdx + 1].id);
        messages.removeAt(msgIdx + 1);
      }
    } else if (targetResponse != null) {
      final aiMsg = ChatMessage(
        id: _uuid.v4(),
        chatId: msg.chatId,
        role: 'assistant',
        content: targetResponse,
      );
      messages.insert(msgIdx + 1, aiMsg);
      _hive.saveMessage(aiMsg.id, aiMsg.toMap());
    }

    messages.refresh();
  }

  void regenerateFromMessage(ChatMessage msg) {
    if (isLoading.value || isStreaming.value) return;
    var idx = messages.indexWhere((m) => m.id == msg.id);
    if (idx < 0) return;
    if (idx == 0 && hasOlderMessages.value) {
      unawaited(loadOlderMessages().then((_) {
        regenerateFromMessage(msg);
      }));
      return;
    }

    final userMsg = idx > 0 ? messages[idx - 1] : null;
    if (userMsg == null || userMsg.role != 'user') return;

    textController.clear();
    inputText.value = '';

    _hive.deleteMessage(msg.id);
    messages.removeAt(idx);

    _scrollToBottom(force: true);

    _generateAIResponse(
      prompt: userMsg.content,
      imagePath: userMsg.imagePath,
      imgBase64: userMsg.imageBase64,
      fileType: userMsg.fileType,
      filePath: userMsg.filePath,
      insertAt: idx,
    );
  }

  void branchNewChat(ChatMessage msg) {
    if (isLoading.value || isStreaming.value) return;
    final idx = messages.indexWhere((m) => m.id == msg.id);
    if (idx < 0) return;

    final stored = _hive.getMessagesForChat(msg.chatId);
    final cutoff = msg.timestamp;
    final historyToCopy = stored.map((m) => ChatMessage.fromMap(m)).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    historyToCopy.retainWhere((m) =>
        m.id != msg.id &&
        !m.timestamp.isAfter(cutoff) &&
        (m.role == 'user' || m.role == 'assistant'));

    createNewChat();

    for (final m in historyToCopy) {
      final copied = ChatMessage(
        id: _uuid.v4(),
        chatId: currentSessionId.value,
        role: m.role,
        content: m.content,
        imageBase64: m.imageBase64,
        imagePath: m.imagePath,
        fileName: m.fileName,
        fileContent: m.fileContent,
        filePath: m.filePath,
        fileType: m.fileType,
        fileSize: m.fileSize,
        tokensPerSec: m.tokensPerSec,
        thoughtDurationSeconds: m.thoughtDurationSeconds,
        timestamp: m.timestamp,
      );
      _hive.saveMessage(copied.id, copied.toMap());
      messages.add(copied);
    }
    _scrollToBottom(force: true);
  }

  void deleteMessage(ChatMessage msg) {
    final idx = messages.indexWhere((m) => m.id == msg.id);
    if (idx < 0) return;
    _hive.deleteMessage(msg.id);
    messages.removeAt(idx);
    if (messages.isEmpty && hasOlderMessages.value) {
      unawaited(loadOlderMessages());
    }
  }

  void saveStreamingDraft() {
    if (!isStreaming.value) return;
    final text = streamingResponse.value.trim();
    if (text.isEmpty || currentSessionId.value.isEmpty) return;
    _dropStreamingDraft();
    try {
      final aiMsg = ChatMessage(
        id: _uuid.v4(),
        chatId: currentSessionId.value,
        role: 'assistant',
        content: text,
      );
      messages.add(aiMsg);
      _hive.saveMessage(aiMsg.id, aiMsg.toMap());
      _draftMsgId = aiMsg.id;
      final session =
          sessions.firstWhereOrNull((s) => s.id == currentSessionId.value);
      if (session != null) {
        final updated = session.copyWith(lastMessage: text);
        _hive.saveSession(updated.id, updated.toMap());
        final idx = sessions.indexWhere((s) => s.id == updated.id);
        if (idx >= 0) sessions[idx] = updated;
      }
    } catch (_) {}
  }

  void _dropStreamingDraft() {
    final id = _draftMsgId;
    _draftMsgId = null;
    if (id == null || id.isEmpty) return;
    try {
      messages.removeWhere((m) => m.id == id);
      _hive.deleteMessage(id);
    } catch (_) {}
  }

  void _saveAssistantMessage({
    required String content,
    String? imageBase64,
    double? tokensPerSec,
    int? thoughtDurationSeconds,
    int? generationDurationMs,
  }) {
    final aiMsg = ChatMessage(
      id: _uuid.v4(),
      chatId: currentSessionId.value,
      role: 'assistant',
      content: content,
      imageBase64: imageBase64,
      tokensPerSec: tokensPerSec,
      thoughtDurationSeconds: thoughtDurationSeconds,
      generationDurationMs: generationDurationMs,
    );
    messages.add(aiMsg);
    _hive.saveMessage(aiMsg.id, aiMsg.toMap());

    final session =
        sessions.firstWhereOrNull((s) => s.id == currentSessionId.value);
    if (session != null) {
      final updated = session.copyWith(lastMessage: aiMsg.content);
      _hive.saveSession(updated.id, updated.toMap());
      final idx = sessions.indexWhere((s) => s.id == updated.id);
      if (idx >= 0) sessions[idx] = updated;
    }
  }

  void _handleUserScroll() {
    if (!scrollController.hasClients) return;
    final position = scrollController.position;
    final distanceFromBottom = position.maxScrollExtent - position.pixels;
    showScrollToBottom.value = distanceFromBottom > 200;
    if (position.pixels <= 240 &&
        hasOlderMessages.value &&
        !isLoadingOlder.value &&
        !isLoading.value) {
      unawaited(loadOlderMessages());
    }

    if (!isStreaming.value) {
      _followStreaming = distanceFromBottom <= 180;
    } else if (distanceFromBottom <= 48) {
      _followStreaming = true;
    }
  }

  void jumpToBottom() {
    if (!scrollController.hasClients) return;
    _followStreaming = true;
    _scrollToBottom(force: true);
  }

  void pauseStreamingFollow() {
    if (isStreaming.value) {
      _followStreaming = false;
    }
  }

  void resumeStreamingFollowIfNearBottom() {
    if (!scrollController.hasClients) return;
    final position = scrollController.position;
    final distanceFromBottom = position.maxScrollExtent - position.pixels;
    if (distanceFromBottom <= 48) {
      _followStreaming = true;
    }
  }

  void _scrollToBottom({bool force = false}) {
    if (!force && isStreaming.value && !_followStreaming) return;
    if (_scrollTimer?.isActive == true) return;

    final delay = isStreaming.value ? 24 : 32;

    _scrollTimer = Timer(Duration(milliseconds: delay), () {
      if (!scrollController.hasClients) return;
      if (!force && isStreaming.value && !_followStreaming) return;
      
      final pos = scrollController.position;
      final target = pos.maxScrollExtent;
      final current = pos.pixels;
      
      if ((target - current).abs() < 4) {
        if (target != current) scrollController.jumpTo(target);
        return;
      }

      final duration = isStreaming.value ? 100 : 250;
      
      scrollController.animateTo(
        target,
        duration: Duration(milliseconds: duration),
        curve: isStreaming.value ? Curves.linear : Curves.easeOutCubic,
      );
    });
  }

  Future<String?> _persistImageFile(String sourcePath, String messageId) async {
    if (kIsWeb) return sourcePath;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final chatDir = Directory('${dir.path}/chat_images');
      if (!await chatDir.exists()) await chatDir.create(recursive: true);
      final ext = sourcePath.split('.').last.toLowerCase();
      final validExt =
          {'jpg', 'jpeg', 'png', 'webp', 'gif', 'heic'}.contains(ext)
              ? ext
              : 'jpg';
      final dest = File('${chatDir.path}/$messageId.$validExt');
      await File(sourcePath).copy(dest.path);
      return dest.path;
    } catch (_) {
      return sourcePath;
    }
  }

  Future<String?> _persistImageBytes(Uint8List bytes, String messageId) async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final chatDir = Directory('${dir.path}/chat_images');
      if (!await chatDir.exists()) await chatDir.create(recursive: true);
      final dest = File('${chatDir.path}/$messageId.png');
      await dest.writeAsBytes(bytes);
      return dest.path;
    } catch (_) {
      return null;
    }
  }

  String _attachmentTypeForExtension(String extension) {
    const imageExtensions = {'png', 'jpg', 'jpeg', 'webp', 'gif', 'heic'};
    const audioExtensions = {'mp3', 'm4a', 'wav', 'aac', 'ogg', 'flac'};
    const textExtensions = {
      'txt', 'md', 'json', 'csv', 'log', 'yaml', 'yml', 'xml',
      'dart', 'kt', 'java', 'js', 'ts', 'py',
    };
    if (imageExtensions.contains(extension)) return 'image';
    if (audioExtensions.contains(extension)) return 'audio';
    if (extension == 'pdf') return 'pdf';
    if (extension == 'docx') return 'docx';
    if (textExtensions.contains(extension)) return 'text';
    return 'file';
  }

  String _defaultAttachmentPrompt(String? fileType) {
    switch (fileType) {
      case 'image':
        return 'Describe this image.';
      case 'pdf':
        return 'Summarize this PDF.';
      case 'docx':
        return 'Summarize this document.';
      case 'audio':
        return 'Transcribe or analyze this audio.';
      case 'text':
        return 'Review this file.';
      default:
        return 'Review this attachment.';
    }
  }

  bool _isImageGenerationPrompt(String prompt) {
    final lower = prompt.toLowerCase().trim();
    if (lower.isEmpty) return false;
    if (lower.startsWith('/image') ||
        lower.startsWith('/img') ||
        lower.startsWith('/draw') ||
        lower.startsWith('/generate image')) {
      return true;
    }
    const triggers = [
      'generate image', 'create image', 'make image', 'generate a image',
      'create a picture', 'generate a picture', 'make a picture',
      'generate photo', 'create photo', 'draw a', 'draw an',
      'painting of', 'illustration of', 'render image', 'generate picture',
    ];
    if (triggers.any((t) => lower.contains(t))) return true;
    final hasImageWord = lower.contains('image') ||
        lower.contains('picture') ||
        lower.contains('photo') ||
        lower.contains('illustration') ||
        lower.contains('artwork');
    final hasAction = lower.contains('generate') ||
        lower.contains('create') ||
        lower.contains('make') ||
        lower.contains('draw') ||
        lower.contains('render') ||
        lower.contains('paint') ||
        lower.contains('design');
    if (hasImageWord && hasAction) return true;
    if (lower.contains('draw ')) return true;
    return false;
  }
}
