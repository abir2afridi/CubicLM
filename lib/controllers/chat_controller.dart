import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:uuid/uuid.dart';
import '../controllers/settings_controller.dart';
import '../core/constants.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../ffi/sd_ffi_bindings.dart';
import '../services/hive_service.dart';
import '../services/web_fetch_service.dart';
import '../services/inference_service.dart';
import '../services/cloud_service.dart';
import '../services/local_image_service.dart';
import '../services/app_log_service.dart';
import '../services/image_generation_notification_service.dart';
import '../services/document_extractor_service.dart';
import '../utils/thought_parser.dart';

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

  final textController = TextEditingController();
  final scrollController = ScrollController();
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
      if (!sttAvailable.value) {
        try {
          final ok = await _speech.initialize();
          sttAvailable.value = ok;
        } catch (_) {
          sttAvailable.value = false;
        }
        if (!sttAvailable.value) return;
      }
      await _speech.listen(
        onResult: (result) {
          textController.text = result.recognizedWords;
          inputText.value = result.recognizedWords;
        },
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 4),
        localeId: 'en_US',
      );
      isListening.value = true;
    } catch (_) {
      isListening.value = false;
    }
  }

  @override
  void onClose() {
    _scrollTimer?.cancel();
    if (_scrollListenerAttached) {
      scrollController.removeListener(_handleUserScroll);
    }
    textController.dispose();
    scrollController.dispose();
    super.onClose();
  }

  // ─── Session Management ─────────────────────────

  void loadSessions() {
    final raw = _hive.getAllSessions();
    sessions.value = raw.map((m) => ChatSession.fromMap(m)).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  void createNewChat() {
    final id = _uuid.v4();
    final session = ChatSession(id: id, title: 'New Chat');
    _hive.saveSession(id, session.toMap());
    sessions.insert(0, session);
    openChat(id);
  }

  void _resetInferenceContext() {
    final inference = Get.find<InferenceService>();
    if (inference.isModelLoaded.value) {
      unawaited(inference.resetConversation());
    }
  }

  void openChat(String sessionId) {
    stopGenerating();
    currentSessionId.value = sessionId;
    final raw = _hive.getMessagesForChat(sessionId);
    messages.value = raw.map((m) => ChatMessage.fromMap(m)).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final inference = Get.find<InferenceService>();
    if (inference.isModelLoaded.value) {
      inference.refreshContextInfo();
    }
    _resetInferenceContext();
    _scrollToBottom(force: true);
  }

  void deleteChat(String sessionId) {
    if (currentSessionId.value == sessionId && isLoading.value) {
      stopGenerating();
    }
    _hive.deleteSession(sessionId);
    sessions.removeWhere((s) => s.id == sessionId);
    if (currentSessionId.value == sessionId) {
      currentSessionId.value = '';
      messages.clear();
    }
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

  // ─── Image Handling ─────────────────────────────

  Future<void> pickImage() async {
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
  }

  Future<void> takePhoto() async {
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
    if (s.inferenceMode.value != 'cloud') return;
    
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

    // Encode image to base64 if it's not already pre-encoded
    String? imgBase64 = imageBase64;
    if (imgBase64 == null && imagePath != null && !kIsWeb) {
      try {
        imgBase64 = base64Encode(await File(imagePath).readAsBytes());
      } catch (_) {}
    }

    // Add user message
    final userMsg = ChatMessage(
      id: _uuid.v4(),
      chatId: currentSessionId.value,
      role: 'user',
      content: effectiveText,
      imageBase64: imgBase64,
      imagePath: imagePath,
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

      final inferenceMode = _hive.getSetting(
            AppConstants.keyInferenceMode,
            defaultValue: 'local',
          ) ??
          'local';

      String rawResponse;

      // Build conversation history
      final history = messages
          .where((m) => m.role == 'user' || m.role == 'assistant')
          .map((m) => {
                'role': m.role,
                'content': m.role == 'assistant'
                    ? splitThoughtTags(m.content).answer
                    : m.content,
              })
          .toList();

      // Web access — fetch readable text for any URLs in the prompt so
      // the model can reason over real page content.
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
          final augmented = await WebFetchService.augmentWithWebContent(prompt);
          if (augmented != prompt) {
            prompt = augmented;
            if (history.isNotEmpty && history.last['role'] == 'user') {
              history[history.length - 1] = {
                'role': 'user',
                'content': augmented,
              };
            }
          }
        }
      } catch (_) {}

      if (inferenceMode == 'local') {
        final localImage = Get.find<LocalImageService>();

        if (localImage.isModelLoaded.value) {
          // Local image generation
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
            rawResponse = '[IMAGE_BASE64]${base64Encode(pngBytes)}';
          } else {
            await imageNotifications.failed();
            rawResponse = '❌ Local image generation failed.';
          }
        } else {
          final inference = Get.find<InferenceService>();
          rawResponse = await inference.generate(
            prompt: prompt,
            systemPrompt: _effectiveSystemPrompt,
            conversationHistory: history,
            source: 'chat',
            imagePath: imagePath,
            audioPath: fileType == 'audio' ? filePath : null,
            onToken: (token) {
              streamingResponse.value += token;
              trackThoughtTiming();
              _scrollToBottom();
            },
          );
        }
      } else {
        final cloud = Get.find<CloudService>();
        final settings = Get.find<SettingsController>();
        final apiMessages = [
          {'role': 'system', 'content': _effectiveSystemPrompt},
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
          onToken: (token) {
            streamingResponse.value += token;
            trackThoughtTiming();
            _scrollToBottom();
          },
        );
      }

      if (thoughtStartedAt != null && thoughtDurationSeconds == null) {
        thoughtDurationSeconds =
            DateTime.now().difference(thoughtStartedAt!).inSeconds;
      }

      if (generationId != _generationSerial) return;

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
      isStreaming.value = false;
      streamingAttachmentType.value = null;
      streamingResponse.value = '';
      generationStartTime.value = null;
      generationLiveDurationSecs.value = 0;
      imageGenStep.value = 0;
      imageGenTotal.value = 0;
      imageGenDecoding.value = false;

      String? outImageBase64;
      if (rawResponse.startsWith('[IMAGE_BASE64]')) {
        outImageBase64 = rawResponse.substring('[IMAGE_BASE64]'.length);
        rawResponse = 'Here is your generated image:';
      }

      final aiMsg = ChatMessage(
        id: _uuid.v4(),
        chatId: currentSessionId.value,
        role: 'assistant',
        content: rawResponse,
        imageBase64: outImageBase64,
        tokensPerSec: tps,
        thoughtDurationSeconds: thoughtDurationSeconds,
        imageGenDurationMs: imageDurationMs,
        generationDurationMs: totalDurationMs,
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
    } catch (e) {
      if (generationId != _generationSerial) return;
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
        content: '❌ Error: $e',
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

    final msgIdx = messages.indexWhere((m) => m.id == msg.id);
    if (msgIdx < 0) return;

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
    final idx = messages.indexWhere((m) => m.id == msg.id);
    if (idx < 0) return;

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

    // Capture history BEFORE creating new chat and clearing 'messages'
    final historyToCopy = messages.sublist(0, idx).where(
      (m) => m.role == 'user' || m.role == 'assistant',
    ).toList();

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

  String get _effectiveSystemPrompt {
    final settings = Get.find<SettingsController>();
    final inference = Get.find<InferenceService>();
    final modelName = settings.inferenceMode.value == 'local'
        ? inference.loadedModelName.value
        : settings.selectedCloudModelName;
    return settings.effectiveSystemPromptForModel(
      modelName,
    );
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
}
