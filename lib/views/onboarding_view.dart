import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/constants.dart';
import '../models/ai_model.dart';
import '../services/device_info_service.dart';
import '../services/download_service.dart';
import '../services/hive_service.dart';
import '../core/routes.dart';
import '../theme/design_tokens.dart';

class OnboardingView extends StatefulWidget {
  const OnboardingView({super.key});

  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<OnboardingView> {
  final _page = PageController();
  int _index = 0;

  // Recommended model download state
  AiModel? _recommendedModel;
  final _isDownloading = false.obs;
  final _downloadProgress = 0.0.obs;
  final _downloadComplete = false.obs;

  @override
  void initState() {
    super.initState();
    _resolveRecommendedModel();
  }

  void _resolveRecommendedModel() {
    if (!Get.isRegistered<DeviceInfoService>()) return;
    final tier = Get.find<DeviceInfoService>().deviceTier.value;
    _recommendedModel = _modelForTier(tier);
  }

  AiModel? _modelForTier(String tier) {
    const models = AppConstants.availableModels;
    switch (tier) {
      case 'low':
        // ~400 MB GGUF
        return _findModel(models, 'LFM2.5-230M-F16.gguf') ??
            _findModel(models, 'SmolLM2-360M-Instruct-f16.gguf');
      case 'mid':
        // ~2 GB GGUF
        return _findModel(models, 'qwen2.5-3b-instruct-q4_k_m.gguf') ??
            _findModel(models, 'gemma-2-2b-it-q4_k_m.gguf');
      case 'high':
      case 'ultra':
        // ~4.5 GB GGUF — but we cap at available 3B models for practicality
        return _findModel(models, 'qwen2.5-3b-instruct-q4_k_m.gguf') ??
            _findModel(models, 'moonlight-16b-a3b-instruct-q3_k_s.gguf');
      default:
        return _findModel(models, 'qwen2.5-3b-instruct-q4_k_m.gguf');
    }
  }

  AiModel? _findModel(List<Map<String, String>> list, String filename) {
    for (final m in list) {
      if (m['filename'] == filename) return AiModel.fromMap(m);
    }
    return null;
  }

  Future<void> _downloadRecommended() async {
    final model = _recommendedModel;
    if (model == null) return;

    if (!Get.isRegistered<DownloadService>()) return;
    final dl = Get.find<DownloadService>();
    if (await dl.isModelDownloaded(model.filename)) {
      _downloadComplete.value = true;
      return;
    }

    _isDownloading.value = true;
    _downloadProgress.value = 0.0;

    // Poll progress while download runs in background.
    // DownloadService stores the DownloadProgress in activeDownloads immediately.
    Timer? timer;
    timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final dp = dl.activeDownloads[model.filename];
      if (dp != null) {
        _downloadProgress.value = dp.progress.value;
      }
    });

    try {
      await dl.downloadModel(url: model.url, filename: model.filename);
      _downloadComplete.value = true;
      _isDownloading.value = false;
      timer.cancel();

      try {
        final hive = Get.find<HiveService>();
        await hive.setSetting(AppConstants.keyLocalModelPath, model.filename);
        await hive.setSetting(AppConstants.keyLocalModelName, model.name);
        await hive.setSetting(AppConstants.keyLocalModelRuntime, model.runtime);
      } catch (_) {}
    } catch (e) {
      _isDownloading.value = false;
      timer.cancel();
      Get.snackbar('Download Failed', '$e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  void _next() {
    if (_index < 2) {
      _page.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    try {
      if (Get.isRegistered<HiveService>()) {
        await Get.find<HiveService>().setSetting(AppConstants.keyOnboardingDone, true);
      }
    } catch (_) {}
    Get.offAllNamed(AppRoutes.home);
  }

  Future<void> _skip() async {
    try {
      if (Get.isRegistered<HiveService>()) {
        await Get.find<HiveService>().setSetting(AppConstants.keyOnboardingDone, true);
      }
    } catch (_) {}
    Get.offAllNamed(AppRoutes.home);
  }

  Future<void> _openHub() async {
    try {
      if (Get.isRegistered<HiveService>()) {
        final hive = Get.find<HiveService>();
        await hive.setSetting(AppConstants.keyOnboardingDone, true);
        await hive.setSetting('onboarding_open_hub', true);
      }
    } catch (_) {}
    Get.offAllNamed(AppRoutes.home);
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Widget _buildRecommendedDownload(bool isDark) {
    final model = _recommendedModel;
    if (model == null) return const SizedBox.shrink();

    return Obx(() {
      final downloading = _isDownloading.value;
      final progress = _downloadProgress.value;
      final complete = _downloadComplete.value;

      return Column(
        children: [
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Dt.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Dt.accent.withValues(alpha: 0.15)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.sparkles, size: 16, color: Dt.accent),
                const SizedBox(width: 8),
                Text('onboarding_recommended'.tr,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, fontWeight: FontWeight.w700, color: Dt.accent)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(model.name,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('${model.size}  •  ${model.description}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11, color: Theme.of(context).hintColor)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (complete)
            Container(
              width: double.infinity,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.checkCircle, size: 18, color: Colors.green),
                    const SizedBox(width: 8),
                    Text('onboarding_download_complete'.tr,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.green)),
                  ],
                ),
              ),
            )
          else if (downloading)
            Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress > 0 ? progress : null,
                    minHeight: 6,
                    backgroundColor:
                        Theme.of(context).hintColor.withValues(alpha: 0.1),
                    color: Dt.accent,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  progress > 0
                      ? '${'onboarding_downloading'.tr} ${(progress * 100).round()}%'
                      : '${'onboarding_downloading'.tr}…',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Dt.accent),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Dt.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  textStyle: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700, fontSize: 13),
                ),
                onPressed: _downloadRecommended,
                icon: const Icon(LucideIcons.download, size: 18),
                label: Text('${'onboarding_download'.tr} ${model.name}'),
              ),
            ),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Dt.canvasDark : Dt.canvas;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Spacer(),
                  if (_index < 2)
                    TextButton(
                      onPressed: _skip,
                      child: Text('onboarding_skip'.tr,
                          style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w600, color: Theme.of(context).hintColor)),
                    )
                  else
                    const SizedBox(height: 48),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _page,
                onPageChanged: (i) => setState(() => _index = i),
                children: [
                  _OnboardPage(
                    icon: LucideIcons.shieldCheck,
                    title: 'onboarding_page1_title'.tr,
                    desc: 'onboarding_page1_desc'.tr,
                    isDark: isDark,
                  ),
                  _OnboardPage(
                    icon: LucideIcons.cloud,
                    title: 'onboarding_page2_title'.tr,
                    desc: 'onboarding_page2_desc'.tr,
                    isDark: isDark,
                  ),
                  _OnboardPage(
                    icon: LucideIcons.download,
                    title: 'onboarding_page3_title'.tr,
                    desc: 'onboarding_page3_desc'.tr,
                    isDark: isDark,
                    extra: _buildRecommendedDownload(isDark),
                  ),
                ],
              ),
            ),
            // Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (i) {
                final sel = i == _index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: sel ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: sel ? Dt.accent : Theme.of(context).hintColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Dt.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  onPressed: _next,
                  child: Text(_index == 2 ? 'onboarding_start'.tr : 'onboarding_next'.tr),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_index == 2)
              TextButton(
                onPressed: _openHub,
                child: Text('onboarding_open_hub'.tr,
                    style: GoogleFonts.plusJakartaSans(color: Dt.accent, fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _OnboardPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  final bool isDark;
  final Widget? extra;
  const _OnboardPage({required this.icon, required this.title, required this.desc, required this.isDark, this.extra});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: Dt.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(icon, size: 44, color: Dt.accent),
          ),
          const SizedBox(height: 32),
          Text(title,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.1)),
          const SizedBox(height: 12),
          Text(desc,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 15, height: 1.5, fontWeight: FontWeight.w500, color: Theme.of(context).hintColor)),
          if (extra != null) extra!,
        ],
      ),
    );
  }
}
