import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../controllers/cloud_model_controller.dart';
import '../controllers/model_controller.dart';
import '../controllers/settings_controller.dart';
import '../core/colors.dart';
import '../services/cloud/model_health.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/design_tokens.dart';
import '../models/ai_model.dart';
import '../services/download_service.dart';
import '../services/usage_tracker_service.dart';
import '../services/inference_service.dart';
import '../services/local_image_service.dart';
import 'explore_skills_mcp_tabs.dart';
import 'explore/add_model_sheet.dart';
import 'explore/toolkit_tab.dart';
import 'gallery_view.dart';

class ModelView extends GetView<ModelController> {
  const ModelView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? Dt.canvasDark : Dt.canvas,
      appBar: AppBar(
        backgroundColor: (isDark ? Dt.canvasDark : Dt.canvas).withValues(alpha: 0.8),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(color: Colors.transparent),
          ),
        ),
        title: Text('model_hub_title'.tr,
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 24, letterSpacing: -0.5)),
        actions: [
          Obx(() {
            if (controller.exploreTab.value != 'hub' ||
                controller.modelScope.value != 'local') {
              return const SizedBox.shrink();
            }
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(LucideIcons.link),
                  tooltip: 'model_add_url_title'.tr,
                  onPressed: () => showAddModelUrlDialog(context, controller),
                ),
                IconButton(
                  icon: const Icon(Icons.file_upload_outlined),
                  tooltip: 'Import from Storage',
                  onPressed: () => controller.importModelFromStorage(),
                ),
              ],
            );
          }),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _buildExploreTabs(context),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Obx(() {
              if (controller.exploreTab.value == 'toolkit') {
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    buildToolkitTab(context),
                  ],
                );
              }
              return Column(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildScopeToggle(context),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildActiveModelBanner(context),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _buildHubList(context),
                ),
              ]);
            }),
          ),
        ],
      ),
    );
  }

  /// Top-level Explore tabs: Model Hub (existing scopes) | Toolkit.
  Widget _buildExploreTabs(BuildContext context) {
    return Obx(() => SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'hub',
              icon: Icon(LucideIcons.boxes, size: 16),
              label: Text('Model Hub', style: TextStyle(fontSize: 13)),
            ),
            ButtonSegment(
              value: 'toolkit',
              icon: Icon(LucideIcons.wrench, size: 16),
              label: Text('Toolkit', style: TextStyle(fontSize: 13)),
            ),
          ],
          selected: {controller.exploreTab.value},
          onSelectionChanged: (s) =>
              controller.exploreTab.value = s.first,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ));
  }

  /// Toolkit tab: Battle Arena + Slide Maker as widget cards with
  /// descriptions (moved here from the chat ⋮ menu).

  Widget _buildHubList(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        if (controller.modelScope.value == 'local') {
          await controller.refreshDownloaded();
        }
      },
      color: Dt.accent,
      child: Obx(() => ListView(
            padding: const EdgeInsets.all(16),
            children: [
                      if (controller.modelScope.value == 'local') ...[
                  _buildImportingProgress(context),
                  _buildLocalFilterChips(context),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "${'model_local_models'.tr} (${controller.filteredDisplayedModels.length})",
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).hintColor,
                          letterSpacing: 1.2,
                        ),
                      ),
                      InkWell(
                        onTap: controller.toggleSort,
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.sort,
                                size: 14,
                                color: Theme.of(context).hintColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                controller.sortSmallestFirst.value
                                    ? 'model_sort_size'.tr
                                    : 'model_sort_name'.tr,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).hintColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (controller.filteredDisplayedModels.isEmpty)
                    _buildEmptyLocalState(context)
                  else
                    ...controller.filteredDisplayedModels
                        .map((model) => _buildModelCard(context, model)),
                ] else if (controller.modelScope.value == 'online') ...[
                  _buildOnlineProviders(context),
                ] else if (controller.modelScope.value == 'skills') ...[
                  _buildSkillsTab(context),
                ] else if (controller.modelScope.value == 'mcp') ...[
                  _buildMcpTab(context),
                ] else if (controller.modelScope.value == 'gallery') ...[
                  _buildGalleryTab(context),
                ],
              ],
            )),
          );
  }

  Widget _buildScopeToggle(BuildContext context) {
    return Obx(() {
      // Ensure legacy value still works; keep 5-way toggle incl. gallery.
      final sel = controller.modelScope.value;
      final normalized = (sel == 'local' ||
              sel == 'online' ||
              sel == 'skills' ||
              sel == 'mcp' ||
              sel == 'gallery')
          ? sel
          : 'local';
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<String>(
          segments: [
            ButtonSegment(
              value: 'local',
              icon: const Icon(LucideIcons.smartphone, size: 16),
              label: Text('explore_local'.tr, style: const TextStyle(fontSize: 13)),
            ),
            ButtonSegment(
              value: 'online',
              icon: const Icon(LucideIcons.cloud, size: 16),
              label: Text('explore_online'.tr, style: const TextStyle(fontSize: 13)),
            ),
            ButtonSegment(
              value: 'skills',
              icon: const Icon(LucideIcons.sparkles, size: 16),
              label: Text('explore_skills'.tr, style: const TextStyle(fontSize: 13)),
            ),
            ButtonSegment(
              value: 'mcp',
              icon: const Icon(LucideIcons.plug, size: 16),
              label: Text('explore_mcp'.tr, style: const TextStyle(fontSize: 13)),
            ),
            const ButtonSegment(
              value: 'gallery',
              icon: Icon(LucideIcons.image, size: 16),
              label: Text('Gallery', style: TextStyle(fontSize: 13)),
            ),
          ],
          selected: {normalized},
          onSelectionChanged: (selection) =>
              controller.modelScope.value = selection.first,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      );
    });
  }

  Widget _buildLocalActions(BuildContext context) {
    final inference = Get.find<InferenceService>();
    return Row(
      children: [
        Expanded(
          child: Obx(() => OutlinedButton.icon(
                onPressed: controller.isImporting.value ||
                        inference.isLoadingModel.value
                    ? null
                    : () => showAddModelUrlDialog(context, controller),
                icon: const Icon(Icons.add_link, size: 16),
                label: const Text('URL'),
              )),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Obx(() => OutlinedButton.icon(
                onPressed: controller.isImporting.value ||
                        inference.isLoadingModel.value
                    ? null
                    : () => controller.importModelFromStorage(),
                icon: const Icon(Icons.file_upload_outlined, size: 16),
                label: const Text('Import'),
              )),
        ),
      ],
    );
  }

  Widget _buildLocalFilterChips(BuildContext context) {
    final labels = {
      'downloaded': 'model_filter_downloaded'.tr,
      'general': 'model_filter_general'.tr,
      'image': 'model_filter_image'.tr,
      'uncensored': 'model_filter_uncensored'.tr,
      'vision': 'model_filter_vision'.tr,
    };
    return Obx(() {
      final selected = controller.localFilter.value.isEmpty
          ? controller.defaultLocalFilter
          : controller.localFilter.value;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final entry in labels.entries) ...[
              InkWell(
                onTap: () => controller.setLocalFilter(entry.key),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected == entry.key
                        ? Dt.accent.withValues(alpha: 0.18)
                        : Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected == entry.key
                          ? Dt.accent.withValues(alpha: 0.3)
                          : Theme.of(context)
                              .dividerColor
                              .withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selected == entry.key) ...[
                        const Icon(Icons.check,
                            size: 16, color: Dt.accent),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        entry.value,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: selected == entry.key
                              ? Dt.accent
                              : Theme.of(context).hintColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      );
    });
  }

  Widget _buildEmptyLocalState(BuildContext context) {
    final filter = controller.localFilter.value.isEmpty
        ? controller.defaultLocalFilter
        : controller.localFilter.value;
    final title = filter == 'downloaded'
        ? 'model_no_downloaded'.tr
        : 'No ${filter == 'vision' ? 'vision' : filter == 'image' ? 'image generation' : filter} models found';
    final subtitle = filter == 'downloaded'
        ? 'model_import_hint'.tr
        : 'model_no_models_filtered'.tr;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor, width: 0.5),
      ),
      child: Column(
        children: [
          Icon(Icons.search_off, size: 32, color: Theme.of(context).hintColor),
          const SizedBox(height: 10),
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: Theme.of(context).hintColor,
            ),
          ),
          if (filter == 'downloaded') ...[
            const SizedBox(height: 14),
            _buildLocalActions(context),
          ],
        ],
      ),
    );
  }

  Widget _buildActiveModelBanner(BuildContext context) {
    return Obx(() {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      if (controller.modelScope.value == 'online') {
        return _buildActiveCloudBanner(context);
      }

      final inference = Get.find<InferenceService>();
      final localImage = Get.find<LocalImageService>();

      final bool isImage = localImage.isModelLoaded.value;
      final bool isText = inference.isModelLoaded.value;

      if (!isImage && !isText) return const SizedBox.shrink();

      final String name = isImage ? localImage.loadedModelName.value : inference.loadedModelName.value;
      final bool useGpu = isImage ? localImage.isUsingGpu.value : inference.isGpuAccelerated.value;
      final String subtitle = isImage 
          ? (useGpu ? '⚡ GPU Accelerated Rendering' : '🖥 CPU Image Synthesis')
          : (useGpu ? '⚡ GPU: ${inference.gpuName.value}' : '🖥 CPU Neural Engine');

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surface.withValues(alpha: 0.5) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Dt.accent.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Dt.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                useGpu ? LucideIcons.zap : LucideIcons.cpu,
                color: Dt.accent,
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isImage ? 'model_active_image'.tr : 'model_active_intelligence'.tr,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      color: Dt.accent,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.firaCode(
                      fontSize: 11,
                      color: Theme.of(context).hintColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(LucideIcons.checkCircle, color: AppColors.success, size: 22),
          ],
        ),
      );
    });
  }

  Widget _buildActiveCloudBanner(BuildContext context) {
    final settings = Get.find<SettingsController>();
    final cloudModels = Get.find<CloudModelController>();
    final providerId = settings.cloudProvider.value;
    final provider = cloudModels.providers.firstWhereOrNull(
      (p) => p.id == providerId,
    );
    final providerName = providerId == 'custom'
        ? settings.customCloudName.value
        : provider?.name ?? providerId;
    final model = cloudModels.activeModelFor(providerId);
    final hasSelectedModel =
        cloudModels.canSelectModel(providerId) && model.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Dt.accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Dt.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.cloud_done,
                color: Dt.accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cloud Provider: $providerName',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: Theme.of(context).hintColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  hasSelectedModel ? model : 'No cloud model selected',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(Icons.check_circle, color: AppColors.success, size: 20),
        ],
      ),
    );
  }

  Widget _buildImportingProgress(BuildContext context) {
    return Obx(() {
      if (!controller.isImporting.value) return const SizedBox.shrink();
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Dt.accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Dt.accent.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Dt.accent)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'model_importing'.tr,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: const LinearProgressIndicator(
                minHeight: 4,
                backgroundColor: Colors.transparent,
                color: Dt.accent,
              ),
            ),
          ],
        ),
      );
    });
  }

  /// Estimated cloud usage (chars/4 tokens — no pricing table).
  Widget _usageCard(BuildContext context) {
    return Obx(() {
      final t = Get.isRegistered<UsageTrackerService>()
          ? Get.find<UsageTrackerService>()
          : null;
      final _ = t?.version.value; // subscribe: refresh card on new records
      final totals = t?.totals() ?? {'in': 0, 'out': 0, 'calls': 0};
      final rows = t?.byProvider().take(4).toList() ?? [];
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surface : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Dt.hairline),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(LucideIcons.gauge, size: 16, color: Dt.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Usage (estimate)',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, fontWeight: FontWeight.w800)),
            ),
            if ((totals['calls'] ?? 0) > 0)
              GestureDetector(
                onTap: () => t?.reset(),
                child: Text('Reset',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).hintColor)),
              ),
          ]),
          const SizedBox(height: 8),
          Text(
              '↓ ${UsageTrackerService.compact(totals['in'] ?? 0)} in · ↑ ${UsageTrackerService.compact(totals['out'] ?? 0)} out · ${totals['calls']} calls',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, fontWeight: FontWeight.w700)),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                    '${r['provider']} · ↓${UsageTrackerService.compact(r['in'] ?? 0)} ↑${UsageTrackerService.compact(r['out'] ?? 0)} · ${r['calls']}',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5,
                        color: Theme.of(context).hintColor)),
              ),
          ],
        ]),
      );
    });
  }

  Widget _buildOnlineProviders(BuildContext context) {
    final cloudModels = Get.find<CloudModelController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _usageCard(context),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                'model_cloud_providers'.tr,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).hintColor,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            Obx(() => Row(mainAxisSize: MainAxisSize.min, children: [
                  _sortChip(context, cloudModels, 'Time', 'time'),
                  const SizedBox(width: 6),
                  _sortChip(context, cloudModels, 'Name', 'name'),
                ])),
          ],
        ),
        const SizedBox(height: 8),
        _buildSyncRow(context, cloudModels),
        const SizedBox(height: 12),
        Obx(() {
          // Track ordering inputs so pin/sort/key changes rebuild order.
          cloudModels.providerSortMode.value;
          cloudModels.pinnedProviders.length;
          cloudModels.modelsByProvider.length;
          cloudModels.allProviders.length;
          final keyed = cloudModels.orderedProviders();
          final unkeyed = cloudModels.unkeyedProviders;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...keyed.map((p) => _buildProviderCard(context, p)),
              if (unkeyed.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  'ADD API KEY',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).hintColor,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Set a key to unlock these providers',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: Theme.of(context).hintColor,
                  ),
                ),
                const SizedBox(height: 8),
                ...unkeyed.map((p) => _buildAddKeyCard(context, p, cloudModels)),
              ],
            ],
          );
        }),
      ],
    );
  }

  /// Global model-list sync row: last auto-sync, cadence picker
  /// (MODEL SYNC INTERVAL HOURS), and manual sync-now.
  Widget _buildSyncRow(
      BuildContext context, CloudModelController cloudModels) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Obx(() {
      final hours = cloudModels.modelSyncIntervalHours.value;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surface : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isDark
                  ? AppColors.border
                  : AppColors.borderLightMode),
        ),
        child: Row(children: [
          const Icon(LucideIcons.refreshCw, size: 14, color: Dt.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              cloudModels.autoSyncLabel(),
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11.5,
                  color: Theme.of(context).hintColor,
                  fontWeight: FontWeight.w600),
            ),
          ),
          InkWell(
            onTap: () => _showSyncIntervalDialog(context, cloudModels),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Dt.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Every ${hours}h',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Dt.accent)),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: () => cloudModels.syncAllNow(),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Sync now',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).hintColor)),
            ),
          ),
        ]),
      );
    });
  }

  void _showSyncIntervalDialog(
      BuildContext context, CloudModelController cloudModels) {
    const options = [6, 12, 24, 48, 168];
    Get.dialog(AlertDialog(
      title: const Text('Model sync interval'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
              'MODEL SYNC INTERVAL HOURS — how often the model list auto-refreshes from each provider.'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final h in options)
                ChoiceChip(
                  label: Text(h == 168 ? 'Weekly' : 'Every ${h}h'),
                  selected:
                      cloudModels.modelSyncIntervalHours.value == h,
                  onSelected: (_) {
                    cloudModels.setSyncIntervalHours(h);
                    Get.back();
                  },
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Get.back(), child: const Text('Close')),
      ],
    ));
  }

  /// Time|Name sort chip for the provider list order.
  Widget _sortChip(BuildContext context, CloudModelController cloudModels,
      String label, String mode) {
    final selected = cloudModels.providerSortMode.value == mode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: () => cloudModels.setProviderSortMode(mode),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? Dt.accent.withValues(alpha: 0.15)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.05)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected
                  ? Dt.accent.withValues(alpha: 0.4)
                  : Colors.transparent),
        ),
        child: Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected
                    ? Dt.accent
                    : Theme.of(context).hintColor)),
      ),
    );
  }

  Widget _buildSkillsTab(BuildContext context) {
    return const ExploreSkillsTab();
  }

  Widget _buildMcpTab(BuildContext context) {
    return const ExploreMcpTab();
  }

  Widget _buildGalleryTab(BuildContext context) {
    return const GalleryView();
  }

  Widget _buildProviderCard(BuildContext context, CloudProviderInfo provider) {
    final settings = Get.find<SettingsController>();
    final cloudModels = Get.find<CloudModelController>();
    final isSelected = settings.cloudProvider.value == provider.id;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? Dt.accent.withValues(alpha: 0.5)
              : (isDark ? AppColors.border : AppColors.borderLightMode),
        ),
      ),
      child: ExpansionTile(
        key: ValueKey('provider_${provider.id}'),
        initiallyExpanded: isSelected,
        shape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isSelected
                ? Dt.accent.withValues(alpha: 0.15)
                : (isDark ? Colors.white.withValues(alpha: 0.05) : Dt.pillMuted),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            provider.icon,
            color: isSelected ? Dt.accent : Theme.of(context).hintColor,
            size: 20,
          ),
        ),
        title: Text(
          provider.name,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        subtitle: Text(
          provider.description,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            color: Theme.of(context).hintColor,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const SizedBox(height: 12),
                if (cloudModels.canSelectModel(provider.id)) ...[
                  // ── Header with count + free filter ──
                  Obx(() {
                    final all = cloudModels.modelsByProvider[provider.id] ?? [];
                    final freeCount = cloudModels.freeModelCountFor(provider.id);
                    final health = cloudModels.healthSummaryFor(provider.id);
                    final online = health.$1;
                    final failed = health.$2;
                    // Wrap (not Row): badges + chips flow to the next
                    // line on narrow screens instead of overflowing.
                    return Wrap(
                      spacing: 6,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Models',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).hintColor,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Dt.accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('${all.length}',
                            style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: Dt.accent)),
                        ),
                        if (freeCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('$freeCount free',
                              style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.success)),
                          ),
                        if (online > 0 || failed > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: (failed > 0 ? AppColors.error : AppColors.success)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('$online online · $failed failed',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: failed > 0
                                      ? AppColors.error
                                      : AppColors.success)),
                          ),
                        if (failed > 0)
                          Obx(() => _miniFilterChip(
                            context,
                            'Hide failed',
                            cloudModels.autoHideFailed.value,
                            () => cloudModels.setAutoHideFailed(
                                !cloudModels.autoHideFailed.value),
                          )),
                        if (freeCount > 0)
                          Obx(() => _miniFilterChip(
                            context,
                            'Free',
                            cloudModels.freeFirstByProvider[provider.id] == true,
                            () => cloudModels.toggleFreeFirst(provider.id),
                          )),
                      ],
                    );
                  }),
                  const SizedBox(height: 10),
                  // ── Search field ──
                  TextField(
                    onChanged: (v) => cloudModels.searchByProvider[provider.id] = v,
                    style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w500),
                    decoration: InputDecoration(
                      hintText: 'model_search_hint'.tr,
                      prefixIcon: const Icon(LucideIcons.search, size: 18),
                      suffixIcon: Obx(() => (cloudModels.searchByProvider[provider.id] ?? '').isNotEmpty
                          ? IconButton(
                              tooltip: 'Clear',
                              onPressed: () {
                                cloudModels.searchByProvider[provider.id] = '';
                              },
                              icon: const Icon(LucideIcons.x, size: 18),
                            )
                          : const SizedBox.shrink()),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      fillColor: isDark ? Colors.black.withValues(alpha: 0.2) : Dt.pillMuted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // ── Auto-detected company filter (aggregator providers) ──
                  Obx(() {
                    final companies =
                        cloudModels.availableCompaniesFor(provider.id);
                    if (companies.length < 2) return const SizedBox.shrink();
                    final selected =
                        cloudModels.companyFilterByProvider[provider.id];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _companyChip(
                                context,
                                'All',
                                Icons.apps,
                                selected == null || selected.isEmpty,
                                () => cloudModels.setCompanyFilter(
                                    provider.id, null),
                                isDark,
                              ),
                              for (final c in companies)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: _companyChip(
                                    context,
                                    cloudModels.companyDisplayName(c),
                                    cloudModels.companyIcon(c) ??
                                        Icons.cloud_outlined,
                                    selected == c,
                                    () => cloudModels.setCompanyFilter(
                                        provider.id, c),
                                    isDark,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    );
                  }),
                  // ── Compact model list ──
                  Container(
                    constraints: const BoxConstraints(maxHeight: 280),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.black.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.02),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
                    ),
                    child: Obx(() {
                      final filtered = cloudModels.filteredModelsFor(provider.id);
                      if (filtered.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Text('model_no_matching'.tr,
                              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Theme.of(context).hintColor)),
                          ),
                        );
                      }
                      final activeModel = cloudModels.activeModelFor(provider.id);
                      return ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final model = filtered[index];
                          final isActive = activeModel == model;
                          final isFree = cloudModels.isFreeModel(provider.id, model);
                          final health = cloudModels.healthFor(provider.id, model);
                          return _modelListTile(
                            context, cloudModels, provider.id,
                            index: index,
                            model: model,
                            isActive: isActive,
                            isFree: isFree,
                            isDark: isDark,
                            healthStatus: health?.status ??
                                ModelHealthStatus.unknown,
                            healthError: health?.error ?? '',
                            onTap: () => cloudModels.selectModel(provider.id, model),
                          );
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  width: double.infinity,
                  child: Obx(() {
                    final configured = cloudModels.isConfigured(provider.id);
                    final isReallyActive = isSelected && configured;
                    // Main action stays full-width; icon actions get
                    // their own row below so the button never shrinks.
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilledButton.tonal(
                            onPressed: () {
                              if (isReallyActive) {
                                cloudModels.deactivateCloudProvider();
                              } else if (configured) {
                                settings.setCloudProvider(provider.id);
                              } else if (provider.id == 'custom') {
                                _showCustomProviderDialog(context, cloudModels);
                              } else {
                                _showProviderKeyDialog(context, cloudModels, provider, openModelsAfterSave: true);
                              }
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: isReallyActive
                                  ? AppColors.success.withValues(alpha: 0.2)
                                  : null,
                              foregroundColor: isReallyActive
                                  ? AppColors.success
                                  : null,
                            ),
                            child: Text(isReallyActive
                                ? 'model_active_provider'.tr
                                : configured
                                    ? 'model_set_as_active'.tr
                                    : provider.id == 'custom'
                                        ? 'model_configure_endpoint'.tr
                                         : 'model_add_api_key'.tr),
                           ),
                         if (configured)
                           Padding(
                             padding: const EdgeInsets.only(top: 8),
                             child: Wrap(
                               spacing: 8,
                               runSpacing: 8,
                               crossAxisAlignment: WrapCrossAlignment.center,
                               children: [
                           if (provider.id != 'custom')
                            Obx(() {
                              final pinned =
                                  cloudModels.isPinned(provider.id);
                              return IconButton(
                                onPressed: () => cloudModels
                                    .togglePin(provider.id),
                                icon: Icon(
                                    pinned
                                        ? Icons.push_pin
                                        : Icons.push_pin_outlined,
                                    size: 20,
                                    color: pinned
                                        ? Dt.accent
                                        : Theme.of(context).hintColor),
                                tooltip: pinned
                                    ? 'Unpin (remove from top)'
                                    : 'Pin to top',
                                style: IconButton.styleFrom(
                                  backgroundColor: pinned
                                      ? Dt.accent
                                          .withValues(alpha: 0.12)
                                      : (isDark
                                          ? Colors.white.withValues(
                                              alpha: 0.05)
                                          : Dt.pillMuted),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                ),
                              );
                            }),
                          IconButton(
                            onPressed: () => _showProviderKeyDialog(context, cloudModels, provider),
                            icon: const Icon(LucideIcons.keyRound, size: 20),
                            tooltip: 'Edit API Key',
                            style: IconButton.styleFrom(
                              backgroundColor: isDark ? Colors.white.withValues(alpha: 0.05) : Dt.pillMuted,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          if (provider.supportsFetch)
                            IconButton(
                              onPressed: () =>
                                  cloudModels.importModels(provider.id),
                              icon: const Icon(LucideIcons.download, size: 20),
                              tooltip: 'Import from /models',
                              style: IconButton.styleFrom(
                                backgroundColor: isDark ? Colors.white.withValues(alpha: 0.05) : Dt.pillMuted,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          Obx(() {
                            final testing =
                                cloudModels.isTesting(provider.id);
                            if (testing) {
                              final done = cloudModels
                                      .testDoneByProvider[provider.id] ??
                                  0;
                              final total = cloudModels
                                      .testTotalByProvider[provider.id] ??
                                  0;
                              return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('$done/$total',
                                        style: GoogleFonts.firaCode(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Dt.accent)),
                                    IconButton(
                                      onPressed: () => cloudModels
                                          .cancelTesting(provider.id),
                                      icon: const Icon(
                                          LucideIcons.square,
                                          size: 18),
                                      tooltip: 'Cancel testing',
                                      style: IconButton.styleFrom(
                                        backgroundColor: AppColors.error
                                            .withValues(alpha: 0.12),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                      ),
                                    ),
                                  ]);
                            }
                            return IconButton(
                              onPressed: () => cloudModels
                                  .testAllModels(provider.id),
                              icon: const Icon(
                                  LucideIcons.activity, size: 20),
                              tooltip:
                                  'Test all models (one tiny call each)',
                              style: IconButton.styleFrom(
                                backgroundColor: isDark
                                    ? Colors.white
                                        .withValues(alpha: 0.05)
                                    : Dt.pillMuted,
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(12)),
                              ),
                            );
                          }),
                          IconButton(
                            onPressed: () => cloudModels.refreshModels(provider.id),
                            icon: const Icon(LucideIcons.refreshCw, size: 20),
                            tooltip: 'Refresh Models',
                            style: IconButton.styleFrom(
                              backgroundColor: isDark ? Colors.white.withValues(alpha: 0.05) : Dt.pillMuted,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                               ],
                             ),
                           ),
                      ],
                    );
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Compact card for providers without an API key — just icon, name,
  /// and an "Add Key" button. No model list or expansion.
  Widget _buildAddKeyCard(
      BuildContext context, CloudProviderInfo provider, CloudModelController cloudModels) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _providerAccent(provider.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark ? AppColors.border : AppColors.borderLightMode),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(provider.icon, color: accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  provider.name,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                Text(
                  provider.description,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: Theme.of(context).hintColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: () {
              if (provider.id == 'custom') {
                _showCustomProviderDialog(context, cloudModels);
              } else {
                _showProviderKeyDialog(context, cloudModels, provider,
                    openModelsAfterSave: true);
              }
            },
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: Text(
              provider.id == 'custom' ? 'Configure' : 'Add Key',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelBadges(BuildContext context, AiModel model) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (model.isVision) _badge(context, 'model_filter_vision'.tr, Colors.orange),
        if (controller.isUncensoredModel(model)) _badge(context, 'model_filter_uncensored'.tr, Colors.red),
        if (controller.isImageModel(model)) _badge(context, 'Imaging', Colors.purple),
        if (model.template == 'llama3') _badge(context, 'Llama 3', Colors.blue),
        if (model.template == 'gemma') _badge(context, 'Gemma', Colors.cyan),
      ],
    );
  }

  Widget _companyChip(
    BuildContext context,
    String label,
    IconData icon,
    bool selected,
    VoidCallback onTap,
    bool isDark,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? Dt.accent.withValues(alpha: 0.15)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Dt.pillMuted),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Dt.accent : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: selected ? Dt.accent : Theme.of(context).hintColor,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected
                    ? Dt.accent
                    : Theme.of(context).hintColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(BuildContext context, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Text(
        text,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _miniFilterChip(BuildContext context, String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? Dt.accent.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? Dt.accent.withValues(alpha: 0.4) : Theme.of(context).dividerColor.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(LucideIcons.check, size: 12, color: Dt.accent),
              const SizedBox(width: 4),
            ],
            Text(label, style: GoogleFonts.plusJakartaSans(
              fontSize: 10, fontWeight: FontWeight.w800, 
              color: selected ? Dt.accent : Theme.of(context).hintColor)),
          ],
        ),
      ),
    );
  }

  Widget _modelListTile(
    BuildContext context,
    CloudModelController cloud,
    String providerId, {
    required int index,
    required String model,
    required bool isActive,
    required bool isFree,
    required bool isDark,
    ModelHealthStatus healthStatus = ModelHealthStatus.unknown,
    String healthError = '',
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: isActive
              ? Dt.accent.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              width: 26,
              padding: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                color: isActive
                    ? Dt.accent.withValues(alpha: 0.15)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.05)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${index + 1}',
                style: GoogleFonts.firaCode(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isActive ? Dt.accent : Theme.of(context).hintColor,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 6, height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive ? Dt.accent : Colors.transparent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                model,
                style: GoogleFonts.firaCode(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive
                      ? Dt.accent
                      : (isDark ? Colors.white70 : Colors.black87),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (healthStatus == ModelHealthStatus.online ||
                healthStatus == ModelHealthStatus.failed ||
                healthStatus == ModelHealthStatus.testing) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: healthStatus == ModelHealthStatus.online
                    ? 'Online — answered a test call'
                    : healthStatus == ModelHealthStatus.testing
                        ? 'Testing…'
                        : (healthError.isEmpty
                            ? 'Failed'
                            : 'Failed: $healthError'),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: healthStatus == ModelHealthStatus.online
                        ? AppColors.success
                        : healthStatus == ModelHealthStatus.testing
                            ? Dt.accent
                            : AppColors.error,
                  ),
                ),
              ),
            ],
            if (isFree) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('FREE',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 8, fontWeight: FontWeight.w800, color: AppColors.success)),
              ),
            ],
            if (isActive) ...[
              const SizedBox(width: 8),
              const Icon(LucideIcons.checkCircle, size: 16, color: Dt.accent),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildModelLoadingProgress(BuildContext context, AiModel model) {
    final inference = Get.find<InferenceService>();
    return Obx(() {
      final progress = inference.modelLoadProgress.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'model_initializing'.tr,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Dt.accent,
                ),
              ),
              Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: GoogleFonts.firaCode(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Dt.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress > 0 ? progress : null,
              backgroundColor: Dt.accent.withValues(alpha: 0.1),
              color: Dt.accent,
              minHeight: 4,
            ),
          ),
        ],
      );
    });
  }

  Future<void> _confirmDeleteModel(BuildContext context, String filename) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('model_delete_title'.tr,
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
            content: Text('model_delete_desc'.tr,
                style: GoogleFonts.plusJakartaSans(fontSize: 14)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('common_cancel'.tr),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('common_delete'.tr),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed) await controller.deleteModel(filename);
  }

  void _confirmDownload(BuildContext context, AiModel model,
      {bool isToDownloadsFolder = false}) {
    // Honor the card's quant pick: everything below stays filename-keyed.
    model = controller.resolveForDownload(model);
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
                isToDownloadsFolder ? 'model_save_to_downloads'.tr : 'model_download_title'.tr,
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
                  ? 'You are about to save ${model.name} to ${controller.saveToDownloadsLabel}.'
                  : 'You are about to download ${model.name} for use in the app.',
              style:
                  GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600),
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
                    'Size: ${controller.modelSizeLabel(model)}',
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
            if (!controller.supportsLocalInference) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Dt.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Dt.accent.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(LucideIcons.cloud,
                        color: Dt.accent, size: 20),
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
                controller.downloadModelToDownloads(model);
              } else {
                controller.downloadModel(model);
              }
            },
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
            child: Text(isToDownloadsFolder ? 'model_save_now'.tr : 'model_download_now'.tr,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildModelCard(BuildContext context, AiModel model) {
    return Obx(() {
      final isDownloaded = controller.isDownloaded(model.filename);
      final inference = Get.find<InferenceService>();
      final localImage = Get.find<LocalImageService>();
      final isActive = inference.loadedModelName.value == model.filename ||
          localImage.loadedModelName.value == model.filename;
      final isCurrentlyDownloading =
          controller.isDownloadingModel(model.filename);
      final isAnyModelLoading =
          inference.isLoadingModel.value || localImage.isLoadingModel.value;
      final isThisTextModelLoading = inference.isLoadingModel.value &&
          inference.loadingModelName.value == model.filename;
      final isThisImageModelLoading = localImage.isLoadingModel.value &&
          localImage.loadedModelName.value == model.filename;
      final isThisModelLoading =
          isThisTextModelLoading || isThisImageModelLoading;
      final disableActions = controller.isImporting.value ||
          isAnyModelLoading ||
          isCurrentlyDownloading;
      final isDark = Theme.of(context).brightness == Brightness.dark;

      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? Dt.accent.withValues(alpha: 0.2)
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: isActive || disableActions ? null : () => controller.loadModel(model.filename),
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
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('ACTIVE', style: GoogleFonts.plusJakartaSans(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.success)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          _buildModelBadges(context, model),
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
                              Icon(LucideIcons.hardDrive, size: 12, color: Theme.of(context).hintColor.withValues(alpha: 0.5)),
                              const SizedBox(width: 4),
                              Text(
                                controller.modelSizeLabel(model),
                                style: GoogleFonts.firaCode(
                                  fontSize: 11,
                                  color: Theme.of(context).hintColor.withValues(alpha: 0.7),
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
                                for (final opt
                                    in model.variantOptions())
                                  ChoiceChip(
                                    label: Text(
                                      opt.filename == model.filename
                                          ? 'Default'
                                          : (model.variants
                                              .firstWhere(
                                                (v) =>
                                                    v.filename ==
                                                    opt.filename,
                                                orElse: () =>
                                                    ModelVariant(
                                                        quant: opt.filename,
                                                        filename:
                                                            opt.filename,
                                                        url: opt.url),
                                              )
                                              .quant),
                                      style:
                                          GoogleFonts.plusJakartaSans(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700),
                                    ),
                                    selected: controller
                                            .resolveForDownload(model)
                                            .filename ==
                                        opt.filename,
                                    selectedColor: Dt.accent
                                        .withValues(alpha: 0.2),
                                    onSelected: (_) => controller
                                        .selectVariant(
                                            model, opt.filename),
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
                                onPressed: disableActions ? null : () => controller.unloadModel(),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.warning,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text('Unload'),
                              )
                            else
                              Tooltip(
                                message: controller.supportsLocalInference
                                    ? 'Load model'
                                    : 'On-device models need the Android app — use Cloud mode',
                                child: FilledButton(
                                  onPressed: (disableActions ||
                                          !controller.supportsLocalInference)
                                      ? null
                                      : () => controller.loadModel(model.filename),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Dt.accent,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text('Load'),
                                ),
                              ),
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: 'Delete model',
                              onPressed: disableActions ? null : () => _confirmDeleteModel(context, model.filename),
                              icon: Icon(
                                LucideIcons.trash2,
                                size: 20,
                                color: AppColors.error.withValues(alpha: 0.6),
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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
                              : () => _confirmDownload(context, model),
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
                  _buildInlineDownloadProgress(context, model),
                ],
                if (isThisModelLoading) ...[
                  const SizedBox(height: 16),
                  _buildModelLoadingProgress(context, model),
                ],
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildInlineDownloadProgress(BuildContext context, AiModel model) {
    final dp = controller.getDownloadProgress(model.filename)!;
    return Obx(() {
      final percent = dp.progress.value * 100;
      final totalLabel = dp.totalBytes.value > 0
          ? DownloadService.formatWholeMb(dp.totalBytes.value)
          : controller.modelSizeLabel(model);
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
                  onPressed: () => controller.resumeDownload(model.filename),
                  icon: const Icon(LucideIcons.play, size: 16),
                  label: const Text('Resume'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.success),
                )
              else
                TextButton.icon(
                  onPressed: () => controller.pauseDownload(model.filename),
                  icon: const Icon(LucideIcons.pause, size: 16),
                  label: const Text('Pause'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.warning),
                ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: () => controller.cancelDownload(model.filename),
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

  Color _providerAccent(String provider) {
    switch (provider) {
      case 'openrouter':
        return AppColors.success;
      case 'deepseek':
        return const Color(0xFF00B8A9);
      case 'google':
        return AppColors.warning;
      case 'nvidia':
        return const Color(0xFF76B900);
      case 'custom':
        return AppColors.info;
      default:
        return Dt.accent;
    }
  }

  Widget _buildErrorBox(BuildContext context, String error) {
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

  void _showCustomProviderDialog(
    BuildContext context,
    CloudModelController cloud,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nameCtrl = TextEditingController();
    final baseUrlCtrl = TextEditingController();
    final apiKeyCtrl = TextEditingController();
    final modelCtrl = TextEditingController();
    final obscureKey = true.obs;
    final error = ''.obs;
    final isVerifying = false.obs;
    final verifiedCount = (-1).obs; // -1 = not verified yet

    Get.dialog(AlertDialog(
      backgroundColor: isDark ? AppColors.surface : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      titlePadding: const EdgeInsets.fromLTRB(26, 26, 22, 0),
      contentPadding: const EdgeInsets.fromLTRB(26, 20, 26, 10),
      actionsPadding: const EdgeInsets.fromLTRB(22, 10, 22, 22),
      title: Row(
        children: [
          Container(
            width: 58, height: 58,
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.tune, color: AppColors.secondary, size: 29),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Custom API', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w800)),
                Text('OpenAI-compatible endpoint', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w500, color: Theme.of(context).hintColor)),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                style: GoogleFonts.plusJakartaSans(fontSize: 14),
                decoration: const InputDecoration(
                  labelText: 'Profile name (optional)',
                  hintText: 'e.g. My Local Server',
                  prefixIcon: Icon(LucideIcons.tag, size: 22),
                  contentPadding: EdgeInsets.symmetric(vertical: 18, horizontal: 18),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: baseUrlCtrl,
                style: GoogleFonts.firaCode(fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  hintText: 'http://192.168.1.100:8080',
                  prefixIcon: Icon(LucideIcons.link, size: 22),
                  contentPadding: EdgeInsets.symmetric(vertical: 18, horizontal: 18),
                ),
              ),
              const SizedBox(height: 12),
              Obx(() => TextField(
                controller: apiKeyCtrl,
                obscureText: obscureKey.value,
                style: GoogleFonts.firaCode(fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'API key',
                  hintText: 'sk-... or leave empty for no auth',
                  prefixIcon: const Icon(Icons.key_outlined, size: 22),
                  suffixIcon: IconButton(
                    tooltip: obscureKey.value ? 'Show' : 'Hide',
                    onPressed: () => obscureKey.value = !obscureKey.value,
                    icon: Icon(obscureKey.value ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 22),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
                ),
              )),
              const SizedBox(height: 12),
              TextField(
                controller: modelCtrl,
                style: GoogleFonts.firaCode(fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Model ID (fallback if fetch fails)',
                  hintText: 'e.g. llama-3.1-8b-instruct',
                  prefixIcon: Icon(Icons.smart_toy_outlined, size: 22),
                  contentPadding: EdgeInsets.symmetric(vertical: 18, horizontal: 18),
                ),
              ),
              const SizedBox(height: 14),
              // Verify button
              SizedBox(
                width: double.infinity,
                child: Obx(() => OutlinedButton.icon(
                  onPressed: isVerifying.value ? null : () async {
                    final baseUrl = baseUrlCtrl.text.trim();
                    if (baseUrl.isEmpty) { error.value = 'Enter Base URL first.'; return; }
                    final uri = Uri.tryParse(baseUrl);
                    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
                      error.value = 'Enter a valid URL.'; return;
                    }
                    error.value = '';
                    isVerifying.value = true;
                    final settings = Get.find<SettingsController>();
                    await settings.setCustomCloudConfig(
                      name: nameCtrl.text.trim(),
                      baseUrl: baseUrlCtrl.text.trim(),
                      apiKey: apiKeyCtrl.text.trim(),
                      model: modelCtrl.text.trim(),
                    );
                    await cloud.selectModel('custom', modelCtrl.text.trim(), showSnackbar: false);
                    await cloud.refreshCustomModels();
                    isVerifying.value = false;
                    final models = cloud.modelsByProvider['custom'] ?? [];
                    verifiedCount.value = models.length;
                    if (cloud.errorByProvider.containsKey('custom')) {
                      error.value = cloud.errorByProvider['custom']!;
                    }
                  },
                  icon: isVerifying.value
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(LucideIcons.wifi, size: 18),
                  label: Text(isVerifying.value ? 'Verifying...' : 'Verify & Load Models'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: AppColors.secondary.withValues(alpha: 0.4)),
                  ),
                )),
              ),
              // Verification result
              Obx(() {
                if (verifiedCount.value < 0) return const SizedBox.shrink();
                final models = cloud.modelsByProvider['custom'] ?? [];
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: models.isNotEmpty
                          ? AppColors.success.withValues(alpha: 0.08)
                          : AppColors.warning.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: models.isNotEmpty
                            ? AppColors.success.withValues(alpha: 0.25)
                            : AppColors.warning.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              models.isNotEmpty ? LucideIcons.checkCircle : LucideIcons.info,
                              size: 16,
                              color: models.isNotEmpty ? AppColors.success : AppColors.warning,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              models.isNotEmpty
                                  ? '${models.length} model${models.length == 1 ? '' : 's'} found'
                                  : 'No models found — enter Model ID manually',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: models.isNotEmpty ? AppColors.success : AppColors.warning,
                              ),
                            ),
                          ],
                        ),
                        if (models.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: models.take(12).map((m) {
                              final isActive = cloud.activeModelFor('custom') == m;
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? Dt.accent.withValues(alpha: 0.15)
                                      : isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isActive
                                        ? Dt.accent.withValues(alpha: 0.4)
                                        : isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(m, style: GoogleFonts.firaCode(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: isActive ? Dt.accent : (isDark ? Colors.white70 : Colors.black54),
                                    )),
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: AppColors.success.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text('FREE', style: GoogleFonts.plusJakartaSans(
                                        fontSize: 8, fontWeight: FontWeight.w800, color: AppColors.success,
                                      )),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                          if (models.length > 12)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text('+ ${models.length - 12} more', style: GoogleFonts.plusJakartaSans(
                                fontSize: 10, color: Theme.of(context).hintColor,
                              )),
                            ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
              Obx(() {
                if (error.isEmpty) return const SizedBox.shrink();
                return _buildErrorBox(context, error.value);
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back(closeOverlays: false),
          child: Text('common_cancel'.tr, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
        ),
        ElevatedButton(
          onPressed: () async {
            final baseUrl = baseUrlCtrl.text.trim();
            final model = modelCtrl.text.trim();
            if (baseUrl.isEmpty) { error.value = 'Base URL is required.'; return; }
            final uri = Uri.tryParse(baseUrl);
            if (uri == null || !uri.hasScheme || (uri.scheme != 'https' && uri.scheme != 'http') || uri.host.isEmpty) {
              error.value = 'Enter a valid URL (http:// or https://).'; return;
            }
            if (model.isEmpty && (cloud.modelsByProvider['custom'] ?? []).isEmpty) {
              error.value = 'Enter a Model ID or verify endpoint first.'; return;
            }
            error.value = '';
            await cloud.saveCustomProvider();
            final activeModel = model.isNotEmpty ? model : (cloud.modelsByProvider['custom'] ?? []).first;
            await cloud.selectModel('custom', activeModel, showSnackbar: false);
            Get.back(closeOverlays: false);
            Get.snackbar('Custom API Saved', '${nameCtrl.text.isEmpty ? "Custom API" : nameCtrl.text} · $activeModel',
                snackPosition: SnackPosition.BOTTOM);
          },
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          ),
          child: Text('Save', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        ),
      ],
    ));
  }

  void _showProviderKeyDialog(
    BuildContext context,
    CloudModelController cloud,
    CloudProviderInfo provider, {
    bool openModelsAfterSave = false,
  }) {
    final keyController = cloud.apiKeyControllerFor(provider.id);
    final obscureKey = true.obs;
    final isVerifying = false.obs;
    // Verify-before-save: Save unlocks only for the exact text that
    // passed verification. Editing the field invalidates it.
    final draftKey = keyController.text.obs;
    final verifiedFor =
        (cloud.apiKeyFor(provider.id).isNotEmpty ? keyController.text : '')
            .obs;
    void onDraftChanged(String v) {
      draftKey.value = v;
      if (v != verifiedFor.value) verifiedFor.value = '';
      cloud.errorByProvider.remove(provider.id);
    }

    final accent = _providerAccent(provider.id);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasExistingKey = cloud.apiKeyFor(provider.id).isNotEmpty;
    Get.dialog(AlertDialog(
      backgroundColor: isDark ? AppColors.surface : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      titlePadding: const EdgeInsets.fromLTRB(26, 26, 22, 0),
      contentPadding: const EdgeInsets.fromLTRB(26, 20, 26, 10),
      actionsPadding: const EdgeInsets.fromLTRB(22, 10, 22, 22),
      title: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(provider.icon, color: accent, size: 29),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  provider.name,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  hasExistingKey ? 'Edit API key' : 'API key required',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).hintColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Obx(
              () => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'API key',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).hintColor,
                        ),
                      ),
                      const Spacer(),
                      if (draftKey.value.isNotEmpty)
                        InkWell(
                          onTap: () {
                            keyController.clear();
                            onDraftChanged('');
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Tooltip(
                            message: 'Clear',
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Icon(
                                Icons.close_rounded,
                                size: 19,
                                color: Theme.of(context).hintColor,
                              ),
                            ),
                          ),
                        ),
                      InkWell(
                        onTap: () async {
                          final data =
                              await Clipboard.getData('text/plain');
                          if (data?.text != null) {
                            keyController.text = data!.text!;
                            keyController.selection =
                                TextSelection.fromPosition(
                              TextPosition(
                                  offset: keyController.text.length),
                            );
                            onDraftChanged(keyController.text);
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Tooltip(
                          message: 'Paste from clipboard',
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(
                              LucideIcons.clipboardPaste,
                              size: 19,
                              color: Theme.of(context).hintColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: keyController,
                    obscureText: obscureKey.value,
                    onChanged: onDraftChanged,
                    style: GoogleFonts.firaCode(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Paste ${provider.name} key',
                      prefixIcon: const Icon(Icons.key_outlined, size: 23),
                      suffixIcon: IconButton(
                        tooltip: obscureKey.value
                            ? 'Show API key'
                            : 'Hide API key',
                        onPressed: () =>
                            obscureKey.value = !obscureKey.value,
                        icon: Icon(
                          obscureKey.value
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 20, horizontal: 18),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Obx(() {
              final error = cloud.errorByProvider[provider.id];
              if (error == null || error.isEmpty) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildErrorBox(context, error),
              );
            }),
            Obx(() {
              final ok = verifiedFor.value.isNotEmpty &&
                  verifiedFor.value == draftKey.value;
              if (!ok) {
                return Text(
                  'Paste the key, verify it, then save.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: Theme.of(context).hintColor,
                    height: 1.35,
                  ),
                );
              }
              final count =
                  cloud.verifiedModelCountByProvider[provider.id] ?? 0;
              return Row(
                children: [
                  const Icon(Icons.check_circle_rounded,
                      size: 16, color: AppColors.success),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      count > 0
                          ? 'Verified — $count models found.'
                          : 'Verified — this key works.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.success,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              );
            }),
            const SizedBox(height: 14),
            // Full-width stacked actions: no cramped 3-button row.
            Obx(() => SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    onPressed: (isVerifying.value ||
                            draftKey.value.trim().isEmpty)
                        ? null
                        : () async {
                            isVerifying.value = true;
                            final err = await cloud.verifyApiKey(
                                provider.id, draftKey.value);
                            isVerifying.value = false;
                            if (err == null) {
                              verifiedFor.value = draftKey.value;
                              cloud.errorByProvider.remove(provider.id);
                            } else {
                              verifiedFor.value = '';
                              cloud.errorByProvider[provider.id] = err;
                            }
                          },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: isVerifying.value
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.verified_outlined, size: 18),
                              const SizedBox(width: 8),
                              Text('Verify Key',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14)),
                            ],
                          ),
                  ),
                )),
            const SizedBox(height: 8),
            Obx(() {
              final ok = verifiedFor.value.isNotEmpty &&
                  verifiedFor.value == draftKey.value;
              return SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: !ok
                      ? null
                      : () async {
                          final value = keyController.text.trim();
                          await cloud.saveApiKey(provider.id, value);
                          await cloud.refreshModels(provider.id);
                          if ((cloud.errorByProvider[provider.id] ?? '')
                              .isNotEmpty) {
                            return;
                          }
                          Get.back(closeOverlays: false);
                        },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.save_outlined, size: 18),
                      const SizedBox(width: 8),
                      Text('Save Key',
                          style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w800, fontSize: 14)),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
      actions: [
        if (hasExistingKey)
          TextButton(
            onPressed: () async {
              await cloud.removeApiKey(provider.id);
              keyController.clear();
              Get.back(closeOverlays: false);
              Get.snackbar(
                'Key Removed',
                '${provider.name} API key deleted',
                snackPosition: SnackPosition.BOTTOM,
              );
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
            child: Text('Remove Key',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
          ),
        TextButton(
          onPressed: () => Get.back(closeOverlays: false),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
          child: Text('common_cancel'.tr,
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
        ),
      ],
    ));
  }
}

