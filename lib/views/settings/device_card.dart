import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/colors.dart';
import '../../services/device_info_service.dart';
import '../../services/inference_service.dart';
import '../../services/local_image_service.dart';
import '../../services/soc_family.dart';
import '../../theme/design_tokens.dart';
import 'apple_widgets.dart';

/// Device spec card.
/// Extracted from views/settings_view.dart.
String localSubtitle() {
  final inf = Get.find<InferenceService>();
  final localImage = Get.find<LocalImageService>();
  if (inf.isModelLoaded.value) {
    return 'Active: ${inf.loadedModelName.value.split('/').last}';
  } else if (localImage.isModelLoaded.value) {
    return 'Active: ${localImage.loadedModelName.value.split('/').last}';
  }
  return 'Optimized for local latency';
}

Widget buildDeviceCard(BuildContext context, bool isDark) {
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

    return appleGroupedCard(context, isDark, children: [
      Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            iconBox(tierColor, tierIcon),
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
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).hintColor)),
                ])),
          ])),
      Divider(
          height: 1,
          indent: 20,
          endIndent: 20,
          color: isDark ? AppColors.border : AppColors.borderLightMode),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(children: [
          iconBox(AppColors.secondary, LucideIcons.cpu),
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
                        size: 13, color: Theme.of(context).hintColor),
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
                    device.socHardware.value != device.processorName.value) ...[
                  const SizedBox(height: 2),
                  Text(device.socHardware.value,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
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
              const Icon(LucideIcons.info, size: 18, color: AppColors.warning),
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
      // ── Specification rows ──
      Divider(
          height: 1,
          indent: 20,
          endIndent: 20,
          color: isDark ? AppColors.border : AppColors.borderLightMode),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
        child: Row(children: [
          Text('SPECIFICATION',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: Theme.of(context).hintColor)),
          const Spacer(),
          InkWell(
            onTap: () => Get.find<DeviceInfoService>().refresh(),
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(LucideIcons.refreshCw, size: 14),
            ),
          ),
        ]),
      ),
      if (device.deviceLabel.value.isNotEmpty)
        specRow(context, isDark, LucideIcons.smartphone, 'Device',
            device.deviceLabel.value),
      if (device.osVersion.value.isNotEmpty)
        specRow(
            context, isDark, LucideIcons.layers, 'OS', device.osVersion.value),
      if (device.cpuInfo.value.isNotEmpty)
        specRow(context, isDark, LucideIcons.cpu, 'CPU', device.cpuInfo.value),
      specRow(
          context,
          isDark,
          LucideIcons.memoryStick,
          'RAM',
          '${device.totalRamGB.value.toStringAsFixed(1)} GB total · '
              '${device.availableRamGB.value.toStringAsFixed(1)} GB free'),
      Padding(
        padding: const EdgeInsets.fromLTRB(52, 6, 20, 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            minHeight: 5,
            value: device.totalRamGB.value > 0
                ? (device.availableRamGB.value / device.totalRamGB.value)
                    .clamp(0.0, 1.0)
                : 0,
            backgroundColor:
                (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
            valueColor: const AlwaysStoppedAnimation<Color>(Dt.accent),
          ),
        ),
      ),
      specRow(context, isDark, LucideIcons.monitorSmartphone, 'Display',
          displaySpec(context)),
      const SizedBox(height: 12),
    ]);
  });
}

String displaySpec(BuildContext context) {
  try {
    final s = MediaQuery.of(context).size;
    return '${s.width.toStringAsFixed(0)}×${s.height.toStringAsFixed(0)} dp';
  } catch (_) {
    return '';
  }
}

Widget specRow(BuildContext context, bool isDark, IconData icon, String label,
    String value) {
  if (value.isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 14, color: Theme.of(context).hintColor),
      const SizedBox(width: 10),
      SizedBox(
        width: 64,
        child: Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).hintColor)),
      ),
      Expanded(
        child: Text(value,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5, fontWeight: FontWeight.w700)),
      ),
    ]),
  );
}
