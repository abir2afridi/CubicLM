import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../controllers/settings_controller.dart';
import '../core/colors.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/design_tokens.dart';
import '../core/constants.dart';
import '../services/inference_service.dart';
import '../services/hive_service.dart';
import '../services/local_image_service.dart';
import '../services/device_info_service.dart';
import '../services/device_info_native.dart' as platform_info;
import '../ffi/sd_ffi_bindings.dart';
import '../services/skills/skill_registry_service.dart';
import '../services/skills/github_skill_source.dart';
import '../services/skills/url_skill_source.dart';
import '../services/mcp/mcp_registry_service.dart';
import '../services/mcp/mcp_config.dart';
import '../services/mcp/mcp_connection.dart';
import '../models/skill_model.dart';
import 'package:file_picker/file_picker.dart';
import 'log_view.dart';

class SettingsView extends GetView<SettingsController> {
  /// When true, renders just the scrollable config sections without its
  /// own Scaffold — used inside the Nodes page's Config tab.
  final bool embedded;
  const SettingsView({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (embedded) return _configBody(context);
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
        title: Text('nodes_config'.tr,
            style:
                GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 28, letterSpacing: -1)),
        toolbarHeight: 70,
        centerTitle: false,
      ),
      body: _configBody(context),
    );
  }

  Widget _configBody(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Obx(() => ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              const SizedBox(height: 16),
              _sectionLabel(context, 'settings_section_diagnostics'.tr),
              _appleGroupedCard(context, isDark, children: [
                _appleListTile(
                  context,
                  isDark,
                  leading:
                      _iconBox(AppColors.info, LucideIcons.terminal),
                  title: 'settings_system_logs'.tr,
                  subtitle: 'settings_system_logs_desc'.tr,
                  trailing: const Icon(LucideIcons.chevronRight, size: 20),
                  showDivider: false,
                  onTap: () => Get.to(() => const LogView()),
                ),
              ]),
              const SizedBox(height: 28),
              _sectionLabel(context, 'settings_section_hardware'.tr),
              _buildDeviceCard(context, isDark),
              const SizedBox(height: 28),
              _sectionLabel(context, 'settings_section_inference'.tr),
              _appleGroupedCard(context, isDark, children: [
                _appleListTile(
                  context,
                  isDark,
                  leading:
                      _iconBox(AppColors.success, LucideIcons.zap),
                  title: 'settings_local_privacy'.tr,
                  subtitle: _localSubtitle(),
                  trailing: controller.inferenceMode.value == 'local'
                      ? const Icon(LucideIcons.check,
                          size: 20,
                          color: Dt.accent)
                      : null,
                  showDivider: true,
                  onTap: () => controller.setInferenceMode('local'),
                ),
                _appleListTile(
                  context,
                  isDark,
                  leading: _iconBox(Dt.accent, LucideIcons.cloud),
                  title: 'settings_cloud_assistant'.tr,
                  subtitle: controller.cloudProvider.value.toUpperCase(),
                  trailing: controller.inferenceMode.value == 'cloud'
                      ? const Icon(LucideIcons.check,
                          size: 20,
                          color: Dt.accent)
                      : null,
                  showDivider: false,
                  onTap: () => controller.setInferenceMode('cloud'),
                ),
              ]),
              const SizedBox(height: 28),
              _sectionLabel(context, 'settings_section_system_prompt'.tr),
              _appleGroupedCard(context, isDark, children: [
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('settings_prompt_desc'.tr,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).hintColor)),
                        const SizedBox(height: 12),
                        TextField(
                          controller: controller.globalSystemPromptController,
                          minLines: 3,
                          maxLines: 8,
                          style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w500),
                          decoration: InputDecoration(
                            hintText: AppConstants.systemPrompt,
                            contentPadding: const EdgeInsets.all(16),
                            suffixIcon: IconButton(
                                icon: const Icon(LucideIcons.save,
                                    size: 22),
                                onPressed: () {
                                  controller.setGlobalSystemPrompt(controller.globalSystemPromptController.text);
                                  Get.snackbar('Saved', 'System prompt updated successfully',
                                    snackPosition: SnackPosition.BOTTOM,
                                    backgroundColor: AppColors.success,
                                    colorText: Colors.white);
                                }),
                          ),
                          onSubmitted: (v) =>
                              controller.setGlobalSystemPrompt(v),
                        ),
                      ]),
                ),
              ]),
              const SizedBox(height: 28),
              _sectionLabel(context, 'settings_section_skills'.tr),
              _buildSkillsSection(context, isDark),
              const SizedBox(height: 28),
              _sectionLabel(context, 'settings_section_mcp'.tr),
              const _McpSection(),
              const SizedBox(height: 28),
              _sectionLabel(context, 'settings_section_local_params'.tr),
              _buildLiteRtCard(context, isDark),
              const SizedBox(height: 12),
              _buildModelParametersCard(context, isDark),
              const SizedBox(height: 28),
              _sectionLabel(context, 'settings_section_image_params'.tr),
              _buildImageGenerationCard(context, isDark),
              const SizedBox(height: 50),
            ],
          ));
  }

  // ── Apple grouped card container ──
  Widget _appleGroupedCard(BuildContext context, bool isDark,
      {required List<Widget> children}) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDark ? Dt.cardDark : Dt.card,
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.07) : Dt.hairline),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  // ── Apple-style list tile ──
  Widget _appleListTile(
    BuildContext context,
    bool isDark, {
    Widget? leading,
    required String title,
    String? subtitle,
    Widget? trailing,
    bool showDivider = true,
    VoidCallback? onTap,
  }) {
    return Column(children: [
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(children: [
            if (leading != null) ...[leading, const SizedBox(width: 16)],
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  Text(title,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isDark ? AppColors.textPrimary : Dt.textPrimary)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12, fontWeight: FontWeight.w500, color: Theme.of(context).hintColor))
                  ],
                ])),
            if (trailing != null) trailing,
          ]),
        ),
      ),
      if (showDivider)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Divider(
              height: 1,
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03)),
        ),
    ]);
  }

  Widget _iconBox(Color color, IconData icon) {
    return Container(
        width: 32,
        height: 32,
        decoration:
            BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 18, color: color));
  }

  Widget _sectionLabel(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, bottom: 8),
      child: Text(title,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: Theme.of(context).hintColor)),
    );
  }

  String _localSubtitle() {
    final inf = Get.find<InferenceService>();
    final localImage = Get.find<LocalImageService>();
    if (inf.isModelLoaded.value) {
      return 'Active: ${inf.loadedModelName.value.split('/').last}';
    } else if (localImage.isModelLoaded.value) {
      return 'Active: ${localImage.loadedModelName.value.split('/').last}';
    }
    return 'Optimized for local latency';
  }

  Widget _buildDeviceCard(BuildContext context, bool isDark) {
    return Obx(() {
      final device = Get.find<DeviceInfoService>();
      Color tierColor;
      IconData tierIcon;
      switch (device.deviceTier.value) {
        case 'low':
          tierColor = AppColors.error;
          tierIcon = LucideIcons.batteryLow;
          break;
        case 'mid':
          tierColor = AppColors.warning;
          tierIcon = LucideIcons.smartphone;
          break;
        case 'high':
          tierColor = AppColors.success;
          tierIcon = LucideIcons.smartphone;
          break;
        case 'ultra':
          tierColor = Dt.accent;
          tierIcon = LucideIcons.rocket;
          break;
        default:
          tierColor = Theme.of(context).hintColor;
          tierIcon = LucideIcons.helpCircle;
      }

      final soc = device.socFamily.value;
      final quantWarning = soc.quantWarning;

      return _appleGroupedCard(context, isDark, children: [
        Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              _iconBox(tierColor, tierIcon),
              const SizedBox(width: 16),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(device.tierDescription,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                        '${device.availableRamGB.value.toStringAsFixed(1)}GB RAM · Context ${device.recommendedContextSize}',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13, fontWeight: FontWeight.w500, color: Theme.of(context).hintColor)),
                  ])),
            ])),
        Divider(height: 1, indent: 20, endIndent: 20, color: isDark ? AppColors.border : AppColors.borderLightMode),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(children: [
            _iconBox(AppColors.secondary, LucideIcons.cpu),
            const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        device.processorName.value.isNotEmpty
                            ? device.processorName.value
                            : soc.displayName,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    if (device.gpuName.value.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(children: [
                        Icon(LucideIcons.gamepad2,
                            size: 13,
                            color: Theme.of(context).hintColor),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(device.gpuName.value,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(context).hintColor)),
                        ),
                      ]),
                    ],
                    if (device.socHardware.value.isNotEmpty &&
                        device.socHardware.value !=
                            device.processorName.value) ...[
                      const SizedBox(height: 2),
                      Text(device.socHardware.value,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12, fontWeight: FontWeight.w500,
                              color: Theme.of(context).hintColor)),
                    ],
                    const SizedBox(height: 4),
                    Text('Recommendation: ${soc.recommendedQuant}',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: quantWarning != null
                                ? AppColors.warning
                                : Theme.of(context).hintColor)),
                  ],
                ),
              ),
          ]),
        ),
        if (quantWarning != null) ...[
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(LucideIcons.info,
                    size: 18, color: AppColors.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(quantWarning,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: AppColors.warning,
                        fontWeight: FontWeight.w600,
                      )),
                ),
              ],
            ),
          ),
        ],
      ]);
      });
  }

  Widget _buildLiteRtCard(BuildContext context, bool isDark) {
    final modes = [
      (
        value: 'auto_fast',
        title: 'Heuristic Optimization',
        subtitle: 'Auto GPU/CPU orchestration',
        icon: LucideIcons.sparkles
      ),
      (
        value: 'gpu_fast',
        title: 'Acceleration Engine',
        subtitle: 'Maximum throughput (Experimental)',
        icon: LucideIcons.zap
      ),
      (
        value: 'cpu_safe',
        title: 'Stability Mode',
        subtitle: 'Predictable CPU execution',
        icon: LucideIcons.shield
      ),
    ];
    return _appleGroupedCard(context, isDark, children: [
      for (var i = 0; i < modes.length; i++)
        _appleListTile(
          context,
          isDark,
          leading: _iconBox(Dt.accent, modes[i].icon),
          title: modes[i].title,
          subtitle: modes[i].subtitle,
          trailing: controller.liteRtPerformanceMode.value == modes[i].value
              ? const Icon(LucideIcons.checkCircle,
                  size: 20,
                  color: Dt.accent)
              : null,
          showDivider: i < modes.length - 1,
          onTap: () => controller.setLiteRtPerformanceMode(modes[i].value),
        ),
    ]);
  }

  Widget _buildModelParametersCard(BuildContext context, bool isDark) {
    return _appleGroupedCard(context, isDark, children: [
      _modelParameterSlider(
        context,
        isDark,
        label: 'settings_inference_temperature'.tr,
        value: controller.temperature.value,
        min: 0.0,
        max: 2.0,
        divisions: 20,
        safeMax: 1.0,
        onChanged: (v) => controller.setTemperature(v),
        icon: LucideIcons.thermometer,
        warning: 'High temperature may result in creative but halluncinated output.',
      ),
      _parameterDivider(isDark),
      // ── Auto Tune (recommended) ──
      Obx(() {
        final auto = controller.autoTuneParams.value;
        return Column(children: [
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            leading: Icon(LucideIcons.sparkles,
                size: 20,
                color: auto ? Dt.accent : Theme.of(context).hintColor),
            title: Row(children: [
              Text('settings_auto_tune'.tr,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('RECOMMENDED',
                        maxLines: 1,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: AppColors.success)),
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _showAutoTuneInfoDialog(context, isDark),
                child: Icon(LucideIcons.info,
                    size: 20, color: Theme.of(context).hintColor),
              ),
            ]),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                auto
                    ? 'Context ${_fmtTokens(controller.effectiveContextSize)} · '
                        'Output ${_fmtTokens(controller.effectiveMaxTokens)} · tuned to RAM'
                    : 'Manual limits — extended ranges up to 1M context',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).hintColor)),
            ),
            trailing: Switch(
                value: auto,
                activeThumbColor: Dt.accent,
                onChanged: (v) => controller.setAutoTuneParams(v)),
          ),
          if (!auto) ...[
            const SizedBox(height: 6),
            _ladderSlider(
              context,
              isDark,
              label: 'settings_output_limit'.tr,
              ladder: _tokLadder,
              value: controller.maxTokens.value,
              safeMax: Get.find<DeviceInfoService>().maxSafeTokens,
              onChanged: (v) => controller.setMaxTokens(v),
              icon: LucideIcons.type,
            ),
            _parameterDivider(isDark),
            _ladderSlider(
              context,
              isDark,
              label: 'settings_context_window'.tr,
              ladder: _contextLadder(),
              value: controller.contextSize.value,
              safeMax:
                  Get.find<DeviceInfoService>().maxSafeContextSize,
              onChanged: (v) => controller.setContextSize(v),
              icon: LucideIcons.history,
              extraWarning: 'Big windows increase memory pressure a lot.',
            ),
          ],
        ]);
      }),
    ]);
  }

  static const List<int> _tokLadder = [
    256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536, 131072,
  ];

  static List<int> _contextLadder() {
    const full = [
      1024, 2048, 4096, 8192, 12288, 16384, 24576, 32768, 49152, 65536,
      98304, 131072, 196608, 262144, 393216, 524288, 786432, 1048576,
    ];
    // LiteRT runtime is hardware-limited to 4K context.
    final inference = Get.find<InferenceService>();
    final hive = Get.find<HiveService>();
    final savedRuntime =
        hive.getSetting<String>(AppConstants.keyLocalModelRuntime) ?? '';
    final isLiteRtActive = (inference.isModelLoaded.value &&
            inference.loadedModelRuntime.value == 'litert') ||
        (!inference.isModelLoaded.value &&
            savedRuntime.toLowerCase() == 'litert');
    if (!isLiteRtActive) return full;
    return full.where((v) => v <= 4096).toList();
  }

  static String _fmtTokens(int v) =>
      v >= 1024 ? '${(v / 1024).toStringAsFixed(v % 1024 == 0 ? 0 : 1)}K' : '$v';

  void _showAutoTuneInfoDialog(BuildContext context, bool isDark) {
    Get.dialog(
      AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(children: [
          const Icon(LucideIcons.sparkles, color: Dt.accent),
          const SizedBox(width: 10),
          Text('settings_auto_tune'.tr,
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        ]),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _infoPoint('📱', 'Sets the context window and output budget to '
                  'the highest your phone\'s RAM can safely run — no guesswork.'),
              _infoPoint('🚀', 'Cloud models are sent WITHOUT an output cap, so '
                  'big models write full detailed answers instead of stopping early.'),
              _infoPoint('📚', 'Works with large-context models — when you switch '
                  'to manual you can push context up to 1M tokens for models that support it.'),
              _infoPoint('🛡️', 'Prevents truncated replies and chat freezes caused '
                  'by too-small limits.'),
              const SizedBox(height: 4),
              Text(
                'Turn it off only if you want manual control of every limit.',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).hintColor),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _infoPoint(String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(emoji, style: const TextStyle(fontSize: 15)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: GoogleFonts.plusJakartaSans(fontSize: 13, height: 1.35)),
        ),
      ]),
    );
  }

  /// Slider over a fixed ladder of standard sizes (log-ish steps).
  Widget _ladderSlider(
    BuildContext context,
    bool isDark, {
    required String label,
    required List<int> ladder,
    required int value,
    required int safeMax,
    required ValueChanged<int> onChanged,
    required IconData icon,
    String? extraWarning,
  }) {
    // Snap current value to nearest ladder entry.
    int idx = 0;
    for (var i = 0; i < ladder.length; i++) {
      if (ladder[i] <= value) idx = i;
    }
    final display = ladder[idx];
    final isOver = display > safeMax;
    final accent = isOver ? AppColors.warning : Dt.accent;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: 10),
          Text(label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 15, fontWeight: FontWeight.w700)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Text(_fmtTokens(display),
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: accent, fontWeight: FontWeight.w800)),
          ),
        ]),
        Slider(
          value: idx.toDouble(),
          min: 0,
          max: (ladder.length - 1).toDouble(),
          divisions: ladder.length - 1,
          activeColor: accent,
          onChanged: (v) {
            final nv = ladder[v.round()];
            if (nv > safeMax && display <= safeMax) {
              HapticFeedback.heavyImpact();
            }
            onChanged(nv);
          },
        ),
        if (isOver)
          Container(
              margin: const EdgeInsets.only(top: 4),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Icon(LucideIcons.info, size: 16, color: accent),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(
                        extraWarning ??
                            'Above this device\'s recommended limit — may cause OOM on low RAM.',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: accent,
                            fontWeight: FontWeight.w600))),
              ])),
      ]),
    );
  }

  Widget _buildImageGenerationCard(BuildContext context, bool isDark) {
    final stepsValue = controller.imageSteps.value.toDouble();
    const safeMax = 8.0;
    final isOver = stepsValue > safeMax;
    final accent = isOver ? AppColors.warning : Dt.accent;
    final selectedBackend = controller.imageGenBackend.value;
    final gpuBackend = controller.recommendedImageGpuBackend();
    final gpuAvailable = gpuBackend != Backend.cpu;

    return _appleGroupedCard(context, isDark, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(LucideIcons.sparkles, size: 16, color: accent),
            const SizedBox(width: 10),
            Text('settings_sampling_steps'.tr,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 15, fontWeight: FontWeight.w700)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(controller.imageSteps.value.toString(),
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: accent,
                      fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 12),
          Slider(
              value: stepsValue.clamp(1, 20),
              min: 1,
              max: 20,
              divisions: 19,
              activeColor: accent,
              onChanged: (v) => controller.setImageSteps(v.toInt())),
          if (isOver)
            Container(
                margin: const EdgeInsets.only(top: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Icon(LucideIcons.info, size: 16, color: accent),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(
                          'Higher steps improve fidelity but increase latency.',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: accent,
                              fontWeight: FontWeight.w600))),
                ])),
        ]),
      ),
      _parameterDivider(isDark),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(LucideIcons.image,
                size: 16,
                color: Dt.accent),
            const SizedBox(width: 10),
            Text('settings_synthesis_resolution'.tr,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 15, fontWeight: FontWeight.w700)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: Dt.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(
                  controller.imageGenSize.value == 0
                      ? 'Automatic'
                      : '${controller.imageGenSize.value}px',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: Dt.accent,
                      fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final option in const [
                (value: 0, label: 'Auto'),
                (value: 256, label: '256p'),
                (value: 320, label: '320p'),
                (value: 384, label: '384p'),
                (value: 512, label: '512p'),
              ])
                ChoiceChip(
                  label: Text(option.label),
                  selected: controller.imageGenSize.value == option.value,
                  onSelected: (_) => controller.setImageGenSize(option.value),
                  labelStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: controller.imageGenSize.value == option.value
                        ? Colors.white
                        : Theme.of(context).hintColor,
                  ),
                  selectedColor: Dt.accent,
                  backgroundColor: isDark ? AppColors.surfaceLight : Dt.pillMuted,
                  side: BorderSide.none,
                  showCheckmark: false,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
            ],
          ),
        ]),
      ),
      _parameterDivider(isDark),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _iconBox(Dt.accent, selectedBackend == Backend.cpu ? LucideIcons.cpu : LucideIcons.zap),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('settings_compute_backend'.tr,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(controller.imageGpuLabel(),
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).hintColor)),
                  ]),
            ),
          ]),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: [
              const ButtonSegment(
                  value: false,
                  icon: Icon(LucideIcons.cpu, size: 18),
                  label: Text('CPU')),
              ButtonSegment(
                  value: true,
                  icon: const Icon(LucideIcons.zap, size: 18),
                  label: Text(
                    'GPU',
                    style: TextStyle(
                      color: selectedBackend == Backend.cpu
                          ? AppColors.error
                          : Colors.white,
                    ),
                  )),
            ],
            selected: {selectedBackend != Backend.cpu},
            onSelectionChanged: (values) {
              final useGpu = values.first;
              if (useGpu && !gpuAvailable) return;
              controller.setImageBackendMode(useGpu);
            },
            showSelectedIcon: false,
          ),
        ]),
      ),
    ]);
  }

  Widget _parameterDivider(bool isDark) {
    return Divider(
      height: 1,
      indent: 20,
      endIndent: 20,
      color: isDark ? AppColors.border.withValues(alpha: 0.5) : AppColors.borderLightMode.withValues(alpha: 0.5),
    );
  }

  Widget _modelParameterSlider(
    BuildContext context,
    bool isDark, {
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required double safeMax,
    required ValueChanged<double> onChanged,
    required IconData icon,
    required String warning,
    String? displayValue,
  }) {
    final isOver = value > safeMax;
    final danger = safeMax < max
        ? ((value - safeMax) / (max - safeMax)).clamp(0.0, 1.0)
        : 0.0;
    final accent = isOver
        ? Color.lerp(AppColors.warning, AppColors.error, danger)!
        : Dt.accent;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: 10),
          Text(label,
              style:
                  GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Text(displayValue ?? value.toStringAsFixed(2),
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: accent, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 12),
        Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            activeColor: accent,
            onChanged: (v) {
              if (v > safeMax && value <= safeMax) {
                HapticFeedback.heavyImpact();
                Get.snackbar('Security Alert', warning,
                    snackPosition: SnackPosition.BOTTOM,
                    backgroundColor: AppColors.error,
                    colorText: Colors.white,
                    duration: const Duration(seconds: 4),
                    margin: const EdgeInsets.all(20));
              } else if (v > safeMax) {
                HapticFeedback.mediumImpact();
              }
              onChanged(v);
            }),
        if (isOver)
          Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Icon(LucideIcons.info, size: 16, color: accent),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(warning,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: accent,
                            fontWeight: FontWeight.w600))),
              ])),
      ]),
    );
  }

  // ── Skills ──
  Widget _buildSkillsSection(BuildContext context, bool isDark) {
    final registry = Get.find<SkillRegistryService>();
    return Obx(() {
      final all = registry.skills.toList();
      final enabledCount = all.where((s) => s.enabled).length;
      return _appleGroupedCard(context, isDark, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(children: [
            _iconBox(Dt.accent, LucideIcons.sparkles),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Skills',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    all.isEmpty
                        ? 'No skills installed'
                        : '$enabledCount of ${all.length} enabled — appended to system prompt',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).hintColor),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _showImportOptions(context),
              icon: const Icon(LucideIcons.upload, size: 16),
              label: Text('Import',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(
                backgroundColor: Dt.accent,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                minimumSize: const Size(0, 36),
              ),
            ),
          ]),
        ),
        if (all.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Text(
              'Skills are offline instruction blocks that teach the model how to handle certain tasks. Import a .md file or enable a built-in skill.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  height: 1.4,
                  color: Theme.of(context).hintColor),
            ),
          )
        else
          for (var i = 0; i < all.length; i++) ...[
            Divider(
                height: 1,
                indent: 20,
                endIndent: 20,
                color: isDark
                    ? AppColors.border.withValues(alpha: 0.5)
                    : AppColors.borderLightMode.withValues(alpha: 0.5)),
            _skillTile(context, isDark, all[i]),
          ],
        const SizedBox(height: 8),
      ]);
    });
  }

  Widget _skillTile(BuildContext context, bool isDark, SkillModel skill) {
    final registry = Get.find<SkillRegistryService>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: skill.enabled
                  ? Dt.accent.withValues(alpha: 0.15)
                  : Theme.of(context).hintColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              skill.isBuiltIn ? LucideIcons.award : LucideIcons.fileText,
              size: 18,
              color: skill.enabled ? Dt.accent : Theme.of(context).hintColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(skill.name,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                  if (skill.isBuiltIn)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('BUILT-IN',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                              color: AppColors.info)),
                    ),
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .hintColor
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(skill.source,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).hintColor)),
                  ),
                ]),
                const SizedBox(height: 2),
                Text(skill.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).hintColor)),
                const SizedBox(height: 2),
                Text('${skill.author} · v${skill.version}',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color:
                            Theme.of(context).hintColor.withValues(alpha: 0.8))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(children: [
            Switch(
              value: skill.enabled,
              activeThumbColor: Dt.accent,
              onChanged: (v) =>
                  v ? registry.enable(skill.id) : registry.disable(skill.id),
            ),
            InkWell(
              onTap: () => _showSkillPreview(context, isDark, skill),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(LucideIcons.eye,
                    size: 18, color: Theme.of(context).hintColor),
              ),
            ),
            if (!skill.isBuiltIn || true)
              InkWell(
                onTap: () => _confirmDeleteSkill(context, isDark, skill),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(LucideIcons.trash2,
                      size: 18, color: AppColors.error.withValues(alpha: 0.8)),
                ),
              ),
          ]),
        ],
      ),
    );
  }

  Future<void> _importSkillFromFile(BuildContext context) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['md', 'markdown', 'txt'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      String? content;
      if (file.bytes != null) {
        content = String.fromCharCodes(file.bytes!);
      } else if (file.path != null) {
        content = await File(file.path!).readAsString();
      }
      if (content == null || content.trim().isEmpty) {
        Get.snackbar('Import failed', 'File is empty',
            snackPosition: SnackPosition.BOTTOM);
        return;
      }
      // Derive name from filename.
      String name = file.name.replaceAll(RegExp(r'\.(md|markdown|txt)$', caseSensitive: false), '');
      name = name.replaceAll(RegExp(r'[-_]+'), ' ').trim();
      if (name.isEmpty) name = 'Imported Skill';
      // Show preview/confirm dialog before saving.
      if (!context.mounted) return;
      await _showImportPreview(context, content, initialName: name);
    } catch (e) {
      Get.snackbar('Import failed', '$e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  void _showImportOptions(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Get.bottomSheet(
      Container(
        decoration: BoxDecoration(
          color: isDark ? Dt.cardDark : Dt.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).hintColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Import Skill',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Choose a source — all imports show a preview before saving.',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: Theme.of(context).hintColor,
                    height: 1.4)),
            const SizedBox(height: 16),
            _importOptionTile(
              context,
              isDark,
              icon: LucideIcons.fileText,
              title: 'From file',
              subtitle: 'Pick a .md file from your device',
              onTap: () {
                Get.back();
                _importSkillFromFile(context);
              },
            ),
            _importOptionTile(
              context,
              isDark,
              icon: LucideIcons.github,
              title: 'Browse Anthropic skills',
              subtitle: 'Flat list from anthropics/skills on GitHub',
              onTap: () {
                Get.back();
                _browseGithubSkills(context);
              },
            ),
            _importOptionTile(
              context,
              isDark,
              icon: LucideIcons.link2,
              title: 'From URL',
              subtitle: 'Paste any direct link to a raw markdown file',
              onTap: () {
                Get.back();
                _importFromUrl(context);
              },
              showDivider: false,
            ),
          ],
        ),
      ),
      isScrollControlled: false,
    );
  }

  Widget _importOptionTile(
    BuildContext context,
    bool isDark, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool showDivider = true,
  }) {
    return Column(children: [
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            _iconBox(Dt.accent, icon),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: Theme.of(context).hintColor,
                          height: 1.3)),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight,
                size: 18, color: Theme.of(context).hintColor),
          ]),
        ),
      ),
      if (showDivider)
        Divider(
            height: 1,
            indent: 50,
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.06)),
    ]);
  }

  Future<void> _browseGithubSkills(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final source = GithubSkillSource();
    // Show loading sheet first.
    Get.bottomSheet(
      _GithubBrowseSheet(source: source, isDark: isDark),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  Future<void> _importFromUrl(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final urlCtrl = TextEditingController();
    final urlOk = await Get.dialog<bool>(
      AlertDialog(
        backgroundColor: isDark ? Dt.cardDark : Dt.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Import from URL',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Paste a direct link to a raw markdown file.',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: Theme.of(context).hintColor)),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: 'https://raw.githubusercontent.com/.../SKILL.md',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Get.back(result: false),
              child: Text('common_cancel'.tr)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Dt.accent),
            onPressed: () => Get.back(result: true),
            child: const Text('Fetch'),
          ),
        ],
      ),
    );
    final url = urlCtrl.text.trim();
    urlCtrl.dispose();
    if (urlOk != true || url.isEmpty) return;
    if (!context.mounted) return;
    // Show loading.
    Get.dialog(
      Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? Dt.cardDark : Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(color: Dt.accent),
            const SizedBox(height: 16),
            Text('Fetching…',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
      barrierDismissible: false,
    );
    try {
      final content = await UrlSkillSource().fetchFromUrl(url);
      if (!context.mounted) return;
      Get.back(); // close loading
      final fm = UrlSkillSource.parseFrontmatter(content);
      final name = fm['name']?.isNotEmpty == true
          ? fm['name']!
          : Uri.tryParse(url)?.pathSegments.last
                  .replaceAll(RegExp(r'\.(md|markdown)$', caseSensitive: false), '')
                  .replaceAll(RegExp(r'[-_]+'), ' ')
                  .trim() ??
              'Imported Skill';
      final desc = fm['description'] ?? '';
      final author = fm['author'] ?? 'URL';
      // Reuse preview dialog but with url source.
      await _showUrlPreview(context, content,
          initialName: name, initialDesc: desc, initialAuthor: author);
    } catch (e) {
      Get.back(); // close loading if still open
      if (Get.isDialogOpen ?? false) Get.back();
      Get.snackbar('Fetch failed', '$e',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: AppColors.error,
          colorText: Colors.white);
    }
  }

  Future<void> _showUrlPreview(BuildContext context, String content,
      {required String initialName,
      String initialDesc = '',
      String initialAuthor = 'URL'}) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nameCtrl = TextEditingController(text: initialName);
    final descCtrl = TextEditingController(text: initialDesc);
    final authorCtrl = TextEditingController(text: initialAuthor);
    final previewOk = await Get.dialog<bool>(
      AlertDialog(
        backgroundColor: isDark ? Dt.cardDark : Dt.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Import Skill',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descCtrl,
                decoration: InputDecoration(
                  labelText: 'Description (optional)',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: authorCtrl,
                decoration: InputDecoration(
                  labelText: 'Author',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
              Text('Preview — ${content.length} chars (untrusted text)',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).hintColor)),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 220),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Dt.pillMuted.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Dt.hairline),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    content.length > 4000
                        ? '${content.substring(0, 4000)}\n…(truncated)'
                        : content,
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, height: 1.4),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Get.back(result: false),
              child: Text('common_cancel'.tr)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Dt.accent),
            onPressed: () => Get.back(result: true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (previewOk != true) {
      nameCtrl.dispose();
      descCtrl.dispose();
      authorCtrl.dispose();
      return;
    }
    try {
      final registry = Get.find<SkillRegistryService>();
      await registry.importFromMarkdown(
        content,
        name: nameCtrl.text,
        description: descCtrl.text,
        author: authorCtrl.text,
        source: 'url',
        enabled: true,
      );
      Get.snackbar('Skill imported', nameCtrl.text.trim(),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: AppColors.success,
          colorText: Colors.white);
    } catch (e) {
      Get.snackbar('Import failed', '$e',
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      nameCtrl.dispose();
      descCtrl.dispose();
      authorCtrl.dispose();
    }
  }

  Future<void> _showImportPreview(BuildContext context, String content,
      {required String initialName}) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nameCtrl = TextEditingController(text: initialName);
    final descCtrl = TextEditingController();
    final authorCtrl = TextEditingController(text: 'User');
    final previewOk = await Get.dialog<bool>(
      AlertDialog(
        backgroundColor: isDark ? Dt.cardDark : Dt.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Import Skill',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descCtrl,
                decoration: InputDecoration(
                  labelText: 'Description (optional)',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: authorCtrl,
                decoration: InputDecoration(
                  labelText: 'Author',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
              Text('Preview — ${content.length} chars',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).hintColor)),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 220),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Dt.pillMuted.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Dt.hairline),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    content.length > 4000
                        ? '${content.substring(0, 4000)}\n…(truncated)'
                        : content,
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, height: 1.4),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Get.back(result: false),
              child: Text('common_cancel'.tr)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Dt.accent),
            onPressed: () => Get.back(result: true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (previewOk != true) return;
    try {
      final registry = Get.find<SkillRegistryService>();
      await registry.importFromMarkdown(
        content,
        name: nameCtrl.text,
        description: descCtrl.text,
        author: authorCtrl.text,
        source: 'file',
        enabled: true,
      );
      Get.snackbar('Skill imported', nameCtrl.text.trim(),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: AppColors.success,
          colorText: Colors.white);
    } catch (e) {
      Get.snackbar('Import failed', '$e',
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      nameCtrl.dispose();
      descCtrl.dispose();
      authorCtrl.dispose();
    }
  }

  void _showSkillPreview(
      BuildContext context, bool isDark, SkillModel skill) {
    Get.dialog(
      AlertDialog(
        backgroundColor: isDark ? Dt.cardDark : Dt.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(skill.name,
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${skill.author} · v${skill.version} · ${skill.source}',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, color: Theme.of(context).hintColor)),
              const SizedBox(height: 4),
              Text(skill.description,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: Theme.of(context).hintColor)),
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 320),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Dt.pillMuted.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  child: Text(skill.content,
                      style:
                          GoogleFonts.plusJakartaSans(fontSize: 12, height: 1.4)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Close')),
        ],
      ),
    );
  }

  void _confirmDeleteSkill(
      BuildContext context, bool isDark, SkillModel skill) {
    Get.dialog(
      AlertDialog(
        backgroundColor: isDark ? Dt.cardDark : Dt.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete skill?',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: Text('Delete "${skill.name}"? This cannot be undone.',
            style: GoogleFonts.plusJakartaSans(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Get.back(), child: Text('common_cancel'.tr)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Get.back();
              Get.find<SkillRegistryService>().delete(skill.id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _GithubBrowseSheet extends StatefulWidget {
  final GithubSkillSource source;
  final bool isDark;
  const _GithubBrowseSheet({required this.source, required this.isDark});

  @override
  State<_GithubBrowseSheet> createState() => _GithubBrowseSheetState();
}

class _GithubBrowseSheetState extends State<_GithubBrowseSheet> {
  late Future<List<GithubSkillEntry>> _future;
  bool _refreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<GithubSkillEntry>> _load({bool force = false}) async {
    try {
      final list = await widget.source.listAvailable(forceRefresh: force);
      setState(() => _error = null);
      return list;
    } catch (e) {
      setState(() => _error = e.toString());
      rethrow;
    }
  }

  Future<void> _import(GithubSkillEntry entry) async {
    Get.dialog(
      Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: widget.isDark ? Dt.cardDark : Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(color: Dt.accent),
            const SizedBox(height: 12),
            Text('Fetching ${entry.path}…',
                style: GoogleFonts.plusJakartaSans(fontSize: 12)),
          ]),
        ),
      ),
      barrierDismissible: false,
    );
    try {
      final content = await widget.source.fetchSkillContent(entry.path);
      if (!mounted) return;
      Get.back();
      // Show preview using same dialog as file import but with github source.
      final fm = UrlSkillSource.parseFrontmatter(content);
      final name = entry.name.isNotEmpty ? entry.name : fm['name'] ?? entry.path.split('/').last;
      final desc = entry.description.isNotEmpty ? entry.description : fm['description'] ?? '';
      // Reuse the preview dialog from SettingsView by delegating to registry directly.
      final previewOk = await Get.dialog<bool>(
        AlertDialog(
          backgroundColor: widget.isDark ? Dt.cardDark : Dt.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Import Skill',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(desc,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: Theme.of(context).hintColor)),
                ],
                const SizedBox(height: 8),
                Text('From: ${entry.path} (untrusted text)',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11, color: Theme.of(context).hintColor)),
                const SizedBox(height: 10),
                Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: widget.isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : Dt.pillMuted.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      content.length > 4000
                          ? '${content.substring(0, 4000)}\n…(truncated)'
                          : content,
                      style:
                          GoogleFonts.plusJakartaSans(fontSize: 12, height: 1.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Get.back(result: false),
                child: Text('common_cancel'.tr)),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Dt.accent),
              onPressed: () => Get.back(result: true),
              child: const Text('Import'),
            ),
          ],
        ),
      );
      if (previewOk != true) return;
      await Get.find<SkillRegistryService>().importFromMarkdown(
        content,
        name: name,
        description: desc,
        author: 'anthropics/skills',
        source: 'github',
        enabled: true,
      );
      Get.snackbar('Skill imported', name,
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: AppColors.success,
          colorText: Colors.white);
    } catch (e) {
      if (Get.isDialogOpen ?? false) Get.back();
      Get.snackbar('Import failed', '$e',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: AppColors.error,
          colorText: Colors.white);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: BoxDecoration(
        color: widget.isDark ? Dt.cardDark : Dt.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        const SizedBox(height: 10),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(context).hintColor.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Browse Anthropic skills',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text('anthropics/skills — flat list, no search',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: Theme.of(context).hintColor,
                          height: 1.3)),
                ],
              ),
            ),
            IconButton(
              onPressed: () async {
                setState(() => _refreshing = true);
                try {
                  final list = await _load(force: true);
                  setState(() {
                    _future = Future.value(list);
                    _refreshing = false;
                  });
                } catch (_) {
                  setState(() => _refreshing = false);
                }
              },
              icon: _refreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(LucideIcons.refreshCw, size: 18),
            ),
            IconButton(
              onPressed: () => Get.back(),
              icon: const Icon(LucideIcons.x, size: 20),
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder<List<GithubSkillEntry>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: Dt.accent));
              }
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(LucideIcons.alertTriangle,
                          size: 32, color: AppColors.warning),
                      const SizedBox(height: 12),
                      Text('Failed to load',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(_error ?? snap.error.toString(),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: Theme.of(context).hintColor)),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () =>
                            setState(() => _future = _load(force: true)),
                        style: FilledButton.styleFrom(
                            backgroundColor: Dt.accent),
                        child: const Text('Retry'),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text('Showing cached list if available.',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  color: Theme.of(context).hintColor)),
                        ),
                    ],
                  ),
                );
              }
              final list = snap.data ?? [];
              if (list.isEmpty) {
                return Center(
                  child: Text('No skills found',
                      style: GoogleFonts.plusJakartaSans(
                          color: Theme.of(context).hintColor)),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                itemCount: list.length,
                separatorBuilder: (_, __) => Divider(
                    height: 1,
                    indent: 12,
                    color: widget.isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.06)),
                itemBuilder: (_, i) {
                  final e = list[i];
                  final alreadyInstalled = Get.find<SkillRegistryService>()
                      .skills
                      .any((s) => s.source == 'github' && s.name == e.name);
                  return ListTile(
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Dt.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(LucideIcons.sparkles,
                          size: 18, color: Dt.accent),
                    ),
                    title: Text(e.name,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    subtitle: e.description.isNotEmpty
                        ? Text(e.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: Theme.of(context).hintColor))
                        : Text(e.path,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                color: Theme.of(context).hintColor)),
                    trailing: alreadyInstalled
                        ? const Icon(LucideIcons.check,
                            size: 18, color: AppColors.success)
                        : FilledButton(
                            onPressed: () => _import(e),
                            style: FilledButton.styleFrom(
                              backgroundColor: Dt.accent,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              minimumSize: const Size(0, 32),
                              tapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text('Import',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                          ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _McpSection extends StatefulWidget {
  const _McpSection();

  @override
  State<_McpSection> createState() => _McpSectionState();
}

class _McpSectionState extends State<_McpSection> {
  final _nameCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  bool _initialized = false;
  bool _obscureToken = true;
  bool _saving = false;

  McpRegistryService get _registry => Get.find<McpRegistryService>();

  @override
  void initState() {
    super.initState();
    _loadFromConfig();
    _registry.getToken().then((v) {
      if (mounted && v != null) _tokenCtrl.text = v;
    });
  }

  void _loadFromConfig() {
    final c = _registry.config.value;
    if (c != null) {
      _nameCtrl.text = c.name;
      _urlCtrl.text = c.url;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _save({bool enableIfValid = false}) async {
    final name = _nameCtrl.text.trim().isEmpty
        ? 'Custom MCP'
        : _nameCtrl.text.trim();
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      Get.snackbar('URL required', 'Please enter your MCP server URL',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      Get.snackbar('Invalid URL', 'Must be http(s)://…',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    setState(() => _saving = true);
    try {
      final token = _tokenCtrl.text.trim();
      await _registry.setToken(token);
      final transport = McpConfig.inferTransport(url);
      final authType =
          token.isEmpty ? McpAuthType.none : McpAuthType.bearer;
      // Preserve enabled flag unless we are explicitly enabling.
      final wasEnabled = _registry.config.value?.enabled ?? false;
      final enabled = enableIfValid ? true : wasEnabled;
      final cfg = McpConfig(
        name: name,
        url: url,
        transport: transport,
        authType: authType,
        enabled: enabled,
      );
      await _registry.saveConfig(cfg);
      Get.snackbar('Saved', 'MCP server ${enabled ? 'enabled' : 'saved'}',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: AppColors.success,
          colorText: Colors.white);
    } catch (e) {
      Get.snackbar('Save failed', '$e',
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Obx(() {
      final cfg = _registry.config.value;
      final status = _registry.status.value;
      final tools = _registry.tools.toList();
      final error = _registry.lastError.value;

      // One-time sync controllers when config loads after init.
      if (!_initialized && cfg != null) {
        _initialized = true;
        _nameCtrl.text = cfg.name;
        _urlCtrl.text = cfg.url;
      }

      return Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: isDark ? Dt.cardDark : Dt.card,
          border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : Dt.hairline),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Dt.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(LucideIcons.plug,
                          size: 18, color: Dt.accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Custom MCP Server',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                            'One remote HTTP/SSE server — no marketplace',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: Theme.of(context).hintColor),
                          ),
                        ],
                      ),
                    ),
                    _statusDot(status),
                  ]),
                  const SizedBox(height: 14),
                  _statusBanner(status, error, tools, isDark),
                ],
              ),
            ),
            Divider(
                height: 1,
                indent: 20,
                endIndent: 20,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.06)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Server name',
                      hintText: 'My MCP Server',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                      prefixIcon: const Icon(LucideIcons.tag, size: 18),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _urlCtrl,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: 'Server URL (http/s)',
                      hintText: 'https://mcp.example.com/mcp',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                      prefixIcon: const Icon(LucideIcons.link2, size: 18),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tokenCtrl,
                    obscureText: _obscureToken,
                    decoration: InputDecoration(
                      labelText: 'Bearer token (optional)',
                      hintText: 'Paste API key / token',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                      prefixIcon: const Icon(LucideIcons.keyRound, size: 18),
                      suffixIcon: IconButton(
                        icon: Icon(
                            _obscureToken
                                ? LucideIcons.eyeOff
                                : LucideIcons.eye,
                            size: 18),
                        onPressed: () =>
                            setState(() => _obscureToken = !_obscureToken),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Token is stored in secure storage (Keystore/Keychain), never in Hive.',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11, color: Theme.of(context).hintColor),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : () => _save(),
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(LucideIcons.save, size: 16),
                    label: Text(_saving ? 'Saving…' : 'Save',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    style: FilledButton.styleFrom(
                      backgroundColor: Dt.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    await _save();
                    try {
                      await _registry.testConnection();
                      Get.snackbar('Connected', 'Server responded',
                          snackPosition: SnackPosition.BOTTOM,
                          backgroundColor: AppColors.success,
                          colorText: Colors.white);
                    } catch (e) {
                      Get.snackbar('Connection failed', '$e',
                          snackPosition: SnackPosition.BOTTOM,
                          backgroundColor: AppColors.error,
                          colorText: Colors.white,
                          duration: const Duration(seconds: 4));
                    }
                  },
                  icon: const Icon(LucideIcons.activity, size: 16),
                  label: Text('Test',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Dt.accent,
                    side: BorderSide(color: Dt.accent.withValues(alpha: 0.3)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                ),
              ]),
            ),
            if (cfg != null) ...[
              Divider(
                  height: 1,
                  indent: 20,
                  endIndent: 20,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.06)),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Row(children: [
                  Expanded(
                    child: Row(children: [
                      Text('Enabled',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      if (tools.isNotEmpty && cfg.enabled && status == McpStatus.connected)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('${tools.length} tools',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.success)),
                        ),
                    ]),
                  ),
                  Switch(
                    value: cfg.enabled,
                    activeThumbColor: Dt.accent,
                    onChanged: (v) async {
                      // Before enabling, show tools preview if we have them.
                      if (v && tools.isNotEmpty) {
                        final ok = await _confirmEnableWithTools(
                            context, isDark, tools);
                        if (!context.mounted) return;
                        if (ok != true) return;
                      } else if (v) {
                        // Try to connect to fetch tools for preview.
                        try {
                          final fetched = await _registry.connect();
                          if (!context.mounted) return;
                          if (fetched.isNotEmpty) {
                            final ok = await _confirmEnableWithTools(
                                context, isDark, fetched);
                            if (!context.mounted) return;
                            if (ok != true) {
                              await _registry.disconnect();
                              return;
                            }
                          }
                        } catch (_) {
                          // Still allow enabling; tools will be fetched on next send.
                        }
                      }
                      final updated = cfg.copyWith(enabled: v);
                      await _registry.saveConfig(updated);
                      if (!v) await _registry.disconnect();
                    },
                  ),
                ]),
              ),
              if (cfg.enabled &&
                  status == McpStatus.connected &&
                  tools.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.04)
                          : Dt.pillMuted.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Exposed tools — model will see these',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).hintColor)),
                        const SizedBox(height: 8),
                        for (final t in tools)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color:
                                        Dt.accent.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(LucideIcons.wrench,
                                      size: 14, color: Dt.accent),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(t.name,
                                          style:
                                              GoogleFonts.plusJakartaSans(
                                                  fontSize: 13,
                                                  fontWeight:
                                                      FontWeight.w700)),
                                      if (t.description.isNotEmpty)
                                        Text(t.description,
                                            maxLines: 2,
                                            overflow:
                                                TextOverflow.ellipsis,
                                            style:
                                                GoogleFonts.plusJakartaSans(
                                                    fontSize: 11,
                                                    color: Theme.of(context)
                                                        .hintColor)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await Get.dialog<bool>(
                        AlertDialog(
                          backgroundColor:
                              isDark ? Dt.cardDark : Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          title: Text('Remove server?',
                              style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w700)),
                          content: Text(
                              'This will delete the URL and token. You can add it again later.',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13)),
                          actions: [
                            TextButton(
                                onPressed: () => Get.back(result: false),
                                child: Text('common_cancel'.tr)),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.error),
                              onPressed: () => Get.back(result: true),
                              child: const Text('Remove'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await _registry.removeConfig();
                        _nameCtrl.clear();
                        _urlCtrl.clear();
                        _tokenCtrl.clear();
                      }
                    },
                    icon: const Icon(LucideIcons.trash2, size: 16),
                    label: Text('Remove server',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: BorderSide(
                          color: AppColors.error.withValues(alpha: 0.3)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    });
  }

  Widget _statusDot(McpStatus s) {
    final color = switch (s) {
      McpStatus.connected => AppColors.success,
      McpStatus.connecting => AppColors.warning,
      McpStatus.error => AppColors.error,
      McpStatus.disconnected => Colors.grey,
    };
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: s == McpStatus.connected
            ? [
                BoxShadow(
                    color: color.withValues(alpha: 0.4), blurRadius: 6)
              ]
            : null,
      ),
    );
  }

  Widget _statusBanner(
      McpStatus status, String error, List<McpTool> tools, bool isDark) {
    final text = switch (status) {
      McpStatus.connected =>
        tools.isEmpty ? 'Connected — no tools exposed' : 'Connected — ${tools.length} tool(s) ready',
      McpStatus.connecting => 'Connecting…',
      McpStatus.error => error.isNotEmpty ? error : 'Connection error',
      McpStatus.disconnected => 'Not connected — save and test your server',
    };
    final color = switch (status) {
      McpStatus.connected => AppColors.success,
      McpStatus.connecting => AppColors.warning,
      McpStatus.error => AppColors.error,
      McpStatus.disconnected => Theme.of(Get.context!).hintColor,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(children: [
        Icon(
          switch (status) {
            McpStatus.connected => LucideIcons.checkCircle,
            McpStatus.connecting => LucideIcons.loader2,
            McpStatus.error => LucideIcons.alertTriangle,
            McpStatus.disconnected => LucideIcons.info,
          },
          size: 16,
          color: color,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ),
      ]),
    );
  }

  Future<bool?> _confirmEnableWithTools(
      BuildContext context, bool isDark, List<McpTool> tools) {
    return Get.dialog<bool>(
      AlertDialog(
        backgroundColor: isDark ? Dt.cardDark : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Enable MCP tools?',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'The model will be able to call these tools. Review them before enabling.',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: Theme.of(context).hintColor),
              ),
              const SizedBox(height: 12),
              for (final t in tools)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(LucideIcons.wrench,
                          size: 14, color: Dt.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.name,
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700)),
                            if (t.description.isNotEmpty)
                              Text(t.description,
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      color: Theme.of(context).hintColor)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Get.back(result: false),
              child: Text('common_cancel'.tr)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Dt.accent),
            onPressed: () => Get.back(result: true),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
  }
}
