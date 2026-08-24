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
        title: Text('Config',
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
              _sectionLabel(context, 'DIAGNOSTICS'),
              _appleGroupedCard(context, isDark, children: [
                _appleListTile(
                  context,
                  isDark,
                  leading:
                      _iconBox(AppColors.info, LucideIcons.terminal),
                  title: 'System Logs',
                  subtitle: 'Debug details & process monitoring',
                  trailing: const Icon(LucideIcons.chevronRight, size: 20),
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
                      _iconBox(AppColors.success, LucideIcons.zap),
                  title: 'Local (Privacy-First)',
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
                  title: 'Cloud Assistant',
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
              _sectionLabel(context, 'LOCAL MODEL PARAMETERS'),
              _buildLiteRtCard(context, isDark),
              const SizedBox(height: 12),
              _buildModelParametersCard(context, isDark),
              const SizedBox(height: 28),
              _sectionLabel(context, 'SYNTHETIC IMAGING PARAMETERS'),
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
        label: 'Inference Temperature',
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
              Text('Auto Tune',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('RECOMMENDED',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: AppColors.success)),
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
              label: 'Output Token Limit',
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
              label: 'Context Window Size',
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
          Text('Auto Tune',
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
            Text('Synthesis Resolution',
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
            _iconBox(Dt.accent, selectedBackend == Backend.cpu ? LucideIcons.cpu : LucideIcons.zap),
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
}
