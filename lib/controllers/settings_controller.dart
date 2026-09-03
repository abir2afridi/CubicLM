import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:local_auth/local_auth.dart' as la;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../core/constants.dart';
import '../services/hive_service.dart';
import '../services/secure_key_store.dart';
import '../services/app_log_service.dart';
import '../services/device_info_service.dart';
import '../services/inference_service.dart';
import '../services/download_service.dart';
import '../services/local_image_service.dart';
import '../ffi/sd_ffi_bindings.dart';
import 'package:sd_flutter_android/sd_flutter_android.dart';
import '../services/skills/skill_injector.dart';
import '../core/languages.dart';

class SettingsController extends GetxController {
  final HiveService _hive = Get.find<HiveService>();
  final SecureKeyStore _keys = Get.find<SecureKeyStore>();

  /// All Hive option-keys that hold API keys and must live in secure storage.
  static const List<String> _secureOptionKeys = [
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

  // Observable settings
  final themeMode = ThemeMode.system.obs;
  final inferenceMode = 'local'.obs; // 'local' or 'cloud'
  final cloudProvider = 'openrouter'.obs;
  final openaiKey = ''.obs;
  final anthropicKey = ''.obs;
  final googleKey = ''.obs;
  final kimiKey = ''.obs;
  final stabilityKey = ''.obs;
  final nvidiaKey = ''.obs;
  final openRouterKey = ''.obs;
  final deepSeekKey = ''.obs;
  final zaiKey = ''.obs;
  final groqKey = ''.obs;
  final mistralKey = ''.obs;
  final togetherKey = ''.obs;
  final xaiKey = ''.obs;
  final perplexityKey = ''.obs;
  final cerebrasKey = ''.obs;
  final fireworksKey = ''.obs;
  final cohereKey = ''.obs;
  final huggingfaceKey = ''.obs;
  final xkiroKey = ''.obs;
  final tokenrouterKey = ''.obs;
  final customCloudName = 'Custom API'.obs;
  final customCloudBaseUrl = ''.obs;
  final customCloudKey = ''.obs;
  final customCloudProfiles = <Map<String, String>>[].obs;
  final customCloudProfileIndex = (-1).obs;
  final openaiModel = 'gpt-5.2'.obs;
  final anthropicModel = 'claude-sonnet-4-6'.obs;
  final googleModel = 'gemini-2.5-flash'.obs;
  final kimiModel = 'kimi-k2.6'.obs;
  final stabilityModel = 'sd3.5-flash'.obs;
  final nvidiaModel = 'meta/llama-3.1-8b-instruct'.obs;
  final openRouterModel = 'openai/gpt-4o-mini'.obs;
  final deepSeekModel = 'deepseek-v4-flash'.obs;
  final zaiModel = 'glm-4.7-flash'.obs;
  final groqModel = 'llama-3.3-70b-versatile'.obs;
  final mistralModel = 'mistral-large-latest'.obs;
  final togetherModel = 'meta-llama/Llama-3.3-70B-Instruct-Turbo'.obs;
  final xaiModel = 'grok-4-fast'.obs;
  final perplexityModel = 'sonar-pro'.obs;
  final cerebrasModel = 'llama-3.3-70b'.obs;
  final fireworksModel = 'accounts/fireworks/models/llama-v3p3-70b-instruct'
      .obs;
  final cohereModel = 'command-a-03-2025'.obs;
  final huggingfaceModel = 'meta-llama/Llama-3.3-70B-Instruct'.obs;
  final xkiroModel = 'openai/gpt-5.2'.obs;
  final tokenrouterModel = 'openai/gpt-5.2'.obs;
  final customCloudModel = ''.obs;
  final globalSystemPrompt = AppConstants.systemPrompt.obs;
  final nvidiaModels = <String>[].obs;
  final isLoadingNvidiaModels = false.obs;
  final temperature = 0.1.obs;
  final maxTokens = 512.obs;
  final contextSize = 2048.obs;
  /// Auto Tune (recommended): derive context & output limits from the
  /// device RAM tier, and let cloud models use their full native output.
  final autoTuneParams = true.obs;
  /// Web access: when on, URLs found in the user's message are fetched
  /// and their readable text is added to the model's context.
  final webFetchEnabled = true.obs;
  /// Dismissible upsell pill shown inside the composer card.
  final composerUpsellDismissed = false.obs;
  final liteRtPerformanceMode = AppConstants.defaultLiteRtPerformanceMode.obs;
  final imageSteps = 1.obs;
  final imageGenForceCpu = AppConstants.defaultImageGenForceCpu.obs;
  final imageGenBackend = Backend.cpu.obs;
  final imageGpuVendor = 'detecting'.obs;
  final imageGenGpuGuardMb = AppConstants.defaultImageGenGpuGuardMb.obs;
  final imageGenSize = AppConstants.defaultImageGenSize.obs;
  final fontScale = AppConstants.defaultFontScale.obs;
  final locale = AppLanguage.fromCode('en').obs;
  final appVersion = ''.obs;

  // Thinking Orb animation selections ('random' or an OrbState name).
  final orbChatAnim = 'random'.obs;
  final orbImageAnim = 'composing'.obs;
  final orbAnalysisAnim = 'random'.obs;

  // Startup — auto-load last model without asking dialog.
  final autoLoadLastModel = false.obs;

  // TTS — read aloud assistant messages.
  final readAloudEnabled = true.obs;

  // App Lock — require device biometrics/PIN to open the app.
  final appLockEnabled = false.obs;
  final biometricsAvailable = false.obs;

  /// True when at least one biometric (or device credential usable by
  /// local_auth) is enrolled. Lets the UI tell "no hardware" apart from
  /// "hardware present, nothing enrolled" (e.g. Windows Hello supported
  /// but never set up — authenticating then would just fail).
  final hasEnrolledBiometrics = false.obs;

  /// Completes once [_detectBiometrics] has run. The lock gate awaits this
  /// before its first auth decision — otherwise a slow first detection
  /// fail-opens the lock on launch (race).
  final Completer<void> _biometricsDetected = Completer<void>();
  Future<void> get biometricsReady => _biometricsDetected.future;

  /// True while the app is locked and waiting for authentication.
  final isLocked = false.obs;

  // Persistent text controllers for settings fields
  final openaiKeyController = TextEditingController();
  final anthropicKeyController = TextEditingController();
  final googleKeyController = TextEditingController();
  final kimiKeyController = TextEditingController();
  final stabilityKeyController = TextEditingController();
  final nvidiaKeyController = TextEditingController();
  final openRouterKeyController = TextEditingController();
  final deepSeekKeyController = TextEditingController();
  final zaiKeyController = TextEditingController();
  final groqKeyController = TextEditingController();
  final mistralKeyController = TextEditingController();
  final togetherKeyController = TextEditingController();
  final xaiKeyController = TextEditingController();
  final perplexityKeyController = TextEditingController();
  final cerebrasKeyController = TextEditingController();
  final fireworksKeyController = TextEditingController();
  final cohereKeyController = TextEditingController();
  final huggingfaceKeyController = TextEditingController();
  final xkiroKeyController = TextEditingController();
  final tokenrouterKeyController = TextEditingController();
  final customCloudNameController = TextEditingController();
  final customCloudBaseUrlController = TextEditingController();
  final customCloudKeyController = TextEditingController();
  final globalSystemPromptController = TextEditingController();

  final openaiModelController = TextEditingController();
  final anthropicModelController = TextEditingController();
  final googleModelController = TextEditingController();
  final kimiModelController = TextEditingController();
  final stabilityModelController = TextEditingController();
  final nvidiaModelController = TextEditingController();
  final openRouterModelController = TextEditingController();
  final deepSeekModelController = TextEditingController();
  final zaiModelController = TextEditingController();
  final groqModelController = TextEditingController();
  final mistralModelController = TextEditingController();
  final togetherModelController = TextEditingController();
  final xaiModelController = TextEditingController();
  final perplexityModelController = TextEditingController();
  final cerebrasModelController = TextEditingController();
  final fireworksModelController = TextEditingController();
  final cohereModelController = TextEditingController();
  final huggingfaceModelController = TextEditingController();
  final xkiroModelController = TextEditingController();
  final tokenrouterModelController = TextEditingController();
  final customCloudModelController = TextEditingController();

  Timer? _apiKeyDebounceTimer;
  Timer? _modelDebounceTimer;

  @override
  void onInit() {
    super.onInit();
    _loadSettings();
    unawaited(_loadAppVersion());
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      appVersion.value = packageInfo.version;
    } catch (_) {
      appVersion.value = '';
    }
  }

  @override
  void onClose() {
    openaiKeyController.dispose();
    anthropicKeyController.dispose();
    googleKeyController.dispose();
    kimiKeyController.dispose();
    stabilityKeyController.dispose();
    nvidiaKeyController.dispose();
    openRouterKeyController.dispose();
    deepSeekKeyController.dispose();
    zaiKeyController.dispose();
    customCloudNameController.dispose();
    customCloudBaseUrlController.dispose();
    customCloudKeyController.dispose();
    globalSystemPromptController.dispose();
    openaiModelController.dispose();
    anthropicModelController.dispose();
    googleModelController.dispose();
    kimiModelController.dispose();
    stabilityModelController.dispose();
    nvidiaModelController.dispose();
    openRouterModelController.dispose();
    deepSeekModelController.dispose();
    zaiModelController.dispose();
    customCloudModelController.dispose();
    _apiKeyDebounceTimer?.cancel();
    _modelDebounceTimer?.cancel();
    _contextReloadTimer?.cancel();
    super.onClose();
  }

  void _loadSettings() {
    unawaited(_migrateKeysFromHive());
    final savedTheme = _hive.getSetting<String>('theme_mode');
    themeMode.value = _themeModeFromString(savedTheme);
    inferenceMode.value = _hive.getSetting(AppConstants.keyInferenceMode,
            defaultValue: 'local') ??
        'local';
    cloudProvider.value = _hive.getSetting(AppConstants.keyCloudProvider,
            defaultValue: 'openrouter') ??
        'openrouter';
    openaiKey.value = _keys.read(AppConstants.keyOpenaiKey);
    anthropicKey.value = _keys.read(AppConstants.keyAnthropicKey);
    googleKey.value = _keys.read(AppConstants.keyGoogleKey);
    kimiKey.value = _keys.read(AppConstants.keyKimiKey);
    stabilityKey.value = _keys.read(AppConstants.keyStabilityKey);
    nvidiaKey.value = _keys.read(AppConstants.keyNvidiaKey);
    openRouterKey.value = _keys.read(AppConstants.keyOpenRouterKey);
    deepSeekKey.value = _keys.read(AppConstants.keyDeepSeekKey);
    zaiKey.value = _keys.read(AppConstants.keyZaiKey);
    groqKey.value = _keys.read(AppConstants.keyGroqKey);
    mistralKey.value = _keys.read(AppConstants.keyMistralKey);
    togetherKey.value = _keys.read(AppConstants.keyTogetherKey);
    xaiKey.value = _keys.read(AppConstants.keyXaiKey);
    perplexityKey.value = _keys.read(AppConstants.keyPerplexityKey);
    cerebrasKey.value = _keys.read(AppConstants.keyCerebrasKey);
    fireworksKey.value = _keys.read(AppConstants.keyFireworksKey);
    cohereKey.value = _keys.read(AppConstants.keyCohereKey);
    huggingfaceKey.value = _keys.read(AppConstants.keyHuggingFaceKey);
    xkiroKey.value = _keys.read(AppConstants.keyXkiroKey);
    tokenrouterKey.value = _keys.read(AppConstants.keyTokenRouterKey);
    customCloudName.value = _hive.getSetting(AppConstants.keyCustomCloudName,
            defaultValue: 'Custom API') ??
        'Custom API';
    customCloudBaseUrl.value =
        _hive.getSetting(AppConstants.keyCustomCloudBaseUrl) ?? '';
    customCloudKey.value = _keys.read(AppConstants.keyCustomCloudKey);
    openaiModel.value = _hive.getSetting(AppConstants.keyOpenaiModel,
            defaultValue: 'gpt-5.2') ??
        'gpt-5.2';
    anthropicModel.value = _hive.getSetting(AppConstants.keyAnthropicModel,
            defaultValue: 'claude-sonnet-4-6') ??
        'claude-sonnet-4-6';
    googleModel.value = _hive.getSetting(AppConstants.keyGoogleModel,
            defaultValue: 'gemini-2.5-flash') ??
        'gemini-2.5-flash';
    kimiModel.value = _hive.getSetting(AppConstants.keyKimiModel,
            defaultValue: 'kimi-k2.6') ??
        'kimi-k2.6';
    stabilityModel.value = _hive.getSetting(AppConstants.keyStabilityModel,
            defaultValue: 'sd3.5-flash') ??
        'sd3.5-flash';
    nvidiaModel.value = _hive.getSetting(AppConstants.keyNvidiaModel,
            defaultValue: 'meta/llama-3.1-8b-instruct') ??
        'meta/llama-3.1-8b-instruct';
    openRouterModel.value = _hive.getSetting(AppConstants.keyOpenRouterModel,
            defaultValue: 'openai/gpt-4o-mini') ??
        'openai/gpt-4o-mini';
    deepSeekModel.value = _hive.getSetting(AppConstants.keyDeepSeekModel,
            defaultValue: 'deepseek-v4-flash') ??
        'deepseek-v4-flash';
    zaiModel.value = _hive.getSetting(AppConstants.keyZaiModel,
            defaultValue: 'glm-4.7-flash') ??
        'glm-4.7-flash';
    groqModel.value = _hive.getSetting(AppConstants.keyGroqModel,
            defaultValue: 'llama-3.3-70b-versatile') ??
        'llama-3.3-70b-versatile';
    mistralModel.value = _hive.getSetting(AppConstants.keyMistralModel,
            defaultValue: 'mistral-large-latest') ??
        'mistral-large-latest';
    togetherModel.value = _hive.getSetting(AppConstants.keyTogetherModel,
            defaultValue: 'meta-llama/Llama-3.3-70B-Instruct-Turbo') ??
        'meta-llama/Llama-3.3-70B-Instruct-Turbo';
    xaiModel.value = _hive.getSetting(AppConstants.keyXaiModel,
            defaultValue: 'grok-4-fast') ??
        'grok-4-fast';
    perplexityModel.value = _hive.getSetting(AppConstants.keyPerplexityModel,
            defaultValue: 'sonar-pro') ??
        'sonar-pro';
    cerebrasModel.value = _hive.getSetting(AppConstants.keyCerebrasModel,
            defaultValue: 'llama-3.3-70b') ??
        'llama-3.3-70b';
    fireworksModel.value = _hive.getSetting(AppConstants.keyFireworksModel,
            defaultValue:
                'accounts/fireworks/models/llama-v3p3-70b-instruct') ??
        'accounts/fireworks/models/llama-v3p3-70b-instruct';
    cohereModel.value = _hive.getSetting(AppConstants.keyCohereModel,
            defaultValue: 'command-a-03-2025') ??
        'command-a-03-2025';
    customCloudModel.value =
        _hive.getSetting(AppConstants.keyCustomCloudModel) ?? '';
    _loadCustomCloudProfiles();
    globalSystemPrompt.value = _hive.getSetting(
            AppConstants.keyGlobalSystemPrompt,
            defaultValue: AppConstants.systemPrompt) ??
        AppConstants.systemPrompt;
    temperature.value = _hive.getSetting(AppConstants.keyTemperature,
            defaultValue: AppConstants.defaultTemperature) ??
        AppConstants.defaultTemperature;
    maxTokens.value = _hive.getSetting(AppConstants.keyMaxTokens,
            defaultValue: AppConstants.defaultMaxTokens) ??
        AppConstants.defaultMaxTokens;
    contextSize.value = _hive.getSetting(AppConstants.keyContextSize,
            defaultValue: AppConstants.defaultContextSize) ??
        AppConstants.defaultContextSize;
    autoTuneParams.value = _hive.getSetting<bool>(
            AppConstants.keyAutoTuneParams,
            defaultValue: true) ??
        true;
    webFetchEnabled.value = _hive.getSetting<bool>(
            AppConstants.keyWebFetchEnabled,
            defaultValue: true) ??
        true;
    composerUpsellDismissed.value = _hive.getSetting<bool>(
            AppConstants.keyComposerUpsellDismissed,
            defaultValue: false) ??
        false;
    if (autoTuneParams.value) {
      // Persist tuned values so the native loaders (which read the Hive
      // keys directly) always pick up tier-matched context/output even if
      // the RAM tier changed since last launch.
      unawaited(_applyAutoTune(writeSettings: true));
    }
    liteRtPerformanceMode.value = _hive.getSetting(
          AppConstants.keyLiteRtPerformanceMode,
          defaultValue: AppConstants.defaultLiteRtPerformanceMode,
        ) ??
        AppConstants.defaultLiteRtPerformanceMode;
    imageSteps.value = _hive.getSetting(AppConstants.keyImageSteps,
            defaultValue: AppConstants.defaultImageSteps) ??
        AppConstants.defaultImageSteps;
    imageGenForceCpu.value = _hive.getSetting(AppConstants.keyImageGenForceCpu,
            defaultValue: AppConstants.defaultImageGenForceCpu) ??
        AppConstants.defaultImageGenForceCpu;
    imageGenGpuGuardMb.value = _hive.getSetting(
            AppConstants.keyImageGenGpuGuardMb,
            defaultValue: AppConstants.defaultImageGenGpuGuardMb) ??
        AppConstants.defaultImageGenGpuGuardMb;
    imageGenSize.value = _hive.getSetting(AppConstants.keyImageGenSize,
            defaultValue: AppConstants.defaultImageGenSize) ??
        AppConstants.defaultImageGenSize;
    final savedImageBackend = _hive.getSetting<int>(
        AppConstants.keyImageGenBackend,
        defaultValue: Backend.cpu.index);
    if (savedImageBackend != null &&
        savedImageBackend >= 0 &&
        savedImageBackend < Backend.values.length &&
        !imageGenForceCpu.value) {
      imageGenBackend.value = Backend.values[savedImageBackend];
    } else {
      imageGenBackend.value = Backend.cpu;
    }
    _detectImageGpu();
    fontScale.value = _hive.getSetting(AppConstants.keyFontScale,
            defaultValue: AppConstants.defaultFontScale) ??
        AppConstants.defaultFontScale;
    final savedLang = _hive.getSetting<String>(AppConstants.keyLanguage,
            defaultValue: 'en') ??
        'en';
    locale.value = AppLanguage.fromCode(savedLang);
    orbChatAnim.value = _hive.getSetting(AppConstants.keyOrbChat,
            defaultValue: 'random') ??
        'random';
    orbImageAnim.value = _hive.getSetting(AppConstants.keyOrbImage,
            defaultValue: 'composing') ??
        'composing';
    orbAnalysisAnim.value = _hive.getSetting(AppConstants.keyOrbAnalysis,
            defaultValue: 'random') ??
        'random';
    autoLoadLastModel.value = _hive.getSetting<bool>(
            AppConstants.keyAutoLoadLastModel,
            defaultValue: false) ??
        false;
    readAloudEnabled.value = _hive.getSetting<bool>(
            AppConstants.keyReadAloud,
            defaultValue: true) ??
        true;
    appLockEnabled.value = _hive.getSetting<bool>(
            AppConstants.keyAppLockEnabled,
            defaultValue: false) ??
        false;
    _detectBiometrics();
    if (appLockEnabled.value && !kIsWeb) {
      // Start locked so the gate shows before any chat content renders.
      isLocked.value = true;
    }

    // Sync controllers with loaded values
    openaiKeyController.text = openaiKey.value;
    anthropicKeyController.text = anthropicKey.value;
    googleKeyController.text = googleKey.value;
    kimiKeyController.text = kimiKey.value;
    stabilityKeyController.text = stabilityKey.value;
    nvidiaKeyController.text = nvidiaKey.value;
    openRouterKeyController.text = openRouterKey.value;
    deepSeekKeyController.text = deepSeekKey.value;
    zaiKeyController.text = zaiKey.value;
    groqKeyController.text = groqKey.value;
    mistralKeyController.text = mistralKey.value;
    togetherKeyController.text = togetherKey.value;
    xaiKeyController.text = xaiKey.value;
    perplexityKeyController.text = perplexityKey.value;
    cerebrasKeyController.text = cerebrasKey.value;
    fireworksKeyController.text = fireworksKey.value;
    cohereKeyController.text = cohereKey.value;
    huggingfaceKeyController.text = huggingfaceKey.value;
    xkiroKeyController.text = xkiroKey.value;
    tokenrouterKeyController.text = tokenrouterKey.value;
    customCloudNameController.text = customCloudName.value;
    customCloudBaseUrlController.text = customCloudBaseUrl.value;
    customCloudKeyController.text = customCloudKey.value;
    globalSystemPromptController.text = globalSystemPrompt.value;

    openaiModelController.text = openaiModel.value;
    anthropicModelController.text = anthropicModel.value;
    googleModelController.text = googleModel.value;
    kimiModelController.text = kimiModel.value;
    stabilityModelController.text = stabilityModel.value;
    nvidiaModelController.text = nvidiaModel.value;
    openRouterModelController.text = openRouterModel.value;
    deepSeekModelController.text = deepSeekModel.value;
    zaiModelController.text = zaiModel.value;
    groqModelController.text = groqModel.value;
    mistralModelController.text = mistralModel.value;
    togetherModelController.text = togetherModel.value;
    xaiModelController.text = xaiModel.value;
    perplexityModelController.text = perplexityModel.value;
    cerebrasModelController.text = cerebrasModel.value;
    fireworksModelController.text = fireworksModel.value;
    cohereModelController.text = cohereModel.value;
    huggingfaceModelController.text = huggingfaceModel.value;
    xkiroModelController.text = xkiroModel.value;
    tokenrouterModelController.text = tokenrouterModel.value;
    customCloudModelController.text = customCloudModel.value;
  }

  TextEditingController apiKeyControllerFor(String provider) {
    switch (provider) {
      case 'anthropic':
        return anthropicKeyController;
      case 'google':
        return googleKeyController;
      case 'kimi':
        return kimiKeyController;
      case 'stability':
        return stabilityKeyController;
      case 'nvidia':
        return nvidiaKeyController;
      case 'openrouter':
        return openRouterKeyController;
      case 'deepseek':
        return deepSeekKeyController;
      case 'zai':
        return zaiKeyController;
      case 'groq':
        return groqKeyController;
      case 'mistral':
        return mistralKeyController;
      case 'together':
        return togetherKeyController;
      case 'xai':
        return xaiKeyController;
      case 'perplexity':
        return perplexityKeyController;
      case 'cerebras':
        return cerebrasKeyController;
      case 'fireworks':
        return fireworksKeyController;
      case 'cohere':
        return cohereKeyController;
      case 'huggingface':
        return huggingfaceKeyController;
      case 'xkiro':
        return xkiroKeyController;
      case 'tokenrouter':
        return tokenrouterKeyController;
      case 'custom':
        return customCloudKeyController;
      default:
        return openaiKeyController;
    }
  }

  TextEditingController modelControllerFor(String provider) {
    switch (provider) {
      case 'anthropic':
        return anthropicModelController;
      case 'google':
        return googleModelController;
      case 'kimi':
        return kimiModelController;
      case 'stability':
        return stabilityModelController;
      case 'nvidia':
        return nvidiaModelController;
      case 'openrouter':
        return openRouterModelController;
      case 'deepseek':
        return deepSeekModelController;
      case 'zai':
        return zaiModelController;
      case 'groq':
        return groqModelController;
      case 'mistral':
        return mistralModelController;
      case 'together':
        return togetherModelController;
      case 'xai':
        return xaiModelController;
      case 'perplexity':
        return perplexityModelController;
      case 'cerebras':
        return cerebrasModelController;
      case 'fireworks':
        return fireworksModelController;
      case 'cohere':
        return cohereModelController;
      case 'huggingface':
        return huggingfaceModelController;
      case 'xkiro':
        return xkiroModelController;
      case 'tokenrouter':
        return tokenrouterModelController;
      case 'custom':
        return customCloudModelController;
      default:
        return openaiModelController;
    }
  }

  String get selectedCloudModelName {
    switch (cloudProvider.value) {
      case 'anthropic':
        return anthropicModel.value;
      case 'google':
        return googleModel.value;
      case 'kimi':
        return kimiModel.value;
      case 'stability':
        return stabilityModel.value;
      case 'nvidia':
        return nvidiaModel.value;
      case 'openrouter':
        return openRouterModel.value;
      case 'deepseek':
        return deepSeekModel.value;
      case 'zai':
        return zaiModel.value;
      case 'groq':
        return groqModel.value;
      case 'mistral':
        return mistralModel.value;
      case 'together':
        return togetherModel.value;
      case 'xai':
        return xaiModel.value;
      case 'perplexity':
        return perplexityModel.value;
      case 'cerebras':
        return cerebrasModel.value;
      case 'fireworks':
        return fireworksModel.value;
      case 'cohere':
        return cohereModel.value;
      case 'huggingface':
        return huggingfaceModel.value;
      case 'xkiro':
        return xkiroModel.value;
      case 'tokenrouter':
        return tokenrouterModel.value;
      case 'custom':
        return customCloudModel.value;
      default:
        return openaiModel.value;
    }
  }

  Future<void> setInferenceMode(String mode) async {
    inferenceMode.value = mode;
    await _hive.setSetting(AppConstants.keyInferenceMode, mode);
  }

  Future<void> setCloudProvider(String provider) async {
    cloudProvider.value = provider;
    await _hive.setSetting(AppConstants.keyCloudProvider, provider);
  }

  /// One-time migration: move API keys from the plaintext Hive settings box
  /// into platform secure storage, then wipe them from Hive.
  Future<void> _migrateKeysFromHive() async {
    const migrationDoneKey = 'api_keys_migrated_to_secure';
    try {
      if (_hive.getSetting<bool>(migrationDoneKey) ?? false) return;
      var moved = 0;
      for (final k in _secureOptionKeys) {
        final legacy = _hive.getSetting<String>(k);
        if (legacy != null && legacy.isNotEmpty && _keys.read(k).isEmpty) {
          await _keys.write(k, legacy);
          moved++;
        }
        // Always wipe the plaintext copy from Hive.
        await _hive.deleteSetting(k);
      }
      await _hive.setSetting(migrationDoneKey, true);
      if (moved > 0 && Get.isRegistered<AppLogService>()) {
        Get.find<AppLogService>().info(
            '[SecureKeyStore] Migrated $moved API keys Hive → secure storage',
            category: LogCategory.system);
      }
    } catch (e) {
      if (Get.isRegistered<AppLogService>()) {
        Get.find<AppLogService>().error('API key migration failed',
            details: e.toString(), category: LogCategory.system);
      }
    }
  }

  Future<void> setApiKey(String provider, String key) async {
    final trimmed = key.trim();
    switch (provider) {
      case 'openai':
        openaiKey.value = trimmed;
        openaiKeyController.text = trimmed;
        await _keys.write(AppConstants.keyOpenaiKey, trimmed);
        break;
      case 'anthropic':
        anthropicKey.value = trimmed;
        anthropicKeyController.text = trimmed;
        await _keys.write(AppConstants.keyAnthropicKey, trimmed);
        break;
      case 'google':
        googleKey.value = trimmed;
        googleKeyController.text = trimmed;
        await _keys.write(AppConstants.keyGoogleKey, trimmed);
        break;
      case 'kimi':
        kimiKey.value = trimmed;
        kimiKeyController.text = trimmed;
        await _keys.write(AppConstants.keyKimiKey, trimmed);
        break;
      case 'stability':
        stabilityKey.value = trimmed;
        stabilityKeyController.text = trimmed;
        await _keys.write(AppConstants.keyStabilityKey, trimmed);
        break;
      case 'nvidia':
        nvidiaKey.value = trimmed;
        nvidiaKeyController.text = trimmed;
        await _keys.write(AppConstants.keyNvidiaKey, trimmed);
        await refreshNvidiaModels();
        break;
      case 'openrouter':
        openRouterKey.value = trimmed;
        openRouterKeyController.text = trimmed;
        await _keys.write(AppConstants.keyOpenRouterKey, trimmed);
        break;
      case 'deepseek':
        deepSeekKey.value = trimmed;
        deepSeekKeyController.text = trimmed;
        await _keys.write(AppConstants.keyDeepSeekKey, trimmed);
        break;
      case 'zai':
        zaiKey.value = trimmed;
        zaiKeyController.text = trimmed;
        await _keys.write(AppConstants.keyZaiKey, trimmed);
        break;
      case 'groq':
        groqKey.value = trimmed;
        groqKeyController.text = trimmed;
        await _keys.write(AppConstants.keyGroqKey, trimmed);
        break;
      case 'mistral':
        mistralKey.value = trimmed;
        mistralKeyController.text = trimmed;
        await _keys.write(AppConstants.keyMistralKey, trimmed);
        break;
      case 'together':
        togetherKey.value = trimmed;
        togetherKeyController.text = trimmed;
        await _keys.write(AppConstants.keyTogetherKey, trimmed);
        break;
      case 'xai':
        xaiKey.value = trimmed;
        xaiKeyController.text = trimmed;
        await _keys.write(AppConstants.keyXaiKey, trimmed);
        break;
      case 'perplexity':
        perplexityKey.value = trimmed;
        perplexityKeyController.text = trimmed;
        await _keys.write(AppConstants.keyPerplexityKey, trimmed);
        break;
      case 'cerebras':
        cerebrasKey.value = trimmed;
        cerebrasKeyController.text = trimmed;
        await _keys.write(AppConstants.keyCerebrasKey, trimmed);
        break;
      case 'fireworks':
        fireworksKey.value = trimmed;
        fireworksKeyController.text = trimmed;
        await _keys.write(AppConstants.keyFireworksKey, trimmed);
        break;
      case 'cohere':
        cohereKey.value = trimmed;
        cohereKeyController.text = trimmed;
        await _keys.write(AppConstants.keyCohereKey, trimmed);
        break;
      case 'huggingface':
        huggingfaceKey.value = trimmed;
        huggingfaceKeyController.text = trimmed;
        await _keys.write(AppConstants.keyHuggingFaceKey, trimmed);
        break;
      case 'xkiro':
        xkiroKey.value = trimmed;
        xkiroKeyController.text = trimmed;
        await _keys.write(AppConstants.keyXkiroKey, trimmed);
        break;
      case 'tokenrouter':
        tokenrouterKey.value = trimmed;
        tokenrouterKeyController.text = trimmed;
        await _keys.write(AppConstants.keyTokenRouterKey, trimmed);
        break;      case 'custom':
        customCloudKey.value = trimmed;
        customCloudKeyController.text = trimmed;
        await _keys.write(AppConstants.keyCustomCloudKey, trimmed);
        break;
    }
  }

  void debouncedSetApiKey(String provider, String key) {
    _apiKeyDebounceTimer?.cancel();
    _apiKeyDebounceTimer = Timer(const Duration(milliseconds: 800), () {
      setApiKey(provider, key);
    });
  }

  void cancelApiKeyDebounce() {
    _apiKeyDebounceTimer?.cancel();
  }

  Future<void> removeApiKey(String provider) async {
    await setApiKey(provider, '');
  }

  Future<void> setCloudModel(String provider, String model) async {
    switch (provider) {
      case 'openai':
        openaiModel.value = model;
        openaiModelController.text = model;
        await _hive.setSetting(AppConstants.keyOpenaiModel, model);
        break;
      case 'anthropic':
        anthropicModel.value = model;
        anthropicModelController.text = model;
        await _hive.setSetting(AppConstants.keyAnthropicModel, model);
        break;
      case 'google':
        googleModel.value = model;
        googleModelController.text = model;
        await _hive.setSetting(AppConstants.keyGoogleModel, model);
        break;
      case 'kimi':
        kimiModel.value = model;
        kimiModelController.text = model;
        await _hive.setSetting(AppConstants.keyKimiModel, model);
        break;
      case 'stability':
        stabilityModel.value = model;
        stabilityModelController.text = model;
        await _hive.setSetting(AppConstants.keyStabilityModel, model);
        break;
      case 'nvidia':
        nvidiaModel.value = model;
        nvidiaModelController.text = model;
        await _hive.setSetting(AppConstants.keyNvidiaModel, model);
        break;
      case 'openrouter':
        openRouterModel.value = model;
        openRouterModelController.text = model;
        await _hive.setSetting(AppConstants.keyOpenRouterModel, model);
        break;
      case 'deepseek':
        deepSeekModel.value = model;
        deepSeekModelController.text = model;
        await _hive.setSetting(AppConstants.keyDeepSeekModel, model);
        break;
      case 'zai':
        zaiModel.value = model;
        zaiModelController.text = model;
        await _hive.setSetting(AppConstants.keyZaiModel, model);
        break;
      case 'groq':
        groqModel.value = model;
        groqModelController.text = model;
        await _hive.setSetting(AppConstants.keyGroqModel, model);
        break;
      case 'mistral':
        mistralModel.value = model;
        mistralModelController.text = model;
        await _hive.setSetting(AppConstants.keyMistralModel, model);
        break;
      case 'together':
        togetherModel.value = model;
        togetherModelController.text = model;
        await _hive.setSetting(AppConstants.keyTogetherModel, model);
        break;
      case 'xai':
        xaiModel.value = model;
        xaiModelController.text = model;
        await _hive.setSetting(AppConstants.keyXaiModel, model);
        break;
      case 'perplexity':
        perplexityModel.value = model;
        perplexityModelController.text = model;
        await _hive.setSetting(AppConstants.keyPerplexityModel, model);
        break;
      case 'cerebras':
        cerebrasModel.value = model;
        cerebrasModelController.text = model;
        await _hive.setSetting(AppConstants.keyCerebrasModel, model);
        break;
      case 'fireworks':
        fireworksModel.value = model;
        fireworksModelController.text = model;
        await _hive.setSetting(AppConstants.keyFireworksModel, model);
        break;
      case 'cohere':
        cohereModel.value = model;
        cohereModelController.text = model;
        await _hive.setSetting(AppConstants.keyCohereModel, model);
        break;
      case 'huggingface':
        huggingfaceModel.value = model;
        huggingfaceModelController.text = model;
        await _hive.setSetting(AppConstants.keyHuggingFaceModel, model);
        break;
      case 'xkiro':
        xkiroModel.value = model;
        xkiroModelController.text = model;
        await _hive.setSetting(AppConstants.keyXkiroModel, model);
        break;
      case 'tokenrouter':
        tokenrouterModel.value = model;
        tokenrouterModelController.text = model;
        await _hive.setSetting(AppConstants.keyTokenRouterModel, model);
        break;      case 'custom':
        customCloudModel.value = model;
        customCloudModelController.text = model;
        await _hive.setSetting(AppConstants.keyCustomCloudModel, model);
        break;
    }
  }

  Future<void> setCustomCloudConfig({
    required String name,
    required String baseUrl,
    required String apiKey,
    required String model,
  }) async {
    final normalizedName = name.trim().isEmpty ? 'Custom API' : name.trim();
    final normalizedBaseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

    customCloudName.value = normalizedName;
    customCloudBaseUrl.value = normalizedBaseUrl;
    customCloudKey.value = apiKey.trim();
    customCloudModel.value = model.trim();

    final profile = <String, String>{
      'name': customCloudName.value,
      'baseUrl': customCloudBaseUrl.value,
      'apiKey': customCloudKey.value,
      'model': customCloudModel.value,
    };
    final index = customCloudProfileIndex.value;
    if (index >= 0 && index < customCloudProfiles.length) {
      customCloudProfiles[index] = profile;
    } else {
      customCloudProfiles.add(profile);
      customCloudProfileIndex.value = customCloudProfiles.length - 1;
    }

    customCloudNameController.text = customCloudName.value;
    customCloudBaseUrlController.text = customCloudBaseUrl.value;
    customCloudKeyController.text = customCloudKey.value;
    customCloudModelController.text = customCloudModel.value;

    await _hive.setSetting(
        AppConstants.keyCustomCloudName, customCloudName.value);
    await _hive.setSetting(
        AppConstants.keyCustomCloudBaseUrl, customCloudBaseUrl.value);
    await _keys.write(AppConstants.keyCustomCloudKey, customCloudKey.value);
    await _hive.setSetting(
        AppConstants.keyCustomCloudModel, customCloudModel.value);
    await _saveCustomCloudProfiles();
  }

  Future<void> clearCustomCloudConfig() async {
    final index = customCloudProfileIndex.value;
    if (index >= 0 && index < customCloudProfiles.length) {
      customCloudProfiles.removeAt(index);
    }
    if (customCloudProfiles.isNotEmpty) {
      await selectCustomCloudProfile(
          index.clamp(0, customCloudProfiles.length - 1).toInt());
      return;
    }
    customCloudName.value = 'Custom API';
    customCloudBaseUrl.value = '';
    customCloudKey.value = '';
    customCloudModel.value = '';

    customCloudNameController.text = customCloudName.value;
    customCloudBaseUrlController.clear();
    customCloudKeyController.clear();
    customCloudModelController.clear();

    await _hive.setSetting(
        AppConstants.keyCustomCloudName, customCloudName.value);
    await _hive.setSetting(AppConstants.keyCustomCloudBaseUrl, '');
    await _keys.write(AppConstants.keyCustomCloudKey, '');
    await _hive.setSetting(AppConstants.keyCustomCloudModel, '');
    customCloudProfileIndex.value = -1;
    await _saveCustomCloudProfiles();
  }

  void beginNewCustomCloudProfile() {
    customCloudProfileIndex.value = -1;
    customCloudName.value = 'Custom API';
    customCloudBaseUrl.value = '';
    customCloudKey.value = '';
    customCloudModel.value = '';
    customCloudNameController.text = customCloudName.value;
    customCloudBaseUrlController.clear();
    customCloudKeyController.clear();
    customCloudModelController.clear();
  }

  Future<void> selectCustomCloudProfile(int index) async {
    if (index < 0 || index >= customCloudProfiles.length) return;
    customCloudProfileIndex.value = index;
    final profile = customCloudProfiles[index];
    customCloudName.value = profile['name'] ?? 'Custom API';
    customCloudBaseUrl.value = profile['baseUrl'] ?? '';
    customCloudKey.value = profile['apiKey'] ?? '';
    customCloudModel.value = profile['model'] ?? '';
    customCloudNameController.text = customCloudName.value;
    customCloudBaseUrlController.text = customCloudBaseUrl.value;
    customCloudKeyController.text = customCloudKey.value;
    customCloudModelController.text = customCloudModel.value;
    await _hive.setSetting(
        AppConstants.keyCustomCloudName, customCloudName.value);
    await _hive.setSetting(
        AppConstants.keyCustomCloudBaseUrl, customCloudBaseUrl.value);
    await _keys.write(AppConstants.keyCustomCloudKey, customCloudKey.value);
    await _hive.setSetting(
        AppConstants.keyCustomCloudModel, customCloudModel.value);
    await _hive.setSetting(AppConstants.keyCustomCloudProfileIndex, index);
  }

  void _loadCustomCloudProfiles() {
    final raw = _hive.getSetting<List>(AppConstants.keyCustomCloudProfiles);
    if (raw != null) {
      customCloudProfiles.assignAll(raw.whereType<Map>().map((profile) =>
          profile.map((key, value) =>
              MapEntry(key.toString(), value?.toString() ?? ''))));
      // Custom-profile API keys moved to secure storage: read them back
      // from SecureKeyStore (old Hive copies were wiped by migration).
      for (var i = 0; i < customCloudProfiles.length; i++) {
        final p = customCloudProfiles[i];
        final hiveKey = '${AppConstants.keyCustomCloudKey}_p$i';
        final secureKey = _keys.read(hiveKey);
        if (secureKey.isNotEmpty) {
          p['apiKey'] = secureKey;
        } else if ((p['apiKey'] ?? '').isNotEmpty) {
          // Legacy inline key: move it now.
          unawaited(_keys.write(hiveKey, p['apiKey']!));
        }
      }
    }
    if (customCloudProfiles.isEmpty && customCloudBaseUrl.value.isNotEmpty) {
      final hiveKey = '${AppConstants.keyCustomCloudKey}_p${customCloudProfiles.length}';
      customCloudProfiles.add({
        'name': customCloudName.value,
        'baseUrl': customCloudBaseUrl.value,
        'apiKey': _keys.read(hiveKey).isNotEmpty
            ? _keys.read(hiveKey)
            : customCloudKey.value,
        'model': customCloudModel.value,
      });
    }
    if (customCloudProfiles.isEmpty) return;
    final savedIndex = _hive.getSetting<int>(
            AppConstants.keyCustomCloudProfileIndex,
            defaultValue: 0) ??
        0;
    final index = savedIndex.clamp(0, customCloudProfiles.length - 1).toInt();
    customCloudProfileIndex.value = index;
    final profile = customCloudProfiles[index];
    customCloudName.value = profile['name'] ?? 'Custom API';
    customCloudBaseUrl.value = profile['baseUrl'] ?? '';
    customCloudKey.value = profile['apiKey'] ?? '';
    customCloudModel.value = profile['model'] ?? '';
  }

  Future<void> _saveCustomCloudProfiles() async {
    // Persist API keys in secure storage (indexed), strip them from the
    // plaintext profile list saved to Hive.
    final sanitized = <Map<String, String>>[];
    for (var i = 0; i < customCloudProfiles.length; i++) {
      final p = Map<String, String>.from(customCloudProfiles[i]);
      await _keys.write(
          '${AppConstants.keyCustomCloudKey}_p$i', p['apiKey'] ?? '');
      p['apiKey'] = '';
      sanitized.add(p);
    }
    await _hive.setSetting(
        AppConstants.keyCustomCloudProfiles, sanitized);
    await _hive.setSetting(
        AppConstants.keyCustomCloudProfileIndex, customCloudProfileIndex.value);
  }

  Future<void> setGlobalSystemPrompt(String prompt) async {
    final normalized =
        prompt.trim().isEmpty ? AppConstants.systemPrompt : prompt.trim();
    globalSystemPrompt.value = normalized;
    globalSystemPromptController.text = normalized;
    await _hive.setSetting(AppConstants.keyGlobalSystemPrompt, normalized);
  }

  String baseSystemPromptForModel(String modelName) {
    final prompt = globalSystemPrompt.value.trim();
    final hasCustomPrompt =
        prompt.isNotEmpty && prompt != AppConstants.systemPrompt;
    if (hasCustomPrompt) return prompt;
    if (AppConstants.isUncensoredModelName(modelName)) {
      return AppConstants.uncensoredSystemPrompt;
    }
    return AppConstants.systemPrompt;
  }

  String effectiveSystemPromptForModel(String modelName) {
    return SkillInjector.injectInto(baseSystemPromptForModel(modelName));
  }

  /// Per-prompt selective skill injection — returns the system prompt
  /// with only the skills relevant to [userPrompt] appended.
  String effectiveSystemPromptForPrompt(
      String modelName, String userPrompt) {
    final base = baseSystemPromptForModel(modelName);
    final relevant = SkillInjector.selectRelevantSkills(userPrompt);
    if (relevant.isEmpty) return base;
    return '$base${SkillInjector.buildForSkills(relevant)}';
  }

  Future<void> refreshNvidiaModels() async {
    if (nvidiaKey.value.trim().isEmpty) return;
    isLoadingNvidiaModels.value = true;
    try {
      final response = await http.get(
        Uri.parse('${AppConstants.nvidiaEndpoint}/models'),
        headers: {'Authorization': 'Bearer ${nvidiaKey.value.trim()}'},
      );
      if (response.statusCode != 200) {
        Get.find<AppLogService>().warning(
          'NVIDIA model list request failed',
          details: '${response.statusCode}: ${response.body}',
          category: LogCategory.cloud,
        );
        return;
      }
      final data = jsonDecode(response.body);
      final rawModels = data['data'] as List? ?? [];
      nvidiaModels.value = rawModels
          .map((model) => model is Map ? model['id']?.toString() : null)
          .whereType<String>()
          .toList();
    } catch (e) {
      Get.find<AppLogService>()
          .warning('NVIDIA model list request failed', details: e, category: LogCategory.cloud);
    } finally {
      isLoadingNvidiaModels.value = false;
    }
  }

  void debouncedSetCloudModel(String provider, String model) {
    _modelDebounceTimer?.cancel();
    _modelDebounceTimer = Timer(const Duration(milliseconds: 800), () {
      setCloudModel(provider, model);
    });
  }

  void cancelModelDebounce() {
    _modelDebounceTimer?.cancel();
  }

  Future<void> setTemperature(double value) async {
    temperature.value = value;
    await _hive.setSetting(AppConstants.keyTemperature, value);
  }

  Future<void> setMaxTokens(int value) async {
    maxTokens.value = value;
    await _hive.setSetting(AppConstants.keyMaxTokens, value);
  }

  Future<void> setContextSize(int value) async {
    int clamped = value;
    if (Get.isRegistered<DeviceInfoService>()) {
      final dev = Get.find<DeviceInfoService>();
      if (clamped > dev.maxSafeContextSize) {
        clamped = dev.maxSafeContextSize;
        Get.snackbar('RAM Guard', 'Clamped to ${dev.maxSafeContextSize} for ${dev.deviceTier.value} tier',
            snackPosition: SnackPosition.BOTTOM);
      }
      if (!dev.canAllocateContextSize(clamped)) {
        clamped = dev.recommendedContextSize;
        Get.snackbar('RAM Guard', 'Not enough RAM — using ${dev.recommendedContextSize}',
            snackPosition: SnackPosition.BOTTOM);
      }
    }
    contextSize.value = clamped;
    await _hive.setSetting(AppConstants.keyContextSize, clamped);
    _scheduleContextReload();
  }

  // ── Auto Tune ──

  /// RAM-tier context size when Auto is on, else the manual slider value.
  int get effectiveContextSize {
    if (!autoTuneParams.value) return contextSize.value;
    if (Get.isRegistered<DeviceInfoService>()) {
      return Get.find<DeviceInfoService>().recommendedContextSize;
    }
    return contextSize.value;
  }

  /// Output budget: scales with the effective context in Auto mode
  /// (~25% of the window), so long detailed answers never get cut off.
  int get effectiveMaxTokens {
    if (!autoTuneParams.value) return maxTokens.value;
    final ctx = effectiveContextSize;
    return (ctx ~/ 4).clamp(512, 16384);
  }

  /// Persist tuned values into the Hive keys the native loaders read.
  Future<void> _applyAutoTune({bool writeSettings = true}) async {
    final ctx = effectiveContextSize;
    final tok = effectiveMaxTokens;
    contextSize.value = ctx;
    maxTokens.value = tok;
    if (writeSettings) {
      await _hive.setSetting(AppConstants.keyContextSize, ctx);
      await _hive.setSetting(AppConstants.keyMaxTokens, tok);
      _scheduleContextReload();
    }
  }

  Future<void> setAutoTuneParams(bool enabled) async {
    autoTuneParams.value = enabled;
    await _hive.setSetting(AppConstants.keyAutoTuneParams, enabled);
    if (enabled) await _applyAutoTune();
  }

  Future<void> setWebFetchEnabled(bool enabled) async {
    webFetchEnabled.value = enabled;
    await _hive.setSetting(AppConstants.keyWebFetchEnabled, enabled);
  }

  Future<void> dismissComposerUpsell() async {
    composerUpsellDismissed.value = true;
    await _hive.setSetting(AppConstants.keyComposerUpsellDismissed, true);
  }

  Timer? _contextReloadTimer;
  bool _isReloadingForContext = false;

  /// Context size is baked into the model at load time, so a live reload is
  /// required for the change to take effect. Debounced because the slider
  /// fires onChanged continuously while dragging.
  void _scheduleContextReload() {
    if (_isReloadingForContext) return;
    _contextReloadTimer?.cancel();
    _contextReloadTimer = Timer(const Duration(milliseconds: 900), () {
      _reloadTextModelForContextSize();
    });
  }

  Future<void> _reloadTextModelForContextSize() async {
    try {
      if (!Get.isRegistered<InferenceService>()) return;
      final inference = Get.find<InferenceService>();
      if (!inference.isModelLoaded.value ||
          inference.isLoadingModel.value ||
          inference.isGenerating.value ||
          _isReloadingForContext) {
        // No model resident (or busy): the saved value applies on next load.
        return;
      }
      final path =
          _hive.getSetting<String>(AppConstants.keyLocalModelPath) ?? '';
      if (path.isEmpty) return;
      final name =
          _hive.getSetting<String>(AppConstants.keyLocalModelName) ?? '';
      final runtime =
          _hive.getSetting<String>(AppConstants.keyLocalModelRuntime) ?? '';
      final wasVision = inference.isVisionLoaded.value;

      _isReloadingForContext = true;
      Get.snackbar(
        'Context Size',
        'Reloading ${name.isNotEmpty ? name : 'model'} to apply the new context window…',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
      await inference.loadModel(
        path,
        modelName: name.isEmpty ? null : name,
        modelRuntime: runtime.isEmpty ? null : runtime,
        enableLiteRtVision: wasVision,
      );
      _isReloadingForContext = false;
    } catch (e) {
      _isReloadingForContext = false;
      Get.find<AppLogService>().error(
        'Context-size reload failed',
        details: e.toString(),
        category: LogCategory.model,
      );
    }
  }

  Future<void> setLiteRtPerformanceMode(String mode) async {
    final normalized = switch (mode) {
      'gpu_fast' => 'gpu_fast',
      'cpu_safe' => 'cpu_safe',
      _ => AppConstants.defaultLiteRtPerformanceMode,
    };
    liteRtPerformanceMode.value = normalized;
    await _hive.setSetting(AppConstants.keyLiteRtPerformanceMode, normalized);
    if (normalized == 'gpu_fast') {
      await _hive.setSetting(AppConstants.keyLiteRtGpuCrashDetected, false);
    }
  }

  Future<void> setImageSteps(int value) async {
    imageSteps.value = value;
    await _hive.setSetting(AppConstants.keyImageSteps, value);
  }

  Future<void> setImageGenForceCpu(bool value) async {
    imageGenForceCpu.value = value;
    await _hive.setSetting(AppConstants.keyImageGenForceCpu, value);
  }

  Future<void> setImageGenGpuGuardMb(int value) async {
    imageGenGpuGuardMb.value = value;
    await _hive.setSetting(AppConstants.keyImageGenGpuGuardMb, value);
  }

  Future<void> setImageGenSize(int value) async {
    final allowed = value == 0 ||
        value == 256 ||
        value == 320 ||
        value == 384 ||
        value == 512;
    final normalized = allowed ? value : AppConstants.defaultImageGenSize;
    imageGenSize.value = normalized;
    await _hive.setSetting(AppConstants.keyImageGenSize, normalized);
  }

  Future<void> _detectImageGpu() async {
    try {
      imageGpuVendor.value = await SdFlutterAndroid.detectGpuVendor();
    } catch (_) {
      imageGpuVendor.value = 'unknown';
    }
  }

  Backend recommendedImageGpuBackend() {
    final vendor = imageGpuVendor.value;
    final preferred = switch (vendor) {
      'adreno' => Backend.opencl,
      'mali' || 'xclipse' || 'powervr' || 'imagination' => Backend.vulkan,
      _ => Backend.vulkan,
    };
    if (preferred.isAvailable) return preferred;
    if (Backend.opencl.isAvailable) return Backend.opencl;
    if (Backend.vulkan.isAvailable) return Backend.vulkan;
    return Backend.cpu;
  }

  String imageGpuLabel() {
    final vendor = imageGpuVendor.value;
    final backend = recommendedImageGpuBackend();
    final vendorLabel = vendor == 'detecting'
        ? 'Detecting'
        : vendor == 'unknown'
            ? 'Unknown GPU'
            : vendor.toUpperCase();
    return backend == Backend.cpu
        ? '$vendorLabel - GPU unavailable'
        : '$vendorLabel - ${backend.displayName}';
  }

  Future<void> setImageBackendMode(bool useGpu) async {
    final backend = useGpu ? recommendedImageGpuBackend() : Backend.cpu;
    imageGenBackend.value = backend;
    imageGenForceCpu.value = !useGpu || backend == Backend.cpu;
    await _hive.setSetting(AppConstants.keyImageGenBackend, backend.index);
    await _hive.setSetting(
        AppConstants.keyImageGenForceCpu, imageGenForceCpu.value);
    if (!Get.isRegistered<LocalImageService>()) return;
    final image = Get.find<LocalImageService>();
    final previous = image.currentBackend.value;
    image.setBackend(backend);
    // The backend only takes effect at load time — reload a resident image
    // model immediately so the toggle is not silently ignored.
    if (image.isModelLoaded.value &&
        !image.isLoadingModel.value &&
        !image.isGenerating.value &&
        previous != backend) {
      await _reloadImageModelForBackend();
    }
  }

  Future<void> _reloadImageModelForBackend() async {
    try {
      final image = Get.find<LocalImageService>();
      final path =
          _hive.getSetting<String>(AppConstants.keyImageModelPath) ?? '';
      final name =
          _hive.getSetting<String>(AppConstants.keyImageModelName) ?? '';
      if (path.isEmpty) return;
      Get.snackbar(
        'Compute Backend',
        'Reloading ${name.isNotEmpty ? name : 'image model'} on ${imageGenBackend.value == Backend.cpu ? 'CPU' : 'GPU'}…',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
      String? taesdPath;
      try {
        if (Get.isRegistered<DownloadService>() &&
            await Get.find<DownloadService>()
                .isModelDownloaded('taesd.safetensors')) {
          taesdPath = await Get.find<DownloadService>()
              .modelPath('taesd.safetensors');
        }
      } catch (_) {}
      await image.unloadModel();
      final result = await image.loadModel(path,
          modelName: name.isEmpty ? null : name, taesdPath: taesdPath);
      final ok = image.isModelLoaded.value;
      Get.snackbar(
        ok ? 'Compute Backend' : 'Reload Failed',
        result,
        snackPosition: SnackPosition.BOTTOM,
        duration: Duration(seconds: ok ? 2 : 6),
      );
    } catch (e) {
      Get.find<AppLogService>().error(
        'Backend reload failed',
        details: e.toString(),
        category: LogCategory.model,
      );
    }
  }

  Future<void> setFontScale(double value) async {
    final clamped = value.clamp(0.8, 1.4);
    fontScale.value = clamped;
    await _hive.setSetting(AppConstants.keyFontScale, clamped);
  }

  Future<void> setLocale(AppLanguage lang) async {
    locale.value = lang;
    await _hive.setSetting(AppConstants.keyLanguage, lang.code);
    Get.updateLocale(lang.locale);
  }

  /// Persist a thinking-orb animation choice ('random' | OrbState name).
  Future<void> setOrbAnim(String slot, String value) async {
    switch (slot) {
      case 'chat':
        orbChatAnim.value = value;
        await _hive.setSetting(AppConstants.keyOrbChat, value);
        break;
      case 'image':
        orbImageAnim.value = value;
        await _hive.setSetting(AppConstants.keyOrbImage, value);
        break;
      case 'analysis':
        orbAnalysisAnim.value = value;
        await _hive.setSetting(AppConstants.keyOrbAnalysis, value);
        break;
    }
  }

  Future<void> setAutoLoadLastModel(bool enabled) async {
    autoLoadLastModel.value = enabled;
    await _hive.setSetting(AppConstants.keyAutoLoadLastModel, enabled);
  }

  Future<void> setReadAloudEnabled(bool enabled) async {
    readAloudEnabled.value = enabled;
    await _hive.setSetting(AppConstants.keyReadAloud, enabled);
  }

  // ─── App Lock (biometric gate) ──────────────────

  final _localAuth = la.LocalAuthentication();

  Future<void> _detectBiometrics() async {
    if (kIsWeb) {
      biometricsAvailable.value = false;
      hasEnrolledBiometrics.value = false;
      if (!_biometricsDetected.isCompleted) _biometricsDetected.complete();
      return;
    }
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final supported = await _localAuth.isDeviceSupported();
      biometricsAvailable.value = canCheck || supported;
      // Enrollment matters: isDeviceSupported() is true on Windows as soon
      // as the OS supports Hello — even with zero methods enrolled.
      try {
        hasEnrolledBiometrics.value =
            (await _localAuth.getAvailableBiometrics()).isNotEmpty;
      } catch (_) {
        hasEnrolledBiometrics.value = false;
      }
    } catch (_) {
      biometricsAvailable.value = false;
      hasEnrolledBiometrics.value = false;
    } finally {
      if (!_biometricsDetected.isCompleted) _biometricsDetected.complete();
    }
  }

  Future<void> setAppLockEnabled(bool enabled) async {
    if (enabled) {
      // Require a successful authentication before arming the lock so the
      // user can't lock themselves out on a device without enrolled biometrics.
      final ok = await authenticate(
          reason: 'Confirm your identity to enable App Lock');
      if (!ok) {
        appLockEnabled.value = false;
        await _hive.setSetting(AppConstants.keyAppLockEnabled, false);
        return;
      }
    }
    appLockEnabled.value = enabled;
    await _hive.setSetting(AppConstants.keyAppLockEnabled, enabled);
    if (!enabled) isLocked.value = false;
  }

  /// Runs the platform biometric/PIN prompt. Fails open (returns true) when
  /// no biometric hardware is available so the app never becomes unusable.
  Future<bool> authenticate({String reason = 'Unlock CubicLM'}) async {
    if (kIsWeb || !biometricsAvailable.value) return true;
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const la.AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    await _hive.setSetting('theme_mode', mode.name);
    Get.changeThemeMode(mode);
    _updateSystemUI();
  }

  void _updateSystemUI() {
    final isDark = themeMode.value == ThemeMode.dark ||
        (themeMode.value == ThemeMode.system &&
            Get.mediaQuery.platformBrightness == Brightness.dark);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: isDark ? Colors.black : Colors.white,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    ));
  }

  static ThemeMode _themeModeFromString(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}
