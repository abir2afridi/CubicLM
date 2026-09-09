import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../controllers/settings_controller.dart';
import '../../core/colors.dart';
import '../../core/constants.dart';
import '../../ffi/sd_ffi_bindings.dart';
import '../../services/device_info_service.dart';
import '../../services/hive_service.dart';
import '../../services/inference_service.dart';
import '../../theme/design_tokens.dart';
import 'apple_widgets.dart';

/// LiteRT + sampling sliders + image generation cards.
/// Extracted from views/settings_view.dart.

SettingsController get _c => Get.find<SettingsController>();

// ── Apple grouped card container ──
Widget buildLiteRtCard(BuildContext context, bool isDark) {
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
  return appleGroupedCard(context, isDark, children: [
    for (var i = 0; i < modes.length; i++)
      appleListTile(
        context,
        isDark,
        leading: iconBox(Dt.accent, modes[i].icon),
        title: modes[i].title,
        subtitle: modes[i].subtitle,
        trailing: _c.liteRtPerformanceMode.value == modes[i].value
            ? const Icon(LucideIcons.checkCircle, size: 20, color: Dt.accent)
            : null,
        showDivider: i < modes.length - 1,
        onTap: () => _c.setLiteRtPerformanceMode(modes[i].value),
      ),
  ]);
}

Widget buildModelParametersCard(BuildContext context, bool isDark) {
  return appleGroupedCard(context, isDark, children: [
    modelParameterSlider(
      context,
      isDark,
      label: 'settings_inference_temperature'.tr,
      value: _c.temperature.value,
      min: 0.0,
      max: 2.0,
      divisions: 20,
      safeMax: 1.0,
      onChanged: (v) => _c.setTemperature(v),
      icon: LucideIcons.thermometer,
      warning:
          'High temperature may result in creative but halluncinated output.',
    ),
    parameterDivider(isDark),
    modelParameterSlider(
      context,
      isDark,
      label: 'Top-P (local)',
      value: _c.topP.value,
      min: 0.0,
      max: 1.0,
      divisions: 20,
      safeMax: 1.0,
      onChanged: (v) => _c.setTopP(v),
      icon: LucideIcons.percent,
      warning: 'Top-P is capped at 1.0.',
    ),
    parameterDivider(isDark),
    modelParameterSlider(
      context,
      isDark,
      label: 'Top-K (local)',
      value: _c.topK.value.toDouble(),
      min: 1,
      max: 100,
      divisions: 99,
      safeMax: 100,
      displayValue: '${_c.topK.value}',
      onChanged: (v) => _c.setTopK(v.round()),
      icon: LucideIcons.listOrdered,
      warning: 'Top-K is capped at 100.',
    ),
    parameterDivider(isDark),
    modelParameterSlider(
      context,
      isDark,
      label: 'Repeat penalty (local)',
      value: _c.repeatPenalty.value,
      min: 1.0,
      max: 1.5,
      divisions: 10,
      safeMax: 1.3,
      onChanged: (v) => _c.setRepeatPenalty(v),
      icon: LucideIcons.repeat,
      warning:
          'High repeat penalty can make output stiff or repetitive in the other direction.',
    ),
    parameterDivider(isDark),
    // ── Auto Tune (recommended) ──
    Obx(() {
      final auto = _c.autoTuneParams.value;
      return Column(children: [
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
          leading: Icon(LucideIcons.sparkles,
              size: 20, color: auto ? Dt.accent : Theme.of(context).hintColor),
          title: Row(children: [
            Text('settings_auto_tune'.tr,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
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
              onTap: () => showAutoTuneInfoDialog(context, isDark),
              child: Icon(LucideIcons.info,
                  size: 20, color: Theme.of(context).hintColor),
            ),
          ]),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
                auto
                    ? 'Context ${_fmtTokens(_c.effectiveContextSize)} · '
                        'Output ${_fmtTokens(_c.effectiveMaxTokens)} · tuned to RAM'
                    : 'Manual limits — extended ranges up to 1M context',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).hintColor)),
          ),
          trailing: Switch(
              value: auto,
              activeThumbColor: Dt.accent,
              onChanged: (v) => _c.setAutoTuneParams(v)),
        ),
        if (!auto) ...[
          const SizedBox(height: 6),
          ladderSlider(
            context,
            isDark,
            label: 'settings_output_limit'.tr,
            ladder: _tokLadder,
            value: _c.maxTokens.value,
            safeMax: Get.find<DeviceInfoService>().maxSafeTokens,
            onChanged: (v) => _c.setMaxTokens(v),
            icon: LucideIcons.type,
          ),
          parameterDivider(isDark),
          ladderSlider(
            context,
            isDark,
            label: 'settings_context_window'.tr,
            ladder: _contextLadder(),
            value: _c.contextSize.value,
            safeMax: Get.find<DeviceInfoService>().maxSafeContextSize,
            onChanged: (v) => _c.setContextSize(v),
            icon: LucideIcons.history,
            extraWarning: 'Big windows increase memory pressure a lot.',
          ),
        ],
      ]);
    }),
  ]);
}

const List<int> _tokLadder = [
  256,
  512,
  1024,
  2048,
  4096,
  8192,
  16384,
  32768,
  65536,
  131072,
];

List<int> _contextLadder() {
  const full = [
    1024,
    2048,
    4096,
    8192,
    12288,
    16384,
    24576,
    32768,
    49152,
    65536,
    98304,
    131072,
    196608,
    262144,
    393216,
    524288,
    786432,
    1048576,
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

String _fmtTokens(int v) =>
    v >= 1024 ? '${(v / 1024).toStringAsFixed(v % 1024 == 0 ? 0 : 1)}K' : '$v';

void showAutoTuneInfoDialog(BuildContext context, bool isDark) {
  Get.dialog(
    AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
            infoPoint(
                '📱',
                'Sets the context window and output budget to '
                    'the highest your phone\'s RAM can safely run — no guesswork.'),
            infoPoint(
                '🚀',
                'Cloud models are sent WITHOUT an output cap, so '
                    'big models write full detailed answers instead of stopping early.'),
            infoPoint(
                '📚',
                'Works with large-context models — when you switch '
                    'to manual you can push context up to 1M tokens for models that support it.'),
            infoPoint(
                '🛡️',
                'Prevents truncated replies and chat freezes caused '
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

Widget infoPoint(String emoji, String text) {
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
Widget ladderSlider(
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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

Widget buildImageGenerationCard(BuildContext context, bool isDark) {
  final stepsValue = _c.imageSteps.value.toDouble();
  const safeMax = 8.0;
  final isOver = stepsValue > safeMax;
  final accent = isOver ? AppColors.warning : Dt.accent;
  final selectedBackend = _c.imageGenBackend.value;
  final gpuBackend = _c.recommendedImageGpuBackend();
  final gpuAvailable = gpuBackend != Backend.cpu;

  return appleGroupedCard(context, isDark, children: [
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
            child: Text(_c.imageSteps.value.toString(),
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: accent, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 12),
        Slider(
            value: stepsValue.clamp(1, 20),
            min: 1,
            max: 20,
            divisions: 19,
            activeColor: accent,
            onChanged: (v) => _c.setImageSteps(v.toInt())),
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
                    child: Text(
                        'Higher steps improve fidelity but increase latency.',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: accent,
                            fontWeight: FontWeight.w600))),
              ])),
      ]),
    ),
    parameterDivider(isDark),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(LucideIcons.image, size: 16, color: Dt.accent),
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
                _c.imageGenSize.value == 0
                    ? 'Automatic'
                    : '${_c.imageGenSize.value}px',
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
                selected: _c.imageGenSize.value == option.value,
                onSelected: (_) => _c.setImageGenSize(option.value),
                labelStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _c.imageGenSize.value == option.value
                      ? Colors.white
                      : Theme.of(context).hintColor,
                ),
                selectedColor: Dt.accent,
                backgroundColor: isDark ? AppColors.surfaceLight : Dt.pillMuted,
                side: BorderSide.none,
                showCheckmark: false,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
          ],
        ),
      ]),
    ),
    parameterDivider(isDark),
    Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(LucideIcons.ban, size: 16, color: Dt.accent),
          const SizedBox(width: 10),
          Text('Negative prompt',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _c.imageGenNegativeController,
          onSubmitted: (v) => _c.setImageGenNegative(v),
          onEditingComplete: () =>
              _c.setImageGenNegative(_c.imageGenNegativeController.text),
          style: GoogleFonts.plusJakartaSans(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'blurry, watermark, extra fingers… (empty = none)',
            hintStyle: GoogleFonts.plusJakartaSans(
                fontSize: 13, color: Theme.of(context).hintColor),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
      ]),
    ),
    parameterDivider(isDark),
    Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(LucideIcons.gauge, size: 16, color: Dt.accent),
          const SizedBox(width: 10),
          Text('Guidance (CFG)',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 15, fontWeight: FontWeight.w700)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: Dt.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Obx(() => Text(_c.imageGenCfg.value.toStringAsFixed(1),
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: Dt.accent,
                    fontWeight: FontWeight.w800))),
          ),
        ]),
        const SizedBox(height: 12),
        Obx(() => Slider(
            value: _c.imageGenCfg.value.clamp(1.0, 15.0),
            min: 1,
            max: 15,
            divisions: 28,
            activeColor: Dt.accent,
            onChanged: (v) => _c.setImageGenCfg((v * 2).roundToDouble() / 2))),
      ]),
    ),
    parameterDivider(isDark),
    Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(LucideIcons.dices, size: 16, color: Dt.accent),
          const SizedBox(width: 10),
          Text('Seed',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 15, fontWeight: FontWeight.w700)),
          const Spacer(),
          Obx(() => Text(
              _c.imageGenSeed.value < 0
                  ? 'Random'
                  : _c.imageGenSeed.value.toString(),
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: Dt.accent,
                  fontWeight: FontWeight.w800))),
          IconButton(
            tooltip: 'Randomize seed',
            icon: const Icon(LucideIcons.dices, size: 20),
            onPressed: () => _c.randomizeImageSeed(),
          ),
          TextButton(
            onPressed: () => _c.setImageGenSeed(-1),
            child: const Text('Auto'),
          ),
        ]),
        Text(
          'Fixed seed reproduces a generation. Auto picks a fresh one each time.',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: Theme.of(context).hintColor,
              fontWeight: FontWeight.w600),
        ),
      ]),
    ),
    parameterDivider(isDark),
    Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          iconBox(
              Dt.accent,
              selectedBackend == Backend.cpu
                  ? LucideIcons.cpu
                  : LucideIcons.zap),
          const SizedBox(width: 16),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('settings_compute_backend'.tr,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(_c.imageGpuLabel(),
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).hintColor)),
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
            _c.setImageBackendMode(useGpu);
          },
          showSelectedIcon: false,
        ),
      ]),
    ),
  ]);
}

Widget parameterDivider(bool isDark) {
  return Divider(
    height: 1,
    indent: 20,
    endIndent: 20,
    color: isDark
        ? AppColors.border.withValues(alpha: 0.5)
        : AppColors.borderLightMode.withValues(alpha: 0.5),
  );
}

Widget modelParameterSlider(
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
            style: GoogleFonts.plusJakartaSans(
                fontSize: 15, fontWeight: FontWeight.w700)),
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
