import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import '../controllers/model_controller.dart';

import 'download_native.dart' if (dart.library.html) 'download_web.dart'
    as platform_dl;

/// State for an individual download.
class DownloadProgress {
  final String filename;
  final RxDouble progress = 0.0.obs;
  final RxInt downloadedBytes = 0.obs;
  final RxInt totalBytes = 0.obs;
  final RxDouble bytesPerSecond = 0.0.obs;
  final RxBool isPaused = false.obs;
  final DateTime startedAt = DateTime.now();

  DownloadProgress({required this.filename});

  Duration? get eta {
    final speed = bytesPerSecond.value;
    final total = totalBytes.value;
    if (speed <= 0 || total <= 0) return null;
    final remaining = total - downloadedBytes.value;
    if (remaining <= 0) return Duration.zero;
    return Duration(seconds: (remaining / speed).ceil());
  }
}

/// Service for downloading GGUF model files with progress tracking.
/// On web: downloads are not supported (models are too large for browser).
class DownloadService extends GetxService with WidgetsBindingObserver {
  /// Currently active downloads.
  final activeDownloads = <String, DownloadProgress>{}.obs;
  final _nativeDownloadIds = <String, int>{};

  bool get isDownloadingAny => activeDownloads.isNotEmpty;

  /// Whether the platform supports downloading models.
  bool get supportsDownload => !kIsWeb;

  Future<String> get modelsDir async => await platform_dl.getModelsDir();

  Future<String> modelPath(String filename) async {
    return '${await modelsDir}/$filename';
  }

  Future<bool> isModelDownloaded(String filename) async {
    if (kIsWeb) return false;
    return await platform_dl.isModelDownloaded(await modelPath(filename));
  }

  Future<List<String>> getDownloadedModels() async {
    if (kIsWeb) return [];
    return await platform_dl.getDownloadedModels(await modelsDir);
  }

  Future<int> getModelSize(String filename) async {
    if (kIsWeb) return 0;
    return await platform_dl.getModelSize(await modelPath(filename));
  }

  Future<int> getRemoteFileSize(String url, {String? authToken}) async {
    if (kIsWeb) return 0;
    return await platform_dl.getRemoteFileSize(url, authToken: authToken);
  }

  @override
  void onInit() {
    super.onInit();

    if (!kIsWeb && Platform.isAndroid) {
      WidgetsBinding.instance.addObserver(this);

      // Initial reconciliation on startup
      reconcileActiveDownloads();

      // Permanent channel progress listener
      const MethodChannel('com.aichat.ai_chat/model_import')
          .setMethodCallHandler((call) async {
        if (call.method == 'importProgress') {
          final data = Map<String, dynamic>.from(call.arguments as Map);
          final filename = data['filename'] as String;
          final downloaded = (data['copiedBytes'] as num).toInt();
          final total = (data['totalBytes'] as num).toInt();
          final speed = (data['bytesPerSecond'] as num).toDouble();
          final status = data['status'] as String;

          var progress = activeDownloads[filename];
          if (progress == null &&
              (status == 'Downloading...' ||
                  status == 'Downloading to phone...' ||
                  status.startsWith('Importing'))) {
            progress = DownloadProgress(filename: filename);
            activeDownloads[filename] = progress;
          }
          if (progress != null) {
            progress.downloadedBytes.value = downloaded;
            progress.totalBytes.value = total;
            progress.bytesPerSecond.value = speed;
            if (total > 0) {
              progress.progress.value = downloaded / total;
            }

            if (status == 'Download complete') {
              activeDownloads.remove(filename);
              _nativeDownloadIds.remove(filename);
              // Trigger reload
              try {
                Get.find<ModelController>().refreshDownloaded();
              } catch (_) {}
            } else if (status.startsWith('Download failed') ||
                status == 'Download cancelled') {
              activeDownloads.remove(filename);
              _nativeDownloadIds.remove(filename);
            }
          }

          // Also update ModelController import state in real-time if it is currently importing
          try {
            final modelCtrl = Get.find<ModelController>();
            if (modelCtrl.isImporting.value) {
              final isPhoneDownload =
                  modelCtrl.importStatus.value.contains('phone') ||
                      modelCtrl.importStatus.value.contains('Starting');

              modelCtrl.importFileName.value = filename;
              modelCtrl.importStatus.value = status;
              modelCtrl.importCopiedBytes.value = downloaded;
              modelCtrl.importTotalBytes.value = total;
              modelCtrl.importBytesPerSecond.value = speed;

              if (status == 'Download complete' ||
                  status.startsWith('Download failed') ||
                  status == 'Download cancelled') {
                if (status == 'Download complete' && isPhoneDownload) {
                  Get.snackbar(
                    'Saved to Downloads',
                    'Import this file to use it in the app.',
                    snackPosition: SnackPosition.BOTTOM,
                    duration: const Duration(seconds: 5),
                  );
                }
                Future.delayed(const Duration(seconds: 3), () {
                  if (modelCtrl.importStatus.value == status) {
                    modelCtrl.isImporting.value = false;
                    modelCtrl.importFileName.value = '';
                    modelCtrl.importStatus.value = '';
                  }
                });
              }
            }
          } catch (_) {}
        }
        return null;
      });
    }
  }

  @override
  void onClose() {
    if (!kIsWeb && Platform.isAndroid) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      reconcileActiveDownloads();
    }
  }

  Future<void> reconcileActiveDownloads() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final list = await platform_dl.getActiveNativeDownloads();
      final recoveredFilenames = <String>{};
      for (final item in list) {
        final id = item['downloadId'] as int;
        final filename = item['filename'] as String;
        final downloaded = item['downloaded'] as int;
        final total = item['total'] as int;
        final status = item['status'] as String;
        recoveredFilenames.add(filename);

        _nativeDownloadIds[filename] = id;

        final progress =
            activeDownloads[filename] ?? DownloadProgress(filename: filename);
        progress.downloadedBytes.value = downloaded;
        progress.totalBytes.value = total;
        progress.bytesPerSecond.value = 0;
        progress.progress.value = total > 0 ? downloaded / total : 0;
        progress.isPaused.value = status == 'Paused';
        if (!activeDownloads.containsKey(filename)) {
          activeDownloads[filename] = progress;
        }
      }

      // Remove UI entries whose native DownloadManager jobs no longer exist.
      final staleFilenames = _nativeDownloadIds.keys
          .where((filename) => !recoveredFilenames.contains(filename))
          .toList();
      for (final filename in staleFilenames) {
        _nativeDownloadIds.remove(filename);
        activeDownloads.remove(filename);
      }
    } catch (e) {
      print('[DownloadService] Failed to reconcile active downloads: $e');
    }
  }

  Future<String> downloadModel({
    required String url,
    required String filename,
    String? authToken,
  }) async {
    if (kIsWeb) return 'ERROR: Downloading models is not supported on web.';

    final downloadProgress = DownloadProgress(filename: filename);
    activeDownloads[filename] = downloadProgress;

    if (Platform.isAndroid) {
      try {
        final modelsDirectory = await modelsDir;
        final result = await platform_dl.startNativeDownload(
          url: url,
          filename: filename,
          modelsDir: modelsDirectory,
        );
        if (result != null) {
          final id = result['downloadId'] as int;
          _nativeDownloadIds[filename] = id;
          return 'NATIVE_BACKGROUND_STARTED';
        }
        throw Exception('Native download failed to start.');
      } catch (e) {
        activeDownloads.remove(filename);
        rethrow;
      }
    } else {
      // Fallback for iOS/Desktop using standard Dio download
      final savePath = await modelPath(filename);
      try {
        final result = await platform_dl.downloadModel(
          url: url,
          savePath: savePath,
          authToken: authToken,
          onProgress: (received, total) {
            downloadProgress.downloadedBytes.value = received;
            downloadProgress.totalBytes.value = total;
            final elapsed = DateTime.now()
                .difference(downloadProgress.startedAt)
                .inMilliseconds;
            if (elapsed > 0) {
              downloadProgress.bytesPerSecond.value =
                  received / (elapsed / 1000);
            }
            if (total > 0) {
              downloadProgress.progress.value = received / total;
            }
          },
        );
        activeDownloads.remove(filename);
        return result;
      } catch (e) {
        activeDownloads.remove(filename);
        rethrow;
      }
    }
  }

  void pauseDownload(String filename) {
    final nativeId = _nativeDownloadIds[filename];
    if (nativeId != null && Platform.isAndroid) {
      platform_dl.cancelNativeDownload(
          downloadId: nativeId, filename: filename);
      activeDownloads.remove(filename);
      _nativeDownloadIds.remove(filename);
    } else {
      platform_dl.pauseDownload(filename);
      activeDownloads[filename]?.isPaused.value = true;
    }
  }

  Future<void> deleteModel(String filename) async {
    if (kIsWeb) return;
    final nativeId = _nativeDownloadIds[filename];
    if (nativeId != null && Platform.isAndroid) {
      await platform_dl.cancelNativeDownload(
          downloadId: nativeId, filename: filename);
      _nativeDownloadIds.remove(filename);
    }
    await platform_dl.deleteModel(await modelPath(filename));
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String formatWholeMb(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = (bytes / (1024 * 1024)).round().clamp(1, 1 << 31);
    return '$mb MB';
  }

  static String formatSpeed(double bytesPerSecond) {
    return '${formatBytes(bytesPerSecond.round())}/s';
  }

  static String formatDuration(Duration? duration) {
    if (duration == null) return '--';
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    }
    if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s';
    }
    return '${duration.inSeconds}s';
  }
}
