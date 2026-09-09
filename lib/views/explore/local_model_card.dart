import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../controllers/model_controller.dart';
import '../../core/colors.dart';
import '../../models/ai_model.dart';
import '../../services/app_log_service.dart';
import '../../services/download_service.dart';
import '../../services/inference_service.dart';
import '../../services/local_image_service.dart';
import '../../theme/design_tokens.dart';
import 'provider_cards.dart';

/// Local model card + download confirm + progress.
/// Extracted from views/model_view.dart.

ModelController get _c => Get.find<ModelController>();

/// Load guarded end-to-end: any Dart-side throw (even before the first
/// await) becomes a persisted log row + snackbar instead of a silent
/// zone error. Native kills are covered by the load breadcrumb.
Future<void> _guardedLoad(String filename) async {
  try {
    await _c.loadModel(filename);
  } catch (e) {
    try {
      Get.find<AppLogService>().error(
        'Model load threw: $filename',
        details: '$e',
        category: LogCategory.model,
      );
    } catch (_) {}
    Get.snackbar(
      'Load failed',
      '$e',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 6),
    );
  }
}

void confirmDownload(BuildContext context, AiModel model,
    {bool isToDownloadsFolder = false}) {
  // Honor the card's quant pick: everything below stays filename-keyed.
  model = _c.resolveForDownload(model);
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(
            isToDownloadsFolder
                ? Icons.save_alt
                : Icons.cloud_download_outlined,
            color: Dt.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isToDownloadsFolder
                  ? 'model_save_to_downloads'.tr
                  : 'model_download_title'.tr,
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isToDownloadsFolder
                ? 'You are about to save ${model.name} to ${_c.saveToDownloadsLabel}.'
                : 'You are about to download ${model.name} for use in the app.',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sd_storage_outlined, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Size: ${_c.modelSizeLabel(model)}',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.wifi, color: AppColors.warning, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'model_wifi_warning'.tr,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: AppColors.warning,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          // ── Desktop/Web have no on-device engine: set expectations
          // before the user downloads gigabytes they cannot load. ──
          if (!_c.supportsLocalInference) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Dt.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Dt.accent.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.cloud, color: Dt.accent, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'On-device loading needs the Android app. On this device, chat with models via Cloud mode.',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18),
          ),
          child: Text('common_cancel'.tr,
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700, color: Theme.of(ctx).hintColor)),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            if (isToDownloadsFolder) {
              _c.downloadModelToDownloads(model);
            } else {
              _c.downloadModel(model);
            }
          },
          style: FilledButton.styleFrom(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 20),
          ),
          child: Text(
              isToDownloadsFolder
                  ? 'model_save_now'.tr
                  : 'model_download_now'.tr,
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );
}

Widget buildModelCard(BuildContext context, AiModel model) {
  return Obx(() {
    final isDownloaded = _c.isDownloaded(model.filename);
    final inference = Get.find<InferenceService>();
    final localImage = Get.find<LocalImageService>();
    final isActive = inference.loadedModelName.value == model.filename ||
        localImage.loadedModelName.value == model.filename;
    final isCurrentlyDownloading = _c.isDownloadingModel(model.filename);
    final isAnyModelLoading =
        inference.isLoadingModel.value || localImage.isLoadingModel.value;
    final isThisTextModelLoading = inference.isLoadingModel.value &&
        inference.loadingModelName.value == model.filename;
    final isThisImageModelLoading = localImage.isLoadingModel.value &&
        localImage.loadedModelName.value == model.filename;
    final isThisModelLoading =
        isThisTextModelLoading || isThisImageModelLoading;
    final disableActions =
        _c.isImporting.value || isAnyModelLoading || isCurrentlyDownloading;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color:
              isActive ? Dt.accent.withValues(alpha: 0.2) : Colors.transparent,
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: isActive || disableActions
            ? null
            : () => _guardedLoad(model.filename),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                model.name,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                              ),
                            ),
                            if (isActive)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.success.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('ACTIVE',
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.success)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        buildModelBadges(context, model),
                        const SizedBox(height: 8),
                        Text(
                          model.description,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: Theme.of(context).hintColor,
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(LucideIcons.hardDrive,
                                size: 12,
                                color: Theme.of(context)
                                    .hintColor
                                    .withValues(alpha: 0.5)),
                            const SizedBox(width: 4),
                            Text(
                              _c.modelSizeLabel(model),
                              style: GoogleFonts.firaCode(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .hintColor
                                    .withValues(alpha: 0.7),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        // Quant picker — only for catalog entries that
                        // ship variants, and only before anything is
                        // downloaded (state below is filename-keyed).
                        if (model.variants.isNotEmpty &&
                            !isDownloaded &&
                            !isCurrentlyDownloading) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final opt in model.variantOptions())
                                ChoiceChip(
                                  label: Text(
                                    opt.filename == model.filename
                                        ? 'Default'
                                        : (model.variants
                                            .firstWhere(
                                              (v) => v.filename == opt.filename,
                                              orElse: () => ModelVariant(
                                                  quant: opt.filename,
                                                  filename: opt.filename,
                                                  url: opt.url),
                                            )
                                            .quant),
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700),
                                  ),
                                  selected:
                                      _c.resolveForDownload(model).filename ==
                                          opt.filename,
                                  selectedColor:
                                      Dt.accent.withValues(alpha: 0.2),
                                  onSelected: (_) =>
                                      _c.selectVariant(model, opt.filename),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!isCurrentlyDownloading && isDownloaded)
                    Padding(
                      padding: const EdgeInsets.only(left: 12, top: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isActive)
                            TextButton(
                              onPressed: disableActions
                                  ? null
                                  : () => _c.unloadModel(),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.warning,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('Unload'),
                            )
                          else
                            Tooltip(
                              message: _c.supportsLocalInference
                                  ? 'Load model'
                                  : 'On-device models need the Android app — use Cloud mode',
                              child: FilledButton(
                                onPressed: (disableActions ||
                                        !_c.supportsLocalInference)
                                    ? null
                                    : () => _guardedLoad(model.filename),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Dt.accent,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text('Load'),
                              ),
                            ),
                          const SizedBox(width: 4),
                          IconButton(
                            tooltip: 'Delete model',
                            onPressed: disableActions
                                ? null
                                : () =>
                                    confirmDeleteModel(context, model.filename),
                            icon: Icon(
                              LucideIcons.trash2,
                              size: 20,
                              color: AppColors.error.withValues(alpha: 0.6),
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 32, minHeight: 32),
                          ),
                        ],
                      ),
                    )
                  else if (!isCurrentlyDownloading && !isDownloaded)
                    Padding(
                      padding: const EdgeInsets.only(left: 12, top: 4),
                      child: IconButton(
                        tooltip: 'Download model',
                        onPressed: disableActions
                            ? null
                            : () => confirmDownload(context, model),
                        icon: const Icon(
                          LucideIcons.download,
                          size: 22,
                          color: Dt.accent,
                        ),
                      ),
                    ),
                ],
              ),
              if (isCurrentlyDownloading) ...[
                const SizedBox(height: 16),
                buildInlineDownloadProgress(context, model),
              ],
              if (isThisModelLoading) ...[
                const SizedBox(height: 16),
                buildModelLoadingProgress(context, model),
              ],
            ],
          ),
        ),
      ),
    );
  });
}

Widget buildInlineDownloadProgress(BuildContext context, AiModel model) {
  final dp = _c.getDownloadProgress(model.filename)!;
  return Obx(() {
    final percent = dp.progress.value * 100;
    final totalLabel = dp.totalBytes.value > 0
        ? DownloadService.formatWholeMb(dp.totalBytes.value)
        : _c.modelSizeLabel(model);
    final remaining = dp.totalBytes.value <= 0
        ? 0
        : (dp.totalBytes.value - dp.downloadedBytes.value)
            .clamp(0, dp.totalBytes.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: dp.progress.value > 0 ? dp.progress.value : null,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            color: AppColors.secondary,
            minHeight: 5,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text(
              '${percent.toStringAsFixed(1)}%',
              style: GoogleFonts.firaCode(
                fontSize: 13,
                color: AppColors.secondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                DownloadService.formatSpeed(dp.bytesPerSecond.value),
                style: GoogleFonts.firaCode(
                  fontSize: 12,
                  color: AppColors.secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Spacer(),
            if (dp.isPaused.value)
              TextButton.icon(
                onPressed: () => _c.resumeDownload(model.filename),
                icon: const Icon(LucideIcons.play, size: 16),
                label: const Text('Resume'),
                style: TextButton.styleFrom(foregroundColor: AppColors.success),
              )
            else
              TextButton.icon(
                onPressed: () => _c.pauseDownload(model.filename),
                icon: const Icon(LucideIcons.pause, size: 16),
                label: const Text('Pause'),
                style: TextButton.styleFrom(foregroundColor: AppColors.warning),
              ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: () => _c.cancelDownload(model.filename),
              icon: const Icon(Icons.close, size: 16),
              label: Text('common_cancel'.tr),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            Text(
              '${DownloadService.formatWholeMb(dp.downloadedBytes.value)} / $totalLabel',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11, color: Theme.of(context).hintColor),
            ),
            if (dp.totalBytes.value > 0)
              Text(
                '${DownloadService.formatWholeMb(remaining)} left',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, color: Theme.of(context).hintColor),
              ),
            Text(
              'ETA: ${DownloadService.formatDuration(dp.eta)}',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11, color: Theme.of(context).hintColor),
            ),
          ],
        ),
      ],
    );
  });
}

Widget buildErrorBox(BuildContext context, String error) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: AppColors.error.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
    ),
    child: Text(
      error,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 11,
        color: AppColors.error,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}
