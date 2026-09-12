import 'dart:async';
import 'dart:io' show Platform, Directory, File;

import 'package:flutter_litert_lm/flutter_litert_lm.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import 'app_log_service.dart';
import 'inference_text.dart';
import 'inference_types.dart';

/// LiteRT-LM inference engine - owns the LiteRT session lifecycle:
/// load, generate (text + multimodal), conversation reset. GGUF lives
/// in inference_gguf.dart; the two engines share no mutable state.

class LiteRtEngine {
  LiteLmEngine? _liteEngine;
  LiteLmConversation? _liteConversation;
  StreamSubscription? _subscription;
  Timer? _idleTimer;
  void Function()? _onStop;
  bool _disposed = false;
  String? _liteConversationSystemPrompt;
  double? _liteConversationTemperature;
  double? _liteConversationTopP;
  int? _liteConversationTopK;
  bool _liteConversationHasMessages = false;

  /// Load a .litertlm model (CPU/GPU backend, vision optional).
  Future<LoadResult> loadModel({
    required String modelPath,
    required int contextSize,
    String performanceMode = 'auto_fast',
    bool forceCpu = false,
    bool clearCache = false,
    bool enableVision = false,
    void Function(double)? onProgress,
  }) async {
    _disposed = false;
    if (!Platform.isAndroid) {
      throw UnsupportedError(
          'LiteRT-LM is enabled for Android only in this app.');
    }


    final tempDir = await getTemporaryDirectory();
    final cacheDir = Directory('${tempDir.path}/litert_cache');
    final backend = forceCpu || performanceMode == 'cpu_safe'
        ? LiteLmBackend.cpu
        : LiteLmBackend.gpu;
    final backendLabel = backend == LiteLmBackend.gpu ? 'GPU' : 'CPU';

    try {
      onProgress?.call(0.05);
      if (clearCache && await cacheDir.exists()) {
        try {
          await cacheDir.delete(recursive: true);
        } catch (_) {}
      }
      await cacheDir.create(recursive: true);
      onProgress?.call(0.18);

      _liteEngine = await _createLiteRtEngine(
        modelPath: modelPath,
        contextSize: contextSize,
        cacheDir: cacheDir.path,
        backend: backend,
        enableVision: enableVision,
      );
      onProgress?.call(0.92);
      print(
          '[Inference] LiteRT-LM loaded with $backendLabel backend, ctx=$contextSize');
      return LoadResult(
        success: true,
        message: 'LiteRT-LM model loaded ($backendLabel backend).',
        gpuName: backend == LiteLmBackend.gpu ? 'LiteRT GPU' : '',
        gpuLayers: backend == LiteLmBackend.gpu ? 1 : 0,
        runtime: 'litert',
        backend: backend.name,
      );
    } catch (error) {
      print('[Inference] LiteRT-LM load failed: $error');
      final errorStr = error.toString();
      if (errorStr.contains('TF_LITE_VISION_ENCODER')) {
        return LoadResult(
          success: false,
          message:
              'This LiteRT-LM file is text-only, but it was loaded as a vision model. Turn off Vision for this model or re-import it as a normal chat model.',
        );
      }
      if (enableVision && errorStr.contains('exactly one signature but got')) {
        print(
            '[Inference] Vision encoder signature mismatch. Falling back to text-only mode.');
        try {
          _liteEngine = await _createLiteRtEngine(
            modelPath: modelPath,
            contextSize: contextSize,
            cacheDir: cacheDir.path,
            backend: backend,
            enableVision: false,
          );
          onProgress?.call(0.92);
          return LoadResult(
            success: true,
            message:
                'Model loaded in text-only mode. Its vision features are incompatible with the LiteRT engine (expected 1 signature, found multiple).',
            gpuName: backend == LiteLmBackend.gpu ? 'LiteRT GPU' : '',
            gpuLayers: backend == LiteLmBackend.gpu ? 1 : 0,
            runtime: 'litert',
            backend: backend.name,
          );
        } catch (fallbackError) {
          print('[Inference] LiteRT-LM fallback load failed: $fallbackError');
          return LoadResult(
            success: false,
            message: 'LiteRT load failed: $fallbackError',
          );
        }
      }
      if (errorStr.contains('exactly one signature but got')) {
        return LoadResult(
          success: false,
          message:
              'This vision model is incompatible with the LiteRT engine (expected 1 signature, found multiple). Please try a standard GGUF model or a text-only LiteRT model instead.',
        );
      }
      rethrow;
    }
  }

  Future<LiteLmEngine> _createLiteRtEngine({
    required String modelPath,
    required int contextSize,
    required String cacheDir,
    required LiteLmBackend backend,
    required bool enableVision,
  }) {
    return LiteLmEngine.create(
      LiteLmEngineConfig(
        modelPath: modelPath,
        backend: backend,
        cacheDir: cacheDir,
        visionBackend: enableVision ? LiteLmBackend.cpu : null,
        audioBackend: null,
        maxNumTokens: contextSize,
      ),
    );
  }

  /// Generate a reply (text or multimodal).
  Future<String> generate({
    required String prompt,
    List<Map<String, String>>? conversationHistory,
    required String systemPrompt,
    required int maxTokens,
    required double temperature,
    double? topP,
    int? topK,
    String? imagePath,
    String? audioPath,
    void Function(String token)? onToken,
  }) async {
    return _generateLiteRt(
      prompt: prompt,
      conversationHistory: conversationHistory,
      systemPrompt: systemPrompt,
      maxTokens: maxTokens,
      temperature: temperature,
      topP: topP ?? 0.95,
      topK: topK ?? 64,
      imagePath: imagePath,
      audioPath: audioPath,
      onToken: onToken,
    );
  }

  Future<String> _generateLiteRt({
    required String prompt,
    List<Map<String, String>>? conversationHistory,
    required String systemPrompt,
    required int maxTokens,
    required double temperature,
    double topP = 0.95,
    int topK = 64,
    String? imagePath,
    String? audioPath,
    void Function(String token)? onToken,
  }) async {
    if (_liteEngine == null) throw Exception('No LiteRT-LM model loaded');

    await _subscription?.cancel();
    await _ensureLiteRtConversation(
      prompt: prompt,
      conversationHistory: conversationHistory,
      systemPrompt: systemPrompt,
      temperature: temperature,
      topP: topP,
      topK: topK,
    );

    final completer = Completer<String>();
    final buffer = StringBuffer();
    bool completed = false;
    bool hasVisibleOutput = false;
    var tokenCount = 0;
    // One fresh-conversation retry for executor invoke failures
    // (mirrors the GGUF hard-reload philosophy).
    bool retried = false;

    void finish(String result) {
      if (!completed && !_disposed) {
        completed = true;
        _idleTimer?.cancel();
        _subscription?.cancel();
        _onStop = null;
        if (!completer.isCompleted) completer.complete(result);
      }
    }

    _onStop = () => finish(buffer.toString());

    if ((imagePath != null && imagePath.isNotEmpty) ||
        (audioPath != null && audioPath.isNotEmpty)) {
      // A missing/empty attachment fails natively with an opaque
      // "failed to invoke" — catch it here with a clear message.
      for (final p in [imagePath, audioPath]) {
        if (p == null || p.isEmpty) continue;
        var ok = false;
        try {
          final f = File(p);
          ok = f.existsSync() && f.lengthSync() > 0;
        } catch (_) {}
        if (!ok) {
          return 'ERROR: Attached file is missing or empty ($p). Re-attach it and try again.';
        }
      }
      final contents = <LiteLmContent>[
        LiteLmContent.text(prompt),
        if (imagePath != null && imagePath.isNotEmpty)
          LiteLmContent.imageFile(imagePath),
        if (audioPath != null && audioPath.isNotEmpty)
          LiteLmContent.audioFile(audioPath),
      ];

      _subscription =
          _liteConversation!.sendMultimodalMessageStream(contents).listen(
        (delta) {
          var text = _cleanLiteRtChunk(delta.text);
          if (text.isEmpty) return;

          if (!hasVisibleOutput) {
            if (!hasPrintableText(text)) return;
            text = text.trimLeft();
            hasVisibleOutput = true;
          }

          if (tokenCount == 0) {
            print('[Inference] LiteRT-LM multimodal FIRST TOKEN received');
          }
          _liteConversationHasMessages = true;
          tokenCount++;
          buffer.write(text);
          onToken?.call(text);
          _idleTimer?.cancel();
          _idleTimer = Timer(const Duration(seconds: 8), () {
            print(
                '[Inference] LiteRT-LM multimodal idle timeout - $tokenCount chunks');
            finish(buffer.toString());
          });
        },
        onDone: () {
          _liteConversationHasMessages = true;
          print(
              '[Inference] LiteRT-LM multimodal stream done - $tokenCount chunks');
          finish(buffer.toString());
        },
        onError: (error) async {
          _logLiteRtError('LiteRT-LM multimodal stream error', error);
          final msg = error.toString();
          if (!retried && isInvokeFailure(msg)) {
            retried = true;
            try {
              await resetConversation();
            } catch (_) {}
            print(
                '[Inference] LiteRT-LM invoke failed — fresh conversation retry.');
            finish(await _generateLiteRt(
              prompt: prompt,
              conversationHistory: conversationHistory,
              systemPrompt: systemPrompt,
              maxTokens: maxTokens,
              temperature: temperature,
              topP: topP,
              topK: topK,
              imagePath: imagePath,
              audioPath: audioPath,
              onToken: onToken,
            ));
            return;
          }
          finish(_friendlyInvokeError(msg, multimodal: true));
        },
      );

      _idleTimer = Timer(const Duration(seconds: 90), () {
        if (tokenCount == 0) {
          finish('ERROR: LiteRT-LM multimodal model did not respond.');
        }
      });

      Future.delayed(const Duration(seconds: 240), () {
        if (!completed) {
          final partial = buffer.toString();
          finish(partial.isEmpty
              ? 'ERROR: LiteRT-LM multimodal generation timed out.'
              : partial);
        }
      });

      return completer.future;
    }

    _subscription = _liteConversation!.sendMessageStream(prompt).listen(
      (delta) {
        var text = _cleanLiteRtChunk(delta.text);
        if (text.isEmpty) return;

        if (!hasVisibleOutput) {
          if (!hasPrintableText(text)) return;
          text = text.trimLeft();
          hasVisibleOutput = true;
        }

        if (tokenCount == 0) {
          print('[Inference] LiteRT-LM FIRST TOKEN received');
        }
        _liteConversationHasMessages = true;
        tokenCount++;
        buffer.write(text);
        onToken?.call(text);
        _idleTimer?.cancel();
        _idleTimer = Timer(const Duration(seconds: 5), () {
          print('[Inference] LiteRT-LM idle timeout - $tokenCount chunks');
          finish(buffer.toString());
        });
      },
      onDone: () {
        _liteConversationHasMessages = true;
        print('[Inference] LiteRT-LM stream done - $tokenCount chunks');
        finish(buffer.toString());
      },
      onError: (error) {
        _logLiteRtError('LiteRT-LM stream error', error);
        finish('ERROR: LiteRT-LM generation failed - $error');
      },
    );

    _idleTimer = Timer(const Duration(seconds: 60), () {
      if (tokenCount == 0) {
        finish('ERROR: LiteRT-LM model did not respond. Try a smaller model.');
      }
    });

    Future.delayed(const Duration(seconds: 180), () {
      if (!completed) {
        final partial = buffer.toString();
        finish(partial.isEmpty
            ? 'ERROR: LiteRT-LM generation timed out.'
            : partial);
      }
    });

    return completer.future;
  }

  /// True for native executor invoke failures (Status 13 / JNI
  /// exception): the session is usually poisoned, so the caller retries
  /// once with a fresh conversation. Public for unit tests.
  static bool isInvokeFailure(String message) =>
      message.contains('invoke the compiled model') ||
      message.contains('Status Code: 13') ||
      message.contains('LiteRtLmJniException');

  /// User-facing text for a failed generation. Invoke failures get
  /// guidance (RAM pressure is the usual cause on phones) instead of a
  /// raw native dump.
  static String friendlyInvokeError(String raw, {bool multimodal = false}) {
    if (isInvokeFailure(raw)) {
      return 'ERROR: The model ran out of working memory mid-generation'
          '${multimodal ? ' (images need much more RAM)' : ''}. '
          'Close other apps, try again${multimodal ? ' without the image' : ''}, '
          'or use a smaller model.';
    }
    return 'ERROR: LiteRT-LM ${multimodal ? 'multimodal ' : ''}generation failed - $raw';
  }

  /// print for logcat/console plus a real ERROR row so stream failures
  /// count in health, persist across kills and carry the open screen.
  void _logLiteRtError(String message, Object error) {
    print('[Inference] $message: $error');
    try {
      if (Get.isRegistered<AppLogService>()) {
        Get.find<AppLogService>().error(
          '[Inference] $message',
          details: error.toString(),
          category: LogCategory.model,
        );
      }
    } catch (_) {}
  }

  String _friendlyInvokeError(String raw, {required bool multimodal}) =>
      friendlyInvokeError(raw, multimodal: multimodal);

  Future<void> _ensureLiteRtConversation({
    required String prompt,
    required List<Map<String, String>>? conversationHistory,
    required String systemPrompt,
    required double temperature,
    double topP = 0.95,
    int topK = 64,
  }) async {
    final hasIncomingHistory = conversationHistory != null &&
        conversationHistory.any((msg) => (msg['content'] ?? '').isNotEmpty);
    final shouldReset = _liteConversation == null ||
        _liteConversationSystemPrompt != systemPrompt ||
        _liteConversationTemperature != temperature ||
        _liteConversationTopP != topP ||
        _liteConversationTopK != topK ||
        (_liteConversationHasMessages && !hasIncomingHistory);

    if (!shouldReset) return;

    try {
      await _liteConversation?.dispose();
    } catch (_) {}

    _liteConversation = await _liteEngine!.createConversation(
      LiteLmConversationConfig(
        systemInstruction: systemPrompt,
        initialMessages:
            _buildLiteRtInitialMessages(prompt, conversationHistory),
        samplerConfig: LiteLmSamplerConfig(
          temperature: temperature,
          topK: topK,
          topP: topP,
        ),
      ),
    );
    _liteConversationSystemPrompt = systemPrompt;
    _liteConversationTemperature = temperature;
    _liteConversationTopP = topP;
    _liteConversationTopK = topK;
    _liteConversationHasMessages = hasIncomingHistory;
  }

  List<LiteLmMessage> _buildLiteRtInitialMessages(
    String prompt,
    List<Map<String, String>>? history,
  ) {
    if (history == null || history.isEmpty) return const [];

    var recent = history.length > 16
        ? history.sublist(history.length - 16)
        : List<Map<String, String>>.from(history);
    if (recent.isNotEmpty &&
        recent.last['role'] == 'user' &&
        recent.last['content'] == prompt) {
      recent = recent.sublist(0, recent.length - 1);
    }

    return recent
        .where((msg) => (msg['content'] ?? '').trim().isNotEmpty)
        .map((msg) {
      final content = msg['content'] ?? '';
      return msg['role'] == 'assistant'
          ? LiteLmMessage.model(content)
          : LiteLmMessage.user(content);
    }).toList();
  }


  /// Stop the current generation, if any.
  Future<void> stop() async {
    if (_disposed) return;
    _idleTimer?.cancel();
    final stopCallback = _onStop;
    _onStop = null;
    stopCallback?.call();
    unawaited(_subscription?.cancel() ?? Future<void>.value());
    _liteConversationHasMessages = true;
  }

  /// Reset persistent conversation state for a clean next session.
  Future<void> resetConversation() async {
    try {
      await _liteConversation?.dispose();
    } catch (_) {}
    _liteConversation = null;
    _liteConversationSystemPrompt = null;
    _liteConversationTemperature = null;
    _liteConversationTopP = null;
    _liteConversationTopK = null;
    _liteConversationHasMessages = false;
  }

  /// Unload the model and free native resources.
  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    try {
      await _liteConversation?.dispose();
    } catch (_) {}
    try {
      await _liteEngine?.dispose();
    } catch (_) {}
    _liteConversation = null;
    _liteEngine = null;
    _liteConversationSystemPrompt = null;
    _liteConversationTemperature = null;
    _liteConversationTopP = null;
    _liteConversationTopK = null;
    _liteConversationHasMessages = false;
  }


  String _cleanLiteRtChunk(String text) {
    return sanitizeGemmaGarbage(
      text
          .replaceAll(
              RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]'),
              '')
          .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
          .replaceAll('\uFFFD', '')
          .replaceAll('<|endoftext|>', '')
          .replaceAll('<|im_end|>', '')
          .replaceAll('<|end|>', ''),
    );
  }
}
