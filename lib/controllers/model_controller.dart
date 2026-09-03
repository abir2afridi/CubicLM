import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/app_snackbar.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/download_service.dart';
import '../services/inference_service.dart';
import '../services/local_image_service.dart';
import '../services/hive_service.dart';
import '../services/app_log_service.dart';
import '../services/device_info_service.dart';
import '../models/ai_model.dart';
import '../core/constants.dart';
import 'settings_controller.dart';

enum _ModelLoadAction { cancel, continueLoad }

class ModelController extends GetxController {
  final DownloadService _download = Get.find<DownloadService>();
  final LocalImageService _localImage = Get.find<LocalImageService>();
  final InferenceService _inference = Get.find<InferenceService>();
  final HiveService _hive = Get.find<HiveService>();
  final SettingsController _settings = Get.find<SettingsController>();

  static const _customModelsKey = 'custom_url_models';
  static const _androidImportChannel =
      MethodChannel('com.aichat.ai_chat/model_import');

  Map<String, DownloadProgress> get activeDownloads =>
      _download.activeDownloads;

  final availableModels = <AiModel>[].obs;
  final downloadedFiles = <String>[].obs;
  final isImporting = false.obs;
  final customModels = <AiModel>[].obs;
  final fileSizes = <String, int>{}.obs;
  final modelScope = 'local'.obs;
  final localFilter = ''.obs;
  final importFileName = ''.obs;
  final importStatus = ''.obs;
  final importCopiedBytes = 0.obs;
  final importTotalBytes = 0.obs;
  final importBytesPerSecond = 0.0.obs;
  final sortSmallestFirst = true.obs;
  final externalDownloadId = Rx<int?>(null);

  void toggleSort() {
    sortSmallestFirst.value = !sortSmallestFirst.value;
  }

  /// Whether the current platform can load local models into an on-device
  /// inference engine. Desktop (Windows) and Web are Cloud-only for now —
  /// the llama.cpp / LiteRT engines ship Android (and iOS) natives only.
  bool get supportsLocalInference => _inference.supportsLocalInference;

  /// Human-readable label for the public Downloads folder on this platform.
  String get saveToDownloadsLabel => Platform.isAndroid
      ? "your phone's public Downloads folder"
      : 'your Downloads folder';

  static const localFilters = [
    'downloaded',
    'general',
    'image',
    'uncensored',
    'vision'
  ];

  List<AiModel> get displayedModels {
    final active = _inference.loadedModelName.value;
    final models = [...availableModels];
    models.sort((a, b) {
      if (a.filename == active) return -1;
      if (b.filename == active) return 1;
      final aDownloaded = isDownloaded(a.filename);
      final bDownloaded = isDownloaded(b.filename);
      if (aDownloaded != bDownloaded) return aDownloaded ? -1 : 1;

      if (sortSmallestFirst.value) {
        final aBytes = _knownModelBytes(a);
        final bBytes = _knownModelBytes(b);
        if (aBytes > 0 && bBytes > 0 && aBytes != bBytes) {
          return aBytes.compareTo(bBytes);
        }
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return models;
  }

  List<AiModel> get filteredDisplayedModels {
    final filter =
        localFilter.value.isEmpty ? defaultLocalFilter : localFilter.value;
    return displayedModels.where((model) {
      switch (filter) {
        case 'downloaded':
          return isDownloaded(model.filename);
        case 'uncensored':
          return isUncensoredModel(model);
        case 'vision':
          return isVisionModel(model);
        case 'image':
          return isImageModel(model);
        case 'general':
        default:
          return isGeneralModel(model);
      }
    }).toList();
  }

  String get defaultLocalFilter =>
      downloadedFiles.isNotEmpty ? 'downloaded' : 'general';

  double get importProgress => importTotalBytes.value <= 0
      ? 0.0
      : (importCopiedBytes.value / importTotalBytes.value)
          .clamp(0.0, 1.0)
          .toDouble();

  int get downloadedCount => downloadedFiles.length;

  String get activeLocalModelName => _inference.loadedModelName.value;

  @override
  void onInit() {
    super.onInit();
    _loadCustomModels();
    availableModels.value = AppConstants.availableModels
        .map((m) => AiModel.fromMap(m))
        .toList()
      ..addAll(customModels);
    refreshDownloaded();
  }

  void _loadCustomModels() {
    final raw =
        _hive.getSetting<List>(_customModelsKey, defaultValue: []) ?? [];
    customModels.value = raw
        .whereType<Map>()
        .map((m) => AiModel.fromMap(Map<String, String>.from(m)))
        .toList();
  }

  Future<void> _saveCustomModels() async {
    await _hive.setSetting(
      _customModelsKey,
      customModels.map((m) => m.toMap()).toList(),
    );
  }

  Future<void> refreshDownloaded() async {
    await _deletePartialImports();
    final files = (await _download.getDownloadedModels())
        .where((file) => !_isAuxiliaryImageFile(file))
        .toList();
    downloadedFiles.value = files;
    for (final file in files) {
      fileSizes[file] = await _download.getModelSize(file);
    }

    // Add any downloaded files that are not in availableModels
    final existingFilenames = availableModels.map((m) => m.filename).toSet();
    for (final file in files) {
      if (!existingFilenames.contains(file)) {
        final lower = file.toLowerCase();
        final runtime = AiModel.runtimeFromFilename(file);
        final isLiteRt = runtime == AiModel.runtimeLiteRt;
        final isVision = isLiteRt && AiModel.hasVisionMarker(lower);

        availableModels.add(AiModel(
          name: file,
          filename: file,
          url: '',
          size: _formatModelSize(file),
          description: 'Imported from local storage',
          template: isLiteRt ? 'litert' : 'chatml',
          runtime: runtime,
          isImported: true,
          isVision: isVision,
        ));
      }
    }

    // Remove any imported models that are no longer downloaded
    availableModels.removeWhere(
        (model) => model.isImported && !files.contains(model.filename));

    if (localFilter.value.isEmpty) {
      localFilter.value = defaultLocalFilter;
    }
  }

  bool isDownloaded(String filename) => downloadedFiles.contains(filename);

  bool _isAuxiliaryImageFile(String filename) {
    final lower = filename.toLowerCase();
    return lower == 'taesd.safetensors' ||
        lower.startsWith('taesd-') ||
        lower.startsWith('taesd_') ||
        lower == 'diffusion_pytorch_model.safetensors' ||
        lower.endsWith('.vae.safetensors') ||
        lower.startsWith('vae-') ||
        lower.startsWith('vae_');
  }

  Future<bool> _isIncompleteCatalogFile(AiModel model, int fileBytes) async {
    if (model.isImported) {
      // Don't bypass for imported models when fileBytes is invalid — check header magic instead.
      if (fileBytes <= 0) return true;
      try {
        final path = await _download.modelPath(model.filename);
        final lower = model.filename.toLowerCase();
        if (lower.endsWith('.safetensors')) {
          if (!await _hasValidSafetensorsHeader(path)) return true;
        } else if (lower.endsWith('.litertlm')) {
          if (!await _hasLikelyValidLiteRtFile(path, fileBytes)) return true;
        } else if (lower.endsWith('.gguf')) {
          final file = File(path);
          if (!await file.exists()) return true;
          RandomAccessFile? raf;
          try {
            raf = await file.open();
            final bytes = await raf.read(4);
            if (bytes.length < 4 ||
                bytes[0] != 0x47 ||
                bytes[1] != 0x47 ||
                bytes[2] != 0x55 ||
                bytes[3] != 0x46) {
              return true;
            }
          } finally {
            await raf?.close();
          }
        } else {
          if (fileBytes < 1024) return true;
        }
      } catch (_) {
        return true;
      }
      return false;
    }
    if (model.url.trim().isEmpty || fileBytes <= 0) {
      return false;
    }
    final expectedBytes = _declaredModelBytes(model);
    if (expectedBytes <= 0) return false;
    // Relax threshold to 85% to comfortably accommodate HuggingFace decimal-scaled catalog sizes 
    // and rounded metadata sizes (e.g. 770.3MB listed as 0.8GB) while still blocking failed downloads.
    return fileBytes < (expectedBytes * 0.85).round();
  }

  bool get isDownloading => _download.isDownloadingAny;

  String get lastLoadedModelName =>
      _hive.getSetting<String>(AppConstants.keyLocalModelName) ?? '';

  bool get canLoadLastModel =>
      lastLoadedModelName.isNotEmpty && isDownloaded(lastLoadedModelName);

  DownloadProgress? getDownloadProgress(String filename) =>
      _download.activeDownloads[filename];

  bool isDownloadingModel(String filename) =>
      _download.activeDownloads.containsKey(filename);

  void setLocalFilter(String filter) {
    if (localFilters.contains(filter)) {
      localFilter.value = filter;
    }
  }

  bool isVisionModel(AiModel model) {
    if (!isLiteRtModel(model)) return false;
    final lower =
        '${model.name} ${model.filename} ${model.description}'.toLowerCase();
    return model.isVision || AiModel.hasVisionMarker(lower);
  }

  bool isUncensoredModel(AiModel model) {
    return AppConstants.isUncensoredModelName(
      '${model.name} ${model.filename} ${model.description}',
    );
  }

  bool isImageModel(AiModel model) {
    final lower = model.filename.toLowerCase();
    return model.runtime == AiModel.runtimeSd ||
        lower.endsWith('.safetensors') ||
        model.template == 'sd';
  }

  bool isLiteRtModel(AiModel model) {
    return model.runtime == AiModel.runtimeLiteRt ||
        model.filename.toLowerCase().endsWith('.litertlm');
  }

  bool isLlamaModel(AiModel model) {
    return model.runtime == AiModel.runtimeLlama ||
        model.filename.toLowerCase().endsWith('.gguf');
  }

  bool isGeneralModel(AiModel model) =>
      !isVisionModel(model) &&
      !isUncensoredModel(model) &&
      !isImageModel(model);

  String modelSizeLabel(AiModel model) {
    final bytes = fileSizes[model.filename] ?? 0;
    if (bytes > 0) return DownloadService.formatBytes(bytes);
    return model.size;
  }

  int _knownModelBytes(AiModel model) {
    final detected = fileSizes[model.filename] ?? 0;
    if (detected > 0) return detected;
    return _declaredModelBytes(model);
  }

  int _declaredModelBytes(AiModel model) {
    final match = RegExp(r'([\d.]+)\s*(GB|MB)', caseSensitive: false)
        .firstMatch(model.size);
    if (match == null) return 0;
    final value = double.tryParse(match.group(1) ?? '') ?? 0;
    final unit = (match.group(2) ?? '').toUpperCase();
    if (unit == 'GB') return (value * 1024 * 1024 * 1024).round();
    if (unit == 'MB') return (value * 1024 * 1024).round();
    return 0;
  }

  String _formatModelSize(String filename) {
    final bytes = fileSizes[filename] ?? 0;
    if (bytes <= 0) return 'Local File';
    return DownloadService.formatBytes(bytes);
  }

  String filenameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final segment = uri?.pathSegments.isNotEmpty == true
        ? uri!.pathSegments.last
        : 'model.gguf';
    final decoded = Uri.decodeComponent(segment.split('?').first);
    if (decoded.toLowerCase().endsWith('.gguf') ||
        decoded.toLowerCase().endsWith('.litertlm') ||
        decoded.toLowerCase().endsWith('.safetensors')) {
      return decoded;
    }
    return '$decoded.gguf';
  }

  Future<String> detectUrlSize(String url) async {
    try {
      final bytes = await _download.getRemoteFileSize(url);
      if (bytes <= 0) return 'Unknown size';
      return DownloadService.formatBytes(bytes);
    } catch (_) {
      return 'Unknown size';
    }
  }

  Future<void> addModelFromUrl({
    required String name,
    required String url,
    String? filename,
    String? description,
    String template = 'chatml',
    String? size,
    bool isVision = false,
  }) async {
    final resolvedFilename = (filename == null || filename.trim().isEmpty)
        ? filenameFromUrl(url)
        : filename.trim();

    final model = AiModel(
      name: name.trim().isEmpty ? resolvedFilename : name.trim(),
      filename: resolvedFilename,
      url: url.trim(),
      size: size == null || size.trim().isEmpty ? 'Unknown size' : size.trim(),
      description: description == null || description.trim().isEmpty
          ? 'Added from custom URL'
          : description.trim(),
      template: template.trim().isEmpty ? 'chatml' : template.trim(),
      runtime: AiModel.runtimeFromFilename(
        resolvedFilename,
        template: template.trim().isEmpty ? 'chatml' : template.trim(),
      ),
      isVision: isVision &&
          AiModel.runtimeFromFilename(
                resolvedFilename,
                template: template.trim().isEmpty ? 'chatml' : template.trim(),
              ) ==
              AiModel.runtimeLiteRt,
      isCustom: true,
    );

    customModels.removeWhere((m) => m.filename == model.filename);
    customModels.add(model);
    availableModels.removeWhere((m) => m.filename == model.filename);
    availableModels.add(model);
    await _saveCustomModels();
  }

  Future<void> downloadModel(AiModel model) async {
    try {
      await _download.downloadModel(
        url: model.url,
        filename: model.filename,
      );
      await refreshDownloaded();
    } catch (e) {
      Get.find<AppLogService>().error('Model download failed', details: e, category: LogCategory.model);
      Get.snackbar('Download Failed', '$e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  /// Saves [model] to the platform's public Downloads folder.
  ///
  /// - Android: delegates to the native DownloadManager bridge
  ///   (`downloadToDownloads`) so the file lands in the phone's public
  ///   Downloads folder and keeps downloading in the background.
  /// - Desktop (Windows/Linux/macOS): downloads with the in-app streaming
  ///   downloader (progress surfaces in the Models tab), then moves the
  ///   finished file into the user's Downloads folder.
  Future<void> downloadModelToDownloads(AiModel model) async {
    if (model.url.trim().isEmpty) {
      Get.snackbar('Download Unavailable', 'This model has no download URL.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    if (Platform.isAndroid) {
      await _downloadToDownloadsAndroid(model);
      return;
    }

    await _downloadToDownloadsDesktop(model);
  }

  Future<void> _downloadToDownloadsAndroid(AiModel model) async {
    try {
      isImporting.value = true;
      importFileName.value = model.filename;
      importStatus.value = 'Starting download...';
      importCopiedBytes.value = 0;
      importTotalBytes.value = 0;
      importBytesPerSecond.value = 0;

      final result =
          await _androidImportChannel.invokeMapMethod<String, dynamic>(
        'downloadToDownloads',
        {'url': model.url, 'filename': model.filename},
      );
      externalDownloadId.value = result?['downloadId'] as int?;
      final filename = result?['filename'] as String? ?? model.filename;
      Get.snackbar(
        'Download Started',
        '$filename is downloading to your Downloads folder.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } on PlatformException catch (e) {
      isImporting.value = false;
      externalDownloadId.value = null;
      Get.find<AppLogService>().error(
        'Download to Downloads failed',
        details: '${e.code}: ${e.message}',
        category: LogCategory.model,
      );
      Get.snackbar('Download Failed', e.message ?? e.code,
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      isImporting.value = false;
      externalDownloadId.value = null;
      Get.find<AppLogService>()
          .error('Download to Downloads failed', details: e);
      Get.snackbar('Download Failed', '$e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  /// Desktop "Save to Downloads": stream into the app models dir first
  /// (reuses pause/resume + validation UI), then move the file out to the
  /// user's Downloads folder so no duplicate multi-GB copy is left behind.
  Future<void> _downloadToDownloadsDesktop(AiModel model) async {
    try {
      isImporting.value = true;
      importFileName.value = model.filename;
      importStatus.value = 'Downloading to Downloads folder...';
      importCopiedBytes.value = 0;
      importTotalBytes.value = 0;
      importBytesPerSecond.value = 0;

      final savedPath = await _download.downloadModel(
        url: model.url,
        filename: model.filename,
      );
      if (savedPath == 'PAUSED') {
        importStatus.value = 'Download paused — resume it from the Models tab.';
        Get.snackbar(
          'Download Paused',
          '${model.filename} will resume from the Models tab.',
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }

      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir == null) {
        // Downloader already placed the file in the app models dir —
        // keep it there as a graceful fallback.
        await refreshDownloaded();
        Get.snackbar(
          'Download Complete',
          '${model.filename} is in the app models folder (Downloads folder unavailable).',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 5),
        );
        return;
      }

      final targetPath =
          await _uniquePath(downloadsDir.path, model.filename);
      try {
        await File(savedPath).rename(targetPath);
      } on FileSystemException {
        // Cross-volume move: fall back to copy + delete.
        await File(savedPath).copy(targetPath);
        await File(savedPath).delete();
      }
      await refreshDownloaded();
      Get.snackbar(
        'Saved to Downloads',
        '${targetPath.split(Platform.pathSeparator).last}\n$targetPath',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 6),
      );
      Get.find<AppLogService>().info(
        'Model saved to Downloads',
        details: targetPath,
        category: LogCategory.model,
      );
    } catch (e) {
      Get.find<AppLogService>().error('Download to Downloads failed',
          details: e, category: LogCategory.model);
      Get.snackbar('Download Failed', '$e',
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      isImporting.value = false;
      importFileName.value = '';
      importStatus.value = '';
      importCopiedBytes.value = 0;
      importTotalBytes.value = 0;
      importBytesPerSecond.value = 0;
    }
  }

  /// Returns a non-colliding file path inside [dirPath] for [filename]
  /// by appending " (1)", " (2)", ... when needed.
  Future<String> _uniquePath(String dirPath, String filename) async {
    var candidate = '$dirPath${Platform.pathSeparator}$filename';
    if (!await File(candidate).exists()) return candidate;
    final dot = filename.lastIndexOf('.');
    final stem = dot > 0 ? filename.substring(0, dot) : filename;
    final ext = dot > 0 ? filename.substring(dot) : '';
    var i = 1;
    while (await File(candidate).exists()) {
      candidate =
          '$dirPath${Platform.pathSeparator}$stem ($i)$ext';
      i++;
    }
    return candidate;
  }

  Future<void> cancelExternalDownload() async {
    if (!Platform.isAndroid) {
      // Desktop "Save to Downloads" runs through the in-app downloader.
      final filename = importFileName.value;
      if (filename.isNotEmpty) {
        try {
          await _download.cancelDownload(filename);
        } catch (e) {
          Get.find<AppLogService>().error('Cancel download failed',
              details: e, category: LogCategory.model);
        }
      }
      externalDownloadId.value = null;
      isImporting.value = false;
      importStatus.value = 'Download cancelled';
      return;
    }
    final id = externalDownloadId.value;
    if (id != null) {
      try {
        await _androidImportChannel.invokeMethod('cancelDownloadToDownloads', {'downloadId': id});
      } catch (e) {
        Get.find<AppLogService>().error('Cancel download failed', details: e, category: LogCategory.model);
      }
      externalDownloadId.value = null;
      isImporting.value = false;
      importStatus.value = 'Download cancelled';
    }
  }

  void pauseDownload(String filename) {
    _download.pauseDownload(filename);
  }

  void resumeDownload(String filename) {
    _download.resumeDownload(filename);
  }

  void cancelDownload(String filename) {
    _download.cancelDownload(filename);
  }

  Future<void> deleteModel(String filename) async {
    await _download.deleteModel(filename);
    await refreshDownloaded();
    // Unload if this was the active model
    if (_inference.loadedModelName.value == filename) {
      await _inference.unloadModel();
    }
  }

  Future<void> loadModel(String filename) async {
    // Desktop (Windows) and Web ship no on-device inference engine yet
    // (llama.cpp / LiteRT natives are Android/iOS only). Fail fast with a
    // clear message instead of letting the user download gigabytes first
    // and then hitting an opaque native error.
    if (!supportsLocalInference) {
      Get.snackbar(
        'Local Models Unavailable',
        'On-device models need the Android app. On this device, use Cloud mode instead.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 5),
      );
      return;
    }
    if (_inference.isLoadingModel.value) {
      Get.snackbar('Model Loading', 'Another model is already loading.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    final path = await _download.modelPath(filename);
    final model =
        availableModels.firstWhereOrNull((m) => m.filename == filename);
    if (_isAuxiliaryImageFile(filename)) {
      Get.snackbar(
        'Helper File',
        '$filename is used internally by image generation and cannot be loaded as a model.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    // Guard: the file must actually exist on this device. Without this the
    // catalog size fallback in _modelFileBytes lets a never-downloaded or
    // deleted model reach the native loader, which fails with an opaque
    // "GGUF model file is missing or unreadable".
    if (!await File(path).exists()) {
      Get.snackbar(
        'Not Downloaded',
        '$filename is not on this device. Download it from the Models tab first.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 5),
      );
      return;
    }
    final isLiteRt = filename.toLowerCase().endsWith('.litertlm') ||
        model?.runtime == AiModel.runtimeLiteRt;
    // Cross-runtime switches are allowed in-place now: the llama.cpp slot
    // pool and the LiteRT session live side by side, and generation picks
    // the engine matching the active model's runtime.
    final fileBytes = await _modelFileBytes(filename, path, model);
    if (model != null && await _isIncompleteCatalogFile(model, fileBytes)) {
      final actual = DownloadService.formatBytes(fileBytes);
      Get.find<AppLogService>().error(
        'Incomplete model file blocked',
        details: '$filename is $actual, expected about ${model.size}',
        category: LogCategory.model,
      );
      Get.snackbar(
        'Incomplete Model File',
        '$filename is only $actual. Delete it and download again.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 6),
      );
      return;
    }
    if (filename.toLowerCase().endsWith('.safetensors') &&
        !await _hasValidSafetensorsHeader(path)) {
      Get.find<AppLogService>().error(
        'Corrupt safetensors file blocked',
        details: '$filename failed safetensors header validation',
        category: LogCategory.model,
      );
      Get.snackbar(
        'Corrupt Model File',
        '$filename did not download correctly. Delete it and download again.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 6),
      );
      return;
    }
    if (isLiteRt && !await _hasLikelyValidLiteRtFile(path, fileBytes)) {
      Get.find<AppLogService>().error(
        'Corrupt LiteRT model file blocked',
        details: '$filename failed LiteRT file validation; size=$fileBytes',
        category: LogCategory.model,
      );
      Get.snackbar(
        'Corrupt Model File',
        '$filename is not a valid LiteRT-LM file. Delete it and download again.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 6),
      );
      return;
    }
    final loadAction = await _confirmModelLoadSafety(
      filename: filename,
      fileBytes: fileBytes,
      isLiteRt: isLiteRt,
    );
    if (loadAction == _ModelLoadAction.cancel) return;
    if (isLiteRt && !await _confirmLiteRtGpuWarning()) return;

    // Switching models mid-reply is allowed: stop the in-flight generation
    // first so the swap does not stall behind it.
    if (_inference.isGenerating.value) {
      await _inference.stopGeneration();
    }

    if (isImageModel(model ??
        AiModel(
          name: filename,
          filename: filename,
          url: '',
          size: '',
          description: '',
          template: '',
        ))) {
      // Auto-download TAESD for fast VAE decode if not present
      String? taesdPath;
      try {
        const taesdFilename = 'taesd.safetensors';
        const taesdUrl = 'https://huggingface.co/madebyollin/taesd/resolve/main/diffusion_pytorch_model.safetensors';
        final hasTaesd = await _download.isModelDownloaded(taesdFilename);
        if (!hasTaesd) {
          print('[ModelController] TAESD not found, downloading...');
          await _download.downloadModel(url: taesdUrl, filename: taesdFilename);
          print('[ModelController] TAESD downloaded successfully');
        } else {
          print('[ModelController] TAESD already present');
        }
        taesdPath = await _download.modelPath(taesdFilename);
      } catch (e) {
        print('[ModelController] TAESD download failed (will use standard VAE): $e');
      }

      // Show loading dialog with live logs
      _showImageModelLoadingDialog(filename);
      final result = await _localImage.loadModel(path, modelName: filename, taesdPath: taesdPath);
      // Close loading dialog
      if (Get.isDialogOpen ?? false) Get.back();

      final isError = !_localImage.isModelLoaded.value;
      if (isError) {
        Get.snackbar(
          'Model Not Loaded',
          result,
          snackPosition: SnackPosition.TOP,
          backgroundColor: const Color(0xFFFF9500).withValues(alpha: 0.15),
          colorText: const Color(0xFFFF9500),
          duration: const Duration(seconds: 6),
          snackStyle: SnackStyle.FLOATING,
          margin: EdgeInsets.fromLTRB(
              16, (Get.overlayContext != null ? MediaQuery.of(Get.overlayContext!).padding.top : 24) + 8, 16, 0),
          borderRadius: 18,
          animationDuration: const Duration(milliseconds: 520),
          forwardAnimationCurve: Curves.easeOutBack,
          reverseAnimationCurve: Curves.easeInCubic,
        );
      } else {
        AppSnackbar.modelSwitched(filename);
      }
    } else {
      final result = await _inference.loadModel(
        path,
        modelName: filename,
        modelRuntime: model?.runtime,
        enableLiteRtVision: model == null ? false : isVisionModel(model),
      );
      if (_inference.isModelLoaded.value) {
        final fallbackToText = result.toLowerCase().contains('text-only');
        _inference.isVisionLoaded.value =
            fallbackToText ? false : (model == null ? false : isVisionModel(model));
        await _settings.setInferenceMode('local');
        AppSnackbar.modelSwitched(filename);
      } else {
        bool showDetails = false;
        Get.dialog(
          StatefulBuilder(
            builder: (context, setState) {
              final friendlyMsg = _getFriendlyErrorMessage(result);
              final isDark = Theme.of(context).brightness == Brightness.dark;
              final detailBg = isDark ? Dt.cardDark : Dt.canvas;
              final detailBorder = isDark ? Dt.pillMutedDark : Dt.hairline;
              
              return AlertDialog(
                backgroundColor: Theme.of(context).dialogTheme.backgroundColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.error.withValues(alpha: isDark ? 0.15 : 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.error_outline_rounded,
                        color: Theme.of(context).colorScheme.error,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Model Load Failed',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        friendlyMsg,
                        style: GoogleFonts.inter(
                          fontSize: 14, 
                          height: 1.5,
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'TROUBLESHOOTING TIPS',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildTipRow(context, Icons.delete_outline_rounded, 'Delete the model and try redownloading it completely.'),
                      _buildTipRow(context, Icons.memory_rounded, 'Ensure your device has at least 2-3 GB of free RAM.'),
                      if (result.toLowerCase().contains('litert') || filename.toLowerCase().endsWith('.litertlm'))
                        _buildTipRow(context, Icons.settings_suggest_rounded, 'Double check if this LiteRT-LM file matches your architecture.'),
                      const SizedBox(height: 12),

                      // Technical Details Toggle Button
                      InkWell(
                        onTap: () => setState(() => showDetails = !showDetails),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                showDetails ? 'Hide Technical Details' : 'Show Technical Details',
                                style: GoogleFonts.inter(
                                  fontSize: 12, 
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              Icon(
                                showDetails ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                size: 16,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ],
                          ),
                        ),
                      ),

                      AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        child: showDetails
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 8),
                                  Container(
                                    constraints: const BoxConstraints(maxHeight: 180),
                                    width: double.maxFinite,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: detailBg,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: detailBorder, width: 1),
                                    ),
                                    child: SingleChildScrollView(
                                      child: SelectableText(
                                        result,
                                        style: GoogleFonts.firaCode(
                                          fontSize: 11,
                                          height: 1.4,
                                          color: isDark ? const Color(0xFFFDA4AF) : const Color(0xFF9F1239),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Get.back(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(
                      'Close',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      }
    }
  }

  Future<int> _modelFileBytes(
    String filename,
    String path,
    AiModel? model,
  ) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.length();
        fileSizes[filename] = bytes;
        return bytes;
      }
    } catch (_) {}
    final cached = fileSizes[filename] ?? 0;
    if (cached > 0) return cached;
    return model == null ? 0 : _knownModelBytes(model);
  }

  Future<bool> _hasValidSafetensorsHeader(String path) async {
    RandomAccessFile? raf;
    try {
      final file = File(path);
      final length = await file.length();
      if (length < 16) return false;
      raf = await file.open();
      final bytes = await raf.read(16);
      if (bytes.length < 16) return false;

      var headerLength = 0;
      for (var i = 0; i < 8; i++) {
        headerLength += bytes[i] << (8 * i);
      }

      if (headerLength <= 2 || headerLength > length - 8) return false;
      if (headerLength > 64 * 1024 * 1024) return false;
      return bytes[8] == 0x7B;
    } catch (_) {
      return false;
    } finally {
      await raf?.close();
    }
  }

  Future<bool> _hasLikelyValidLiteRtFile(String path, int fileBytes) async {
    RandomAccessFile? raf;
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      final length = await file.length();
      if (length < 10 * 1024 * 1024) return false;

      raf = await file.open();
      final bytes = await raf.read(16);
      if (bytes.length < 8) return false;

      // Verify LiteRT-LM magic identifier 'LITERTLM' at bytes 0-7
      final hasLmLiteRt = bytes[0] == 0x4C && // 'L'
          bytes[1] == 0x49 && // 'I'
          bytes[2] == 0x54 && // 'T'
          bytes[3] == 0x45 && // 'E'
          bytes[4] == 0x52 && // 'R'
          bytes[5] == 0x54 && // 'T'
          bytes[6] == 0x4C && // 'L'
          bytes[7] == 0x4D; // 'M'

      if (hasLmLiteRt) {
        return true;
      }

      // Note: We intentionally DO NOT allow standard TFLite models starting with 'TFL3' at offset 4
      // if they lack the 'LITERTLM' container header, because the native LiteRT-LM engine 
      // strictly expects the .litertlm conversational bundle structure and will crash with a
      // SIGABRT native assert check failure if it is not present.
      return false;
    } catch (_) {
      return false;
    } finally {
      await raf?.close();
    }
  }

  /// Gate a local model load on available memory.
  ///
  /// Switching models is a one-tap action: the previously loaded model is freed
  /// automatically, so no dialog is shown for an ordinary swap. A prompt only
  /// appears when memory is genuinely too tight to load safely.
  Future<_ModelLoadAction> _confirmModelLoadSafety({
    required String filename,
    required int fileBytes,
    required bool isLiteRt,
  }) async {
    final availableRamGb = await _refreshAvailableRamGb();

    final availableBytes = (availableRamGb * 1024 * 1024 * 1024).round();
    final hasMeasuredMemory = availableBytes > 0 && fileBytes > 0;
    // Include KV cache estimate (contextSize * 2.5KB) for more accurate guard
    int estimatedNeed = fileBytes;
    try {
      if (Get.isRegistered<SettingsController>() && Get.isRegistered<DeviceInfoService>()) {
        final ctx = Get.find<SettingsController>().effectiveContextSize;
        final dev = Get.find<DeviceInfoService>();
        estimatedNeed = fileBytes + dev.estimatedKvBytes(ctx);
      }
    } catch (_) {}
    final isCriticallyLow = hasMeasuredMemory &&
        (availableBytes < estimatedNeed || _isLowMemoryBytes(availableBytes));

    // Enough headroom (or nothing measurable to warn about) — load straight
    // away. Any resident model is freed by InferenceService.loadModel.
    if (!isCriticallyLow) return _ModelLoadAction.continueLoad;

    final modelLabel = fileBytes > 0
        ? DownloadService.formatWholeMb(fileBytes)
        : 'Unknown size';
    final ramLabel = availableBytes > 0
        ? DownloadService.formatWholeMb(availableBytes)
        : 'Unknown';
    final lower = filename.toLowerCase();
    final runtimeLabel = isLiteRt
        ? 'LiteRT-LM'
        : lower.endsWith('.gguf')
            ? 'GGUF'
            : lower.endsWith('.safetensors')
                ? 'Image model'
                : 'Local model';

    final result = await Get.dialog<_ModelLoadAction>(
      AlertDialog(
        title: const Text('Restart recommended'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(filename),
            const SizedBox(height: 12),
            Text('Runtime: $runtimeLabel'),
            Text('Available RAM: $ramLabel'),
            Text('Model size: $modelLabel'),
            const SizedBox(height: 12),
            const Text(
              'Available RAM is lower than recommended. This can crash the app if Android cannot reserve enough memory.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: _ModelLoadAction.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Get.back(result: _ModelLoadAction.cancel);
              try {
                await _androidImportChannel.invokeMethod('restartApp');
              } catch (_) {
                SystemNavigator.pop();
              }
            },
            child: const Text('Restart app'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _refreshAvailableRamGb();
              Get.back(result: _ModelLoadAction.continueLoad);
            },
            child: const Text('Load anyway'),
          ),
        ],
      ),
      barrierDismissible: false,
    );
    return result ?? _ModelLoadAction.cancel;
  }

  Future<bool> _confirmLiteRtGpuWarning() async {
    final mode = _settings.liteRtPerformanceMode.value;
    if (mode == 'cpu_safe') return true;

    final accepted = _hive.getSetting<bool>(
          AppConstants.keyLiteRtGpuWarningAccepted,
          defaultValue: false,
        ) ??
        false;
    if (accepted) return true;

    final modeLabel = mode == 'gpu_fast' ? 'GPU Fast' : 'Auto Fast';
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: Text('$modeLabel LiteRT speed'),
        content: const Text(
          'GPU can make LiteRT models much faster, closer to Edge Gallery speed. '
          'On some phones GPU/OpenCL can crash the app while loading. '
          'If that happens, Auto Fast will use CPU on the next load.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Continue'),
          ),
        ],
      ),
      barrierDismissible: false,
    );

    if (confirmed == true) {
      await _hive.setSetting(AppConstants.keyLiteRtGpuWarningAccepted, true);
      return true;
    }
    return false;
  }

  bool _isLowMemoryBytes(int bytes) => bytes < 768 * 1024 * 1024;

  Future<double> _refreshAvailableRamGb() async {
    try {
      final device = Get.find<DeviceInfoService>();
      await device.refreshMemoryInfo();
      return device.availableRamGB.value;
    } catch (_) {
      return 0;
    }
  }

  void _showImageModelLoadingDialog(String filename) {
    final localImage = Get.find<LocalImageService>();
    Get.dialog(
      Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Get.isDarkMode ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 20),
              Text(
                'Loading $filename',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Obx(() {
                final log = localImage.latestLog.value;
                if (log.isEmpty) {
                  return const Text(
                    'Initializing model...',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  );
                }
                return Text(
                  log,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                );
              }),
            ],
          ),
        ),
      ),
      barrierDismissible: false,
    );
  }

  Future<void> unloadModel() async {
    await _inference.unloadModel();
    await _localImage.unloadModel();
  }

  Future<void> importModelFromStorage() async {
    if (isImporting.value) {
      Get.snackbar(
          'Import in Progress', 'Wait for the current import to finish.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    if (Platform.isAndroid) {
      await _importModelWithAndroidPicker();
      return;
    }

    String? partialImportPath;
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.any,
        withData: false,
        withReadStream: true,
      );

      if (result != null) {
        final picked = result.files.single;
        final filename = picked.name;
        final lower = filename.toLowerCase();

        if (!lower.endsWith('.gguf') &&
            !lower.endsWith('.litertlm') &&
            !lower.endsWith('.safetensors')) {
          Get.snackbar('Unsupported Model',
              'Only .gguf, .litertlm, and .safetensors files can be imported.',
              snackPosition: SnackPosition.BOTTOM);
          return;
        }

        final file = picked.path == null ? null : File(picked.path!);
        final totalBytes = picked.size > 0
            ? picked.size
            : file == null
                ? 0
                : await file.length();
        if (totalBytes <= 0) {
          Get.snackbar('Import Failed', 'The selected file is empty.',
              snackPosition: SnackPosition.BOTTOM);
          return;
        }

        final sourceStream = picked.readStream ?? file?.openRead();
        if (sourceStream == null) {
          Get.snackbar(
            'Import Failed',
            'Unable to read the selected file. Try selecting it from local storage.',
            snackPosition: SnackPosition.BOTTOM,
          );
          return;
        }

        final modelsDir = await _download.modelsDir;
        final destPath = '$modelsDir/$filename';
        final partPath = '$destPath.part';
        partialImportPath = partPath;
        final destFile = File(destPath);
        final partFile = File(partPath);
        var shouldReplace = false;

        if (await destFile.exists()) {
          final replace = await _confirmReplace(filename);
          if (!replace) return;
          shouldReplace = true;
        }

        isImporting.value = true;
        importFileName.value = filename;
        importStatus.value = 'Copying to app storage...';
        importCopiedBytes.value = 0;
        importTotalBytes.value = totalBytes;
        importBytesPerSecond.value = 0;

        if (await partFile.exists()) {
          await partFile.delete();
        }

        await _copyWithProgress(sourceStream, partFile);
        if (shouldReplace && await destFile.exists()) {
          await destFile.delete();
        }
        await partFile.rename(destPath);
        fileSizes[filename] = await File(destPath).length();

        await refreshDownloaded();
        localFilter.value = 'downloaded';
        importStatus.value = 'Import complete';
        Get.snackbar('Import Successful', 'Model $filename imported.',
            snackPosition: SnackPosition.BOTTOM);
      }
    } catch (e) {
      if (partialImportPath != null) {
        final partialFile = File(partialImportPath);
        if (await partialFile.exists()) {
          await partialFile.delete();
        }
      }
      Get.find<AppLogService>().error('Model import failed', details: e, category: LogCategory.model);
      Get.snackbar('Import Failed', '$e', snackPosition: SnackPosition.BOTTOM);
    } finally {
      isImporting.value = false;
      importFileName.value = '';
      importStatus.value = '';
      importCopiedBytes.value = 0;
      importTotalBytes.value = 0;
      importBytesPerSecond.value = 0;
    }
  }

  Future<void> _importModelWithAndroidPicker() async {
    try {
      isImporting.value = true;
      importFileName.value = '';
      importStatus.value = 'Select a model file...';
      importCopiedBytes.value = 0;
      importTotalBytes.value = 0;
      importBytesPerSecond.value = 0;

      final result =
          await _androidImportChannel.invokeMapMethod<String, dynamic>(
        'pickAndImportModel',
        {'modelsDir': await _download.modelsDir},
      );

      if (result?['cancelled'] == true) return;

      final filename = result?['filename'] as String?;
      if (filename != null && filename.isNotEmpty) {
        fileSizes[filename] = (result?['bytes'] as num?)?.toInt() ??
            await _download.getModelSize(filename);
        await refreshDownloaded();
        localFilter.value = 'downloaded';
        Get.snackbar('Import Successful', 'Model $filename imported.',
            snackPosition: SnackPosition.BOTTOM);
      }
    } on PlatformException catch (e) {
        Get.find<AppLogService>().error(
          'Android model import failed',
          details: '${e.code}: ${e.message}',
          category: LogCategory.model,
        );
      Get.snackbar('Import Failed', e.message ?? e.code,
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.find<AppLogService>()
          .error('Android model import failed', details: e, category: LogCategory.model);
      Get.snackbar('Import Failed', '$e', snackPosition: SnackPosition.BOTTOM);
    } finally {
      isImporting.value = false;
      importFileName.value = '';
      importStatus.value = '';
      importCopiedBytes.value = 0;
      importTotalBytes.value = 0;
      importBytesPerSecond.value = 0;
    }
  }

  Future<void> _copyWithProgress(
    Stream<List<int>> source,
    File destination,
  ) async {
    final startedAt = DateTime.now();
    final sink = destination.openWrite();
    try {
      await for (final chunk in source) {
        sink.add(chunk);
        importCopiedBytes.value += chunk.length;
        final elapsed =
            DateTime.now().difference(startedAt).inMilliseconds / 1000;
        if (elapsed > 0) {
          importBytesPerSecond.value = importCopiedBytes.value / elapsed;
        }
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      await sink.close();
      if (await destination.exists()) {
        await destination.delete();
      }
      rethrow;
    }
  }

  Future<bool> _confirmReplace(String filename) async {
    final result = await Get.dialog<bool>(
      Builder(
        builder: (context) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          
          return AlertDialog(
            backgroundColor: Theme.of(context).dialogTheme.backgroundColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: isDark ? 0.15 : 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.copy_all_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Model Already Exists',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
            content: Text(
              'A model file named "$filename" is already imported in your local app storage. Would you like to replace it?',
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.5,
                color: isDark ? Colors.white70 : Colors.black87,
                fontWeight: FontWeight.w500,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Get.back(result: false),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Get.back(result: true),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                ),
                child: Text(
                  'Replace File',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    return result ?? false;
  }

  Future<void> _deletePartialImports() async {
    try {
      final dir = Directory(await _download.modelsDir);
      if (!await dir.exists()) return;
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.toLowerCase().endsWith('.part')) {
          await entity.delete();
        }
      }
    } catch (_) {}
  }

  String _getFriendlyErrorMessage(String rawError) {
    final lower = rawError.toLowerCase();
    if (lower.contains('unknown model architecture') ||
        lower.contains('unsupported model architecture')) {
      return 'This GGUF uses a model architecture that is not supported by the bundled llama.cpp runtime. Update the app runtime or try a GGUF exported for a supported architecture.';
    }
    if (lower.contains('missing key') ||
        lower.contains('failed to load gguf split')) {
      return 'This appears to be a split GGUF model, but one or more required model files are missing. Import every split into the same folder before loading it.';
    }
    if (lower.contains('failed to load model from buffer') ||
        lower.contains('invalid_argument') ||
        lower.contains('invalid gguf') ||
        lower.contains('missing or unreadable') ||
        lower.contains('incomplete') ||
        lower.contains('corrupt')) {
      return 'The model file appears to be incomplete or corrupted. This usually happens when the download is interrupted or the file is invalid.';
    }
    if (lower.contains('out of memory') ||
        lower.contains('allocate') ||
        lower.contains('oom') ||
        lower.contains('cannot allocate')) {
      return 'Your device ran out of memory (RAM) trying to load this model. Mobile devices have strict memory limits; try using a smaller or more highly quantized model (e.g., 1B or 3B parameters, q4_k_m quantized).';
    }
    if (lower.contains('opencl') ||
        lower.contains('vulkan') ||
        lower.contains('opengl') ||
        lower.contains('gpu') ||
        lower.contains('cl_') ||
        lower.contains('driver')) {
      return 'A hardware or GPU driver error occurred while initializing the model. Try disabling GPU acceleration or switching to CPU-only inference in Settings.';
    }
    return 'The native AI engine encountered an unexpected error while loading the model. Please check the technical details below for more information.';
  }

  Widget _buildTipRow(BuildContext context, IconData icon, String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: isDark ? 0.15 : 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.45,
                color: isDark ? Colors.white70 : Colors.black87,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
