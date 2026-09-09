import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../controllers/cloud_model_controller.dart';
import '../../controllers/model_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../core/colors.dart';
import '../../models/ai_model.dart';
import '../../services/cloud/model_health.dart';
import '../../services/inference_service.dart';
import '../../theme/design_tokens.dart';
import 'provider_dialogs.dart';
import 'provider_theme.dart';

/// Cloud provider cards, badges, model list tiles.
/// Extracted from views/model_view.dart.

ModelController get _c => Get.find<ModelController>();

Widget buildProviderCard(BuildContext context, CloudProviderInfo provider) {
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Dt.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('${all.length}',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Dt.accent)),
                      ),
                      if (freeCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('$freeCount free',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.success)),
                        ),
                      if (online > 0 || failed > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: (failed > 0
                                    ? AppColors.error
                                    : AppColors.success)
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
                        Obx(() => miniFilterChip(
                              context,
                              'Hide failed',
                              cloudModels.autoHideFailed.value,
                              () => cloudModels.setAutoHideFailed(
                                  !cloudModels.autoHideFailed.value),
                            )),
                      if (freeCount > 0)
                        Obx(() => miniFilterChip(
                              context,
                              'Free',
                              cloudModels.freeFirstByProvider[provider.id] ==
                                  true,
                              () => cloudModels.toggleFreeFirst(provider.id),
                            )),
                    ],
                  );
                }),
                const SizedBox(height: 10),
                // ── Search field ──
                TextField(
                  onChanged: (v) =>
                      cloudModels.searchByProvider[provider.id] = v,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, fontWeight: FontWeight.w500),
                  decoration: InputDecoration(
                    hintText: 'model_search_hint'.tr,
                    prefixIcon: const Icon(LucideIcons.search, size: 18),
                    suffixIcon: Obx(() =>
                        (cloudModels.searchByProvider[provider.id] ?? '')
                                .isNotEmpty
                            ? IconButton(
                                tooltip: 'Clear',
                                onPressed: () {
                                  cloudModels.searchByProvider[provider.id] =
                                      '';
                                },
                                icon: const Icon(LucideIcons.x, size: 18),
                              )
                            : const SizedBox.shrink()),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    fillColor: isDark
                        ? Colors.black.withValues(alpha: 0.2)
                        : Dt.pillMuted,
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
                            companyChip(
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
                                child: companyChip(
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
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.05)),
                  ),
                  child: Obx(() {
                    final filtered = cloudModels.filteredModelsFor(provider.id);
                    if (filtered.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text('model_no_matching'.tr,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: Theme.of(context).hintColor)),
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
                        final isFree =
                            cloudModels.isFreeModel(provider.id, model);
                        final health =
                            cloudModels.healthFor(provider.id, model);
                        return modelListTile(
                          context,
                          cloudModels,
                          provider.id,
                          index: index,
                          model: model,
                          isActive: isActive,
                          isFree: isFree,
                          isDark: isDark,
                          healthStatus:
                              health?.status ?? ModelHealthStatus.unknown,
                          healthError: health?.error ?? '',
                          onTap: () =>
                              cloudModels.selectModel(provider.id, model),
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
                            showCustomProviderDialog(context, cloudModels);
                          } else {
                            showProviderKeyDialog(
                                context, cloudModels, provider,
                                openModelsAfterSave: true);
                          }
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: isReallyActive
                              ? AppColors.success.withValues(alpha: 0.2)
                              : null,
                          foregroundColor:
                              isReallyActive ? AppColors.success : null,
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
                                    onPressed: () =>
                                        cloudModels.togglePin(provider.id),
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
                                          ? Dt.accent.withValues(alpha: 0.12)
                                          : (isDark
                                              ? Colors.white
                                                  .withValues(alpha: 0.05)
                                              : Dt.pillMuted),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                    ),
                                  );
                                }),
                              IconButton(
                                onPressed: () => showProviderKeyDialog(
                                    context, cloudModels, provider),
                                icon:
                                    const Icon(LucideIcons.keyRound, size: 20),
                                tooltip: 'Edit API Key',
                                style: IconButton.styleFrom(
                                  backgroundColor: isDark
                                      ? Colors.white.withValues(alpha: 0.05)
                                      : Dt.pillMuted,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                              if (provider.supportsFetch)
                                IconButton(
                                  onPressed: () =>
                                      cloudModels.importModels(provider.id),
                                  icon: const Icon(LucideIcons.download,
                                      size: 20),
                                  tooltip: 'Import from /models',
                                  style: IconButton.styleFrom(
                                    backgroundColor: isDark
                                        ? Colors.white.withValues(alpha: 0.05)
                                        : Dt.pillMuted,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
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
                                          icon: const Icon(LucideIcons.square,
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
                                  onPressed: () =>
                                      cloudModels.testAllModels(provider.id),
                                  icon: const Icon(LucideIcons.activity,
                                      size: 20),
                                  tooltip:
                                      'Test all models (one tiny call each)',
                                  style: IconButton.styleFrom(
                                    backgroundColor: isDark
                                        ? Colors.white.withValues(alpha: 0.05)
                                        : Dt.pillMuted,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                );
                              }),
                              IconButton(
                                onPressed: () =>
                                    cloudModels.refreshModels(provider.id),
                                icon:
                                    const Icon(LucideIcons.refreshCw, size: 20),
                                tooltip: 'Refresh Models',
                                style: IconButton.styleFrom(
                                  backgroundColor: isDark
                                      ? Colors.white.withValues(alpha: 0.05)
                                      : Dt.pillMuted,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
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
Widget buildAddKeyCard(BuildContext context, CloudProviderInfo provider,
    CloudModelController cloudModels) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final accent = providerAccent(provider.id);
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
              showCustomProviderDialog(context, cloudModels);
            } else {
              showProviderKeyDialog(context, cloudModels, provider,
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

Widget buildModelBadges(BuildContext context, AiModel model) {
  return Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      if (model.isVision)
        badge(context, 'model_filter_vision'.tr, Colors.orange),
      if (_c.isUncensoredModel(model))
        badge(context, 'model_filter_uncensored'.tr, Colors.red),
      if (_c.isImageModel(model)) badge(context, 'Imaging', Colors.purple),
      if (model.template == 'llama3') badge(context, 'Llama 3', Colors.blue),
      if (model.template == 'gemma') badge(context, 'Gemma', Colors.cyan),
    ],
  );
}

Widget companyChip(
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
            : (isDark ? Colors.white.withValues(alpha: 0.05) : Dt.pillMuted),
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
              color: selected ? Dt.accent : Theme.of(context).hintColor,
            ),
          ),
        ],
      ),
    ),
  );
}

Widget badge(BuildContext context, String text, Color color) {
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

Widget miniFilterChip(
    BuildContext context, String label, bool selected, VoidCallback onTap) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color:
            selected ? Dt.accent.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected
              ? Dt.accent.withValues(alpha: 0.4)
              : Theme.of(context).dividerColor.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selected) ...[
            const Icon(LucideIcons.check, size: 12, color: Dt.accent),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: selected ? Dt.accent : Theme.of(context).hintColor)),
        ],
      ),
    ),
  );
}

Widget modelListTile(
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
        color: isActive ? Dt.accent.withValues(alpha: 0.1) : Colors.transparent,
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
            width: 6,
            height: 6,
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
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      color: AppColors.success)),
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

Widget buildModelLoadingProgress(BuildContext context, AiModel model) {
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

Future<void> confirmDeleteModel(BuildContext context, String filename) async {
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
  if (confirmed) await _c.deleteModel(filename);
}
