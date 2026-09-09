import 'dart:async';
import 'dart:io' show Platform;

import 'package:llama_flutter_android/llama_flutter_android.dart';

import 'inference_gguf.dart';
import 'inference_litert.dart';
import 'inference_types.dart';

/// Whether the current platform supports local inference.
bool get supportsLocalInference => Platform.isAndroid || Platform.isIOS;

/// Android & iOS inference engine — thin router over the GGUF engine
/// ([GgufEngine]) and the LiteRT engine ([LiteRtEngine]).
///
/// The two engines share no mutable state: a GGUF edit can never break
/// LiteRT and vice versa. All engine-specific logic lives in those
/// files; this facade only routes by runtime and tracks which side is
/// active. Public API is unchanged (see inference_stub.dart for web).
class InferenceEngine {
  final GgufEngine _gguf = GgufEngine();
  final LiteRtEngine _lite = LiteRtEngine();
  bool _isLiteRt = false;
  bool _disposed = false;

  static String _runtimeFor(String modelPath, String? modelRuntime) {
    final runtime = modelRuntime?.toLowerCase();
    if (runtime == 'litert' || runtime == 'llama') return runtime!;
    final lower = modelPath.toLowerCase();
    if (lower.endsWith('.litertlm')) return 'litert';
    return 'llama';
  }

  Future<LoadResult> loadModel({
    required String modelPath,
    String? modelRuntime,
    required int contextSize,
    required String deviceTier,
    bool isTensorSoC = false,
    String liteRtPerformanceMode = 'auto_fast',
    bool forceLiteRtCpu = false,
    bool clearLiteRtCache = false,
    bool enableLiteRtVision = false,
    void Function(double)? onProgress,
  }) async {
    _disposed = false;
    final runtime = _runtimeFor(modelPath, modelRuntime);
    if (runtime == 'litert') {
      _isLiteRt = true;
      return _lite.loadModel(
        modelPath: modelPath,
        contextSize: contextSize,
        performanceMode: liteRtPerformanceMode,
        forceCpu: forceLiteRtCpu,
        clearCache: clearLiteRtCache,
        enableVision: enableLiteRtVision,
        onProgress: onProgress,
      );
    }
    _isLiteRt = false;
    return _gguf.loadModel(
      modelPath: modelPath,
      contextSize: contextSize,
      deviceTier: deviceTier,
      isTensorSoC: isTensorSoC,
      onProgress: onProgress,
    );
  }

  /// Instantly activate an already-resident GGUF model in the native pool.
  /// Returns false when [modelPath] is not resident (caller falls back to a
  /// full load).
  Future<bool> switchActiveModel(String modelPath) async {
    final ok = await _gguf.switchActiveModel(modelPath);
    if (ok) _isLiteRt = false;
    return ok;
  }

  /// Paths of GGUF models currently resident in the native pool.
  Future<List<String>> residentModels() => _gguf.residentModels();

  /// Free one specific resident GGUF model (all slots stay otherwise).
  Future<void> freeResidentModel(String modelPath) =>
      _gguf.freeResidentModel(modelPath);

  Future<String> generate({
    required String prompt,
    List<Map<String, String>>? conversationHistory,
    required String systemPrompt,
    required String modelName,
    required int maxTokens,
    required double temperature,
    double? topP,
    int? topK,
    double? repeatPenalty,
    String? imagePath,
    String? audioPath,
    void Function(String token)? onToken,
  }) {
    if (_isLiteRt) {
      return _lite.generate(
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
      );
    }
    return _gguf.generate(
      prompt: prompt,
      conversationHistory: conversationHistory,
      systemPrompt: systemPrompt,
      modelName: modelName,
      maxTokens: maxTokens,
      temperature: temperature,
      topP: topP,
      topK: topK,
      repeatPenalty: repeatPenalty,
      imagePath: imagePath,
      audioPath: audioPath,
      onToken: onToken,
    );
  }

  /// Stop the current generation, if any.
  Future<void> stop() async {
    if (_disposed) return;
    if (_isLiteRt) {
      await _lite.stop();
    } else {
      await _gguf.stop();
    }
  }

  /// Reset any persistent conversation state so the next generation
  /// starts with a clean context. Essential when switching chat sessions.
  Future<void> resetConversation() async {
    if (_isLiteRt) {
      await _lite.resetConversation();
    }
    // llama.cpp (GGUF) is stateless per-generation — no native
    // conversation object to reset.
  }

  Future<ContextInfo?> getContextInfo() async {
    if (_isLiteRt) return null;
    return _gguf.getContextInfo();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    // Always attempt the native free: the Kotlin/C++ side can hold a model this
    // object never saw succeed (a load that threw partway still leaves g_model
    // resident), and skipping the free is what blocks all later loads until the
    // process restarts.
    await _gguf.dispose();
    await _lite.dispose();
  }
}
