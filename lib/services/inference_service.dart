import 'dart:async';
import 'package:get/get.dart';
import 'hive_service.dart';
import '../core/constants.dart';
import 'device_info_service.dart';
import 'app_log_service.dart';

// Conditionally import llama_flutter_android — only on Android
import 'inference_android.dart' if (dart.library.html) 'inference_stub.dart'
    as platform;

/// Cross-platform inference service.
/// - Android / iOS: uses llama_flutter_android for local GGUF models
/// - Android: uses flutter_litert_lm for LiteRT-LM models
/// - Web: cloud-only mode (local inference coming soon)
class InferenceService extends GetxService {
  final HiveService _hive = Get.find<HiveService>();

  // ── Observable State ──
  final isModelLoaded = false.obs;
  final isGenerating = false.obs;
  final isLoadingModel = false.obs;
  final isVisionLoaded = false.obs;
  final loadingModelName = ''.obs;
  final loadedModelName = ''.obs;
  final tokenCount = 0.obs;
  final tokensPerSecond = 0.0.obs;
  final contextTokensUsed = 0.obs;
  final contextTokensTotal = 0.obs;
  final modelLoadProgress = 0.0.obs;
  final generationSource = ''.obs;
  final streamingText = ''.obs;
  final gpuName = ''.obs;
  final gpuLayersUsed = 0.obs;
  final isGpuAccelerated = false.obs;
  final loadedModelRuntime = ''.obs;
  final loadedBackend = ''.obs;

  /// Whether the current platform supports local inference.
  bool get supportsLocalInference => platform.supportsLocalInference;

  // Platform-specific engine
  platform.InferenceEngine? _engine;
  String _sessionNativeRuntime = '';

  String get sessionNativeRuntime => _sessionNativeRuntime;

  bool requiresAppRestartForRuntime(String runtime) {
    final normalized = runtime.toLowerCase();
    if (normalized != 'llama' && normalized != 'litert') return false;
    return _sessionNativeRuntime.isNotEmpty &&
        _sessionNativeRuntime != normalized;
  }

  Future<String> loadModel(
    String modelPath, {
    String? modelName,
    String? modelRuntime,
    bool enableLiteRtVision = false,
  }) async {
    if (!supportsLocalInference) {
      return 'ERROR: Local inference is not available on this platform. Use Cloud mode.';
    }
    if (isLoadingModel.value) return 'ERROR: Model is already loading.';

    if (modelPath.toLowerCase().endsWith('.safetensors')) {
      return 'ERROR: Cannot load image generation models (.safetensors) into the local text engine. Native local image generation requires the upcoming stable-diffusion engine update. Use Cloud Stability AI for now.';
    }

    try {
      final runtime = _runtimeFor(modelPath, modelRuntime);
      final isLiteRt = runtime == 'litert';
      final liteRtMode = _hive.getSetting<String>(
            AppConstants.keyLiteRtPerformanceMode,
            defaultValue: AppConstants.defaultLiteRtPerformanceMode,
          ) ??
          AppConstants.defaultLiteRtPerformanceMode;
      final hadPendingGpuLoad = isLiteRt &&
          (_hive.getSetting<bool>(
                AppConstants.keyLiteRtGpuLoadPending,
                defaultValue: false,
              ) ??
              false);
      if (hadPendingGpuLoad) {
        await _hive.setSetting(AppConstants.keyLiteRtGpuLoadPending, false);
        await _hive.setSetting(AppConstants.keyLiteRtGpuCrashDetected, true);
      }
      final gpuCrashDetected = isLiteRt &&
          (_hive.getSetting<bool>(
                AppConstants.keyLiteRtGpuCrashDetected,
                defaultValue: false,
              ) ??
              false);
      final forceLiteRtCpu = isLiteRt &&
          (liteRtMode == 'cpu_safe' ||
              (liteRtMode == 'auto_fast' && gpuCrashDetected));
      final shouldTryLiteRtGpu =
          isLiteRt && !forceLiteRtCpu && liteRtMode != 'cpu_safe';

      await unloadModel();
      isLoadingModel.value = true;
      loadingModelName.value = modelName ?? modelPath.split('/').last;
      modelLoadProgress.value = 0.0;

      _engine = platform.InferenceEngine();

      final contextSize = _hive.getSetting<int>(
            AppConstants.keyContextSize,
            defaultValue: AppConstants.defaultContextSize,
          ) ??
          AppConstants.defaultContextSize;

      final finalContextSize =
          isLiteRt ? contextSize.clamp(512, 4096) : contextSize;

      final lastLoadedContext =
          _hive.getSetting<int>('last_loaded_context_size') ?? 0;
      final contextChanged = isLiteRt && lastLoadedContext != finalContextSize;

      final deviceTier = _getDeviceTier();
      final isTensorSoC = _getIsTensorSoC();

      final requestedModelName = modelName ?? modelPath.split('/').last;
      var activeModelName = requestedModelName;
      var result = await _loadModelOnEngine(
        modelPath: modelPath,
        modelRuntime: modelRuntime,
        contextSize: finalContextSize,
        deviceTier: deviceTier,
        isTensorSoC: isTensorSoC,
        liteRtPerformanceMode: liteRtMode,
        forceLiteRtCpu: forceLiteRtCpu,
        clearLiteRtCache: hadPendingGpuLoad ||
            (isLiteRt && gpuCrashDetected) ||
            contextChanged,
        markLiteRtGpuPending: shouldTryLiteRtGpu,
        enableLiteRtVision: enableLiteRtVision,
      );

      if (!result.success &&
          result.message.toLowerCase().contains('model already loaded')) {
        final savedModelName =
            _hive.getSetting<String>(AppConstants.keyLocalModelName) ?? '';
        final adoptedModelName =
            savedModelName.isNotEmpty ? savedModelName : requestedModelName;
        activeModelName = adoptedModelName;
        result = platform.LoadResult(
          success: true,
          message: savedModelName == requestedModelName
              ? 'Model already loaded.'
              : 'A native model is already loaded. Unload it before loading another model.',
          runtime: modelRuntime ??
              _hive.getSetting<String>(AppConstants.keyLocalModelRuntime) ??
              '',
          backend:
              _hive.getSetting<String>(AppConstants.keyLocalModelBackend) ?? '',
        );
      }

      if (!result.success) {
        isModelLoaded.value = false;
        isLoadingModel.value = false;
        loadingModelName.value = '';
        modelLoadProgress.value = 0.0;
        loadedModelName.value = '';
        loadedModelRuntime.value = '';
        loadedBackend.value = '';
        gpuName.value = '';
        gpuLayersUsed.value = 0;
        isGpuAccelerated.value = false;
        Get.find<AppLogService>().error(
          'Local model load failed',
          details:
              'model=$requestedModelName, runtime=$runtime, backend=${result.backend}, message=${result.message}',
        );
        return result.message;
      }

      isModelLoaded.value = result.success;
      isLoadingModel.value = false;
      loadingModelName.value = '';
      modelLoadProgress.value = 1.0;
      loadedModelName.value = activeModelName;
      loadedModelRuntime.value = result.runtime;
      if (result.runtime == 'llama' || result.runtime == 'litert') {
        _sessionNativeRuntime = result.runtime;
      }
      loadedBackend.value = result.backend;
      gpuName.value = result.gpuName;
      gpuLayersUsed.value = result.gpuLayers;
      isGpuAccelerated.value = result.backend == 'gpu' || result.gpuLayers > 0;
      if (isLiteRt && result.backend == 'gpu') {
        await _hive.setSetting(AppConstants.keyLiteRtGpuCrashDetected, false);
      }
      contextTokensUsed.value = 0;
      contextTokensTotal.value = finalContextSize;

      await _hive.setSetting(AppConstants.keyLocalModelPath, modelPath);
      await _hive.setSetting(
          AppConstants.keyLocalModelName, loadedModelName.value);
      await _hive.setSetting(
          AppConstants.keyLocalModelRuntime, loadedModelRuntime.value);
      await _hive.setSetting(
          AppConstants.keyLocalModelBackend, loadedBackend.value);

      if (isLiteRt) {
        await _hive.setSetting('last_loaded_context_size', finalContextSize);
      }

      return result.message;
    } catch (e) {
      isModelLoaded.value = false;
      isLoadingModel.value = false;
      loadingModelName.value = '';
      modelLoadProgress.value = 0.0;
      loadedBackend.value = '';
      Get.find<AppLogService>().error('Failed to load local model', details: e);
      return 'ERROR: Failed to load model — $e';
    }
  }

  Future<void> unloadModel() async {
    final engine = _engine;
    _engine = null;
    if (engine != null) {
      await stopGeneration();
      await engine.dispose();
    }
    isModelLoaded.value = false;
    isVisionLoaded.value = false;
    loadedModelName.value = '';
    loadingModelName.value = '';
    loadedModelRuntime.value = '';
    loadedBackend.value = '';
    gpuLayersUsed.value = 0;
    isGpuAccelerated.value = false;
    gpuName.value = '';
    contextTokensUsed.value = 0;
    contextTokensTotal.value = 0;
    _sessionNativeRuntime = '';
  }

  Future<String> generate({
    required String prompt,
    String? systemPrompt,
    List<Map<String, String>>? conversationHistory,
    String source = 'chat',
    String? imagePath,
    String? audioPath,
    void Function(String token)? onToken,
  }) async {
    if (!supportsLocalInference || _engine == null || !isModelLoaded.value) {
      return 'ERROR: No model loaded. Go to Models tab to download and load one.';
    }

    if (isGenerating.value) {
      // Wait for previous generation
      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (!isGenerating.value) break;
      }
      if (isGenerating.value) {
        await stopGeneration();
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }

    isGenerating.value = true;
    tokenCount.value = 0;
    tokensPerSecond.value = 0.0;
    generationSource.value = source;
    streamingText.value = '';

    final startTime = DateTime.now();
    DateTime? firstVisibleTokenAt;
    Timer? tokenFlushTimer;
    final tokenFlushBuffer = StringBuffer();

    void flushTokenBuffer() {
      if (tokenFlushBuffer.isEmpty) return;
      final text = tokenFlushBuffer.toString();
      tokenFlushBuffer.clear();
      onToken?.call(text);
    }

    try {
      final temperature = _hive.getSetting<double>(
            AppConstants.keyTemperature,
            defaultValue: AppConstants.defaultTemperature,
          ) ??
          AppConstants.defaultTemperature;

      final maxTokens = _hive.getSetting<int>(
            AppConstants.keyMaxTokens,
            defaultValue: AppConstants.defaultMaxTokens,
          ) ??
          AppConstants.defaultMaxTokens;

      final result = await _engine!.generate(
        prompt: prompt,
        conversationHistory: conversationHistory,
        systemPrompt: systemPrompt ?? AppConstants.systemPrompt,
        modelName: loadedModelName.value,
        maxTokens: maxTokens,
        temperature: temperature,
        imagePath: imagePath,
        audioPath: audioPath,
        onToken: (token) {
          firstVisibleTokenAt ??= DateTime.now();
          tokenCount.value++;
          streamingText.value += token;
          final speedStart = firstVisibleTokenAt ?? startTime;
          final elapsedSeconds =
              DateTime.now().difference(speedStart).inMilliseconds / 1000.0;
          if (elapsedSeconds > 0) {
            tokensPerSecond.value = tokenCount.value / elapsedSeconds;
          }
          if (loadedModelRuntime.value == 'litert') {
            tokenFlushBuffer.write(token);
            tokenFlushTimer ??= Timer(const Duration(milliseconds: 60), () {
              tokenFlushTimer = null;
              flushTokenBuffer();
            });
          } else {
            onToken?.call(token);
          }
        },
      );
      tokenFlushTimer?.cancel();
      flushTokenBuffer();

      await refreshContextInfo();
      isGenerating.value = false;
      generationSource.value = '';

      // Detect Tensor SoC + Gemma Q4_K_M corruption: model outputs only
      // special tokens and terminates immediately with empty result.
      if (result.trim().isEmpty &&
          tokenCount.value < 5 &&
          loadedModelName.value.toLowerCase().contains('gemma')) {
        final isTensor = _getIsTensorSoC();
        if (isTensor) {
          return '⚠️ This Gemma model is incompatible with your Pixel\'s Google Tensor chip. '
              'The Q4_K_M quantization format has a known bug on Tensor SoC that produces empty responses.\n\n'
              'Try one of these fixes:\n'
              '1. Download a Q4_0 or Q5_K_M version of the same model\n'
              '2. Use a different model (Qwen, Phi, or Llama-3)\n'
              '3. Switch to Cloud mode in Settings';
        }
      }

      return result;
    } catch (e) {
      isGenerating.value = false;
      generationSource.value = '';
      streamingText.value = '';
      tokenFlushTimer?.cancel();
      flushTokenBuffer();
      Get.find<AppLogService>().error('Local generation failed', details: e);
      return 'ERROR: $e';
    }
  }

  Future<void> stopGeneration() async {
    isGenerating.value = false;
    tokenCount.value = 0;
    generationSource.value = '';
    streamingText.value = '';
    final engine = _engine;
    if (engine != null) {
      unawaited(engine.stop().timeout(const Duration(seconds: 1)).catchError(
            (_) {},
          ));
    }
  }

  /// Reset the native conversation context. Call this whenever the user
  /// switches to a different chat session so old context doesn't leak.
  Future<void> resetConversation() async {
    final engine = _engine;
    if (engine != null) {
      await engine.resetConversation();
    }
  }

  Future<void> refreshContextInfo() async {
    if (!supportsLocalInference || _engine == null || !isModelLoaded.value) {
      return;
    }

    final info = await _engine!.getContextInfo();
    if (info == null) return;

    contextTokensUsed.value = info.tokensUsed;
    contextTokensTotal.value = info.contextSize;
  }

  String _getDeviceTier() {
    try {
      final device = Get.find<DeviceInfoService>();
      return device.deviceTier.value;
    } catch (_) {
      return 'mid';
    }
  }

  bool _getIsTensorSoC() {
    try {
      final device = Get.find<DeviceInfoService>();
      return device.isTensorSoC.value;
    } catch (_) {
      return false;
    }
  }

  Future<platform.LoadResult> _loadModelOnEngine({
    required String modelPath,
    required String? modelRuntime,
    required int contextSize,
    required String deviceTier,
    bool isTensorSoC = false,
    required String liteRtPerformanceMode,
    required bool forceLiteRtCpu,
    required bool clearLiteRtCache,
    required bool markLiteRtGpuPending,
    required bool enableLiteRtVision,
  }) async {
    var gpuLoadFailed = false;
    try {
      if (markLiteRtGpuPending) {
        await _hive.setSetting(AppConstants.keyLiteRtGpuLoadPending, true);
      }
      final result = await _engine!.loadModel(
        modelPath: modelPath,
        modelRuntime: modelRuntime,
        contextSize: contextSize,
        deviceTier: deviceTier,
        isTensorSoC: isTensorSoC,
        liteRtPerformanceMode: liteRtPerformanceMode,
        forceLiteRtCpu: forceLiteRtCpu,
        clearLiteRtCache: clearLiteRtCache,
        enableLiteRtVision: enableLiteRtVision,
        onProgress: (p) => modelLoadProgress.value = _normalizeProgress(p),
      );
      if (result.success ||
          !markLiteRtGpuPending ||
          liteRtPerformanceMode != 'auto_fast') {
        return result;
      }

      await _hive.setSetting(AppConstants.keyLiteRtGpuLoadPending, false);
      await _hive.setSetting(AppConstants.keyLiteRtGpuCrashDetected, true);
      modelLoadProgress.value = 0.0;
      return await _engine!.loadModel(
        modelPath: modelPath,
        modelRuntime: modelRuntime,
        contextSize: contextSize,
        deviceTier: deviceTier,
        isTensorSoC: isTensorSoC,
        liteRtPerformanceMode: liteRtPerformanceMode,
        forceLiteRtCpu: true,
        clearLiteRtCache: true,
        enableLiteRtVision: enableLiteRtVision,
        onProgress: (p) => modelLoadProgress.value = _normalizeProgress(p),
      );
    } catch (e) {
      if (markLiteRtGpuPending && liteRtPerformanceMode == 'auto_fast') {
        await _hive.setSetting(AppConstants.keyLiteRtGpuLoadPending, false);
        await _hive.setSetting(AppConstants.keyLiteRtGpuCrashDetected, true);
        try {
          modelLoadProgress.value = 0.0;
          return await _engine!.loadModel(
            modelPath: modelPath,
            modelRuntime: modelRuntime,
            contextSize: contextSize,
            deviceTier: deviceTier,
            isTensorSoC: isTensorSoC,
            liteRtPerformanceMode: liteRtPerformanceMode,
            forceLiteRtCpu: true,
            clearLiteRtCache: true,
            enableLiteRtVision: enableLiteRtVision,
            onProgress: (p) => modelLoadProgress.value = _normalizeProgress(p),
          );
        } catch (cpuError) {
          return platform.LoadResult(
            success: false,
            message: 'ERROR: Failed to load model - $cpuError',
          );
        }
      }
      gpuLoadFailed = true;
      return platform.LoadResult(
        success: false,
        message: 'ERROR: Failed to load model - $e',
      );
    } finally {
      if (markLiteRtGpuPending) {
        if (gpuLoadFailed) {
          await _hive.setSetting(AppConstants.keyLiteRtGpuCrashDetected, true);
        }
        await _hive.setSetting(AppConstants.keyLiteRtGpuLoadPending, false);
      }
    }
  }

  double _normalizeProgress(double progress) {
    if (progress.isNaN || progress.isInfinite) return 0.0;
    final normalized = progress > 1 ? progress / 100 : progress;
    return normalized.clamp(0.0, 1.0).toDouble();
  }

  String _runtimeFor(String modelPath, String? modelRuntime) {
    final runtime = modelRuntime?.toLowerCase();
    if (runtime == 'litert' || runtime == 'llama') return runtime!;
    return modelPath.toLowerCase().endsWith('.litertlm') ? 'litert' : 'llama';
  }
}
