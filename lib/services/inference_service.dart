import 'dart:async';
import 'dart:io' show File, FileMode, RandomAccessFile;
import 'dart:typed_data';
import 'package:get/get.dart';
import 'hive_service.dart';
import 'inference_types.dart';
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

  /// GGUF models currently resident in the native multi-model pool
  /// (file names, not full paths). Used by the in-chat switcher to mark
  /// models that can be activated instantly.
  final residentTextModels = <String>[].obs;

  /// Re-query the native pool for resident model paths.
  Future<void> refreshResidency() async {
    try {
      final paths = await _engine?.residentModels() ?? const <String>[];
      residentTextModels.value = paths
          .map((p) => p.split('/').last)
          .toList(growable: true);
    } catch (_) {
      // Pool info is best-effort; never block loading on it.
    }
  }

  /// True when [filename] can be switched to without any loading.
  bool isResident(String filename) => residentTextModels.contains(filename);

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

  /// Validates a GGUF file before it reaches the native loader. Returns a
  /// reason string when the file cannot be a valid model, null when it
  /// looks sane. Native llama.cpp aborts (SIGABRT/SIGBUS, instant app
  /// death) on malformed headers AND on tensor data cut short by a
  /// truncated download — Dart must reject these before the FFI boundary.
  /// A valid 32-byte magic alone proves nothing: truncation usually hits
  /// the tensor payload at the END of the file, so the full tensor table
  /// is parsed and every known tensor must fit inside the file.
  /// Public for unit tests.
  static String? validateGgufHeader(File f) {
    try {
      final len = f.lengthSync();
      if (len < 1024 * 1024) return 'file too small (${len}B)';
      final raf = f.openSync(mode: FileMode.read);
      try {
        final head = raf.readSync(32);
        if (head.length < 32) return 'cannot read header';
        final bd = head.buffer.asByteData(head.offsetInBytes);
        if (bd.getUint8(0) != 0x47 || // G
            bd.getUint8(1) != 0x47 || // G
            bd.getUint8(2) != 0x55 || // U
            bd.getUint8(3) != 0x46) {
          // F
          return 'bad magic';
        }
        final version = bd.getUint32(4, Endian.little);
        if (version != 2 && version != 3) return 'unknown version $version';
        final tensors = bd.getUint64(8, Endian.little);
        if (tensors == 0 || tensors > 100000) {
          return 'implausible tensor count $tensors';
        }
        return _validateGgufTensors(raf, len, tensors);
      } finally {
        raf.closeSync();
      }
    } catch (e) {
      return 'unreadable ($e)';
    }
  }

  /// Block length (elements) and byte size per GGML quant block.
  /// Only long-stable, certain type IDs are listed. Anything else
  /// returns null (skipped, never a false alarm): a wrong size would
  /// either block a valid model or miss a cut, both worse than skipping.
  static int? _ggmlBlockBytes(int type, int nelements) {
    switch (type) {
      case 0:
        return nelements * 4; // F32
      case 1:
        return nelements * 2; // F16
      case 2:
        return (nelements ~/ 32) * 18; // Q4_0
      case 3:
        return (nelements ~/ 32) * 20; // Q4_1
      case 6:
        return (nelements ~/ 32) * 22; // Q5_0
      case 7:
        return (nelements ~/ 32) * 24; // Q5_1
      case 8:
        return (nelements ~/ 32) * 34; // Q8_0
      case 10:
        return (nelements ~/ 256) * 84; // Q2_K
      case 11:
        return (nelements ~/ 256) * 110; // Q3_K
      case 12:
        return (nelements ~/ 256) * 144; // Q4_K
      case 13:
        return (nelements ~/ 256) * 176; // Q5_K
      case 14:
        return (nelements ~/ 256) * 210; // Q6_K
      case 15:
        return (nelements ~/ 256) * 260; // Q8_K
      default:
        return null;
    }
  }

  /// Parses GGUF metadata + tensor infos and requires every known tensor
  /// to end inside the file. Returns null when sane (or unverifiable).
  static String? _validateGgufTensors(
      RandomAccessFile raf, int fileLen, int tensorCount) {
    // Read enough to cover any realistic header (tokenizer arrays can
    // be several MB). Overruns inside a fully-read header are definitive.
    const cap = 32 * 1024 * 1024;
    final want = fileLen < cap ? fileLen : cap;
    raf.setPositionSync(0);
    final bytes = raf.readSync(want);
    if (bytes.length < 32) return 'cannot read header';
    final bd = bytes.buffer.asByteData(bytes.offsetInBytes);
    // Header is exactly 24 bytes: magic(4) + version(4) + tensor
    // count(8) + metadata count(8). Metadata KVs start right after.
    int pos = 24;

    int u32() {
      final v = bd.getUint32(pos, Endian.little);
      pos += 4;
      return v;
    }

    int u64() {
      final v = bd.getUint64(pos, Endian.little);
      pos += 8;
      return v;
    }

    void skipString() {
      final n = u64();
      pos += n;
    }

    void checkBounds(String what) {
      if (pos < 0 || pos > bytes.length) {
        throw StateError('$what overruns file');
      }
    }

    try {
      final metaCount = bd.getUint64(16, Endian.little);
      if (metaCount > 100000) return 'implausible metadata count $metaCount';
      for (var i = 0; i < metaCount; i++) {
        checkBounds('metadata key');
        skipString();
        checkBounds('metadata type');
        final type = u32();
        checkBounds('metadata value');
        switch (type) {
          case 8: // string
            skipString();
            break;
          case 9: // array
            final elemType = u32();
            final arrLen = u64();
            if (arrLen > 1000000) {
              throw StateError('metadata array too long');
            }
            for (var j = 0; j < arrLen; j++) {
              if (elemType == 8) {
                skipString();
              } else {
                pos += _ggufScalarBytes(elemType);
              }
              checkBounds('metadata array element');
            }
            break;
          default:
            pos += _ggufScalarBytes(type);
            break;
        }
        checkBounds('metadata end');
        if (pos > cap) return null; // header bigger than window: unverifiable
      }
      var maxEnd = 0;
      var checked = 0;
      for (var i = 0; i < tensorCount; i++) {
        checkBounds('tensor name');
        skipString();
        checkBounds('tensor dims');
        final nDims = u32();
        if (nDims > 8) throw StateError('implausible dims $nDims');
        var nelements = 1;
        for (var d = 0; d < nDims; d++) {
          checkBounds('tensor dim');
          final dim = u64();
          if (dim > (1 << 40)) throw StateError('implausible dim $dim');
          nelements *= dim;
          if (nelements > (1 << 48)) throw StateError('tensor too big');
        }
        checkBounds('tensor type/offset');
        final ttype = u32();
        final offset = u64();
        final size = _ggmlBlockBytes(ttype, nelements);
        if (size != null) {
          final end = offset + size;
          if (end > maxEnd) maxEnd = end;
          checked++;
        }
      }
      if (checked == 0) return null; // nothing verifiable
      // Tensor data starts after the header, aligned up. We don't know
      // the exact alignment without re-scanning metadata values, so use
      // the table end rounded up to 32 (the default) as the base: any
      // real file's base is >= this only if alignment <= 32... to stay
      // sound for larger alignments, add one alignment span of slack.
      // Tensor data starts after the header, aligned up (default 32).
      // Absolute end = aligned table end + relative tensor end; one
      // alignment span of slack keeps this sound for larger alignments.
      final dataBase = ((pos + 31) ~/ 32) * 32;
      if (dataBase + maxEnd + 32 > fileLen) {
        return 'truncated file: tensor data ends past EOF '
            '(${(dataBase + maxEnd) ~/ (1024 * 1024)}MB > ${fileLen ~/ (1024 * 1024)}MB)';
      }
      return null;
    } catch (e) {
      final msg = '$e';
      final windowed = bytes.length < fileLen;
      if (msg.contains('overruns') ||
          msg.contains('implausible') ||
          msg.contains('too long') ||
          msg.contains('too big')) {
        // Ran past the read window on a bigger file: unverifiable, not
        // proof of corruption. Only a true EOF overrun is a rejection.
        if (windowed && msg.contains('overruns')) return null;
        return 'corrupt header ($msg)';
      }
      return null; // short read inside window: unverifiable, don't block
    }
  }

  static int _ggufScalarBytes(int type) {
    switch (type) {
      case 0:
      case 1:
        return 1;
      case 2:
      case 3:
        return 2;
      case 4:
      case 5:
      case 6:
        return 4;
      case 10:
      case 11:
      case 12:
        return 8;
      default:
        throw StateError('unknown scalar type $type');
    }
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

    // Pre-flight: never hand a missing/empty file to the native layer — it
    // responds with an opaque "GGUF model file is missing or unreadable".
    final modelFile = File(modelPath);
    var fileOk = false;
    try {
      fileOk = modelFile.existsSync() && modelFile.lengthSync() > 0;
    } catch (_) {
      fileOk = false;
    }
    if (!fileOk) {
      final savedPath =
          _hive.getSetting<String>(AppConstants.keyLocalModelPath) ?? '';
      if (savedPath == modelPath) {
        // Stale pointer from a previous install/cleared storage — clear it so
        // the resume flow stops offering this model.
        await _hive.setSetting(AppConstants.keyLocalModelPath, '');
        await _hive.setSetting(AppConstants.keyLocalModelName, '');
        await _hive.setSetting(AppConstants.keyLocalModelRuntime, '');
        await _hive.setSetting(AppConstants.keyLocalModelBackend, '');
      }
      Get.find<AppLogService>().error(
        'Model file missing',
        details: 'path=$modelPath',
        category: LogCategory.model,
      );
      return
          'ERROR: "${modelName ?? modelPath.split('/').last}" is not on this device. Open the Models tab and download it first.';
    }

    // GGUF header sanity: a valid magic with garbage metadata segfaults
    // the native loader (no catch possible from Dart). Reject early.
    if (modelPath.toLowerCase().endsWith('.gguf')) {
      final headerError = validateGgufHeader(modelFile);
      if (headerError != null) {
        Get.find<AppLogService>().error(
          'Model file failed header check',
          details: 'path=$modelPath, reason=$headerError',
          category: LogCategory.model,
        );
        return 'ERROR: "${modelName ?? modelPath.split('/').last}" looks corrupted ($headerError). Re-download it from the Models tab.';
      }
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

      final contextSizeSetting = _hive.getSetting<int>(
            AppConstants.keyContextSize,
            defaultValue: AppConstants.defaultContextSize,
          ) ??
          AppConstants.defaultContextSize;

      // ── Instant switch: GGUF already resident in the native pool ────────
      // No unload, no reload — just make it the active slot. Only valid when
      // the requested context size matches what the resident slot was loaded
      // with; otherwise fall through to a real load so the new size applies.
      if (!isLiteRt) {
        _engine ??= platform.InferenceEngine();
        final lastLoadedCtx =
            _hive.getSetting<int>('last_loaded_context_size') ?? 0;
        final residentMatchesCtx =
            lastLoadedCtx == 0 || lastLoadedCtx == contextSizeSetting;
        if (residentMatchesCtx) {
          final switched = await _engine!.switchActiveModel(modelPath);
          if (switched) {
            final requestedName = modelName ?? modelPath.split('/').last;
            isModelLoaded.value = true;
            isLoadingModel.value = false;
            loadingModelName.value = '';
            modelLoadProgress.value = 1.0;
            loadedModelName.value = requestedName;
            loadedModelRuntime.value = 'llama';
            _sessionNativeRuntime = 'llama';
            isVisionLoaded.value = false;
            contextTokensUsed.value = 0;
            contextTokensTotal.value = contextSizeSetting;
            await _hive.setSetting(AppConstants.keyLocalModelPath, modelPath);
            await _hive.setSetting(
                AppConstants.keyLocalModelName, loadedModelName.value);
            await _hive.setSetting(
                AppConstants.keyLocalModelRuntime, 'llama');
            Get.find<AppLogService>()
                .info('Instant switch to resident model: $requestedName', category: LogCategory.model);
            try {
              await Get.find<AppLogService>()
                  .setBreadcrumb('model-load-done', requestedName);
            } catch (_) {}
            refreshResidency();
            return 'Switched to $requestedName instantly (no reload).';
          }
        }
      }

      // Pool-aware load for GGUF: the native layer frees only the target
      // slot, so other resident models stay loaded. LiteRT is single-session:
      // a litert→litert swap still needs the old one freed first, but a
      // llama→litert switch keeps the GGUF pool resident for instant return.
      final previousRuntime = loadedModelRuntime.value;
      if (isLiteRt && previousRuntime == 'litert') {
        await unloadModel();
      }
      isLoadingModel.value = true;
      loadingModelName.value = modelName ?? modelPath.split('/').last;
      modelLoadProgress.value = 0.0;

      _engine ??= platform.InferenceEngine();

      final contextSize = _hive.getSetting<int>(
            AppConstants.keyContextSize,
            defaultValue: AppConstants.defaultContextSize,
          ) ??
          AppConstants.defaultContextSize;

      final finalContextSize =
          isLiteRt ? contextSize.clamp(512, 4096) : contextSize;

      // Cap context by CURRENT free RAM (not tier): the KV cache scales
      // with ctx, and requesting 4096+ with <3GB free is a native OOM —
      // instant app death with no Dart log.
      var cappedCtx = finalContextSize;
      try {
        if (Get.isRegistered<DeviceInfoService>()) {
          final avail =
              Get.find<DeviceInfoService>().availableRamGB.value;
          if (avail > 0 && avail < 2.0) {
            cappedCtx = cappedCtx.clamp(512, 1024);
          } else if (avail > 0 && avail < 3.0) {
            cappedCtx = cappedCtx.clamp(512, 2048);
          }
          if (cappedCtx != finalContextSize) {
            Get.find<AppLogService>().info(
              'Context capped to $cappedCtx (free RAM ${avail.toStringAsFixed(1)}GB)',
              category: LogCategory.model,
            );
          }
        }
      } catch (_) {}

      final lastLoadedContext =
          _hive.getSetting<int>('last_loaded_context_size') ?? 0;
      final contextChanged = isLiteRt && lastLoadedContext != cappedCtx;

      final deviceTier = _getDeviceTier();
      final isTensorSoC = _getIsTensorSoC();

      final requestedModelName = modelName ?? modelPath.split('/').last;
      final activeModelName = requestedModelName;
      // Evidence row BEFORE the native call: a JNI-time abort kills the
      // process with no Dart exception, so without this the log shows
      // nothing and the next crash is undebuggable. Breadcrumb + flush
      // survive even SIGKILL (info rows alone would die in memory).
      try {
        final sizeMb = modelFile.lengthSync() ~/ (1024 * 1024);
        final logSvc = Get.find<AppLogService>();
        logSvc.info(
          'Loading local model: $requestedModelName (${sizeMb}MB, ctx=$cappedCtx, tier=$deviceTier)',
          category: LogCategory.model,
        );
        await logSvc.setBreadcrumb(
            'native-load-start', '$requestedModelName (${sizeMb}MB)');
        await logSvc.flush();
      } catch (_) {}
      final result = await _loadModelOnEngine(
        modelPath: modelPath,
        modelRuntime: modelRuntime,
        contextSize: cappedCtx,
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

      // Note: there is deliberately no "model already loaded" recovery path
      // here. The native layer now frees any resident model before loading
      // (LlamaController.loadModel), so that error should not occur — and
      // reporting success for a load that never happened would leave the UI
      // naming one model while inference ran another.

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
          category: LogCategory.model,
        );
        try {
          await Get.find<AppLogService>()
              .setBreadcrumb('model-load-failed', requestedModelName);
        } catch (_) {}
        return result.message;
      }

      try {
        await Get.find<AppLogService>()
            .setBreadcrumb('model-load-done', requestedModelName);
      } catch (_) {}
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
      contextTokensTotal.value = cappedCtx;

      await _hive.setSetting(AppConstants.keyLocalModelPath, modelPath);
      await _hive.setSetting(
          AppConstants.keyLocalModelName, loadedModelName.value);
      await _hive.setSetting(
          AppConstants.keyLocalModelRuntime, loadedModelRuntime.value);
      await _hive.setSetting(
          AppConstants.keyLocalModelBackend, loadedBackend.value);

      // Track loaded context size across ALL runtimes so the instant-switch
      // path can tell when a resident slot predates a context-size change.
      await _hive.setSetting('last_loaded_context_size', cappedCtx);

      refreshResidency();

      return result.message;
    } catch (e) {
      isModelLoaded.value = false;
      isLoadingModel.value = false;
      loadingModelName.value = '';
      modelLoadProgress.value = 0.0;
      loadedBackend.value = '';
      Get.find<AppLogService>().error('Failed to load local model', details: e, category: LogCategory.model);
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
    residentTextModels.assignAll(<String>[]);
    // _sessionNativeRuntime is intentionally NOT cleared. Unloading frees the
    // model, but the runtime's .so files stay loaded in the process for its
    // lifetime, so the cross-runtime guard must keep firing after an unload.
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

      // Local sampling params (GGUF + LiteRT; cloud uses provider defaults).
      final topP = _hive.getSetting<double>(
            AppConstants.keyTopP,
            defaultValue: AppConstants.defaultTopP,
          ) ??
          AppConstants.defaultTopP;
      final topK = _hive.getSetting<int>(
            AppConstants.keyTopK,
            defaultValue: AppConstants.defaultTopK,
          ) ??
          AppConstants.defaultTopK;
      final repeatPenalty = _hive.getSetting<double>(
            AppConstants.keyRepeatPenalty,
            defaultValue: AppConstants.defaultRepeatPenalty,
          ) ??
          AppConstants.defaultRepeatPenalty;

      final result = await _engine!.generate(
        prompt: prompt,
        conversationHistory: conversationHistory,
        systemPrompt: systemPrompt ?? AppConstants.systemPrompt,
        modelName: loadedModelName.value,
        maxTokens: maxTokens,
        temperature: temperature,
        topP: topP,
        topK: topK,
        repeatPenalty: repeatPenalty,
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
      Get.find<AppLogService>().error('Local generation failed', details: e, category: LogCategory.model);
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

  Future<LoadResult> _loadModelOnEngine({
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
          return LoadResult(
            success: false,
            message: 'ERROR: Failed to load model - $cpuError',
          );
        }
      }
      gpuLoadFailed = true;
      return LoadResult(
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
