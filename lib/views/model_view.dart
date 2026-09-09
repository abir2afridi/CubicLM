import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../controllers/cloud_model_controller.dart';
import '../controllers/model_controller.dart';
import '../controllers/settings_controller.dart';
import '../core/colors.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/design_tokens.dart';
import '../services/usage_tracker_service.dart';
import '../services/inference_service.dart';
import '../services/local_image_service.dart';
import 'explore_skills_mcp_tabs.dart';
import 'explore/add_model_sheet.dart';
import 'explore/local_model_card.dart';
import 'explore/provider_cards.dart';
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
        backgroundColor:
            (isDark ? Dt.canvasDark : Dt.canvas).withValues(alpha: 0.8),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(color: Colors.transparent),
          ),
        ),
        title: Text('model_hub_title'.tr,
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800,
                fontSize: 24,
                letterSpacing: -0.5)),
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
          onSelectionChanged: (s) => controller.exploreTab.value = s.first,
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
                      .map((model) => buildModelCard(context, model)),
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
              label: Text('explore_local'.tr,
                  style: const TextStyle(fontSize: 13)),
            ),
            ButtonSegment(
              value: 'online',
              icon: const Icon(LucideIcons.cloud, size: 16),
              label: Text('explore_online'.tr,
                  style: const TextStyle(fontSize: 13)),
            ),
            ButtonSegment(
              value: 'skills',
              icon: const Icon(LucideIcons.sparkles, size: 16),
              label: Text('explore_skills'.tr,
                  style: const TextStyle(fontSize: 13)),
            ),
            ButtonSegment(
              value: 'mcp',
              icon: const Icon(LucideIcons.plug, size: 16),
              label:
                  Text('explore_mcp'.tr, style: const TextStyle(fontSize: 13)),
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
                        const Icon(Icons.check, size: 16, color: Dt.accent),
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

      final String name = isImage
          ? localImage.loadedModelName.value
          : inference.loadedModelName.value;
      final bool useGpu = isImage
          ? localImage.isUsingGpu.value
          : inference.isGpuAccelerated.value;
      final String subtitle = isImage
          ? (useGpu ? '⚡ GPU Accelerated Rendering' : '🖥 CPU Image Synthesis')
          : (useGpu
              ? '⚡ GPU: ${inference.gpuName.value}'
              : '🖥 CPU Neural Engine');

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color:
              isDark ? AppColors.surface.withValues(alpha: 0.5) : Colors.white,
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
                    isImage
                        ? 'model_active_image'.tr
                        : 'model_active_intelligence'.tr,
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
            const Icon(LucideIcons.checkCircle,
                color: AppColors.success, size: 22),
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
            child: const Icon(Icons.cloud_done, color: Dt.accent, size: 20),
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
              color:
                  isDark ? Colors.white.withValues(alpha: 0.06) : Dt.hairline),
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
                        fontSize: 11.5, color: Theme.of(context).hintColor)),
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
              ...keyed.map((p) => buildProviderCard(context, p)),
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
                ...unkeyed.map((p) => buildAddKeyCard(context, p, cloudModels)),
              ],
            ],
          );
        }),
      ],
    );
  }

  /// Global model-list sync row: last auto-sync, cadence picker
  /// (MODEL SYNC INTERVAL HOURS), and manual sync-now.
  Widget _buildSyncRow(BuildContext context, CloudModelController cloudModels) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Obx(() {
      final hours = cloudModels.modelSyncIntervalHours.value;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surface : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isDark ? AppColors.border : AppColors.borderLightMode),
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
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
                  selected: cloudModels.modelSyncIntervalHours.value == h,
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
        TextButton(onPressed: () => Get.back(), child: const Text('Close')),
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
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
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
                color: selected ? Dt.accent : Theme.of(context).hintColor)),
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
}
