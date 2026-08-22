import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../controllers/settings_controller.dart';
import '../core/colors.dart';
import '../core/constants.dart';
import '../services/inference_service.dart';
import '../services/hive_service.dart';
import '../services/local_image_service.dart';
import '../services/device_info_service.dart';
import '../services/device_info_native.dart' as platform_info;
import '../ffi/sd_ffi_bindings.dart';
import 'log_view.dart';

class SettingsView extends GetView<SettingsController> {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.bg : AppColors.bgLight,
      appBar: AppBar(
        backgroundColor: (isDark ? AppColors.bg : AppColors.bgLight).withValues(alpha: 0.8),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(color: Colors.transparent),
          ),
        ),
        title: Text('Settings',
            style:
                GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 28, letterSpacing: -1)),
        toolbarHeight: 70,
        centerTitle: false,
      ),
      body: Obx(() => ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              const SizedBox(height: 12),
              _sectionLabel(context, 'APPEARANCE'),
              _appleGroupedCard(context, isDark, children: [
                for (final mode in [
                  ThemeMode.light,
                  ThemeMode.dark,
                  ThemeMode.system
                ])
                  _appleListTile(
                    context,
                    isDark,
                    leading: Icon(_themeModeIcon(mode),
                        size: 20, color: Theme.of(context).hintColor),
                    title: _themeModeName(mode),
                    trailing: controller.themeMode.value == mode
                        ? const Icon(Icons.check_rounded,
                            size: 20,
                            color: AppColors.primary)
                        : null,
                    showDivider: mode != ThemeMode.system,
                    onTap: () => controller.setThemeMode(mode),
                  ),
              ]),
              const SizedBox(height: 20),
              Obx(() => _buildFontSizeCard(context, isDark)),
              const SizedBox(height: 28),
              _sectionLabel(context, 'DIAGNOSTICS'),
              _appleGroupedCard(context, isDark, children: [
                _appleListTile(
                  context,
                  isDark,
                  leading:
                      _iconBox(AppColors.info, Icons.terminal_rounded),
                  title: 'System Logs',
                  subtitle: 'Debug details & process monitoring',
                  trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                  showDivider: false,
                  onTap: () => Get.to(() => const LogView()),
                ),
              ]),
              const SizedBox(height: 28),
              _sectionLabel(context, 'HARDWARE CAPABILITIES'),
              _buildDeviceCard(context, isDark),
              const SizedBox(height: 28),
              _sectionLabel(context, 'INFERENCE MODE'),
              _appleGroupedCard(context, isDark, children: [
                _appleListTile(
                  context,
                  isDark,
                  leading:
                      _iconBox(AppColors.success, Icons.bolt_rounded),
                  title: 'Local (Privacy-First)',
                  subtitle: _localSubtitle(),
                  trailing: controller.inferenceMode.value == 'local'
                      ? const Icon(Icons.check_rounded,
                          size: 20,
                          color: AppColors.primary)
                      : null,
                  showDivider: true,
                  onTap: () => controller.setInferenceMode('local'),
                ),
                _appleListTile(
                  context,
                  isDark,
                  leading: _iconBox(AppColors.primary, Icons.cloud_done_rounded),
                  title: 'Cloud Assistant',
                  subtitle: controller.cloudProvider.value.toUpperCase(),
                  trailing: controller.inferenceMode.value == 'cloud'
                      ? const Icon(Icons.check_rounded,
                          size: 20,
                          color: AppColors.primary)
                      : null,
                  showDivider: false,
                  onTap: () => controller.setInferenceMode('cloud'),
                ),
              ]),
              const SizedBox(height: 28),
              _sectionLabel(context, 'GLOBAL SYSTEM PROMPT'),
              _appleGroupedCard(context, isDark, children: [
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Defines base personality for all models',
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
                                icon: const Icon(Icons.save_rounded,
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
              _sectionLabel(context, 'LOCAL MODEL PARAMETERS'),
              _buildLiteRtCard(context, isDark),
              const SizedBox(height: 12),
              _buildModelParametersCard(context, isDark),
              const SizedBox(height: 28),
              _sectionLabel(context, 'SYNTHETIC IMAGING PARAMETERS'),
              _buildImageGenerationCard(context, isDark),
              const SizedBox(height: 28),
              _sectionLabel(context, 'APP INFO'),
              _appleGroupedCard(context, isDark, children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(children: [
                    Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]),
                        clipBehavior: Clip.antiAlias,
                        child: Image.asset(
                          'assets/icons/CubicLM.png',
                          fit: BoxFit.cover,
                        )),
                    const SizedBox(width: 16),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('CubicLM',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 18, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text('Developed by Abir Hasan Siam (CodeCraftedStudio)',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary.withValues(alpha: 0.7))),
                          const SizedBox(height: 1),
                          Text(
                              controller.appVersion.value.isEmpty
                                   ? 'Engineering Build'
                                   : 'Version ${controller.appVersion.value}',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).hintColor)),
                        ]),
                  ]),
                ),
              ]),
              const SizedBox(height: 50),
            ],
          )),
    );
  }

  // ── Apple grouped card container ──
  Widget _appleGroupedCard(BuildContext context, bool isDark,
      {required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.02) : const Color(0xFFF1F5F9).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
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
                          color: isDark ? AppColors.textPrimary : const Color(0xFF0F172A))),
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
          tierIcon = Icons.battery_saver_rounded;
          break;
        case 'mid':
          tierColor = AppColors.warning;
          tierIcon = Icons.phone_android_rounded;
          break;
        case 'high':
          tierColor = AppColors.success;
          tierIcon = Icons.smartphone_rounded;
          break;
        case 'ultra':
          tierColor = AppColors.primary;
          tierIcon = Icons.rocket_launch_rounded;
          break;
        default:
          tierColor = Theme.of(context).hintColor;
          tierIcon = Icons.device_unknown_rounded;
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
            _iconBox(AppColors.secondary, Icons.memory_rounded),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(soc.displayName,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  if (device.socHardware.value.isNotEmpty) ...[
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
                const Icon(Icons.info_outline_rounded,
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
        icon: Icons.auto_mode_rounded
      ),
      (
        value: 'gpu_fast',
        title: 'Acceleration Engine',
        subtitle: 'Maximum throughput (Experimental)',
        icon: Icons.bolt_rounded
      ),
      (
        value: 'cpu_safe',
        title: 'Stability Mode',
        subtitle: 'Predictable CPU execution',
        icon: Icons.shield_rounded
      ),
    ];
    return _appleGroupedCard(context, isDark, children: [
      for (var i = 0; i < modes.length; i++)
        _appleListTile(
          context,
          isDark,
          leading: _iconBox(AppColors.primary, modes[i].icon),
          title: modes[i].title,
          subtitle: modes[i].subtitle,
          trailing: controller.liteRtPerformanceMode.value == modes[i].value
              ? const Icon(Icons.check_circle_rounded,
                  size: 20,
                  color: AppColors.primary)
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
        label: 'Inference Temperature',
        value: controller.temperature.value,
        min: 0.0,
        max: 2.0,
        divisions: 20,
        safeMax: 1.0,
        onChanged: (v) => controller.setTemperature(v),
        icon: Icons.thermostat_rounded,
        warning: 'High temperature may result in creative but halluncinated output.',
      ),
      _parameterDivider(isDark),
      _modelParameterSlider(
        context,
        isDark,
        label: 'Output Token Limit',
        value: controller.maxTokens.value.toDouble(),
        min: 64,
        max: 4096,
        divisions: 63,
        safeMax: Get.find<DeviceInfoService>().maxSafeTokens.toDouble(),
        onChanged: (v) => controller.setMaxTokens(v.toInt()),
        displayValue: controller.maxTokens.value.toString(),
        icon: Icons.text_fields_rounded,
        warning: 'Extreme token limits may lead to OOM crashes on this device.',
      ),
      _parameterDivider(isDark),
      (() {
        final inference = Get.find<InferenceService>();
        final savedRuntime = Get.find<HiveService>()
                .getSetting<String>(AppConstants.keyLocalModelRuntime) ??
            '';
        final isLiteRtActive = (inference.isModelLoaded.value &&
                inference.loadedModelRuntime.value == 'litert') ||
            (!inference.isModelLoaded.value &&
                savedRuntime.toLowerCase() == 'litert');
        final maxContext = isLiteRtActive ? 4096.0 : 8192.0;
        final divisions = isLiteRtActive ? 7 : 15;
        final currentValue =
            controller.contextSize.value.toDouble().clamp(512.0, maxContext);

        return _modelParameterSlider(
          context,
          isDark,
          label: 'Context Window Size',
          value: currentValue,
          min: 512,
          max: maxContext,
          divisions: divisions,
          safeMax: Get.find<DeviceInfoService>().maxSafeContextSize.toDouble(),
          onChanged: (v) => controller.setContextSize(v.toInt()),
          displayValue: currentValue.toInt().toString(),
          icon: Icons.history_rounded,
          warning: isLiteRtActive
              ? 'LiteRT context window is hardware-limited to 4K for stability.'
              : 'Expanding the context window increases memory pressure significantly.',
        );
      })(),
    ]);
  }

  Widget _buildImageGenerationCard(BuildContext context, bool isDark) {
    final stepsValue = controller.imageSteps.value.toDouble();
    const safeMax = 8.0;
    final isOver = stepsValue > safeMax;
    final accent = isOver ? AppColors.warning : AppColors.primary;
    final selectedBackend = controller.imageGenBackend.value;
    final gpuBackend = controller.recommendedImageGpuBackend();
    final gpuAvailable = gpuBackend != Backend.cpu;

    return _appleGroupedCard(context, isDark, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.auto_awesome_rounded, size: 16, color: accent),
            const SizedBox(width: 10),
            Text('Sampling Steps',
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
                  Icon(Icons.info_rounded, size: 16, color: accent),
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
            const Icon(Icons.photo_size_select_actual_rounded,
                size: 16,
                color: AppColors.primary),
            const SizedBox(width: 10),
            Text('Synthesis Resolution',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 15, fontWeight: FontWeight.w700)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(
                  controller.imageGenSize.value == 0
                      ? 'Automatic'
                      : '${controller.imageGenSize.value}px',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: AppColors.primary,
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
                  selectedColor: AppColors.primary,
                  backgroundColor: isDark ? AppColors.surfaceLight : const Color(0xFFF1F5F9),
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
            _iconBox(AppColors.primary, selectedBackend == Backend.cpu ? Icons.memory_rounded : Icons.bolt_rounded),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Compute Backend',
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
                  icon: Icon(Icons.memory_rounded, size: 18),
                  label: Text('CPU')),
              ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.bolt_rounded, size: 18),
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

  Widget _buildFontSizeCard(BuildContext context, bool isDark) {
    const min = 0.8;
    const max = 1.4;

    String scaleLabel(double v) {
      if (v <= 0.85) return 'Compact';
      if (v <= 0.95) return 'Default';
      if (v <= 1.05) return 'Comfortable';
      if (v <= 1.25) return 'Large';
      return 'Accessible';
    }

    return _appleGroupedCard(context, isDark, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.format_size_rounded, size: 16, color: AppColors.primary),
            const SizedBox(width: 10),
            Text('Typography Scale',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 15, fontWeight: FontWeight.w700)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(scaleLabel(controller.fontScale.value),
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 12),
          Slider(
            value: controller.fontScale.value.clamp(min, max),
            min: min,
            max: max,
            divisions: 12,
            activeColor: AppColors.primary,
            onChanged: (v) => controller.setFontScale(v),
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
        : AppColors.primary;

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
                Icon(Icons.info_rounded, size: 16, color: accent),
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

  String _themeModeName(ThemeMode m) => m == ThemeMode.light
      ? 'Light Day'
      : m == ThemeMode.dark
          ? 'Deep Night'
          : 'System Sync';
  IconData _themeModeIcon(ThemeMode m) => m == ThemeMode.light
      ? Icons.wb_sunny_rounded
      : m == ThemeMode.dark
          ? Icons.nights_stay_rounded
          : Icons.settings_brightness_rounded;
}
