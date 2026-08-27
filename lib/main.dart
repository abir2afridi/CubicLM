import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
// import 'firebase_options.dart';
import 'controllers/settings_controller.dart';
import 'controllers/cloud_model_controller.dart';
import 'controllers/server_controller.dart';
import 'controllers/model_controller.dart';
import 'core/theme.dart';
//////
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

    // Initialize Firebase before any Firebase-dependent services
    try {
      // await Firebase.initializeApp(
      //   options: DefaultFirebaseOptions.currentPlatform,
      // );
    } catch (e) {
      appLog.error('[Firebase] Initialization failed', details: e, category: LogCategory.system);
    }

    // Support phones and tablets in portrait or landscape.
    if (!kIsWeb) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }

    // ── Robust init with timeouts — never let native splash stuck ──
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

    Future<void> safePut<T extends GetxService>(
        Future<T> Function() factory, String name,
        {Duration timeout = const Duration(seconds: 5),
        bool required = false}) async {
      try {
        await withTimeout(Get.putAsync(factory), name, timeout: timeout);
      } catch (e) {
        appLog.error('Service $name failed to init',
            details: e.toString(), category: LogCategory.system);
        if (required) rethrow;
        // Non-required services can stay unregistered — callers must handle missing via isRegistered check.
      }
    }

    // Support phones and tablets in portrait or landscape.
    if (!kIsWeb) {
      try {
        await withTimeout(
            SystemChrome.setPreferredOrientations([
              DeviceOrientation.portraitUp,
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]),
            'setPreferredOrientations',
            timeout: const Duration(seconds: 2));
      } catch (_) {}
    }

    // Initialize Hive (with corruption recovery)
    try {
      await withTimeout(Hive.initFlutter(), 'Hive.initFlutter',
          timeout: const Duration(seconds: 6));
    } catch (e) {
      appLog.error('Hive.initFlutter failed — trying recovery',
          details: e.toString(), category: LogCategory.system);
      // Try to delete corrupted boxes and retry once.
      try {
        await Hive.deleteFromDisk();
        await Hive.initFlutter();
      } catch (_) {}
    }

    // Register global services — Hive is required, others are best-effort.
    try {
      await withTimeout(Get.putAsync(() => HiveService().init()), 'HiveService',
          timeout: const Duration(seconds: 6));
    } catch (e) {
      // Last resort: delete and recreate.
      try {
        await Hive.deleteFromDisk();
        await Hive.initFlutter();
        await Get.putAsync(() => HiveService().init());
      } catch (e2) {
        appLog.error('HiveService recovery failed',
            details: e2.toString(), category: LogCategory.system);
      }
    }

    // Non-critical services — timeout but don't block forever.
    await safePut(() => NotificationHistoryService().init(),
        'NotificationHistoryService',
        timeout: const Duration(seconds: 4));
    await safePut(() => SkillRegistryService().init(),
        'SkillRegistryService',
        timeout: const Duration(seconds: 4));
    await safePut(() => McpRegistryService().init(), 'McpRegistryService',
        timeout: const Duration(seconds: 4));
    await safePut(() => DeviceInfoService().init(), 'DeviceInfoService',
        timeout: const Duration(seconds: 4));

    // Settings controller must be initialized before runApp for theme support
    final settingsController = Get.put(SettingsController());
    Get.put(CloudModelController());

    Get.put(InferenceService());
    Get.put(CloudService());
    Get.put(DownloadService());
    Get.put(LocalImageService());
    final crashReporting = await () async {
      try {
        return await withTimeout(Get.putAsync(() => CrashReportingService().init()),
            'CrashReportingService',
            timeout: const Duration(seconds: 4));
      } catch (_) {
        // Return a no-op if crash reporting fails — don't block startup.
        return Get.put(CrashReportingService());
      }
    }();
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      // Include the diagnostic payload (e.g. "The relevant error-causing
      // widget was: …") so layout issues like RenderFlex overflow are
      // pinpointed in System Logs instead of logging a bare first line.
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
    Get.put(ServerController(), permanent: true);
    Get.put(ModelController());

    // Auto-configure inference settings based on device RAM
    // Fire-and-forget with timeout — never block startup.
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

    runApp(const CubicLMApp());

    // Apply system UI after frame is rendered so Get.mediaQuery is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      settingsController.setThemeMode(settingsController.themeMode.value);
    });
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

/// Validates that remembered models still exist on disk.
/// Does NOT auto-load — the HomeView will ask the user on first launch.
void _validateLastModel() async {
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
    final settings = Get.find<SettingsController>();
    return Obx(() {
      final themeMode = settings.themeMode.value;
      final scale = settings.fontScale.value; // read here → Obx tracks it
      return GetMaterialApp(
        title: 'CubicLM',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeMode,
        initialRoute: AppRoutes.home,
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
