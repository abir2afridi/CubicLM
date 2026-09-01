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
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/design_tokens.dart';
import '../models/ai_model.dart';
import '../services/download_service.dart';
import '../services/inference_service.dart';
import '../services/local_image_service.dart';
import 'explore_skills_mcp_tabs.dart';
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
            if (controller.modelScope.value != 'local') {
              return const SizedBox.shrink();
            }
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(LucideIcons.link),
                  tooltip: 'model_add_url_title'.tr,
                  onPressed: () => _showAddUrlDialog(context),
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
            child: _buildScopeToggle(context),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildActiveModelBanner(context),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: RefreshIndicator(
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
          ),
        ),
        ],
      ),
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
                    : () => _showAddUrlDialog(context),
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

  void _showAddUrlDialog(BuildContext context) {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final filenameController = TextEditingController();
    final sizeController = TextEditingController();
    final templateController = TextEditingController(text: 'chatml');
    final isVision = false.obs;
    final isDetecting = false.obs;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.655),
      builder: (ctx) => _AddModelUrlSheet(
        nameController: nameController,
        urlController: urlController,
        filenameController: filenameController,
        sizeController: sizeController,
        templateController: templateController,
        isVision: isVision,
        isDetecting: isDetecting,
        modelController: controller,
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

  Widget _buildOnlineProviders(BuildContext context) {
    final cloudModels = Get.find<CloudModelController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'model_cloud_providers'.tr,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).hintColor,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        ...cloudModels.providers.map((p) => _buildProviderCard(context, p)),
      ],
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
                    return Row(
                      children: [
                        Text(
                          'Models',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).hintColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Dt.accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('${all.length}',
                            style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: Dt.accent)),
                        ),
                        if (freeCount > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('$freeCount free',
                              style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.success)),
                          ),
                        ],
                        const Spacer(),
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
                          return _modelListTile(
                            context, cloudModels, provider.id,
                            index: index,
                            model: model,
                            isActive: isActive,
                            isFree: isFree,
                            isDark: isDark,
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
                    return Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonal(
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
                        ),
                        if (configured) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () => _showProviderKeyDialog(context, cloudModels, provider),
                            icon: const Icon(LucideIcons.keyRound, size: 20),
                            tooltip: 'Edit API Key',
                            style: IconButton.styleFrom(
                              backgroundColor: isDark ? Colors.white.withValues(alpha: 0.05) : Dt.pillMuted,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
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
                  ? 'You are about to save ${model.name} to your phone\'s public Downloads folder.'
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
                        ],
                      ),
                    ),
                    if (!isCurrentlyDownloading && isDownloaded)
                      Padding(
                        padding: const EdgeInsets.only(left: 12, top: 4),
                        child: IconButton(
                          tooltip: isActive ? 'Unload model' : 'Delete model',
                          onPressed: disableActions
                              ? null
                              : isActive
                                  ? () => controller.unloadModel()
                                  : () => _confirmDeleteModel(context, model.filename),
                          icon: Icon(
                            isActive ? LucideIcons.logOut : LucideIcons.trash2,
                            size: 20,
                            color: isActive ? AppColors.warning : AppColors.error.withValues(alpha: 0.6),
                          ),
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
              () => TextField(
                controller: keyController,
                obscureText: obscureKey.value,
                style: GoogleFonts.firaCode(fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'API key',
                  hintText: 'Paste ${provider.name} key',
                  prefixIcon: const Icon(Icons.key_outlined, size: 23),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Paste from clipboard',
                        onPressed: () async {
                          final data = await Clipboard.getData('text/plain');
                          if (data?.text != null) {
                            keyController.text = data!.text!;
                            keyController.selection = TextSelection.fromPosition(
                              TextPosition(offset: keyController.text.length),
                            );
                          }
                        },
                        icon: const Icon(LucideIcons.clipboardPaste, size: 20),
                      ),
                      IconButton(
                        tooltip: obscureKey.value ? 'Show API key' : 'Hide API key',
                        onPressed: () => obscureKey.value = !obscureKey.value,
                        icon: Icon(
                          obscureKey.value
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
                ),
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
            Text(
              'Save the key to verify it and load live models.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: Theme.of(context).hintColor,
                height: 1.35,
              ),
            ),
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
        ElevatedButton(
          onPressed: () async {
            final value = keyController.text.trim();
            if (value.isEmpty || isVerifying.value) return;
            isVerifying.value = true;
            await cloud.saveApiKey(provider.id, value);
            await cloud.refreshModels(provider.id);
            isVerifying.value = false;
            if ((cloud.errorByProvider[provider.id] ?? '').isNotEmpty) {
              return;
            }
            Get.back(closeOverlays: false);
          },
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          ),
          child:
              Obx(() => Text(isVerifying.value ? 'Verifying...' : 'Save Key')),
        ),
      ],
    ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add Model URL — Modern Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _AddModelUrlSheet extends StatefulWidget {
  final TextEditingController nameController;
  final TextEditingController urlController;
  final TextEditingController filenameController;
  final TextEditingController sizeController;
  final TextEditingController templateController;
  final RxBool isVision;
  final RxBool isDetecting;
  final ModelController modelController;

  const _AddModelUrlSheet({
    required this.nameController,
    required this.urlController,
    required this.filenameController,
    required this.sizeController,
    required this.templateController,
    required this.isVision,
    required this.isDetecting,
    required this.modelController,
  });

  @override
  State<_AddModelUrlSheet> createState() => _AddModelUrlSheetState();
}

class _AddModelUrlSheetState extends State<_AddModelUrlSheet> {
  static const _templates = ['chatml', 'llama3', 'gemma', 'phi3', 'custom'];
  Timer? _urlDebounce;
  final RxString _urlError = ''.obs;
  final RxString _urlWarning = ''.obs;

  @override
  void initState() {
    super.initState();
    widget.urlController.addListener(_onUrlChanged);
  }

  @override
  void dispose() {
    widget.urlController.removeListener(_onUrlChanged);
    _urlDebounce?.cancel();
    super.dispose();
  }

  String _detectTemplateFromUrlOrFilename(String url, String filename) {
    final textToSearch = '$url $filename'.toLowerCase();
    if (textToSearch.contains('gemma')) {
      return 'gemma';
    } else if (textToSearch.contains('llama3') ||
        textToSearch.contains('llama-3') ||
        textToSearch.contains('llama_3') ||
        textToSearch.contains('llama 3')) {
      return 'llama3';
    } else if (textToSearch.contains('phi3') ||
        textToSearch.contains('phi-3') ||
        textToSearch.contains('phi_3') ||
        textToSearch.contains('phi 3')) {
      return 'phi3';
    }
    return 'chatml'; // Default fallback
  }

  void _onUrlChanged() {
    final url = widget.urlController.text.trim();
    if (url.isNotEmpty) {
      final filename = widget.modelController.filenameFromUrl(url);
      widget.filenameController.text = filename;
      widget.templateController.text =
          _detectTemplateFromUrlOrFilename(url, filename);
    }

    _urlDebounce?.cancel();
    _urlDebounce = Timer(const Duration(milliseconds: 900), () async {
      if (url.isEmpty) {
        _urlError.value = '';
        _urlWarning.value = '';
        widget.sizeController.text = '';
        return;
      }

      // Check if it is a valid HTTP/HTTPS URL format
      final uri = Uri.tryParse(url);
      if (uri == null ||
          !uri.hasScheme ||
          (uri.scheme != 'http' && uri.scheme != 'https')) {
        _urlError.value =
            'Invalid URL format. Must start with http:// or https://';
        _urlWarning.value = '';
        widget.sizeController.text = 'Unknown size';
        return;
      }

      _urlError.value = '';
      _urlWarning.value = '';
      widget.isDetecting.value = true;
      try {
        final sizeLabel = await widget.modelController.detectUrlSize(url);
        if (sizeLabel == 'Unknown size') {
          _urlWarning.value =
              'Could not resolve file size. Ensure the URL is accessible.';
          widget.sizeController.text = 'Unknown size';
        } else {
          _urlWarning.value = '';
          widget.sizeController.text = sizeLabel;
        }
      } catch (e) {
        _urlWarning.value = 'Could not resolve file size: $e';
        widget.sizeController.text = 'Unknown size';
      } finally {
        widget.isDetecting.value = false;
      }
    });
  }

  Future<void> _detectSize() async {
    final url = widget.urlController.text.trim();
    if (url.isEmpty) return;
    widget.isDetecting.value = true;
    try {
      final sizeLabel = await widget.modelController.detectUrlSize(url);
      if (sizeLabel == 'Unknown size') {
        _urlWarning.value =
            'Could not resolve file size. Ensure the URL is accessible.';
        widget.sizeController.text = 'Unknown size';
      } else {
        _urlWarning.value = '';
        widget.sizeController.text = sizeLabel;
      }
    } catch (e) {
      _urlWarning.value = 'Could not resolve file size: $e';
      widget.sizeController.text = 'Unknown size';
    } finally {
      widget.isDetecting.value = false;
    }
  }

  Future<void> _submit() async {
    final url = widget.urlController.text.trim();
    if (url.isEmpty) return;

    // Validate format synchronously
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      _urlError.value =
          'Invalid URL format. Must start with http:// or https://';
      return;
    }

    if (_urlError.value.isNotEmpty) return;
    _urlDebounce?.cancel();

    await widget.modelController.addModelFromUrl(
      name: widget.nameController.text.trim().isEmpty
          ? widget.filenameController.text
          : widget.nameController.text.trim(),
      url: url,
      filename: widget.filenameController.text,
      size: widget.sizeController.text.isEmpty
          ? 'Unknown size'
          : widget.sizeController.text,
      description: 'Added custom model via URL',
      template: widget.templateController.text,
      isVision: widget.isVision.value,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? Dt.canvasDark : Dt.canvas;
    final fieldBg = isDark ? Dt.cardDark : Dt.card;
    final borderCol =
        isDark ? Dt.pillMutedDark : Dt.hairline;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        margin: EdgeInsets.only(bottom: bottomPadding),
        decoration: BoxDecoration(
          color: sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? AppColors.border : Dt.hairline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 4),

            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [Dt.cardDark, Dt.canvasDark]
                      : [Dt.pillMuted, Dt.canvas],
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Dt.accent, Color(0xFF009B7D)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Dt.accent.withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(LucideIcons.link,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'model_add_url_title'.tr,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'model_url_desc'.tr,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: isDark
                                ? AppColors.textSecondary
                                : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(LucideIcons.x,
                        color:
                            isDark ? AppColors.textSecondary : Colors.black54,
                        size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor:
                          isDark ? AppColors.surface : Dt.pillMuted,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.all(8),
                    ),
                  ),
                ],
              ),
            ),

            // Accent divider
            Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  Dt.accent.withValues(alpha: 0.6),
                  AppColors.secondary.withValues(alpha: 0.3),
                  Colors.transparent,
                ]),
              ),
            ),

            // Scrollable form
            Flexible(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionLabel(
                        label: 'MODEL URL', color: Dt.accent),
                    const SizedBox(height: 8),
                    _SheetTextField(
                      controller: widget.urlController,
                      hint: 'https://huggingface.co/…/model.gguf',
                      prefixIcon: LucideIcons.link,
                      keyboardType: TextInputType.url,
                      bg: fieldBg,
                      border: borderCol,
                    ),
                    Obx(() {
                      if (_urlError.value.isNotEmpty) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 6, left: 4),
                          child: Row(
                            children: [
                              const Icon(LucideIcons.alertCircle,
                                  size: 13, color: AppColors.error),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _urlError.value,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    color: AppColors.error,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      } else if (_urlWarning.value.isNotEmpty) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 6, left: 4),
                          child: Row(
                            children: [
                              const Icon(LucideIcons.alertTriangle,
                                  size: 13, color: Colors.orange),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _urlWarning.value,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    color: Colors.orange,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    }),
                    const SizedBox(height: 20),

                    const _SectionLabel(label: 'MODEL INFO'),
                    const SizedBox(height: 8),
                    _SheetTextField(
                      controller: widget.nameController,
                      hint: 'Display name  (e.g. Qwen3-0.6B)',
                      prefixIcon: LucideIcons.tag,
                      bg: fieldBg,
                      border: borderCol,
                    ),
                    const SizedBox(height: 12),
                    _SheetTextField(
                      controller: widget.filenameController,
                      hint: 'Filename  (e.g. qwen3-0.6b.gguf)',
                      prefixIcon: Icons.insert_drive_file_outlined,
                      bg: fieldBg,
                      border: borderCol,
                    ),
                    const SizedBox(height: 20),

                    const _SectionLabel(label: 'FILE SIZE'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _SheetTextField(
                            controller: widget.sizeController,
                            hint: 'e.g. 1.2 GB',
                            prefixIcon: LucideIcons.gauge,
                            bg: fieldBg,
                            border: borderCol,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Obx(() => _DetectSizeButton(
                              isLoading: widget.isDetecting.value,
                              onTap: _detectSize,
                            )),
                      ],
                    ),
                    const SizedBox(height: 20),

                    const _SectionLabel(label: 'CHAT TEMPLATE'),
                    const SizedBox(height: 8),
                    _TemplateSelector(
                      controller: widget.templateController,
                      templates: _templates,
                      bg: fieldBg,
                      border: borderCol,
                      accentColor: Dt.accent,
                    ),
                    const SizedBox(height: 20),

                    Obx(() => _VisionToggle(
                          value: widget.isVision.value,
                          onChanged: (v) => widget.isVision.value = v,
                          bg: fieldBg,
                          border: borderCol,
                        )),
                    const SizedBox(height: 28),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isDark
                                  ? AppColors.textSecondary
                                  : Colors.black54,
                              side: BorderSide(color: borderCol),
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            child: Text('common_cancel'.tr,
                                style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w600, fontSize: 14)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 3,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Dt.accent, Color(0xFF009B7D)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      Dt.accent.withValues(alpha: 0.4),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: _submit,
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 15),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                          LucideIcons.arrowDownCircle,
                                          color: Colors.white,
                                          size: 18),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Add Model',
                                        style: GoogleFonts.plusJakartaSans(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  final Color color;
  const _SectionLabel({required this.label, this.color = AppColors.textMuted});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final resolvedColor = color == AppColors.textMuted
        ? (isDark ? AppColors.textMuted : Dt.textMuted)
        : color;
    return Text(
      label,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
        color: resolvedColor,
      ),
    );
  }
}

// ── Styled text field ─────────────────────────────────────────────────────────
class _SheetTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData prefixIcon;
  final TextInputType? keyboardType;
  final Color bg;
  final Color border;

  const _SheetTextField({
    required this.controller,
    required this.hint,
    required this.prefixIcon,
    this.keyboardType,
    required this.bg,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: 1,
        style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w400),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: isDark ? AppColors.textMuted : Dt.textMuted),
          prefixIcon: Icon(prefixIcon,
              color: isDark ? AppColors.textMuted : Dt.textMuted,
              size: 18),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}

// ── Detect Size button ────────────────────────────────────────────────────────
class _DetectSizeButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onTap;
  const _DetectSizeButton({required this.isLoading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: isLoading
              ? (isDark ? AppColors.surface : Dt.pillMuted)
              : Dt.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isLoading
                ? (isDark ? AppColors.border : Dt.toggleTrackOff)
                : Dt.accent.withValues(alpha: 0.4),
          ),
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Dt.accent),
                )
              : const Icon(LucideIcons.radar,
                  color: Dt.accent, size: 22),
        ),
      ),
    );
  }
}

// ── Template selector ─────────────────────────────────────────────────────────
class _TemplateSelector extends StatefulWidget {
  final TextEditingController controller;
  final List<String> templates;
  final Color bg;
  final Color border;
  final Color accentColor;

  const _TemplateSelector({
    required this.controller,
    required this.templates,
    required this.bg,
    required this.border,
    required this.accentColor,
  });

  @override
  State<_TemplateSelector> createState() => _TemplateSelectorState();
}

class _TemplateSelectorState extends State<_TemplateSelector> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: widget.templates.map((t) {
          final sel = widget.controller.text == t;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => widget.controller.text = t),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: sel
                      ? widget.accentColor.withValues(alpha: 0.18)
                      : widget.bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: sel
                        ? widget.accentColor.withValues(alpha: 0.6)
                        : widget.border,
                    width: sel ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  t,
                  style: GoogleFonts.firaCode(
                    fontSize: 13,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                    color: sel
                        ? widget.accentColor
                        : (isDark
                            ? AppColors.textSecondary
                            : Dt.textMuted),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Vision toggle ─────────────────────────────────────────────────────────────
class _VisionToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color bg;
  final Color border;

  const _VisionToggle({
    required this.value,
    required this.onChanged,
    required this.bg,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = value
        ? (isDark ? Colors.white : AppColors.secondary)
        : (isDark ? AppColors.textSecondary : Colors.black87);

    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: value ? AppColors.secondary.withValues(alpha: 0.12) : bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: value ? AppColors.secondary.withValues(alpha: 0.5) : border,
            width: value ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: value
                    ? AppColors.secondary.withValues(alpha: 0.2)
                    : (isDark ? AppColors.surface : Dt.pillMuted),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                value ? LucideIcons.eye : LucideIcons.eyeOff,
                color: value
                    ? AppColors.secondary
                    : (isDark ? AppColors.textMuted : Dt.textMuted),
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vision Model',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: titleColor,
                    ),
                  ),
                  Text(
                    'Supports image input (multimodal)',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: isDark
                          ? AppColors.textMuted
                          : Dt.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppColors.secondary,
              activeTrackColor: AppColors.secondary.withValues(alpha: 0.3),
              inactiveThumbColor:
                  isDark ? AppColors.textMuted : Dt.textMuted,
              inactiveTrackColor:
                  isDark ? AppColors.surface : Dt.pillMuted,
            ),
          ],
        ),
      ),
    );
  }
}
