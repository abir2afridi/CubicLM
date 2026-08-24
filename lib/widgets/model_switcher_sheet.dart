import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../controllers/cloud_model_controller.dart';
import '../controllers/home_controller.dart';
import '../controllers/model_controller.dart';
import '../controllers/settings_controller.dart';
import '../core/colors.dart';
import '../models/ai_model.dart';
import '../services/inference_service.dart';
import '../services/local_image_service.dart';
import 'app_ui.dart';

/// Opens the in-chat model switcher.
///
/// Picking a downloaded local model swaps it in immediately — the resident model
/// is freed and the new one loads in a single tap, no unload step and no app
/// restart. The one exception is a GGUF ↔ LiteRT switch, which still prompts to
/// restart because the two native runtimes cannot safely co-exist in one
/// process (see [ModelController.loadModel]).
void showModelSwitcherSheet(BuildContext context) {
  showAppBottomSheet<void>(
    context,
    builder: (_) => const ModelSwitcherSheet(),
  );
}

class ModelSwitcherSheet extends StatefulWidget {
  const ModelSwitcherSheet({super.key});

  @override
  State<ModelSwitcherSheet> createState() => _ModelSwitcherSheetState();
}

class _ModelSwitcherSheetState extends State<ModelSwitcherSheet> {
  /// 'local' or 'cloud'. Seeded from the current inference mode so the sheet
  /// opens on the tab the user is actually chatting with.
  late String _scope;

  @override
  void initState() {
    super.initState();
    _scope = Get.find<SettingsController>().inferenceMode.value == 'cloud'
        ? 'cloud'
        : 'local';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        // Outer chrome (rounded top + drag handle) comes from AppBottomSheet.
        return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(
                      'Switch Model',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? AppColors.textPrimary
                            : const Color(0xFF0F172A),
                      ),
                    ),
                    const Spacer(),
                    _ManageModelsButton(isDark: isDark),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _ActiveModelHeader(isDark: isDark),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _ScopeToggle(
                  scope: _scope,
                  isDark: isDark,
                  onChanged: (value) => setState(() => _scope = value),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _scope == 'local'
                    ? _LocalModelList(
                        scrollController: scrollController, isDark: isDark)
                    : _CloudModelList(
                        scrollController: scrollController, isDark: isDark),
              ),
     ],
        );
      },
    );
  }
}

// ── Header ──

class _ManageModelsButton extends StatelessWidget {
  final bool isDark;

  const _ManageModelsButton({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        Get.find<HomeController>().changeTab(1);
      },
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Text(
              'Manage',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_forward_rounded,
                size: 15, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

class _ActiveModelHeader extends StatelessWidget {
  final bool isDark;

  const _ActiveModelHeader({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final settings = Get.find<SettingsController>();
      final inference = Get.find<InferenceService>();
      final localImage = Get.find<LocalImageService>();
      final isCloud = settings.inferenceMode.value == 'cloud';

      final String label;
      final String subtitle;
      final IconData icon;
      final Color accent;

      if (isCloud) {
        final model = settings.selectedCloudModelName;
        label = model.isEmpty ? 'No cloud model selected' : model;
        subtitle = '☁ ${_providerLabel(settings)}';
        icon = Icons.cloud_outlined;
        accent = AppColors.primary;
      } else if (inference.isLoadingModel.value) {
        label = inference.loadingModelName.value.isEmpty
            ? 'Loading…'
            : _stripExtension(inference.loadingModelName.value);
        final pct = (inference.modelLoadProgress.value * 100).clamp(0, 100);
        subtitle = 'Loading · ${pct.round()}%';
        icon = Icons.downloading_rounded;
        accent = AppColors.warning;
      } else if (inference.isModelLoaded.value) {
        label = _stripExtension(inference.loadedModelName.value);
        subtitle = inference.isGpuAccelerated.value
            ? '⚡ GPU${inference.gpuName.value.isEmpty ? '' : ': ${inference.gpuName.value}'}'
            : '🖥 CPU Neural Engine';
        icon = inference.isGpuAccelerated.value
            ? Icons.bolt_rounded
            : Icons.memory_rounded;
        accent = AppColors.success;
      } else if (localImage.isModelLoaded.value) {
        label = _stripExtension(localImage.loadedModelName.value);
        subtitle = localImage.isUsingGpu.value
            ? '⚡ GPU Image Synthesis'
            : '🖥 CPU Image Synthesis';
        icon = Icons.image_rounded;
        accent = AppColors.success;
      } else {
        label = 'No model loaded';
        subtitle = 'Pick one below to start chatting';
        icon = Icons.hourglass_empty_rounded;
        accent = AppColors.warning;
      }

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.bg.withValues(alpha: 0.4)
              : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accent, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isCloud ? 'ACTIVE CLOUD MODEL' : 'ACTIVE MODEL',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppColors.textPrimary
                          : const Color(0xFF0F172A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.firaCode(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).hintColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  String _providerLabel(SettingsController settings) {
    final id = settings.cloudProvider.value;
    if (id == 'custom') {
      final name = settings.customCloudName.value;
      return name.isEmpty ? 'Custom API' : name;
    }
    final provider = Get.find<CloudModelController>()
        .providers
        .firstWhereOrNull((p) => p.id == id);
    return provider?.name ?? id;
  }
}

class _ScopeToggle extends StatelessWidget {
  final String scope;
  final bool isDark;
  final ValueChanged<String> onChanged;

  const _ScopeToggle({
    required this.scope,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg.withValues(alpha: 0.4) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _tab('local', 'On Device', Icons.smartphone_rounded, context),
          _tab('cloud', 'Cloud', Icons.cloud_outlined, context),
        ],
      ),
    );
  }

  Widget _tab(String value, String label, IconData icon, BuildContext context) {
    final selected = scope == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? (isDark ? AppColors.surfaceLight : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            border: selected
                ? Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                  )
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 15,
                  color: selected
                      ? AppColors.primary
                      : Theme.of(context).hintColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? AppColors.primary
                      : Theme.of(context).hintColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Local models ──

class _LocalModelList extends StatefulWidget {
  final ScrollController scrollController;
  final bool isDark;

  const _LocalModelList({
    required this.scrollController,
    required this.isDark,
  });

  @override
  State<_LocalModelList> createState() => _LocalModelListState();
}

class _LocalModelListState extends State<_LocalModelList> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    return Obx(() {
      final models = Get.find<ModelController>();
      final inference = Get.find<InferenceService>();

      final entries = models.availableModels
          .where((model) =>
              models.isDownloaded(model.filename) && !models.isImageModel(model))
          .toList()
        ..sort((a, b) {
          final active = inference.loadedModelName.value;
          if (a.filename == active) return -1;
          if (b.filename == active) return 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });

      if (entries.isEmpty) {
        return _EmptyState(
          icon: Icons.download_rounded,
          title: 'No models downloaded',
          message: 'Download a model to chat on device.',
          actionLabel: 'Browse models',
          onAction: () {
            Navigator.pop(context);
            Get.find<HomeController>().changeTab(1);
          },
          isDark: isDark,
        );
      }

      final q = _query.trim().toLowerCase();
      final filtered = q.isEmpty
          ? entries
          : entries
              .where((m) =>
                  m.name.toLowerCase().contains(q) ||
                  m.filename.toLowerCase().contains(q))
              .toList();

      final activeName = inference.loadedModelName.value;
      final loadingName = inference.isLoadingModel.value
          ? inference.loadingModelName.value
          : '';

      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color:
                    isDark ? AppColors.textPrimary : const Color(0xFF0F172A),
              ),
              decoration: InputDecoration(
                hintText: 'Search downloaded models…',
                hintStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                prefixIcon: const Icon(Icons.search_rounded, size: 19),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        onPressed: () => setState(() => _query = ''),
                        icon: const Icon(Icons.close_rounded, size: 17),
                      ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
                filled: true,
                fillColor: isDark
                    ? AppColors.bg.withValues(alpha: 0.45)
                    : const Color(0xFFF1F5F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(13),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'No matching models',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: widget.scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 2, 20, 24),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final model = filtered[index];
                      final isActive = model.filename == activeName;
                      final isLoading = model.filename == loadingName;
                      final isResident = !models.isLiteRtModel(model) &&
                          inference.isResident(model.filename);
                      return _ModelRow(
                        title: model.name,
                        subtitle: _localSubtitle(models, model),
                        isActive: isActive,
                        isLoading: isLoading,
                        progress:
                            isLoading ? inference.modelLoadProgress.value : null,
                        badge: models.isLiteRtModel(model)
                            ? 'LiteRT'
                            : isResident
                                ? 'In memory · instant'
                                : 'GGUF',
                        badgeColor: models.isLiteRtModel(model)
                            ? AppColors.secondary
                            : isResident
                                ? AppColors.success
                                : null,
                        isDark: isDark,
                        // Any load while one is in flight is dropped by
                        // ModelController, so disable the rows rather than
                        // let taps silently no-op.
                        onTap: isActive || inference.isLoadingModel.value
                            ? null
                            : () {
                                Navigator.pop(context);
                                models.loadModel(model.filename);
                              },
                      );
                    },
                  ),
          ),
        ],
      );
    });
  }

  String _localSubtitle(ModelController models, AiModel model) {
    final size = models.modelSizeLabel(model);
    if (models.isVisionModel(model)) {
      return size.isEmpty ? 'Vision' : '$size · Vision';
    }
    return size;
  }
}

// ── Cloud models ──

/// Cloud tab of the switcher: every configured provider gets its own
/// collapsible section (like the Explore page's Online list), plus a
/// global search box that matches models across ALL providers at once.
class _CloudModelList extends StatefulWidget {
  final ScrollController scrollController;
  final bool isDark;

  const _CloudModelList({
    required this.scrollController,
    required this.isDark,
  });

  @override
  State<_CloudModelList> createState() => _CloudModelListState();
}

class _CloudModelListState extends State<_CloudModelList> {
  String _query = '';

  /// One key per provider section so we can auto-scroll an expanded
  /// section into view instead of letting it grow off-screen below.
  final Map<String, GlobalKey> _sectionKeys = {};

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    return Obx(() {
      final cloudModels = Get.find<CloudModelController>();
      final settings = Get.find<SettingsController>();

      // Only providers with a key/config can list models.
      final providers = cloudModels.providers
          .where((p) => cloudModels.canSelectModel(p.id))
          .toList()
        ..sort((a, b) {
          final activeId = cloudModels.activeProvider;
          if (a.id == activeId) return -1;
          if (b.id == activeId) return 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });

      if (providers.isEmpty) {
        return _EmptyState(
          icon: Icons.key_off_rounded,
          title: 'API key needed',
          message:
              'Add a key for any provider to use cloud models.',
          actionLabel: 'Open cloud settings',
          onAction: () {
            Navigator.pop(context);
            Get.find<HomeController>().changeTab(1);
          },
          isDark: isDark,
        );
      }

      return Column(
        children: [
          // ── Global search across all providers ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.textPrimary : const Color(0xFF0F172A),
              ),
              decoration: InputDecoration(
                hintText: 'Search all cloud models…',
                hintStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                prefixIcon:
                    const Icon(Icons.search_rounded, size: 19),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        onPressed: () => setState(() => _query = ''),
                        icon: const Icon(Icons.close_rounded, size: 17),
                      ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
                filled: true,
                fillColor: isDark
                    ? AppColors.bg.withValues(alpha: 0.45)
                    : const Color(0xFFF1F5F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(13),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _query.trim().isEmpty
                ? _buildGroupedView(cloudModels, settings, providers, isDark)
                : _buildSearchView(cloudModels, providers, isDark),
          ),
        ],
      );
    });
  }

  // ── Grouped sections (one per provider) ──

  Widget _buildGroupedView(
    CloudModelController cloudModels,
    SettingsController settings,
    List<CloudProviderInfo> providers,
    bool isDark,
  ) {
    final isCloudActive = settings.inferenceMode.value == 'cloud';
    return ListView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 24),
      itemCount: providers.length,
      itemBuilder: (context, index) => _providerSection(
        cloudModels,
        settings,
        providers[index],
        isDark,
        isActiveSection:
            isCloudActive && providers[index].id == cloudModels.activeProvider,
      ),
    );
  }

  Widget _providerSection(
    CloudModelController cloudModels,
    SettingsController settings,
    CloudProviderInfo provider,
    bool isDark, {
    required bool isActiveSection,
  }) {
    return KeyedSubtree(
      key: _sectionKeys.putIfAbsent(provider.id, () => GlobalKey()),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surface : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActiveSection
                ? AppColors.primary.withValues(alpha: 0.5)
                : (isDark ? AppColors.border : AppColors.borderLightMode),
          ),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: ValueKey('switcher_${provider.id}'),
            initiallyExpanded: isActiveSection,
            backgroundColor: Colors.transparent,
            collapsedBackgroundColor: Colors.transparent,
            shape: const Border(),
            collapsedShape: const Border(),
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            onExpansionChanged: (open) {
              if (!open) return;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Future.delayed(const Duration(milliseconds: 260), () {
                  if (!mounted) return;
                  final ctx = _sectionKeys[provider.id]?.currentContext;
                  if (ctx != null && ctx.mounted) {
                    Scrollable.ensureVisible(
                      ctx,
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                      alignment: 0.0,
                    );
                  }
                });
              });
            },
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isActiveSection
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : const Color(0xFFF1F5F9)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                provider.icon,
                color: isActiveSection
                    ? AppColors.primary
                    : Theme.of(context).hintColor,
                size: 20,
              ),
            ),
            title: Text(
              provider.id == 'custom'
                  ? _customName(settings)
                  : provider.name,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              provider.id == 'custom'
                  ? 'Custom OpenAI-compatible endpoint'
                  : provider.description,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: Theme.of(context).hintColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isActiveSection)
                  const Icon(Icons.check_circle_rounded,
                      size: 18, color: AppColors.success),
                const SizedBox(width: 6),
                Icon(
                  Icons.expand_more_rounded,
                  size: 22,
                  color: Theme.of(context).hintColor,
                ),
              ],
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(),
                    const SizedBox(height: 12),
                    // -- Header with count + free filter (same as Explore) --
                    Obx(() {
                      final all =
                          cloudModels.modelsByProvider[provider.id] ?? [];
                      final freeCount =
                          cloudModels.freeModelCountFor(provider.id);
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
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('${all.length}',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary)),
                          ),
                          if (freeCount > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.success
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('$freeCount free',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.success)),
                            ),
                          ],
                          const Spacer(),
                          if (freeCount > 0)
                            _miniFilterChip(
                              context,
                              'Free',
                              cloudModels.freeFirstByProvider[provider.id] ==
                                  true,
                              () =>
                                  cloudModels.toggleFreeFirst(provider.id),
                              isDark,
                            ),
                        ],
                      );
                    }),
                    const SizedBox(height: 10),
                    // -- Per-provider search (same as Explore) --
                    TextField(
                      onChanged: (v) =>
                          cloudModels.searchByProvider[provider.id] = v,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13, fontWeight: FontWeight.w500),
                      decoration: InputDecoration(
                        hintText: 'Search models...',
                        prefixIcon:
                            const Icon(Icons.search_rounded, size: 18),
                        suffixIcon: Obx(() => (cloudModels.searchByProvider[
                                        provider.id] ??
                                    '')
                                .isNotEmpty
                            ? IconButton(
                                tooltip: 'Clear',
                                onPressed: () => cloudModels
                                    .searchByProvider[provider.id] = '',
                                icon: const Icon(Icons.close_rounded,
                                    size: 18),
                              )
                            : const SizedBox.shrink()),
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 10),
                        fillColor: isDark
                            ? Colors.black.withValues(alpha: 0.2)
                            : const Color(0xFFF1F5F9),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // -- Auto-detected company filter (same as Explore) --
                    Obx(() {
                      final companies =
                          cloudModels.availableCompaniesFor(provider.id);
                      if (companies.length < 2) {
                        return const SizedBox.shrink();
                      }
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
                                    () => cloudModels
                                        .setCompanyFilter(provider.id, null),
                                    isDark),
                                for (final c in companies)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(left: 6),
                                    child: _companyChip(
                                        context,
                                        cloudModels
                                            .companyDisplayName(c),
                                        cloudModels.companyIcon(c) ??
                                            Icons.cloud_outlined,
                                        selected == c,
                                        () => cloudModels
                                            .setCompanyFilter(provider.id, c),
                                        isDark),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                      );
                    }),
                    // -- Compact boxed model list (same as Explore) --
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
                        final filtered =
                            cloudModels.filteredModelsFor(provider.id);
                        if (filtered.isEmpty) {
                          return Center(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 24),
                              child: Text('No matching models',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      color:
                                          Theme.of(context).hintColor)),
                            ),
                          );
                        }
                        final activeModel =
                            cloudModels.activeModelFor(provider.id);
                        return ListView.builder(
                          shrinkWrap: true,
                          padding:
                              const EdgeInsets.symmetric(vertical: 4),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final model = filtered[index];
                            final isActive = isActiveSection &&
                                activeModel == model;
                            final isFree = cloudModels.isFreeModel(
                                provider.id, model);
                            return _ModelRow(
                              title: model,
                              subtitle: '',
                              isActive: isActive,
                              isLoading: false,
                              progress: null,
                              badge: isFree ? 'FREE' : null,
                              badgeColor:
                                  isFree ? AppColors.success : null,
                              isDark: isDark,
                              onTap: isActive
                                  ? null
                                  : () {
                                      Navigator.pop(context);
                                      cloudModels.selectModel(
                                          provider.id, model);
                                    },
                            );
                          },
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -- Small pill chip used in section headers (Free toggle) --
  Widget _miniFilterChip(BuildContext context, String label, bool selected,
      VoidCallback onTap, bool isDark) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.15)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(14),
          border: selected
              ? Border.all(color: AppColors.primary.withValues(alpha: 0.4))
              : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: selected
                ? AppColors.primary
                : Theme.of(context).hintColor,
          ),
        ),
      ),
    );
  }

  // -- Company pill chip (auto-detected vendor filters) --
  Widget _companyChip(BuildContext context, String label, IconData icon,
      bool selected, VoidCallback onTap, bool isDark) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.15)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 13,
                color: selected
                    ? AppColors.primary
                    : Theme.of(context).hintColor),
            const SizedBox(width: 4),
            Text(label,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected
                        ? AppColors.primary
                        : Theme.of(context).hintColor)),
          ],
        ),
      ),
    );
  }

  // ── Flat search results across all providers ──

  Widget _buildSearchView(
    CloudModelController cloudModels,
    List<CloudProviderInfo> providers,
    bool isDark,
  ) {
    final q = _query.trim().toLowerCase();
    final settings = Get.find<SettingsController>();
    final isCloudActive = settings.inferenceMode.value == 'cloud';
    final activeProviderId = cloudModels.activeProvider;

    final matches = <MapEntry<CloudProviderInfo, String>>[];
    for (final p in providers) {
      for (final id in cloudModels.modelsByProvider[p.id] ?? const <String>[]) {
        if (id.toLowerCase().contains(q)) {
          matches.add(MapEntry(p, id));
        }
      }
    }

    if (matches.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No matching models',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).hintColor,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 24),
      itemCount: matches.length,
      itemBuilder: (context, index) {
        final entry = matches[index];
        final provider = entry.key;
        final id = entry.value;
        final isActive = isCloudActive &&
            provider.id == activeProviderId &&
            id == cloudModels.activeModelFor(provider.id);
        final isFree = cloudModels.isFreeModel(provider.id, id);
        return _ModelRow(
          title: id,
          subtitle: provider.id == 'custom'
              ? _customName(settings)
              : provider.name,
          isActive: isActive,
          isLoading: false,
          progress: null,
          badge: isFree ? 'FREE' : null,
          badgeColor: isFree ? AppColors.success : null,
          isDark: isDark,
          onTap: isActive
              ? null
              : () {
                  Navigator.pop(context);
                  cloudModels.selectModel(provider.id, id);
                },
        );
      },
    );
  }

  String _customName(SettingsController settings) {
    final name = settings.customCloudName.value;
    return name.isEmpty ? 'Custom API' : name;
  }
}

// ── Shared rows ──

class _ModelRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isActive;
  final bool isLoading;
  final double? progress;
  final String? badge;
  final Color? badgeColor;
  final bool isDark;
  final VoidCallback? onTap;

  const _ModelRow({
    required this.title,
    required this.subtitle,
    required this.isActive,
    required this.isLoading,
    required this.progress,
    required this.badge,
    required this.isDark,
    required this.onTap,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    final accent = badgeColor ?? AppColors.primary;
    final isDisabled = onTap == null && !isActive;

    return Opacity(
      opacity: isDisabled ? 0.5 : 1.0,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.primary.withValues(alpha: 0.08)
                    : (isDark
                        ? AppColors.bg.withValues(alpha: 0.35)
                        : const Color(0xFFF8FAFC)),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isActive
                      ? AppColors.primary.withValues(alpha: 0.4)
                      : (isDark
                          ? AppColors.border
                          : AppColors.borderLightMode),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _stripExtension(title),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? AppColors.textPrimary
                                    : const Color(0xFF0F172A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (subtitle.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).hintColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            badge!,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                              color: accent,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 10),
                      if (isLoading)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.warning,
                          ),
                        )
                      else if (isActive)
                        const Icon(Icons.check_circle_rounded,
                            size: 20, color: AppColors.success)
                      else
                        Icon(Icons.radio_button_unchecked_rounded,
                            size: 20,
                            color: isDark
                                ? AppColors.surfaceLight
                                : const Color(0xFFCBD5E1)),
                    ],
                  ),
                  if (isLoading) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: (progress ?? 0).clamp(0.0, 1.0),
                        minHeight: 3,
                        backgroundColor: isDark
                            ? AppColors.surfaceLight
                            : const Color(0xFFE2E8F0),
                        color: AppColors.warning,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final bool isDark;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, size: 28, color: AppColors.primary),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color:
                    isDark ? AppColors.textPrimary : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).hintColor,
              ),
            ),
            const SizedBox(height: 18),
            TextButton(
              onPressed: onAction,
              child: Text(
                actionLabel,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _stripExtension(String name) {
  for (final ext in const ['.gguf', '.litertlm', '.safetensors']) {
    if (name.toLowerCase().endsWith(ext)) {
      return name.substring(0, name.length - ext.length);
    }
  }
  return name;
}
