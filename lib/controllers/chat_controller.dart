import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart'
    show compute, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:uuid/uuid.dart';
import '../controllers/settings_controller.dart';
import '../controllers/model_controller.dart';
import '../controllers/cloud_model_controller.dart';
import '../controllers/home_controller.dart';
import '../core/constants.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../ffi/sd_ffi_bindings.dart';
import '../services/hive_service.dart';
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

const int _visionImageMaxSide = 768;
const int _visionImageJpegQuality = 72;

Uint8List? _resizeVisionImageBytes(Map<String, dynamic> args) {
  final bytes = args['bytes'] as Uint8List;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  final longestSide = decoded.width > decoded.height ? decoded.width : decoded.height;
  if (longestSide <= _visionImageMaxSide) {
    return bytes;
  }

  final resized = img.copyResize(
    decoded,
    width: decoded.width >= decoded.height ? _visionImageMaxSide : null,
    height: decoded.height > decoded.width ? _visionImageMaxSide : null,
    interpolation: img.Interpolation.average,
  );
  return Uint8List.fromList(
    img.encodeJpg(resized, quality: _visionImageJpegQuality),
  );
}

class ChatController extends GetxController {
  final HiveService _hive = Get.find<HiveService>();
  final _uuid = const Uuid();

  // State
  final sessions = <ChatSession>[].obs;
  final messages = <ChatMessage>[].obs;
  final currentSessionId = ''.obs;
  final isLoading = false.obs;
  final inputText = ''.obs;
  final selectedImagePath = Rxn<String>();
  final selectedImageBase64 = Rxn<String>();
  final selectedFileName = Rxn<String>();
  final selectedFileContent = Rxn<String>();
  final selectedFilePath = Rxn<String>();
  final selectedFileType = Rxn<String>();
  final selectedFileSize = 0.obs;

  // Real-time streaming state — the AI response as it's being generated
  final streamingResponse = ''.obs;
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

  // Speech-to-text
  final isListening = false.obs;
  final sttAvailable = false.obs;
  final _speech = stt.SpeechToText();

  // ─── Hands-free voice mode ───
  // Loop: listen → (final result) auto-send → reply → speak → listen.
  // Built from existing pieces (toggleListening/sendMessage/TtsService).
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
  }

  void _detachVoiceWorkers() {
    for (final w in _voiceWorkers) {
      try {
        w.dispose();
      } catch (_) {}
    }
    _voiceWorkers.clear();
  }

  /// Speaks the latest assistant reply when a hands-free turn settles,
  /// then the TTS watcher re-arms listening.
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

  // ─── Find in open chat ───
  final findActive = false.obs;
  final findQuery = ''.obs;
  final findMatches = <String>[].obs; // message ids, chronological
  final findIndex = 0.obs;
  final findController = TextEditingController();
  final _findKeys = <String, GlobalKey>{};

  /// Stable per-message key: doubles as the list identity key (state by
  /// id, not position) and the find-jump anchor for ensureVisible.
  GlobalKey findKeyFor(String id) =>
      _findKeys.putIfAbsent(id, GlobalKey.new);

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

  /// Searches the loaded window, then pulls older pages (max 5) until a
  /// hit or exhaustion — so find works beyond the newest 100 without
  /// dumping the whole history into memory. Superseded flights abort.
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

  /// Chat history drawer scaffold + its search field. Bound by ChatView;
  /// lets desktop shortcuts (Ctrl+F) open the drawer and focus search
  /// without a BuildContext.
  final chatScaffoldKey = GlobalKey<ScaffoldState>();
  final historySearchFocus = FocusNode();

  /// Desktop shortcut (Ctrl+F): open the history drawer and focus its
  /// search field so the user can immediately type.
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
    _initSpeech();
    _loadAutoBackupPrefs();
    // Pick up Android share-target text (cold start).
    unawaited(checkSharedText());
    // Silent scheduled backup, once per process (no-op unless enabled).
    if (!_autoBackupChecked) {
      _autoBackupChecked = true;
      unawaited(Future.delayed(
          const Duration(seconds: 10), () => maybeAutoBackup()));
    }
  }

  static bool _autoBackupChecked = false;

  /// Pull text shared from other Android apps (ACTION_SEND → MainActivity
  /// stash → getSharedText). Fills the composer and jumps to the chat tab.
  /// No-op on other platforms; never throws.
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
      Get.snackbar('Shared text added',
          'Review and tap send when ready.',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 3));
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
      // Runtime mic permission first — without it initialize() fails
      // silently and the user never sees a system dialog.
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
            ),          );
          return;
        }
        if (!mic.isGranted) return; // denied (not permanent) — stay silent
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
          // Hands-free: final transcript auto-sends (once per utterance).
          if (voiceMode.value && result.finalResult) {
            final said = result.recognizedWords.trim();
            if (said.isNotEmpty &&
                _voiceSendArmed &&
                !isLoading.value) {
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

  /// Speech locale following the app language (mirrors TTS mapping).
  /// Falls back to en-US when unknown or unset.
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

  /// Pinned sessions float to the top, then most-recently-updated first.
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

  /// Archived chats hide from the drawer (unless revealed). The open chat
  /// stays open when archived — only the list filters it out.
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

  /// Show/hide archived chats in the drawer list.
  final showArchived = false.obs;

  int get archivedCount => sessions.where((s) => s.archived).length;

  /// Hidden chats: stronger hide — out of the drawer AND search hits
  /// until revealed. The open chat stays open when hidden.
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

  /// Show/hide hidden chats in the drawer list.
  final showHidden = false.obs;

  int get hiddenCount => sessions.where((s) => s.hidden).length;

  /// Label/folder filter for the drawer ('' = all labels).
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

  /// Set (or clear with empty) a chat's label/folder.
  void setLabel(String sessionId, String label) {
    final session = sessions.firstWhereOrNull((s) => s.id == sessionId);
    if (session == null) return;
    final updated = session.copyWith(label: label.trim());
    _hive.saveSession(updated.id, updated.toMap());
    final idx = sessions.indexWhere((s) => s.id == updated.id);
    if (idx >= 0) sessions[idx] = updated;
    sessions.sort(_sessionSort);
  }

  /// Per-chat persona (system-prompt addition). Empty clears to global.
  void setPersona(String sessionId, String persona) {
    final session = sessions.firstWhereOrNull((s) => s.id == sessionId);
    if (session == null) return;
    final updated = session.copyWith(persona: persona.trim());
    _hive.saveSession(updated.id, updated.toMap());
    final idx = sessions.indexWhere((s) => s.id == updated.id);
    if (idx >= 0) sessions[idx] = updated;
  }

  /// Persona of the currently open chat ('' when none).
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
    // Sort (don't blind-insert at 0) so a new unpinned chat never jumps
    // above pinned sessions until the next reload.
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
    // Windowed load: newest N messages only. Huge histories no longer
    // parse + inflate all at once; older pages load on scroll-to-top.
    final raw = _hive.getMessagesForChatPaged(
      sessionId,
      limit: _chatPageSize,
    );
    messages.value = raw.map((m) => ChatMessage.fromMap(m)).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    hasOlderMessages.value = raw.length >= _chatPageSize;
    // Warm image bytes off the critical path: async file reads (thread
    // pool) so first scroll over an image doesn't stall on sync I/O in
    // build. Fire-and-forget; bubbles render text immediately.
    unawaited(_preloadChatImages(sessionId, messages.toList()));
    final inference = Get.find<InferenceService>();
    if (inference.isModelLoaded.value) {
      inference.refreshContextInfo();
    }
    _resetInferenceContext();
    final opened = sessions.firstWhereOrNull((s) => s.id == sessionId);
    if (opened != null) unawaited(_applySessionModel(opened));
    _scrollToBottom(force: true);
  }

  /// Gate for per-chat lock: authenticate first, then open unlocked.
  /// Never throws; failed auth stays on the current chat.
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

  /// Toggle the per-chat lock (title stays visible; content is gated).
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

  /// Number of messages loaded per chat window page.
  static const int _chatPageSize = 100;

  /// True when older messages may exist beyond the loaded window.
  final hasOlderMessages = false.obs;

  /// True while a load-older page is in flight (re-entrancy guard).
  final isLoadingOlder = false.obs;

  /// Prepends the next older page, preserving the visual scroll position.
  /// No-op when everything is loaded or a load is already running.
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
      final oldestMs =
          messages.first.timestamp.millisecondsSinceEpoch;
      final raw = _hive.getMessagesForChatPaged(
        sessionId,
        limit: _chatPageSize,
        beforeTimestampMs: oldestMs,
      );
      if (currentSessionId.value != sessionId) return; // switched mid-flight
      if (raw.isEmpty) {
        hasOlderMessages.value = false;
        return;
      }
      final older = raw.map((m) => ChatMessage.fromMap(m)).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      // De-dupe against the window edge (equal timestamps possible).
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
            (oldPixels + (newMax - oldMax))
                .clamp(0.0, newMax.toDouble()),
          );
        } catch (_) {}
      });
    } finally {
      isLoadingOlder.value = false;
    }
  }

  /// Preloads image payloads for [msgs] without blocking. Skips anything
  /// already cached and stops early if the user switched chats mid-flight.
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
    // Snapshot for Undo (image files on disk are not restorable).
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

  /// Restore the most recently deleted chat (5s UNDO window).
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

  /// Build the backup JSON string, or null when there is nothing to back
  /// up. Shared by manual export and silent auto-backup.
  ///
  /// - [includeImages]: keep base64 image payloads (much larger file).
  /// - [passphrase]: non-empty encrypts the payload (AES-256-CBC,
  ///   SHA-256 key). Import then requires the same passphrase.
  Future<String?> buildBackupJson({
    bool includeImages = false,
    String? passphrase,
  }) async {
    final sessionsRaw = _hive.getAllSessions();
    final messagesRaw = _hive.getAllMessagesRaw();
    if (sessionsRaw.isEmpty) return null;

    final sessionsOut = sessionsRaw.map((s) {
      final m = Map<String, dynamic>.from(s);
      if (!includeImages) m.remove('imageBase64');
      return m;
    }).map((s) => ChatSession.fromMap(s).toMap()).toList();

    final messagesOut = messagesRaw.map((m) {
      final c = Map<String, dynamic>.from(m);
      // File paths never transfer across devices.
      c['imagePath'] = null;
      if (!includeImages) c['imageBase64'] = null;
      return c;
    }).toList();

    final inner = {
      'sessions': sessionsOut,
      'messages': messagesOut,
    };
    final Map<String, dynamic> payload;
    final pass = (passphrase ?? '').trim();
    if (pass.isNotEmpty) {
      final plain = Uint8List.fromList(utf8.encode(
        '${HiveService.backupMagic}${jsonEncode(inner)}',
      ));
      final packed = await _hive.encryptBackupBytes(plain, pass);
      payload = {
        'app': 'CubicLM',
        'type': 'chat_backup_encrypted',
        'version': 1,
        'algo': 'aes256cbc-sha256',
        'exportedAt': DateTime.now().toIso8601String(),
        'data': base64Encode(packed),
      };
    } else {
      payload = {
        'app': 'CubicLM',
        'type': 'chat_backup',
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        ...inner,
      };
    }
    return jsonEncode(payload);
  }

  /// Export every session + message to a single JSON backup file and open
  /// the system share sheet. Desktop has no share sheet — a native save
  /// dialog is shown instead so the user picks the destination directly.
  Future<String?> exportAllChats({
    bool includeImages = false,
    String? passphrase,
  }) async {
    try {
      final jsonStr = await buildBackupJson(
          includeImages: includeImages, passphrase: passphrase);
      if (jsonStr == null) return 'empty';

      if (!kIsWeb &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        return await _exportChatsDesktop(jsonStr);
      }

      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().toIso8601String().split('T').first;
      final file = File('${dir.path}/cubiclm_chat_backup_$stamp.json');
      await file.writeAsString(jsonStr, flush: true);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: 'CubicLM chat backup',
      );
      return null;
    } catch (e) {
      Get.find<AppLogService>().error('Backup export failed',
          details: e, category: LogCategory.chat);
      return 'error';
    }
  }

  /// Desktop export: native save dialog writes the JSON directly to the
  /// path the user picks. Returns null on success, 'cancelled' when the
  /// user dismisses the dialog, 'error' on failure.
  Future<String?> _exportChatsDesktop(String jsonStr) async {
    try {
      final stamp = DateTime.now().toIso8601String().split('T').first;
      final outPath = await FilePicker.saveFile(
        dialogTitle: 'Save CubicLM chat backup',
        fileName: 'cubiclm_chat_backup_$stamp.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: Uint8List.fromList(utf8.encode(jsonStr)),
      );
      if (outPath == null) return 'cancelled';
      Get.snackbar(
        'Backup saved',
        outPath,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 6),
      );
      Get.find<AppLogService>().info('Chat backup exported',
          details: outPath, category: LogCategory.chat);
      return null;
    } catch (e) {
      Get.find<AppLogService>().error('Backup export failed',
          details: e, category: LogCategory.chat);
      return 'error';
    }
  }

  /// Silent scheduled backup: writes unencrypted JSON (no images) to the
  /// app documents dir when enabled and due, keeping the last 3 files.
  /// Runs once per process from onInit. Never throws, never prompts.
  /// NOTE: auto-backups are unencrypted (no unattended passphrase) —
  /// use manual export with a passphrase for sensitive chats.
  Future<void> maybeAutoBackup() async {
    try {
      final enabled = _hive.getSetting<bool>(
              AppConstants.keyAutoBackupEnabled,
              defaultValue: false) ??
          false;
      if (enabled != true) return;
      if (kIsWeb) return;
      final days = _hive.getSetting<int>(AppConstants.keyAutoBackupDays,
              defaultValue: 7) ??
          7;
      final last = _hive.getSetting<int>(AppConstants.keyLastAutoBackup,
              defaultValue: 0) ??
          0;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (nowMs - last < days * 24 * 60 * 60 * 1000) return;
      final jsonStr = await buildBackupJson();
      if (jsonStr == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final file = File('${dir.path}/cubiclm_auto_backup_$stamp.json');
      await file.writeAsString(jsonStr, flush: true);
      // Prune to the last 3 auto-backups.
      final autos = Directory(dir.path)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('cubiclm_auto_backup_'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      for (final old in autos.skip(3)) {
        try {
          await old.delete();
        } catch (_) {}
      }
      await _hive.setSetting(AppConstants.keyLastAutoBackup, nowMs);
      Get.find<AppLogService>().info('Auto backup saved',
          details: file.path, category: LogCategory.chat);
    } catch (_) {}
  }

  Future<void> setAutoBackup(bool enabled, [int? days]) async {
    autoBackupEnabled.value = enabled;
    await _hive.setSetting(AppConstants.keyAutoBackupEnabled, enabled);
    if (days != null) {
      autoBackupDays.value = days;
      await _hive.setSetting(AppConstants.keyAutoBackupDays, days);
    }
  }

  /// Export app settings WITHOUT secrets (API keys live in secure
  /// storage and custom-profile inline keys are excluded too).
  /// Returns null on success, or an error string. Desktop shows a native
  /// save dialog; mobile shares the file.
  static final _settingsSecretKeys = {
    AppConstants.keyOpenaiKey,
    AppConstants.keyAnthropicKey,
    AppConstants.keyGoogleKey,
    AppConstants.keyKimiKey,
    AppConstants.keyStabilityKey,
    AppConstants.keyNvidiaKey,
    AppConstants.keyOpenRouterKey,
    AppConstants.keyDeepSeekKey,
    AppConstants.keyZaiKey,
    AppConstants.keyGroqKey,
    AppConstants.keyMistralKey,
    AppConstants.keyTogetherKey,
    AppConstants.keyXaiKey,
    AppConstants.keyPerplexityKey,
    AppConstants.keyCerebrasKey,
    AppConstants.keyFireworksKey,
    AppConstants.keyCohereKey,
    AppConstants.keyHuggingFaceKey,
    AppConstants.keyXkiroKey,
    AppConstants.keyTokenRouterKey,
    AppConstants.keyCustomCloudKey,
    AppConstants.keyCustomCloudProfiles,
    AppConstants.keyServerApiKey,
  };
  static final _settingsSecretPattern =
      RegExp(r'token|secret|password|apikey|api_key|credential', caseSensitive: false);

  Future<String?> exportSettings() async {
    try {
      final all = _hive.getAllSettingsRaw();
      all.removeWhere((k, _) =>
          _settingsSecretKeys.contains(k) ||
          _settingsSecretPattern.hasMatch(k));
      final payload = {
        'app': 'CubicLM',
        'type': 'settings_backup',
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'settings': all,
      };
      final jsonStr = jsonEncode(payload);
      final stamp = DateTime.now().toIso8601String().split('T').first;
      final fileName = 'cubiclm_settings_$stamp.json';
      if (!kIsWeb &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        final outPath = await FilePicker.saveFile(
          dialogTitle: 'Save CubicLM settings',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['json'],
          bytes: Uint8List.fromList(utf8.encode(jsonStr)),
        );
        if (outPath == null) return 'cancelled';
        Get.find<AppLogService>().info('Settings exported',
            details: outPath, category: LogCategory.chat);
        return null;
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(jsonStr, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: 'CubicLM settings',
      );
      return null;
    } catch (e) {
      Get.find<AppLogService>().error('Settings export failed',
          details: e, category: LogCategory.chat);
      return 'error';
    }
  }

  /// Import a settings backup. Secrets are never imported (skipped).
  /// Returns null on success, or an error string. Some settings apply
  /// after an app restart.
  Future<String?> importSettings() async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (picked == null || picked.files.isEmpty) return 'cancelled';
      final bytes = picked.files.first.bytes ??
          await File(picked.files.first.path!).readAsBytes();
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map || decoded['type'] != 'settings_backup') {
        return 'Not a CubicLM settings file.';
      }
      final map = Map<String, dynamic>.from(decoded['settings'] ?? {});
      var applied = 0;
      for (final e in map.entries) {
        if (_settingsSecretKeys.contains(e.key) ||
            _settingsSecretPattern.hasMatch(e.key)) {
          continue;
        }
        try {
          // Only JSON-native values cross devices safely.
          jsonEncode(e.value);
          await _hive.setSetting(e.key, e.value);
          applied++;
        } catch (_) {}
      }
      Get.find<AppLogService>().info('Settings imported: $applied applied',
          category: LogCategory.chat);
      return null;
    } catch (e) {
      return 'Import failed: $e';
    }
  }

  /// Import a previously exported CubicLM chat backup. Existing sessions
  /// and messages are never overwritten — only new items are merged in.
  /// Encrypted backups require [passphrase]: 'locked' when missing,
  /// 'invalid' when wrong. Returns an error string, or null on success.
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

      // NOTE: Uint8List.toString() yields "[123, 34, ...]" — never the file
      // content. Decode picked bytes as UTF-8 explicitly, else a valid
      // backup picked with withData:true always fails as 'invalid'.
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
      final hasData =
          body['sessions'] is List || body['messages'] is List;
      // Plain backups carry type 'chat_backup'; decrypted payloads and
      // legacy files may omit it but must carry data.
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

      // Build the set of existing message keys to skip duplicates.
      final existingMessageKeys = _hive
          .getAllMessagesRaw()
          .map((m) => _messageKey(m['chatId']?.toString() ?? '',
              m['id']?.toString() ?? ''))
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
      // image_picker ships no Windows/Linux/macOS implementation — a bare
      // call throws MissingPluginException and crashes the attach flow.
      // Route desktop gallery-picks through FilePicker instead.
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
      Get.find<AppLogService>().error('Image pick failed',
          details: e, category: LogCategory.chat);
      Get.snackbar('Image Pick Failed',
          'Could not pick an image on this device.',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  /// Desktop gallery-pick via the native file dialog. Resize/compress still
  /// happens later in the shared send path (_resizeVisionImageBytes).
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
    // No camera capture on desktop — fail with guidance, not a plugin crash.
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
      case 'anthropic': modelName = s.anthropicModel.value; break;
      case 'google': modelName = s.googleModel.value; break;
      case 'kimi': modelName = s.kimiModel.value; break;
      case 'stability': modelName = s.stabilityModel.value; break;
      case 'nvidia': modelName = s.nvidiaModel.value; break;
      case 'openrouter': modelName = s.openRouterModel.value; break;
      case 'deepseek': modelName = s.deepSeekModel.value; break;
      case 'custom': modelName = s.customCloudModel.value; break;
      default: modelName = s.openaiModel.value; break;
    }
    
    final model = modelName.toLowerCase();
    
    // Known vision keywords in cloud model names
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
        backgroundColor: const Color(0xFFFF9500).withValues(alpha: 0.95), // Warning Orange
        colorText: Colors.white,
        margin: const EdgeInsets.all(12),
      );
    }
  }

  /// Local mode: only LiteRT vision sessions accept images on-device
  /// today — GGUF has no mmproj loader, so attaching a picture to a GGUF
  /// chat fails at generate time. Warn at attach time instead, while the
  /// user can still switch to Cloud or load a vision .litertlm.
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
          'png',
          'jpg',
          'jpeg',
          'webp',
          'gif',
          'heic',
          'pdf',
          'docx',
          'mp3',
          'm4a',
          'wav',
          'aac',
          'ogg',
          'flac',
          'txt',
          'md',
          'json',
          'csv',
          'log',
          'yaml',
          'yml',
          'xml',
          'dart',
          'kt',
          'java',
          'js',
          'ts',
          'py'
        ],
        withData: kIsWeb,
      );
      if (result == null) return;
      final file = result.files.single;
      final extension = file.extension?.toLowerCase() ?? '';
      final fileType = _attachmentTypeForExtension(extension);

      // Reject unsupported or extension-less files
      if (extension.isEmpty || fileType == 'file') {
        Get.snackbar(
          'Unsupported file',
          'Only images, audio, PDF, DOCX, and text/code files are supported.',
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }

      if (fileType == 'image') {
        final bytes = file.bytes ??
            (file.path != null ? await File(file.path!).readAsBytes() : null);
        if (bytes == null) return;
        final optimizedPath = await _prepareVisionImagePath(
          bytes: bytes,
          originalName: file.name,
          fallbackPath: file.path,
        );

        selectedFileName.value = file.name;
        selectedFilePath.value = optimizedPath;
        selectedFileType.value = 'image';
        selectedFileSize.value = await File(optimizedPath).length();
        selectedFileContent.value = null;
        selectedImagePath.value = optimizedPath;
        selectedImageBase64.value = null;
        _checkVisionSupport();
        return;
      }

      selectedFileName.value = file.name;
      selectedFilePath.value = file.path;
      selectedFileType.value = fileType;
      selectedFileSize.value = file.size;
      selectedFileContent.value = null;

      selectedImagePath.value = null;
      selectedImageBase64.value = null;

      if (fileType == 'pdf' || fileType == 'docx') {
        final path = file.path;
        if (path != null) {
          try {
            var content = await DocumentExtractorService.extractText(
              path,
              extension,
            );
            if (content.length > 12000) {
              content =
                  '${content.substring(0, 12000)}\n\n[File truncated for context size]';
            }
            selectedFileContent.value = content;
          } catch (e) {
            Get.find<AppLogService>().warning(
              'Document extraction failed',
              details: e,
              category: LogCategory.chat,
            );
            selectedFileContent.value = '[Could not extract text from ${selectedFileName.value}: $e]';
          }
        }
      } else if (fileType == 'text') {
        final bytes = file.bytes ??
            (file.path != null ? await File(file.path!).readAsBytes() : null);
        if (bytes == null) return;
        selectedFileSize.value = file.size > 0 ? file.size : bytes.length;
        var content = utf8.decode(bytes, allowMalformed: true);
        if (content.length > 12000) {
          content =
              '${content.substring(0, 12000)}\n\n[File truncated for context size]';
        }
        selectedFileContent.value = content;
      }
    } catch (e) {
      Get.find<AppLogService>().warning('File attachment failed', details: e, category: LogCategory.chat);
      Get.snackbar('File not attached', '$e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  void clearFile() {
    selectedFileName.value = null;
    selectedFileContent.value = null;
    selectedFilePath.value = null;
    selectedFileType.value = null;
    selectedFileSize.value = 0;
  }

  Future<String> _prepareVisionImagePath({
    required Uint8List bytes,
    required String originalName,
    String? fallbackPath,
  }) async {
    final resized = await compute(_resizeVisionImageBytes, {'bytes': bytes});
    if (resized == null) {
      if (fallbackPath != null && fallbackPath.isNotEmpty) return fallbackPath;
      final tempDir = await getTemporaryDirectory();
      final failedDecodeFile = File(
        '${tempDir.path}/ai_chat_image_${DateTime.now().millisecondsSinceEpoch}_$originalName',
      );
      await failedDecodeFile.writeAsBytes(bytes, flush: false);
      return failedDecodeFile.path;
    }

    if (resized.length == bytes.length &&
        fallbackPath != null &&
        fallbackPath.isNotEmpty) {
      return fallbackPath;
    }

    final tempDir = await getTemporaryDirectory();
    final file = File(
      '${tempDir.path}/ai_chat_vision_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(resized, flush: false);
    return file.path;
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

    // Create a session if none selected
    if (currentSessionId.value.isEmpty) {
      createNewChat();
    }

    // Encode image to base64 for cloud API (transient, not persisted).
    // base64 over MBs of pixels runs on a worker, not the UI thread.
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

    // Add user message — store file path, not base64 (prevents Hive bloat)
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

    // Clear input preview
    textController.clear();
    inputText.value = '';
    clearImage(deleteFile: false);
    clearFile();
    _scrollToBottom(force: true);

    // Update session title
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

    // Generate AI Response
    await _generateAIResponse(
      prompt: effectiveText,
      imagePath: imagePath,
      imgBase64: imgBase64,
      fileType: fileType,
      filePath: filePath,
    );
  }

  /// History char budget ≈ 60% of the context window at ~4 chars/token,
  /// leaving room for the system prompt, current turn and the response.
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

  /// Keeps the newest message (current turn) plus as many older turns as
  /// fit [maxChars]. Pure logic lives in `lib/utils/history_budget.dart`
  /// (unit-tested); this delegates so all call sites share semantics.
  List<Map<String, String>> _fitHistoryToBudget(
          List<Map<String, String>> history, int maxChars) =>
      fitHistoryToBudget(history, maxChars);

  Future<void> _generateAIResponse({
    required String prompt,
    String? imagePath,
    String? imgBase64,
    String? fileType,
    String? filePath,
    int? insertAt, // Optional index to insert assistant message
  }) async {
    final generationId = ++_generationSerial;
    isLoading.value = true;
    isStreaming.value = true;
    streamingAttachmentType.value =
        (imagePath != null || fileType == 'audio') ? fileType : null;
    streamingResponse.value = '';
    generationStartTime.value = DateTime.now();
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
    final tokenBuf = StringBuffer();
    Timer? tokenFlushTimer;
    // Adaptive flush: fast generators batch at ~3fps, slow ones stay at
    // ~7fps so first tokens still appear instantly.
    var flushMs = 150;

    try {
      DateTime? thoughtStartedAt;
      int? thoughtDurationSeconds;

      void trackThoughtTiming() {
        final parts = splitThoughtTags(streamingResponse.value);
        if (parts.hasThought && parts.isThinking && thoughtStartedAt == null) {
          thoughtStartedAt = DateTime.now();
        }
        if (parts.hasThought &&
            !parts.isThinking &&
            thoughtStartedAt != null &&
            thoughtDurationSeconds == null) {
          thoughtDurationSeconds =
              DateTime.now().difference(thoughtStartedAt!).inSeconds;
        }
      }

      void flushTokens() {
        if (tokenBuf.isNotEmpty) {
          // Adapt BEFORE clearing: big batches mean a fast engine that
          // would otherwise spam rebuilds.
          flushMs = tokenBuf.length > 200 ? 300 : 150;
          streamingResponse.value += tokenBuf.toString();
          tokenBuf.clear();
          trackThoughtTiming();
          _scrollToBottom();
        }
      }

      void bufferToken(String t) {
        tokenBuf.write(t);
        // Coalesce flushes: 40ms rebuilt the entire list per flush.
        tokenFlushTimer ??= Timer(Duration(milliseconds: flushMs), () {
          flushTokens();
          tokenFlushTimer = null;
        });
      }

      final inferenceMode = _hive.getSetting(
            AppConstants.keyInferenceMode,
            defaultValue: 'local',
          ) ??
          'local';

      String rawResponse;

      // Build conversation history from storage, not the UI window: the
      // visible list is paged (newest 100) and must not truncate model
      // context. Cap at recent turns — engines slice to ≤16 anyway.
      // Maps built straight from raw rows (same strings fromMap would
      // parse — no round-trip needed for role/content).
      final storedForHistory = _hive.getMessagesForChatPaged(
        currentSessionId.value,
        limit: 40,
      );
      var history = storedForHistory.map((m) {
        final role = m['role']?.toString() ?? '';
        var content = m['content']?.toString() ?? '';
        if (role == 'assistant') {
          content = splitThoughtTags(content).answer;
        }
        return {'role': role, 'content': content};
      }).where((e) => e['role'] == 'user' || e['role'] == 'assistant').toList();

      // Fallback: if storage came back empty but the UI holds turns
      // (write/query race or store hiccup), build from the visible list
      // so the model never loses context silently.
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

      // Token-budget trim: local models run on a small context window
      // (≈4 chars/token, 60% reserved for history) so a long code answer
      // must not overflow it and wipe context. Cloud models get a large
      // budget (their windows are 32k+). Oversized turns are
      // middle-truncated, never fully dropped.
      final preTrimTurns = history.length;
      final historyBudget = inferenceMode == 'local'
          ? _historyCharBudget()
          : 48000;
      history = _fitHistoryToBudget(history, historyBudget);

      // Observability: what context the model actually receives (roles +
      // sizes only, never content).
      try {
        final chars = history.fold<int>(
            0, (s, m) => s + (m['content'] ?? '').length);
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

      // Skill relevance — only inject skills relevant to this prompt.
      final settingsForPrompt = Get.find<SettingsController>();
      final modelNameForPrompt = inferenceMode == 'local'
          ? Get.find<InferenceService>().loadedModelName.value
          : settingsForPrompt.selectedCloudModelName;
      final relevantSkills = SkillInjector.selectRelevantSkills(prompt);
      final List<String> usedSkillNames =
          relevantSkills.map((s) => s.name).toList();
      var basePrompt =
          settingsForPrompt.baseSystemPromptForModel(modelNameForPrompt);
      // Per-chat persona overrides tone per conversation (empty = global).
      final persona = currentPersona;
      if (persona.isNotEmpty) {
        basePrompt = '$basePrompt\n\n[Chat persona]\n$persona';
      }
      final String systemPromptForThisTurn = relevantSkills.isEmpty
          ? basePrompt
          : '$basePrompt${SkillInjector.buildForSkills(relevantSkills)}';

      // Web access — fetch readable text for any URLs in the prompt so
      // the model can reason over real page content.
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

      if (inferenceMode == 'local') {
        final localImage = Get.find<LocalImageService>();

        if (localImage.isModelLoaded.value &&
            _isImageGenerationPrompt(prompt)) {
          // Local image generation — only when prompt explicitly asks for image creation
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
                  final elapsed = DateTime.now().difference(start).inMilliseconds;
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
          
          final genDurationMs = imageGenStartTime.value != null
              ? DateTime.now().difference(imageGenStartTime.value!).inMilliseconds
              : null;

          if (pngBytes != null) {
            await imageNotifications.complete(durationMs: genDurationMs ?? 0);
            rawResponse =
                '[IMAGE_BASE64]${await compute(base64Encode, pngBytes)}';
          } else {
            await imageNotifications.failed();
            rawResponse = '❌ Local image generation failed.';
          }
        } else {
          final inference = Get.find<InferenceService>();
          rawResponse = await inference.generate(
            prompt: prompt,
            systemPrompt: systemPromptForThisTurn,
            conversationHistory: history,
            source: 'chat',
            imagePath: imagePath,
            audioPath: fileType == 'audio' ? filePath : null,
            onToken: bufferToken,
          );
          flushTokens();
          tokenFlushTimer?.cancel();
        }
      } else {
        final cloud = Get.find<CloudService>();
        final settings = Get.find<SettingsController>();
        final apiMessages = [
          {'role': 'system', 'content': systemPromptForThisTurn},
          ...history,
        ];
        rawResponse = await cloud.sendMessage(
          messages: apiMessages,
          imageBase64: imgBase64,
          temperature: settings.temperature.value,
          // Auto Tune: no output cap — let the model use its full native
          // budget so long, detailed answers are never truncated.
          maxTokens: settings.autoTuneParams.value
              ? null
              : settings.maxTokens.value,
          onToken: bufferToken,
        );
          flushTokens();
          tokenFlushTimer?.cancel();
      }

      if (thoughtStartedAt != null && thoughtDurationSeconds == null) {
        thoughtDurationSeconds =
            DateTime.now().difference(thoughtStartedAt!).inSeconds;
      }

      if (generationId != _generationSerial) {
        tokenFlushTimer?.cancel();
        tokenBuf.clear();
        return;
      }

      final tps = inferenceMode == 'local'
          ? Get.find<InferenceService>().tokensPerSecond.value
          : null;
      
      final totalDurationMs = generationStartTime.value != null
          ? DateTime.now().difference(generationStartTime.value!).inMilliseconds
          : null;
      
      final imageDurationMs = imageGenStartTime.value != null
          ? DateTime.now().difference(imageGenStartTime.value!).inMilliseconds
          : null;

      _generationTimer?.cancel();
      _generationTimer = null;
      tokenFlushTimer?.cancel();
      tokenBuf.clear();
      isStreaming.value = false;
      streamingAttachmentType.value = null;
      streamingResponse.value = '';
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

      final aiMsg = ChatMessage(
        id: aiMsgId,
        chatId: currentSessionId.value,
        role: 'assistant',
        content: rawResponse,
        imageBase64: outImageBase64,
        imagePath: outImagePath,
        tokensPerSec: tps,
        thoughtDurationSeconds: thoughtDurationSeconds,
        imageGenDurationMs: imageDurationMs,
        generationDurationMs: totalDurationMs,
        webSources: webSources.isEmpty ? null : webSources,
        usedSkills: usedSkillNames.isEmpty ? null : usedSkillNames,
      );
      
      if (insertAt != null && insertAt >= 0 && insertAt <= messages.length) {
        messages.insert(insertAt, aiMsg);
      } else {
        messages.add(aiMsg);
      }
      _hive.saveMessage(aiMsg.id, aiMsg.toMap());
      imageGenStartTime.value = null;

      final session =
          sessions.firstWhereOrNull((s) => s.id == currentSessionId.value);
      if (session != null) {
        final updated = session.copyWith(lastMessage: aiMsg.content);
        _hive.saveSession(updated.id, updated.toMap());
        final idx = sessions.indexWhere((s) => s.id == updated.id);
        if (idx >= 0) sessions[idx] = updated;
      }
      unawaited(HapticFeedback.mediumImpact());
      // Background ping: the answer finished while the app is
      // backgrounded — notify so the user knows to come back.
      try {
        final st = WidgetsBinding.instance.lifecycleState;
        if (st == AppLifecycleState.paused ||
            st == AppLifecycleState.hidden ||
            st == AppLifecycleState.inactive) {
          final answerPreview =
              splitThoughtTags(rawResponse).answer.trim();
          unawaited(Get.find<ImageGenerationNotificationService>()
              .notifyChatDone(answerPreview.isNotEmpty
                  ? answerPreview
                  : rawResponse));
        }
      } catch (_) {}
      // One-shot compare: challenger answers the same prompt, then the
      // primary setup is restored. Skipped for image generations.
      if (_compareRef != null && outImageBase64 == null) {
        await _runComparison(
          prompt: prompt,
          systemPrompt: systemPromptForThisTurn,
          history: history,
        );
      }
    } catch (e) {
      if (generationId != _generationSerial) {
        tokenFlushTimer?.cancel();
        tokenBuf.clear();
        return;
      }
      tokenFlushTimer?.cancel();
      tokenBuf.clear();
      isStreaming.value = false;
      streamingAttachmentType.value = null;
      streamingResponse.value = '';
      imageGenStep.value = 0;
      imageGenTotal.value = 0;
      imageGenDecoding.value = false;
      if (imageGenStartTime.value != null) {
        await Get.find<ImageGenerationNotificationService>().failed();
      }
      imageGenStartTime.value = null;
      Get.find<AppLogService>().error('Chat response failed', details: e, category: LogCategory.chat);
      final errorMsg = ChatMessage(
        id: _uuid.v4(),
        chatId: currentSessionId.value,
        role: 'assistant',
        content: _friendlyGenerationError(e),
      );
      messages.add(errorMsg);
      _hive.saveMessage(errorMsg.id, errorMsg.toMap());
      unawaited(HapticFeedback.heavyImpact());
    }

    if (generationId == _generationSerial) {
      isLoading.value = false;
      _scrollToBottom();
    }
  }

  void stopGenerating() {
    if (!isLoading.value && !isStreaming.value) return;
    // Hands-free: user-stopped turns stay quiet (no auto-speak/listen).
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

  // ─── Prompt templates ─────────────────────────

  static const _kTemplatesKey = 'prompt_templates_v1';
  final promptTemplates = <Map<String, String>>[].obs;
  bool _templatesLoaded = false;

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

  void ensureTemplatesLoaded() {
    if (_templatesLoaded) return;
    _templatesLoaded = true;
    try {
      final raw = _hive.getSetting<String>(_kTemplatesKey);
      if (raw == null || raw.isEmpty) {
        promptTemplates.assignAll(_defaultTemplates());
        unawaited(_hive.setSetting(_kTemplatesKey, jsonEncode(promptTemplates)));
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
        promptTemplates.assignAll(
            list.isEmpty ? _defaultTemplates() : list);
      }
    } catch (_) {
      promptTemplates.assignAll(_defaultTemplates());
    }
  }

  /// Insert a template into the composer (appends, keeps existing text).
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
    await _hive.setSetting(_kTemplatesKey, jsonEncode(promptTemplates.toList()));
  }

  Future<void> deletePromptTemplate(String id) async {
    ensureTemplatesLoaded();
    promptTemplates
        .removeWhere((t) => t['id'] == id && (t['builtin'] ?? '').isEmpty);
    await _hive.setSetting(_kTemplatesKey, jsonEncode(promptTemplates.toList()));
  }

  // ─── Multi-select (bulk copy/share/delete) ────

  final selectionMode = false.obs;
  final selectedIds = <String>{}.obs;

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

  /// Selected turns as markdown (for copy/share).
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

  // ─── Per-chat model pin ─────────────────────────

  /// True when the open chat overrides the global inference mode/model.
  bool get chatHasModelPin {
    final sid = currentSessionId.value;
    if (sid.isEmpty) return false;
    final s = sessions.firstWhereOrNull((e) => e.id == sid);
    return s != null && s.modelMode.isNotEmpty;
  }

  /// Short label of the pinned model for the header pill ('' = none).
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

  /// Capture the CURRENT global mode+model into the open chat.
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

  /// Forget the override — the chat follows the global mode again.
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

  /// Apply the session's pinned model after opening it. Never throws —
  /// a missing local file just warns and keeps the global setup.
  Future<void> _applySessionModel(ChatSession s) async {
    if (s.modelMode.isEmpty) return;
    try {
      final settings = Get.find<SettingsController>();
      if (s.modelMode == 'cloud') {
        final cmc = Get.find<CloudModelController>();
        if (s.modelProvider == 'custom') {
          final idx =
              int.tryParse(s.modelId.replaceFirst('custom-profile:', '')) ??
                  0;
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

  // ─── Side-by-side compare ─────────────────────────

  /// Challenger for the NEXT send only: {mode, provider, model}.
  /// Cleared after the comparison runs (one-shot, never sticky).
  Map<String, String>? _compareRef;
  final compareLabel = ''.obs;

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

  /// Run the challenger on the same prompt+history AFTER the primary
  /// answer is saved. Always restores the primary setup in finally so
  /// the user's active model never silently changes.
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
    // Capture primary BEFORE any switch.
    final primaryMode = settings.inferenceMode.value;
    final primaryProvider = settings.cloudProvider.value;
    final primaryCloudModel = settings.selectedCloudModelName;
    final primaryCustomIdx = settings.customCloudProfileIndex.value;
    final primaryLocal = Get.find<InferenceService>().loadedModelName.value;
    final label = ref['mode'] == 'cloud'
        ? '${ref['provider']}: ${ref['model']}'
        : (ref['model'] ?? '')
            .replaceAll('.gguf', '')
            .replaceAll('.GGUF', '');
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
          maxTokens: settings.autoTuneParams.value
              ? null
              : settings.maxTokens.value,
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
      if (currentSessionId.value != chatId) return; // switched mid-compare
      final msg = ChatMessage(
        id: _uuid.v4(),
        chatId: chatId,
        role: 'assistant',
        content: '⚖️ $label\n\n${answer.trim()}',
      );
      messages.add(msg);
      _hive.saveMessage(msg.id, msg.toMap());
    } catch (e) {
      Get.find<AppLogService>().warning('Compare failed: $e',
          category: LogCategory.chat);
      Get.snackbar('Compare failed', e.toString(),
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      // Restore primary setup no matter what.
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

  /// Friendly error text for the chat bubble. Raw provider payloads
  /// (OpenRouter 429 walls, HTML error pages) are unreadable in-chat —
  /// the bubble gets the short version with a remedy, while the full
  /// details stay in System Logs → Chat (logged by the caller).
  String _friendlyGenerationError(Object e) {
    final s = e.toString();
    final lower = s.toLowerCase();
    final rateLimited = lower.contains('429') ||
        lower.contains('rate_limit') ||
        lower.contains('rate-limit') ||
        lower.contains('rate limited');
    if (rateLimited) {
      var wait = '';
      final m =
          RegExp(r'retry_after_seconds"?\s*:\s*(\d+)').firstMatch(s);
      if (m != null) wait = ' (~${m.group(1)}s)';
      return '⏳ The provider rate-limited this request$wait '
          '(free shared pool).\n\n• Wait a bit and retry\n'
          '• Or add your own API key: Explore → provider card → Add API Key';
    }
    if (lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection refused') ||
        lower.contains('network is unreachable') ||
        lower.contains('timed out') ||
        lower.contains('timeoutexception')) {
      return '🌐 Network error — check your connection and retry.';
    }
    if (s.length > 300) {
      return '❌ Error: ${s.substring(0, 300)}…\n'
          '(Full details in System Logs → Chat)';
    }
    return '❌ Error: $s';
  }

  // ─── Edit / Regenerate / Branch ─────────────────────────

  /// Edit a user message, saving the version history.
  void editMessage(ChatMessage msg, String newContent) {
    if (isLoading.value || isStreaming.value) return;
    if (msg.role != 'user') return;
    final idx = messages.indexWhere((m) => m.id == msg.id);
    if (idx < 0) return;

    // Safety: Clear main input to prevent accidental double-send from background
    textController.clear();
    inputText.value = '';

    // Grab current assistant reply if present
    String? currentAssistantResponse;
    if (idx + 1 < messages.length && messages[idx + 1].role == 'assistant') {
      currentAssistantResponse = messages[idx + 1].content;
    }

    // Initialize or copy revisions list
    final allRevisions = List<Map<String, dynamic>>.from(msg.revisions ?? []);
    
    // If this is the first edit, add the original version first
    if (allRevisions.isEmpty) {
      allRevisions.add({
        'content': msg.content,
        'response': currentAssistantResponse,
      });
    } else {
      // Update the 'current' revision in the list before adding a new one
      // because navigateRevision might have changed which one is 'active' in the UI
      allRevisions[msg.revisionIndex] = {
        'content': msg.content,
        'response': currentAssistantResponse,
      };
    }

    // Add the NEW version to the end of the list
    allRevisions.add({
      'content': newContent,
      'response': null, // Response will be generated
    });

    // Remove old assistant reply from UI and Hive (it will be replaced by new generation)
    if (idx + 1 < messages.length && messages[idx + 1].role == 'assistant') {
      _hive.deleteMessage(messages[idx + 1].id);
      messages.removeAt(idx + 1);
    }

    // Update user message to the new version
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

    // Generate new AI Response
    _generateAIResponse(
      prompt: newContent,
      imagePath: msg.imagePath,
      imgBase64: msg.imageBase64,
      fileType: msg.fileType,
      filePath: msg.filePath,
      insertAt: idx + 1, // Insert right after the edited user message
    );
  }

  /// Navigate between different versions of a message.
  void navigateRevision(ChatMessage msg, int direction) {
    final revisions = msg.revisions;
    if (revisions == null || revisions.isEmpty) return;

    final targetIdx = msg.revisionIndex + direction;
    if (targetIdx < 0 || targetIdx >= revisions.length) return;

    var msgIdx = messages.indexWhere((m) => m.id == msg.id);
    if (msgIdx < 0) return;
    // Window edge: the true adjacent reply may sit in an unloaded page.
    // Pull older history first so messages[msgIdx + 1] is really the reply.
    if (msgIdx == 0 && hasOlderMessages.value) {
      // Best-effort sync load (cheap: one page from Hive).
      unawaited(loadOlderMessages().then((_) {
        navigateRevision(msg, direction);
      }));
      return;
    }

    // Current assistant response (if any) should be saved back to the current revision
    String? currentResponse;
    if (msgIdx + 1 < messages.length && messages[msgIdx + 1].role == 'assistant') {
      currentResponse = messages[msgIdx + 1].content;
    }
    
    final updatedRevisions = List<Map<String, dynamic>>.from(revisions);
    updatedRevisions[msg.revisionIndex] = {
      'content': msg.content,
      'response': currentResponse,
    };

    // Get the target version
    final targetRevision = updatedRevisions[targetIdx];
    final targetContent = targetRevision['content'] as String;
    final targetResponse = targetRevision['response'] as String?;

    // Update the user message in UI and Hive
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

    // Update or remove the assistant reply
    if (msgIdx + 1 < messages.length && messages[msgIdx + 1].role == 'assistant') {
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
        // This version has no response yet? (Shouldn't happen with current logic, but safe to handle)
        _hive.deleteMessage(messages[msgIdx + 1].id);
        messages.removeAt(msgIdx + 1);
      }
    } else if (targetResponse != null) {
      // If assistant message was missing but we have a response in history, re-add it
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
    // Window edge: the preceding user message may sit in an unloaded
    // page — load it first instead of regenerating against nothing.
    if (idx == 0 && hasOlderMessages.value) {
      unawaited(loadOlderMessages().then((_) {
        regenerateFromMessage(msg);
      }));
      return;
    }

    final userMsg = idx > 0 ? messages[idx - 1] : null;
    if (userMsg == null || userMsg.role != 'user') return;

    // Safety: Clear main input
    textController.clear();
    inputText.value = '';

    // Remove the old assistant message
    _hive.deleteMessage(msg.id);
    messages.removeAt(idx);

    _scrollToBottom(force: true);

    // Trigger AI response without adding a new user message
    _generateAIResponse(
      prompt: userMsg.content,
      imagePath: userMsg.imagePath,
      imgBase64: userMsg.imageBase64,
      fileType: userMsg.fileType,
      filePath: userMsg.filePath,
      insertAt: idx, // Insert where the old assistant message was
    );
  }

  void branchNewChat(ChatMessage msg) {
    if (isLoading.value || isStreaming.value) return;
    final idx = messages.indexWhere((m) => m.id == msg.id);
    if (idx < 0) return;

    // Capture history from storage, not the UI window: the visible list
    // is paged and a windowed sublist would silently drop older context
    // from the branch.
    final stored = _hive.getMessagesForChat(msg.chatId);
    final cutoff = msg.timestamp;
    final historyToCopy = stored
        .map((m) => ChatMessage.fromMap(m))
        .toList()
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
    // Don't strand the user on an empty window while older pages exist.
    if (messages.isEmpty && hasOlderMessages.value) {
      unawaited(loadOlderMessages());
    }
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
    
    // Show button if we are more than 200px away from bottom
    showScrollToBottom.value = distanceFromBottom > 200;

    // Paged history: near the top edge, pull the next older page.
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

    _scrollTimer = Timer(const Duration(milliseconds: 80), () {
      if (!scrollController.hasClients) return;
      if (!force && isStreaming.value && !_followStreaming) return;
      final target = scrollController.position.maxScrollExtent;
      if ((target - scrollController.position.pixels).abs() < 8) return;
      scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
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
      final validExt = {
        'jpg',
        'jpeg',
        'png',
        'webp',
        'gif',
        'heic'
      }.contains(ext)
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
      'txt',
      'md',
      'json',
      'csv',
      'log',
      'yaml',
      'yml',
      'xml',
      'dart',
      'kt',
      'java',
      'js',
      'ts',
      'py',
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
    // Explicit prefixes always mean image generation.
    if (lower.startsWith('/image') ||
        lower.startsWith('/img') ||
        lower.startsWith('/draw') ||
        lower.startsWith('/generate image')) {
      return true;
    }
    const triggers = [
      'generate image',
      'create image',
      'make image',
      'generate a image',
      'create a picture',
      'generate a picture',
      'make a picture',
      'generate photo',
      'create photo',
      'draw a',
      'draw an',
      'painting of',
      'illustration of',
      'render image',
      'generate picture',
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
    // Also catch simple "draw X" without article.
    if (lower.contains('draw ')) return true;
    return false;
  }
}
