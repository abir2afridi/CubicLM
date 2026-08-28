import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'controllers/settings_controller.dart';
import 'controllers/cloud_model_controller.dart';
import 'controllers/server_controller.dart';
import 'controllers/model_controller.dart';
import 'core/theme.dart';
import 'core/routes.dart';
import 'services/hive_service.dart';
import 'services/inference_service.dart';
import 'services/cloud_service.dart';
import 'services/download_service.dart';
import 'services/device_info_service.dart';
import 'services/local_image_service.dart';
import 'services/app_log_service.dart';
import 'services/crash_reporting_service.dart';
import 'services/image_generation_notification_service.dart';
import 'services/notification_history_service.dart';
import 'services/skills/skill_registry_service.dart';
import 'services/mcp/mcp_registry_service.dart';
import 'core/constants.dart';

void main() {
  final appLogBuffer = <String>[];

  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Register logger first so everything routes to it
    final appLog = AppLogService();
    Get.put(appLog);

    // Flush buffered prints
    for (final line in appLogBuffer) {
      appLog.info(line);
    }
    appLogBuffer.clear();

    appLog.info('App started', category: LogCategory.system);

    // Support phones and tablets in portrait or landscape.
    if (!kIsWeb) {
      try {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]).timeout(const Duration(seconds: 2));
      } catch (_) {}
    }

    // ── Helpers ──
    Future<T> withTimeout<T>(Future<T> f, String name,
        {Duration timeout = const Duration(seconds: 5)}) async {
      try {
        return await f.timeout(timeout);
      } catch (e, s) {
        appLog.error('Init $name timed out / failed',
            details: '$e\n$s', category: LogCategory.system);
        rethrow;
      }
    }

    // ── CRITICAL PATH: Hive must be ready before SettingsController, but must NEVER block runApp >6s ──
    // Use short timeouts + memory fallback so native launch_background is removed quickly.
    bool hiveIsFallback = false;
    try {
      await withTimeout(Hive.initFlutter(), 'Hive.initFlutter',
          timeout: const Duration(seconds: 4));
    } catch (e) {
      appLog.error('Hive.initFlutter failed — trying recovery',
          details: e.toString(), category: LogCategory.system);
      try {
        await Hive.deleteFromDisk();
        await Hive.initFlutter().timeout(const Duration(seconds: 3));
      } catch (_) {}
    }

    try {
      await withTimeout(Get.putAsync(() => HiveService().init()), 'HiveService',
          timeout: const Duration(seconds: 5));
    } catch (e) {
      appLog.error('HiveService init failed — using memory fallback',
          details: e.toString(), category: LogCategory.system);
      if (!Get.isRegistered<HiveService>()) {
        try {
          await Hive.deleteFromDisk();
          await Hive.initFlutter().timeout(const Duration(seconds: 3));
          await Get.putAsync(() => HiveService().init())
              .timeout(const Duration(seconds: 5));
        } catch (_) {
          Get.put(HiveService.fallback());
          hiveIsFallback = true;
        }
      }
    }
    if (!Get.isRegistered<HiveService>()) {
      Get.put(HiveService.fallback());
      hiveIsFallback = true;
    } else {
      try {
        hiveIsFallback = Get.find<HiveService>().isFallback;
      } catch (_) {}
    }
    if (hiveIsFallback) {
      appLog.warning(
          'Running with in-memory storage — settings will not persist until storage is cleared or app is reinstalled',
          category: LogCategory.system);
    }

    // Settings controller must be initialized before runApp for theme support.
    // Hive fallback ensures this never throws.
    late SettingsController settingsController;
    try {
      settingsController = Get.put(SettingsController());
    } catch (e, s) {
      appLog.error('SettingsController init failed',
          details: '$e\n$s', category: LogCategory.system);
      // Force fallback hive and retry once.
      if (!Get.isRegistered<HiveService>() ||
          !Get.find<HiveService>().isFallback) {
        try {
          if (Get.isRegistered<HiveService>()) {
            Get.delete<HiveService>(force: true);
          }
        } catch (_) {}
        Get.put(HiveService.fallback());
      }
      settingsController = Get.put(SettingsController());
    }

    // Lightweight sync services — no async, never blocks first frame.
    try {
      Get.put(CloudModelController());
      Get.put(InferenceService());
      Get.put(CloudService());
      Get.put(DownloadService());
      Get.put(LocalImageService());
      Get.put(ServerController(), permanent: true);
      Get.put(ModelController());
    } catch (e, s) {
      appLog.error('Sync service put failed',
          details: '$e\n$s', category: LogCategory.system);
    }

    // Crash reporting — put dummy now, real init deferred.
    CrashReportingService crashReporting;
    if (Get.isRegistered<CrashReportingService>()) {
      crashReporting = Get.find<CrashReportingService>();
    } else {
      crashReporting = Get.put(CrashReportingService());
    }

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      final message = StringBuffer(details.exceptionAsString());
      if (details.informationCollector != null) {
        for (final line in details.informationCollector!()) {
          message.write('\n$line');
        }
      }
      appLog.error(
        message.toString(),
        details: details.stack?.toString() ?? 'No stack',
        category: LogCategory.system,
      );
      crashReporting.recordFlutterFatal(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      appLog.error(
        error.toString(),
        details: stack.toString(),
        category: LogCategory.system,
      );
      crashReporting.recordFatal(error, stack, reason: 'platform_dispatcher');
      return true;
    };

    final imageNotifications = Get.put(ImageGenerationNotificationService());

    // ── RUN APP IMMEDIATELY — removes Android launch_background native splash ──
    runApp(const CubicLMApp());

    // Apply system UI after first frame so Get.mediaQuery is available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        settingsController.setThemeMode(settingsController.themeMode.value);
      } catch (_) {}
    });

    // ── DEFERRED HEAVY INIT — after splash (~2.1s) + Home first frame, never janks shimmer ──
    unawaited(Future.delayed(const Duration(milliseconds: 2200),
        () => _initDeferredServices(appLog, imageNotifications)));

    // Auto-configure inference settings based on device RAM (fire-and-forget).
    unawaited(withTimeout(Future(() => _autoConfigureForDevice()),
            'autoConfigureForDevice',
            timeout: const Duration(seconds: 2))
        .catchError((e) => appLog.error('autoConfigure failed',
            details: e.toString(), category: LogCategory.system)));

    // Keep last model as a quick-load option, but do not auto-load on startup.
    unawaited(withTimeout(Future(() => _validateLastModel()),
            'validateLastModel',
            timeout: const Duration(seconds: 3))
        .catchError((e) => appLog.error('validateLastModel failed',
            details: e.toString(), category: LogCategory.system)));
  }, (error, stack) async {
    if (Get.isRegistered<AppLogService>()) {
      Get.find<AppLogService>().error(
        'Uncaught zone error: $error',
        details: stack.toString(),
        category: LogCategory.system,
      );
    }
    if (Get.isRegistered<CrashReportingService>()) {
      await Get.find<CrashReportingService>()
          .recordFatal(error, stack, reason: 'run_zoned_guarded');
    }
  }, zoneSpecification: ZoneSpecification(
    print: (self, parent, zone, line) {
      if (Get.isRegistered<AppLogService>()) {
        Get.find<AppLogService>().info(line);
      } else {
        appLogBuffer.add(line);
      }
      parent.print(zone, line);
    },
  ));
}

/// Deferred services that previously blocked runApp and caused native splash to hang.
Future<void> _initDeferredServices(
    AppLogService appLog, ImageGenerationNotificationService imageNotifications) async {
  Future<T> withTimeout<T>(Future<T> f, String name,
      {Duration timeout = const Duration(seconds: 4)}) async {
    try {
      return await f.timeout(timeout);
    } catch (e, s) {
      appLog.error('Deferred init $name timed out / failed',
          details: '$e\n$s', category: LogCategory.system);
      rethrow;
    }
  }

  Future<void> safePut<T extends GetxService>(
      Future<T> Function() factory, String name,
      {Duration timeout = const Duration(seconds: 4)}) async {
    if (Get.isRegistered<T>()) return;
    try {
      await withTimeout(Get.putAsync(factory), name, timeout: timeout);
    } catch (e) {
      appLog.error('Service $name failed to init',
          details: e.toString(), category: LogCategory.system);
    }
  }

  await safePut(() => NotificationHistoryService().init(),
      'NotificationHistoryService',
      timeout: const Duration(seconds: 4));
  await safePut(() => SkillRegistryService().init(), 'SkillRegistryService',
      timeout: const Duration(seconds: 4));
  await safePut(() => McpRegistryService().init(), 'McpRegistryService',
      timeout: const Duration(seconds: 4));
  await safePut(() => DeviceInfoService().init(), 'DeviceInfoService',
      timeout: const Duration(seconds: 4));

  // Upgrade crash reporting from dummy to real.
  try {
    final cr = Get.find<CrashReportingService>();
    await withTimeout(cr.init(), 'CrashReportingService',
        timeout: const Duration(seconds: 4));
  } catch (_) {}

  try {
    await withTimeout(imageNotifications.init(), 'ImageNotifications.init',
        timeout: const Duration(seconds: 4));
  } catch (e) {
    appLog.error('ImageNotifications.init failed',
        details: e.toString(), category: LogCategory.system);
  }
  try {
    await withTimeout(imageNotifications.configureBackgroundService(),
        'ImageNotifications.configureBackgroundService',
        timeout: const Duration(seconds: 4));
  } catch (e) {
    appLog.error('ImageNotifications.configureBackgroundService failed',
        details: e.toString(), category: LogCategory.system);
  }
}

/// Validates that remembered models still exist on disk.
/// Does NOT auto-load — the HomeView will ask the user on first launch.
void _validateLastModel() async {
  if (!Get.isRegistered<HiveService>() || !Get.isRegistered<DownloadService>()) return;
  final hive = Get.find<HiveService>();
  final downloadService = Get.find<DownloadService>();

  // Validate last text/LLM model
  final textModelName = hive.getSetting<String>(AppConstants.keyLocalModelName);
  final textModelPath = hive.getSetting<String>(AppConstants.keyLocalModelPath);
  if (textModelName != null &&
      textModelName.isNotEmpty &&
      textModelPath != null &&
      textModelPath.isNotEmpty) {
    if (!await downloadService.isModelDownloaded(textModelName)) {
      await hive.setSetting(AppConstants.keyLocalModelPath, '');
      await hive.setSetting(AppConstants.keyLocalModelName, '');
    }
  }

  // Validate last image model
  final imageModelName =
      hive.getSetting<String>(AppConstants.keyImageModelName);
  final imageModelPath =
      hive.getSetting<String>(AppConstants.keyImageModelPath);
  if (imageModelName != null &&
      imageModelName.isNotEmpty &&
      imageModelPath != null &&
      imageModelPath.isNotEmpty) {
    if (!await downloadService.isModelDownloaded(imageModelName)) {
      await hive.setSetting(AppConstants.keyImageModelPath, '');
      await hive.setSetting(AppConstants.keyImageModelName, '');
    }
  }
}

/// Auto-set optimized inference params based on device RAM (only on first launch).
void _autoConfigureForDevice() {
  if (!Get.isRegistered<HiveService>() || !Get.isRegistered<DeviceInfoService>()) return;
  final hive = Get.find<HiveService>();
  final device = Get.find<DeviceInfoService>();

  // Only auto-configure if user hasn't already set values (first launch)
  final hasConfigured =
      hive.getSetting<bool>('device_auto_configured') ?? false;
  if (hasConfigured) return;

  hive.setSetting(AppConstants.keyContextSize, device.recommendedContextSize);
  hive.setSetting(AppConstants.keyMaxTokens, device.recommendedMaxTokens);
  hive.setSetting(AppConstants.keyTemperature, 0.3);
  hive.setSetting('device_auto_configured', true);

  Get.find<AppLogService>().info(
      '[AutoConfig] Set context=${device.recommendedContextSize}, '
      'maxTokens=${device.recommendedMaxTokens} for ${device.totalRamGB.value.toStringAsFixed(1)}GB RAM',
      category: LogCategory.system);
}

class CubicLMApp extends StatelessWidget {
  const CubicLMApp({super.key});

  @override
  Widget build(BuildContext context) {
    // SettingsController is put before runApp, but guard for fallback / hot-restart.
    if (!Get.isRegistered<SettingsController>()) {
      return GetMaterialApp(
        title: 'CubicLM',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        initialRoute: AppRoutes.splash,
        getPages: AppPages.pages,
      );
    }
    final settings = Get.find<SettingsController>();
    return Obx(() {
      final themeMode = settings.themeMode.value;
      final scale = settings.fontScale.value;
      return GetMaterialApp(
        title: 'CubicLM',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeMode,
        initialRoute: AppRoutes.splash,
        getPages: AppPages.pages,
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        ),
      );
    });
  }
}
