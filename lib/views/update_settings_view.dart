import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/colors.dart';
import '../services/update_service.dart';
import '../theme/design_tokens.dart';

/// Update-center preferences (Update page → ⋮ → Update Settings).
///
/// DOWNLOADS controls when the auto path may fetch an APK (Android only);
/// UPDATES controls install + auto-check behavior. Manual download from
/// the Update page always stays available regardless of these toggles.
class UpdateSettingsView extends StatelessWidget {
  const UpdateSettingsView({super.key});

  UpdateService get _svc => Get.isRegistered<UpdateService>()
      ? Get.find<UpdateService>()
      : Get.put(UpdateService());

  Future<void> _pickTime(
      BuildContext context, int initialMin, Future<void> Function(int) save) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
          hour: initialMin ~/ 60, minute: initialMin % 60),
    );
    if (picked != null) {
      await save(picked.hour * 60 + picked.minute);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final svc = _svc;
    return Scaffold(
      appBar: AppBar(
        title: Text('Update Settings',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _label(context, 'DOWNLOADS'),
          _card(isDark, [
            Obx(() => _switch(
                  context,
                  isDark,
                  icon: LucideIcons.download,
                  title: 'Download automatically',
                  subtitle: svc.autoDownload.value
                      ? 'Fetch updates in the background'
                      : 'Only download when you tap',
                  value: svc.autoDownload.value,
                  onChanged: (v) => svc.setAutoDownload(v),
                )),
            Obx(() => _switch(
                  context,
                  isDark,
                  icon: LucideIcons.wifi,
                  title: 'Download over Wi-Fi',
                  subtitle: 'Required updates on Wi-Fi connections',
                  value: svc.wifiOnly.value,
                  enabled: svc.autoDownload.value,
                  onChanged: (v) => svc.setWifiOnly(v),
                )),
            Obx(() => _switch(
                  context,
                  isDark,
                  icon: LucideIcons.smartphone,
                  title: 'Download using mobile data',
                  subtitle: svc.allowMobileData.value
                      ? 'Mobile data may be used'
                      : 'Never use mobile data',
                  value: svc.allowMobileData.value,
                  enabled: svc.autoDownload.value,
                  onChanged: (v) => svc.setAllowMobileData(v),
                )),
            Obx(() => _switch(
                  context,
                  isDark,
                  icon: LucideIcons.clock,
                  title: 'Download only during set hours',
                  subtitle: svc.scheduledWindow.value
                      ? 'Inside ${UpdateService.formatMinutes(svc.windowStartMin.value)} – ${UpdateService.formatMinutes(svc.windowEndMin.value)}'
                      : 'Any time of day',
                  value: svc.scheduledWindow.value,
                  enabled: svc.autoDownload.value,
                  onChanged: (v) => svc.setScheduledWindow(v),
                )),
            Obx(() {
              if (!svc.autoDownload.value || !svc.scheduledWindow.value) {
                return const SizedBox.shrink();
              }
              return Column(children: [
                _timeRow(
                  context,
                  isDark,
                  title: 'Turn on automatic downloads',
                  value: UpdateService.formatMinutes(
                      svc.windowStartMin.value),
                  onTap: () => _pickTime(context, svc.windowStartMin.value,
                      (m) => svc.setWindowStart(m)),
                ),
                _timeRow(
                  context,
                  isDark,
                  title: 'Turn off automatic downloads',
                  value: UpdateService.formatMinutes(
                      svc.windowEndMin.value),
                  showDivider: false,
                  onTap: () => _pickTime(context, svc.windowEndMin.value,
                      (m) => svc.setWindowEnd(m)),
                ),
              ]);
            }),
          ]),
          const SizedBox(height: 20),
          _label(context, 'UPDATES'),
          _card(isDark, [
            Obx(() => _switch(
                  context,
                  isDark,
                  icon: LucideIcons.packageCheck,
                  title: 'Install automatically',
                  subtitle:
                      'Open the installer right after download (Android still asks once)',
                  value: svc.autoInstall.value,
                  onChanged: (v) => svc.setAutoInstall(v),
                )),
            Obx(() => _switch(
                  context,
                  isDark,
                  icon: LucideIcons.refreshCw,
                  title: 'Check automatically',
                  subtitle: svc.autoCheck.value
                      ? 'Daily check for new versions'
                      : 'Only check when you tap',
                  value: svc.autoCheck.value,
                  showDivider: false,
                  onChanged: (v) => svc.setAutoCheck(v),
                )),
          ]),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(text,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: Theme.of(context).hintColor)),
    );
  }

  Widget _card(bool isDark, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Dt.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _switch(
    BuildContext context,
    bool isDark, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
    bool showDivider = true,
  }) {
    return Column(children: [
      Opacity(
        opacity: enabled ? 1.0 : 0.45,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            Icon(icon, size: 20, color: Dt.accent),
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
                            color: Theme.of(context).hintColor)),
                  ]),
            ),
            Switch.adaptive(
              value: value,
              activeThumbColor: Dt.accent,
              onChanged: enabled ? onChanged : null,
            ),
          ]),
        ),
      ),
      if (showDivider)
        Divider(
            height: 1,
            indent: 50,
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.05)),
    ]);
  }

  Widget _timeRow(
    BuildContext context,
    bool isDark, {
    required String title,
    required String value,
    required VoidCallback onTap,
    bool showDivider = true,
  }) {
    return Column(children: [
      InkWell(
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Expanded(
              child: Text(title,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            Text(value,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Dt.accent)),
            const SizedBox(width: 4),
            Icon(LucideIcons.chevronRight,
                size: 16, color: Theme.of(context).hintColor),
          ]),
        ),
      ),
      if (showDivider)
        Divider(
            height: 1,
            indent: 50,
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.05)),
    ]);
  }
}
