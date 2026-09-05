import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'controllers/settings_controller.dart';
import 'controllers/chat_controller.dart';
import 'controllers/cloud_model_controller.dart';
import 'controllers/server_controller.dart';
import 'controllers/model_controller.dart';
import 'core/theme.dart';
import 'core/routes.dart';
import 'services/hive_service.dart';
import 'services/secure_key_store.dart';
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
import 'services/tts_service.dart';
import 'services/usage_tracker_service.dart';
import 'services/update_service.dart';
import 'core/constants.dart';
import 'core/languages.dart';
import 'core/app_translations.dart';

void main() {
  final appLogBuffer = <String>[];
  _bootStart = DateTime.now();
  // Cold-start trace: single stopwatch, phase lines in System Logs so the
  // slowest init is visible without a profiler attached.
  final bootClock = Stopwatch()..start();
  void trace(String phase) {
    final ms = bootClock.elapsedMilliseconds;
    final line = '[boot +${ms}ms] $phase';
    if (Get.isRegistered<AppLogService>()) {
      try {
        Get.find<AppLogService>().info(line, category: LogCategory.system);
      } catch (_) {}
    } else {
      appLogBuffer.add(line);
    }
  }

  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // ── Windows Desktop: native window config (before any UI shows) ──
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      try {
        await windowManager.ensureInitialized();
        const opts = WindowOptions(
          minimumSize: Size(400, 700),
          size: Size(1280, 800),
          center: true,
          title: 'CubicLM',
          titleBarStyle: TitleBarStyle.normal,
          backgroundColor: Colors.transparent,
        );
        await windowManager.waitUntilReadyToShow(opts, () async {
          await windowManager.show();
          await windowManager.focus();
        });
        // Intercept close so generation/downloads aren't killed silently —
        // LockGate.onWindowClose confirms when busy, destroys otherwise.
        await windowManager.setPreventClose(true);
      } catch (_) {
        // window_manager is Windows-only; ignore on other platforms.
      }
    }

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

    // ── Secure storage for API keys (needed before HiveService for encryption) ──
    try {
      await withTimeout(Get.putAsync(() => SecureKeyStore().init()),
          'SecureKeyStore',
          timeout: const Duration(seconds: 4));
    } catch (e) {
      appLog.error('SecureKeyStore init failed — API keys stay in memory',
          details: e.toString(), category: LogCategory.system);
      if (!Get.isRegistered<SecureKeyStore>()) {
        Get.put(SecureKeyStore(), permanent: true);
        unawaited(Get.find<SecureKeyStore>().init());
      }
    }

    // ── Hive with encrypted storage ──
    SecureKeyStore? secureKeyStore;
    if (Get.isRegistered<SecureKeyStore>()) {
      secureKeyStore = Get.find<SecureKeyStore>();
    }

    try {
      await withTimeout(
          Get.putAsync(() => HiveService().init(secureKeyStore: secureKeyStore)),
          'HiveService',
          timeout: const Duration(seconds: 5));
    } catch (e) {
      appLog.error('HiveService init failed — using memory fallback',
          details: e.toString(), category: LogCategory.system);
      if (!Get.isRegistered<HiveService>()) {
        try {
          await Hive.deleteFromDisk();
          await Hive.initFlutter().timeout(const Duration(seconds: 3));
          await Get.putAsync(
                  () => HiveService().init(secureKeyStore: secureKeyStore))
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

    // One-time migration: Hive plaintext API keys → secure storage.
    try {
      await _migrateApiKeysFromHive();
    } catch (e) {
      appLog.error('API key migration failed',
          details: e.toString(), category: LogCategory.system);
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
      Get.put(UsageTrackerService());
      Get.put(DownloadService());
      Get.put(LocalImageService());
      Get.put(ServerController(), permanent: true);
      Get.put(ModelController());
      // TTS — GetxService, async init deferred but instance available immediately.
      Get.put(TtsService());
      unawaited(Get.find<TtsService>().init().then((_) {}, onError: (_) {}));
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
      final text = message.toString();
      if (text.contains('improper use of a GetX')) {
        // Harmless GetX empty-scope hint, not an app failure: keep it
        // searchable in logs but out of errors, diagnostics and crash
        // reports (it used to file a Crashlytics FATAL per occurrence).
        appLog.debug(
          text,
          details: details.stack?.toString() ?? 'No stack',
          category: LogCategory.system,
        );
        return;
      }
      appLog.error(
        text,
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
    trace('critical path done (Hive + Settings)');
    runApp(const CubicLMApp());

    // Apply system UI after first frame so Get.mediaQuery is available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      trace('first frame');
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
      // Persist now — the app may be about to be killed.
      unawaited(Get.find<AppLogService>().flush());
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
    // No logging here: callers log once with their own context (safePut
    // logs service failures; specific blocks log specifics). Logging here
    // too produced duplicate rows for every timeout.
    return f.timeout(timeout);
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
  // DeviceInfo probes hardware (getprop/Vulkan) — slow devices need room.
  await safePut(() => DeviceInfoService().init(), 'DeviceInfoService',
      timeout: const Duration(seconds: 10));
  await safePut(() => UpdateService().init(), 'UpdateService',
      timeout: const Duration(seconds: 4));
  // Kick off auto-check (3s delay + 24h throttle inside the service),
  // honoring the Update-center "Check automatically" pref.
  try {
    if (Get.isRegistered<UpdateService>()) {
      final svc = Get.find<UpdateService>();
      if (svc.autoCheck.value) unawaited(svc.check());
    }
  } catch (_) {}

  // Upgrade crash reporting from dummy to real.
  try {
    final cr = Get.find<CrashReportingService>();
    await withTimeout(cr.init(), 'CrashReportingService',
        timeout: const Duration(seconds: 4));
  } catch (e) {
    appLog.error('Service CrashReportingService failed to init',
        details: e.toString(), category: LogCategory.system);
  }

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
  final bootMs =
      DateTime.now().difference(_bootStart ?? DateTime.now()).inMilliseconds;
  appLog.info('[boot +${bootMs}ms] deferred init done',
      category: LogCategory.system);
}

/// Process start, captured before anything else for boot tracing.
DateTime? _bootStart;

Future<void> _migrateApiKeysFromHive() async {
  if (!Get.isRegistered<HiveService>() || !Get.isRegistered<SecureKeyStore>()) {
    return;
  }
  final hive = Get.find<HiveService>();
  if (hive.isFallback) return;
  if (hive.getSetting<bool>('api_keys_migrated_to_secure') ?? false) return;
  final keys = Get.find<SecureKeyStore>();
  const optionKeys = [
    AppConstants.keyOpenaiKey,
    AppConstants.keyAnthropicKey,
    AppConstants.keyGoogleKey,
    AppConstants.keyKimiKey,
    AppConstants.keyStabilityKey,
    AppConstants.keyNvidiaKey,
    AppConstants.keyOpenRouterKey,
    AppConstants.keyDeepSeekKey,
    AppConstants.keyZaiKey,
    AppConstants.keyGroqKey,
    AppConstants.keyMistralKey,
    AppConstants.keyTogetherKey,
    AppConstants.keyXaiKey,
    AppConstants.keyPerplexityKey,
    AppConstants.keyCerebrasKey,
    AppConstants.keyFireworksKey,
    AppConstants.keyCohereKey,
    AppConstants.keyHuggingFaceKey,
    AppConstants.keyXkiroKey,
    AppConstants.keyTokenRouterKey,
    AppConstants.keyCustomCloudKey,
    AppConstants.keyServerApiKey,
  ];
  var moved = 0;
  for (final k in optionKeys) {
    final legacy = hive.getSetting<String>(k);
    if (legacy != null && legacy.isNotEmpty && keys.read(k).isEmpty) {
      await keys.write(k, legacy);
      moved++;
    }
    await hive.deleteSetting(k);
  }
  // Custom-profile inline keys → per-profile secure slots
  final raw = hive.getSetting<List>(AppConstants.keyCustomCloudProfiles);
  if (raw != null) {
    for (var i = 0; i < raw.length; i++) {
      final m = raw[i];
      if (m is Map) {
        final ak = m['apiKey']?.toString() ?? '';
        if (ak.isNotEmpty) {
          final perKey = '${AppConstants.keyCustomCloudKey}_p$i';
          if (keys.read(perKey).isEmpty) {
            await keys.write(perKey, ak);
            moved++;
          }
        }
      }
    }
    // Wipe inline keys from the persisted list
    final sanitized = raw.map((e) {
      if (e is Map) {
        final copy = Map<String, dynamic>.from(e);
        copy['apiKey'] = '';
        return copy;
      }
      return e;
    }).toList();
    await hive.setSetting(AppConstants.keyCustomCloudProfiles, sanitized);
  }
  await hive.setSetting('api_keys_migrated_to_secure', true);
  if (moved > 0) {
    Get.find<AppLogService>().info('[Migration] Moved $moved API keys Hive -> secure storage',
        category: LogCategory.system);
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
        translations: AppTranslations(),
        locale: AppLanguage.localeFromCode('en'),
        fallbackLocale: AppLanguage.localeFromCode('en'),
      );
    }
    final settings = Get.find<SettingsController>();
    return Obx(() {
      final themeMode = settings.themeMode.value;
      final scale = settings.fontScale.value;
      final currentLocale = settings.locale.value.locale;
      return GetMaterialApp(
        title: 'CubicLM',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeMode,
        initialRoute: AppRoutes.splash,
        getPages: AppPages.pages,
        translations: AppTranslations(),
        locale: currentLocale,
        fallbackLocale: AppLanguage.localeFromCode('en'),
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(
            textScaler: TextScaler.linear(scale),
          ),
          child: LockGate(child: child!),
        ),
      );
    });
  }
}

/// ── App Lock gate ────────────────────────────────────────────────────
/// When App Lock is enabled, covers the whole app with an unlock screen
/// on launch and every time the app returns from the background.
class LockGate extends StatefulWidget {
  final Widget child;
  const LockGate({super.key, required this.child});

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate>
    with WidgetsBindingObserver, WindowListener {
  bool _authAttempted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Desktop has no mobile lifecycle — window blur (Alt-Tab/minimize)
    // must arm the lock too. Android never touches window_manager.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      windowManager.addListener(this);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAuth());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  /// window_manager: losing focus counts as "background" on desktop.
  @override
  void onWindowBlur() {
    final settings = _settings();
    if (settings == null) return;
    if (settings.appLockEnabled.value) settings.isLocked.value = true;
    // Desktop never hits AppLifecycleState.paused, so snapshot a
    // streaming draft here too (same kill-recovery as Android).
    try {
      if (Get.isRegistered<ChatController>()) {
        Get.find<ChatController>().saveStreamingDraft();
      }
    } catch (_) {}
  }

  /// window_manager: close is intercepted (setPreventClose at startup).
  /// Destroy immediately when idle; confirm when a reply is generating
  /// or models are downloading so work isn't killed silently.
  @override
  void onWindowClose() async {
    var busyReason = '';
    try {
      if (Get.isRegistered<ChatController>()) {
        final chat = Get.find<ChatController>();
        if (chat.isLoading.value || chat.isStreaming.value) {
          busyReason = 'A reply is still generating.';
        }
      }
      if (busyReason.isEmpty && Get.isRegistered<ModelController>()) {
        if (Get.find<ModelController>().activeDownloads.isNotEmpty) {
          busyReason = 'Model downloads are still in progress.';
        }
      }
    } catch (_) {}
    if (busyReason.isEmpty) {
      await windowManager.destroy();
      return;
    }
    final quit = await Get.dialog<bool>(
      AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Quit CubicLM?'),
        content: Text('$busyReason Quitting now will stop it.'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Quit anyway'),
          ),
        ],
      ),
    );
    if (quit == true) await windowManager.destroy();
  }

  SettingsController? _settings() {
    try {
      if (Get.isRegistered<SettingsController>()) {
        return Get.find<SettingsController>();
      }
    } catch (_) {}
    return null;
  }

  void _maybeAuth() async {
    if (_authAttempted) return;
    final settings = _settings();
    if (settings == null) return;
    if (settings.appLockEnabled.value && settings.isLocked.value) {
      _authAttempted = true;
      // Wait for biometric detection: authenticating before it completes
      // fail-opens the lock on first launch (race).
      await settings.biometricsReady;
      if (!mounted) return;
      _authenticate(settings);
    }
  }

  DateTime? _backgroundedAt;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final settings = _settings();
    if (settings == null) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgroundedAt = DateTime.now();
      // Timeout 0 locks at once; timed mode decides on resume.
      if (settings.appLockEnabled.value &&
          settings.lockTimeoutMinutes.value <= 0) {
        settings.isLocked.value = true;
      }
      // Hands-free must not keep listening in the background.
      // Streaming answers snapshot a pause-draft (kill recovery).
      try {
        if (Get.isRegistered<ChatController>()) {
          final chat = Get.find<ChatController>();
          if (chat.voiceMode.value) chat.setVoiceMode(false);
          chat.saveStreamingDraft();
        }
      } catch (_) {}
    } else if (state == AppLifecycleState.resumed) {
      final t = settings.lockTimeoutMinutes.value;
      if (settings.appLockEnabled.value &&
          !settings.isLocked.value &&
          t > 0) {
        final bg = _backgroundedAt;
        if (bg != null && DateTime.now().difference(bg).inMinutes >= t) {
          settings.isLocked.value = true;
        }
      }
      if (settings.isLocked.value) _authenticate(settings);
      // Pick up Android share-target text (warm resume).
      try {
        if (Get.isRegistered<ChatController>()) {
          unawaited(Get.find<ChatController>().checkSharedText());
        }
      } catch (_) {}
    }
  }

  Future<void> _authenticate(SettingsController settings) async {
    final ok = await settings.authenticate();
    if (!mounted) return;
    if (ok) settings.isLocked.value = false;
    // On failure the lock screen stays up with a manual retry button.
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings();
    if (settings == null) return widget.child;
    return Obx(() {
      final locked =
          settings.appLockEnabled.value && settings.isLocked.value;
      if (!locked) return widget.child;
      return _LockScreen(onUnlock: () => _authenticate(settings));
    });
  }
}

class _LockScreen extends StatelessWidget {
  final VoidCallback onUnlock;
  const _LockScreen({required this.onUnlock});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? const Color(0xFF0D0D0F) : const Color(0xFFF8F4ED),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: const Color(0xFFFF4D00).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_rounded,
                  size: 40, color: Color(0xFFFF4D00)),
            ),
            const SizedBox(height: 24),
            Text(
              'CubicLM is locked',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF1C1C1E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Authenticate to continue',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF4D00),
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              ),
              onPressed: onUnlock,
              icon: const Icon(Icons.fingerprint_rounded, size: 22),
              label: Text(
                'Unlock',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
