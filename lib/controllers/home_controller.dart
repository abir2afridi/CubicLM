import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../services/hive_service.dart';
import '../services/inference_service.dart';
import '../services/local_image_service.dart';
import '../services/app_log_service.dart';
import '../services/device_info_service.dart';
import '../controllers/settings_controller.dart';
import '../core/constants.dart';
import '../core/routes.dart';
import '../theme/design_tokens.dart';
import '../utils/app_snackbar.dart';
import 'package:lucide_icons/lucide_icons.dart';

class HomeController extends GetxController {
  final currentTab = 0.obs;
  bool _resumeDialogShown = false;

  void changeTab(int index) {
    if (currentTab.value != index) {
      HapticFeedback.lightImpact();
      currentTab.value = index;
    }
  }

  /// One-time startup resume: if [autoLoadLastModel] is on, loads silently;
  /// otherwise shows a dialog. Delayed to let splash→home transition finish
  /// without jank and to avoid blocking the first frame with sync file checks.
  Future<void> checkResumeModel(BuildContext context) async {
    if (_resumeDialogShown) return;
    _resumeDialogShown = true;

    // Let the splash fade + Home scaffold settle (prevents "atka mere" lag).
    await Future.delayed(const Duration(milliseconds: 520));

    final hive = Get.find<HiveService>();

    // The saved absolute path must still point at a real, non-empty file.
    // Use async check off the UI thread to avoid blocking splash fade.
    Future<bool> savedPathExistsAsync(String? p) async {
      if (p == null || p.isEmpty) return false;
      try {
        final exists = await File(p).exists().timeout(
              const Duration(milliseconds: 400),
              onTimeout: () => false,
            );
        if (!exists) return false;
        final len = await File(p).length().timeout(
              const Duration(milliseconds: 400),
              onTimeout: () => 0,
            );
        return len > 0;
      } catch (_) {
        return false;
      }
    }

    // Check text model (async, non-blocking)
    final textName = hive.getSetting<String>(AppConstants.keyLocalModelName);
    final textPath = hive.getSetting<String>(AppConstants.keyLocalModelPath);
    final textRuntime = hive.getSetting<String>(AppConstants.keyLocalModelRuntime);
    var hasText = textName != null &&
        textName.isNotEmpty &&
        await savedPathExistsAsync(textPath);
    if ((textName?.isNotEmpty ?? false) && !hasText) {
      await hive.setSetting(AppConstants.keyLocalModelPath, '');
      await hive.setSetting(AppConstants.keyLocalModelName, '');
      await hive.setSetting(AppConstants.keyLocalModelRuntime, '');
      await hive.setSetting(AppConstants.keyLocalModelBackend, '');
    }

    // Check image model
    final imageName = hive.getSetting<String>(AppConstants.keyImageModelName);
    final imagePath = hive.getSetting<String>(AppConstants.keyImageModelPath);
    var hasImage = imageName != null &&
        imageName.isNotEmpty &&
        await savedPathExistsAsync(imagePath);
    if ((imageName?.isNotEmpty ?? false) && !hasImage) {
      await hive.setSetting(AppConstants.keyImageModelPath, '');
      await hive.setSetting(AppConstants.keyImageModelName, '');
    }

    // Nothing to resume — user picks a model from Explore when needed.
    if (!hasText && !hasImage) return;
    if (!context.mounted) return;

    // Respect Settings → Auto-load toggle.
    bool autoLoad = false;
    try {
      if (Get.isRegistered<SettingsController>()) {
        // SettingsController is already put before runApp, but guard for fallback.
        final s = Get.find<SettingsController>();
        autoLoad = s.autoLoadLastModel.value;
      } else {
        autoLoad = hive.getSetting<bool>(AppConstants.keyAutoLoadLastModel,
                defaultValue: false) ??
            false;
      }
    } catch (_) {}

    final label = hasText && hasImage
        ? '$textName & $imageName'
        : (hasText ? textName : imageName);

    if (autoLoad) {
      // ── Safe auto-load: only after chat interface is fully settled ──
      // User reported: model load starting during splash (APK loading) + Home init
      // together = 2nd open freeze. So we wait until chat UI is idle.
      // 1. Wait for deferred services (DeviceInfo etc.) + Home first frame.
      for (int i = 0; i < 15; i++) {
        if (!context.mounted) return;
        // Home must be visible and splash fully gone.
        final splashGone = Get.currentRoute == AppRoutes.home;
        final deferredReady = Get.isRegistered<DeviceInfoService>();
        if (splashGone && deferredReady) break;
        await Future.delayed(const Duration(milliseconds: 200));
      }
      if (!context.mounted) return;
      // Extra 1.2s so user sees chat interface before heavy mmap starts.
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!context.mounted) return;

      // 2. Skip if same model already resident.
      try {
        if (hasText && Get.isRegistered<InferenceService>()) {
          final inf = Get.find<InferenceService>();
          if (inf.isModelLoaded.value &&
              inf.loadedModelName.value == textName &&
              inf.isLoadingModel.value == false) {
            hasText = false;
          }
        }
        if (hasImage && Get.isRegistered<LocalImageService>()) {
          final img = Get.find<LocalImageService>();
          if (img.isModelLoaded.value &&
              img.loadedModelName.value == imageName &&
              img.isLoadingModel.value == false) {
            hasImage = false;
          }
        }
      } catch (_) {}
      if (!hasText && !hasImage) return;

      // 3. Crash-loop guard: if last auto-load was < 90s ago, skip this time.
      final lastAttempt = hive.getSetting<int>('last_auto_load_attempt') ?? 0;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (lastAttempt > 0 && nowMs - lastAttempt < 90000) {
        if (context.mounted) {
          AppSnackbar.showTop(
            'Auto-load skipped',
            'Last auto-load was recent — tap Load to retry.',
            icon: LucideIcons.pauseCircle,
            iconName: 'pauseCircle',
            duration: const Duration(seconds: 3),
            logHistory: false,
          );
        }
        return;
      }
      await hive.setSetting('last_auto_load_attempt', nowMs);

      // 4. RAM guard: skip if file > 80% of available RAM (would OOM and kill app).
      try {
        if (Get.isRegistered<DeviceInfoService>()) {
          final dev = Get.find<DeviceInfoService>();
          final availMb = (dev.availableRamGB.value * 1024).toInt();
          if (availMb > 0) {
            for (final p in [if (hasText) textPath, if (hasImage) imagePath]) {
              if (p == null) continue;
              final len = await File(p).length().timeout(
                    const Duration(milliseconds: 400),
                    onTimeout: () => 0,
                  );
              final lenMb = len ~/ (1024 * 1024);
              if (lenMb > 0 && lenMb > availMb * 0.8) {
                if (context.mounted) {
                  AppSnackbar.showTop(
                    'Not enough RAM',
                    'Need ~${lenMb}MB for $label but only ${availMb}MB free.',
                    icon: LucideIcons.alertTriangle,
                    iconName: 'alertTriangle',
                    duration: const Duration(seconds: 4),
                    logHistory: false,
                  );
                }
                await hive.setSetting('last_auto_load_attempt', 0);
                return;
              }
            }
          }
        }
      } catch (_) {}

      // 5. Defer heavy mmap — now truly after chat interface, no splash clash.
      Future.delayed(const Duration(milliseconds: 400), () async {
        try {
          if (hasText) {
            await Get.find<InferenceService>()
                .loadModel(textPath!,
                    modelName: textName, modelRuntime: textRuntime)
                .timeout(const Duration(seconds: 90));
          }
          if (hasImage) {
            await Get.find<LocalImageService>()
                .loadModel(imagePath!, modelName: imageName)
                .timeout(const Duration(seconds: 90));
          }
          await hive.setSetting('last_auto_load_attempt', 0);
        } catch (e) {
          try {
            Get.find<AppLogService>().error(
              'Auto-load failed',
              details: e.toString(),
              category: LogCategory.model,
            );
          } catch (_) {}
          await hive.setSetting('last_auto_load_attempt', 0);
        }
      });
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Resume Session?',
            style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.w600)),
        content: Text(
            'Load your last model${hasImage && hasText ? 's' : ''}?\n\n$label',
            style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Skip',
                style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Dt.accent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.of(context).pop();
              if (hasText) {
                Get.find<InferenceService>().loadModel(textPath!,
                    modelName: textName, modelRuntime: textRuntime);
              }
              if (hasImage) {
                Get.find<LocalImageService>().loadModel(imagePath!,
                    modelName: imageName);
              }
            },
            child: const Text('Load'),
          ),
        ],
      ),
    );
  }
}
