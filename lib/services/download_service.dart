import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
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
  String? url;
  String? authToken;

  DownloadProgress({required this.filename, this.url, this.authToken});

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

  /// Persisted metadata for paused downloads (survives app restarts).
  final _pausedRecords = <String, Map<String, dynamic>>{};
  String? _pausedStorePath;

  Future<void> _loadPausedRecords() async {
    if (kIsWeb) return;
    if (_pausedStorePath != null) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _pausedStorePath = '${dir.path}/paused_downloads.json';
      final f = File(_pausedStorePath!);
      if (await f.exists()) {
        final decoded = jsonDecode(await f.readAsString());
        if (decoded is Map) {
          decoded.forEach((k, v) {
            if (v is Map) _pausedRecords[k.toString()] = Map<String, dynamic>.from(v);
          });
        }
      }
    } catch (e) {
      print('[DownloadService] Failed to load paused downloads: $e');
    }
  }

  Future<void> _savePausedRecords() async {
    if (kIsWeb) return;
    try {
      await _loadPausedRecords();
      final f = File(_pausedStorePath!);
      await f.writeAsString(jsonEncode(_pausedRecords), flush: true);
    } catch (e) {
      print('[DownloadService] Failed to save paused downloads: $e');
    }
  }

  void _updateProgress(
      DownloadProgress dp, int received, int total, double bps) {
    dp.downloadedBytes.value = received;
    if (total > 0) dp.totalBytes.value = total;
    dp.bytesPerSecond.value = bps;
    if (total > 0) {
      dp.progress.value = (received / total).clamp(0.0, 1.0);
    }
  }

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
                  status == 'Paused' ||
                  status.startsWith('Importing'))) {
            progress = DownloadProgress(filename: filename);
            activeDownloads[filename] = progress;
          }
          if (progress != null) {
            progress.downloadedBytes.value = downloaded;
            progress.totalBytes.value = total;
            progress.bytesPerSecond.value = speed;
            if (total > 0) {
              progress.progress.value = (downloaded / total).clamp(0.0, 1.0);
            }
            if (status == 'Paused') {
              progress.isPaused.value = true;
            } else if (status.startsWith('Downloading')) {
              progress.isPaused.value = false;
            }

            if (status == 'Download complete') {
              activeDownloads.remove(filename);
              _nativeDownloadIds.remove(filename);
              _nativeStreams.remove(filename);
              // Trigger reload
              try {
                Get.find<ModelController>().refreshDownloaded();
              } catch (_) {}
            } else if (status.startsWith('Download failed') ||
                status == 'Download cancelled') {
              // Keep the card when the user intentionally paused — the
              // native monitor reports "cancelled" right after a pause.
              final wasPaused =
                  activeDownloads[filename]?.isPaused.value ?? false;
              if (!wasPaused) {
                activeDownloads.remove(filename);
                _nativeDownloadIds.remove(filename);
                _nativeStreams.remove(filename);
              }
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

      // Merge native foreground-service downloads (Running/Paused/Failed).
      if (!kIsWeb && Platform.isAndroid) {
        try {
          final streams = await platform_dl.getNativeStreamDownloads();
          for (final s in streams) {
            final fn = s['filename'] as String?;
            if (fn == null || fn.isEmpty) continue;
            final status = (s['status'] as String?) ?? 'Running';
            if (status == 'Running') {
              _nativeStreams.add(fn);
            } else {
              _nativeStreams.remove(fn);
            }
            final url = s['url'] as String?;
            if (url == null || url.isEmpty) continue;
            final downloaded = (s['downloaded'] as num?)?.toInt() ?? 0;
            final total = (s['total'] as num?)?.toInt() ?? 0;
            var dp = activeDownloads[fn];
            dp ??= DownloadProgress(filename: fn, url: url);
            dp.url ??= url;
            dp.downloadedBytes.value = downloaded;
            if (total > 0) {
              dp.totalBytes.value = total;
              dp.progress.value = (downloaded / total).clamp(0.0, 1.0);
            }
            // Native Failed entries surface as paused so the user can retry.
            dp.isPaused.value = status != 'Running';
            activeDownloads[fn] = dp;
            _pausedRecords[fn] = {
              'url': url,
              'authToken': dp.authToken,
              'downloaded': downloaded,
              'total': total,
            };
          }
          await _savePausedRecords();
        } catch (e) {
          print('[DownloadService] stream reconcile failed: $e');
        }
      }

      // Restore paused downloads persisted from previous sessions so the
      // Resume buttons survive an app restart.
      await _loadPausedRecords();
      for (final entry in _pausedRecords.entries) {
        final filename = entry.key;
        if (_nativeDownloadIds.containsKey(filename)) continue;
        if (activeDownloads.containsKey(filename)) continue;
        final url = entry.value['url'] as String?;
        if (url == null || url.isEmpty) continue;
        final restored = DownloadProgress(
          filename: filename,
          url: url,
          authToken: entry.value['authToken'] as String?,
        )..isPaused.value = true;
        final downloaded = (entry.value['downloaded'] as num?)?.toInt() ?? 0;
        final total = (entry.value['total'] as num?)?.toInt() ?? 0;
        restored.downloadedBytes.value = downloaded;
        restored.totalBytes.value = total;
        if (total > 0) {
          restored.progress.value = (downloaded / total).clamp(0.0, 1.0);
        }
        activeDownloads[filename] = restored;
      }

      // ── Cleanup: remove stale paused records for files that are now fully downloaded ──
      // Fixes "download completed but still shows downloading → resume shows already downloaded".
      final completed = <String>[];
      for (final e in _pausedRecords.entries.toList()) {
        final fn = e.key;
        final total = (e.value['total'] as num?)?.toInt() ?? 0;
        final downloaded = (e.value['downloaded'] as num?)?.toInt() ?? 0;
        final isProgressDone = total > 0 && downloaded >= (total * 0.99);
        bool fileDone = false;
        try {
          fileDone = await isModelDownloaded(fn);
        } catch (_) {}
        if (fileDone || isProgressDone) {
          // Double-check file actually exists before discarding.
          if (fileDone) {
            completed.add(fn);
            activeDownloads.remove(fn);
            _nativeStreams.remove(fn);
          } else if (isProgressDone) {
            // Progress says done but file not yet visible (rename pending) — poll once more.
            try {
              if (await isModelDownloaded(fn)) {
                completed.add(fn);
                activeDownloads.remove(fn);
                _nativeStreams.remove(fn);
              }
            } catch (_) {}
          }
        } else {
          // If file is now visible even with stale progress, also clear.
          try {
            if (await isModelDownloaded(fn)) {
              completed.add(fn);
              activeDownloads.remove(fn);
            }
          } catch (_) {}
        }
      }
      if (completed.isNotEmpty) {
        for (final fn in completed) {
          _pausedRecords.remove(fn);
        }
        await _savePausedRecords();
        try {
          Get.find<ModelController>().refreshDownloaded();
        } catch (_) {}
      }
    } catch (e) {
      print('[DownloadService] Failed to reconcile active downloads: $e');
    }
  }

  /// Filenames owned by the native foreground-service downloader.
  final _nativeStreams = <String>{};

  Future<String> downloadModel({
    required String url,
    required String filename,
    String? authToken,
  }) async {
    if (kIsWeb) return 'ERROR: Downloading models is not supported on web.';

    final downloadProgress = DownloadProgress(
      filename: filename,
      url: url,
      authToken: authToken,
    );
    activeDownloads[filename] = downloadProgress;

    // Android → native foreground service (keeps downloading after the
    // app is closed; pause/resume preserve the .part file byte-exact).
    if (!kIsWeb && Platform.isAndroid) {
      final ok = await platform_dl.startNativeStreamDownload(
        url: url,
        filename: filename,
        modelsDir: await modelsDir,
      );
      if (ok != null) {
        _nativeStreams.add(filename);
        await _loadPausedRecords();
        _pausedRecords.remove(filename);
        await _savePausedRecords();
        return 'NATIVE_STREAM_STARTED';
      }
      // Service failed to start — fall through to in-app streaming.
    }

    final savePath = await modelPath(filename);
    try {
      // Resumable streaming download (HTTP Range based).
      final result = await platform_dl.streamDownload(
        url: url,
        savePath: savePath,
        authToken: authToken,
        onProgress: (received, total, bps) =>
            _updateProgress(downloadProgress, received, total, bps),
      );
      if (result == 'PAUSED') {
        // Entry stays visible with the Resume button; pauseDownload()
        // persists the record.
        return 'PAUSED';
      }
      activeDownloads.remove(filename);
      _pausedRecords.remove(filename);
      await _savePausedRecords();
      try {
        Get.find<ModelController>().refreshDownloaded();
      } catch (_) {}
      return result;
    } catch (e) {
      activeDownloads.remove(filename);
      rethrow;
    }
  }

  Future<void> pauseDownload(String filename) async {
    final dp = activeDownloads[filename];
    if (dp == null) return;

    // Mark paused BEFORE cancelling so late "cancelled" native events
    // don't wipe the card.
    dp.isPaused.value = true;
    dp.bytesPerSecond.value = 0;
    platform_dl.cancelStreamDownload(filename);

    if (!kIsWeb && Platform.isAndroid) {
      if (_nativeStreams.remove(filename)) {
        platform_dl.pauseNativeStream(filename);
      }
      // Legacy in-flight native DownloadManager job from an older session.
      final nativeId = _nativeDownloadIds[filename];
      if (nativeId != null) {
        await platform_dl.cancelNativeDownload(
            downloadId: nativeId, filename: filename);
        _nativeDownloadIds.remove(filename);
        dp.downloadedBytes.value = 0;
      }
    }

    await _loadPausedRecords();
    _pausedRecords[filename] = {
      'url': dp.url,
      'authToken': dp.authToken,
      'downloaded': dp.downloadedBytes.value,
      'total': dp.totalBytes.value,
    };
    await _savePausedRecords();
  }

  Future<void> resumeDownload(String filename) async {
    var dp = activeDownloads[filename];
    await _loadPausedRecords();
    final record = _pausedRecords[filename];

    if (dp == null) {
      dp = DownloadProgress(
        filename: filename,
        url: record?['url'] as String?,
        authToken: record?['authToken'] as String?,
      );
      activeDownloads[filename] = dp;
    }
    dp.url ??= record?['url'] as String?;
    dp.authToken ??= record?['authToken'] as String?;

    if (dp.url == null || dp.url!.isEmpty) {
      Get.snackbar('Resume unavailable',
          'No source URL stored for this download.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    final recTotal = (record?['total'] as num?)?.toInt() ?? 0;
    if (recTotal > 0 && dp.totalBytes.value <= 0) dp.totalBytes.value = recTotal;

    dp.isPaused.value = false;
    dp.bytesPerSecond.value = 0;

    // Android → hand back to the native foreground service; it picks up
    // the existing .part file and continues via a Range request.
    if (!kIsWeb && Platform.isAndroid) {
      final ok = await platform_dl.startNativeStreamDownload(
        url: dp.url!,
        filename: filename,
        modelsDir: await modelsDir,
      );
      if (ok != null) {
        _nativeStreams.add(filename);
        return;
      }
    }

    final savePath = await modelPath(filename);
    try {
      // In-app streaming fallback resumes from the .part file too.
      final result = await platform_dl.streamDownload(
        url: dp.url!,
        savePath: savePath,
        authToken: dp.authToken,
        onProgress: (received, total, bps) =>
            _updateProgress(dp!, received, total, bps),
      );
      if (result == 'PAUSED') return;
      activeDownloads.remove(filename);
      _nativeStreams.remove(filename);
      _pausedRecords.remove(filename);
      await _savePausedRecords();
      try {
        Get.find<ModelController>().refreshDownloaded();
      } catch (_) {}
    } catch (e) {
      dp.isPaused.value = true;
      await _loadPausedRecords();
      _pausedRecords[filename] = {
        'url': dp.url,
        'authToken': dp.authToken,
        'downloaded': dp.downloadedBytes.value,
        'total': dp.totalBytes.value,
      };
      await _savePausedRecords();
      Get.snackbar('Resume failed', '$e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> cancelDownload(String filename) async {
    platform_dl.cancelStreamDownload(filename);
    if (!kIsWeb && Platform.isAndroid) {
      if (_nativeStreams.remove(filename)) {
        platform_dl.cancelNativeStream(filename);
      }
      final nativeId = _nativeDownloadIds[filename];
      if (nativeId != null) {
        await platform_dl.cancelNativeDownload(
            downloadId: nativeId, filename: filename);
        _nativeDownloadIds.remove(filename);
      }
    }
    platform_dl.pauseDownload(filename);
    activeDownloads.remove(filename);
    await _loadPausedRecords();
    _pausedRecords.remove(filename);
    await _savePausedRecords();
    if (!kIsWeb) {
      try {
        final partFile = File('${await modelPath(filename)}.part');
        if (await partFile.exists()) await partFile.delete();
      } catch (_) {}
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
    await _loadPausedRecords();
    _pausedRecords.remove(filename);
    await _savePausedRecords();
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
