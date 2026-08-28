import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../controllers/settings_controller.dart';
import '../core/colors.dart';
import 'about_view.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/design_tokens.dart';
import '../widgets/app_ui.dart';
import '../widgets/thinking_orb.dart';

/// Dedicated App Settings page — personalisation & about info.
///
/// Split out of the main Config page: appearance (theme), typography
/// scale, and app info live here; everything inference/model related
/// stays in Config.
class AppSettingsView extends GetView<SettingsController> {
  const AppSettingsView({super.key});

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
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Get.back(),
        ),
        title: Text('App Settings',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800,
                fontSize: 24,
                letterSpacing: -1)),
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
                        ? const Icon(LucideIcons.check,
                            size: 20, color: Dt.accent)
                        : null,
                    showDivider: mode != ThemeMode.system,
                    onTap: () => controller.setThemeMode(mode),
                  ),
              ]),
              const SizedBox(height: 20),
              _buildFontSizeCard(context, isDark),
              const SizedBox(height: 28),
              _sectionLabel(context, 'THINKING ORBS'),
              _appleGroupedCard(context, isDark, children: [
                _orbTile(context, isDark,
                    icon: LucideIcons.messageSquare,
                    title: 'While chatting',
                    subtitle: 'Loading animation during AI responses',
                    slot: 'chat',
                    selection: controller.orbChatAnim),
                _orbTile(context, isDark,
                    icon: LucideIcons.image,
                    title: 'Image generation',
                    subtitle: 'Animation while synthesizing images',
                    slot: 'image',
                    selection: controller.orbImageAnim),
                _orbTile(context, isDark,
                    icon: LucideIcons.brain,
                    title: 'Analyzing',
                    subtitle: 'Animation during thought analysis',
                    slot: 'analysis',
                    selection: controller.orbAnalysisAnim,
                    showDivider: false),
              ]),
              const SizedBox(height: 28),
              _sectionLabel(context, 'STARTUP'),
              _appleGroupedCard(context, isDark, children: [
                Obx(() => _appleSwitchTile(
                      context,
                      isDark,
                      leading: const Icon(LucideIcons.rocket,
                          size: 20, color: Dt.accent),
                      title: 'Auto-load last model',
                      subtitle: controller.autoLoadLastModel.value
                          ? 'Opens directly with your last local model — no popup'
                          : 'Ask every time whether to load the last model',
                      value: controller.autoLoadLastModel.value,
                      onChanged: (v) =>
                          controller.setAutoLoadLastModel(v),
                    )),
              ]),
              const SizedBox(height: 28),
              _sectionLabel(context, 'APP INFO'),
              _appleGroupedCard(context, isDark, children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: InkWell(
                    onTap: () => Get.to(() => const AboutView()),
                    borderRadius: BorderRadius.circular(12),
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
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('CubicLM',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text(
                                'Developed by Abir Hasan Siam (CodeCraftedStudio)',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Dt.accent
                                        .withValues(alpha: 0.7))),
                            const SizedBox(height: 1),
                            Obx(() => Text(
                                controller.appVersion.value.isEmpty
                                    ? 'Engineering Build'
                                    : 'Version ${controller.appVersion.value}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).hintColor))),
                          ]),
                    ),
                  ]),
                  ),
                ),
              ]),
              const SizedBox(height: 50),
            ],
          )),
    );
  }

  // ── Typography ──

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
            const Icon(LucideIcons.type,
                size: 16, color: Dt.accent),
            const SizedBox(width: 10),
            Text('Typography Scale',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 15, fontWeight: FontWeight.w700)),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: Dt.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(scaleLabel(controller.fontScale.value),
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: Dt.accent,
                      fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 12),
          Slider(
            value: controller.fontScale.value.clamp(min, max),
            min: min,
            max: max,
            divisions: 12,
            activeColor: Dt.accent,
            onChanged: (v) => controller.setFontScale(v),
          ),
        ]),
      ),
    ]);
  }

  String _themeModeName(ThemeMode m) => m == ThemeMode.light
      ? 'Light Day'
      : m == ThemeMode.dark
          ? 'Deep Night'
          : 'System Sync';

  IconData _themeModeIcon(ThemeMode m) => m == ThemeMode.light
      ? LucideIcons.sun
      : m == ThemeMode.dark
          ? LucideIcons.moon
          : LucideIcons.sunMoon;

  // ── Thinking Orbs ──

  Widget _orbTile(
    BuildContext context,
    bool isDark, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String slot,
    required RxString selection,
    bool showDivider = true,
  }) {
    return Column(children: [
      InkWell(
        onTap: () => _openOrbPicker(context, isDark,
            title: title, slot: slot, selection: selection),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(children: [
            Icon(icon, size: 20, color: Theme.of(context).hintColor),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? AppColors.textPrimary
                                : Dt.textPrimary)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).hintColor)),
                  ]),
            ),
            const SizedBox(width: 12),
            // Live preview of the current selection.
            Obx(() {
              final fixed = orbStateFromName(selection.value);
              return fixed != null
                  ? ThinkingOrb(size: 26, state: fixed)
                  : const ThinkingOrb(size: 26, autoCycle: true);
            }),
            const SizedBox(width: 10),
            Icon(LucideIcons.chevronRight,
                size: 18, color: Theme.of(context).hintColor),
          ]),
        ),
      ),
      if (showDivider)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Divider(
              height: 1,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.03)),
        ),
    ]);
  }

  void _openOrbPicker(
    BuildContext context,
    bool isDark, {
    required String title,
    required String slot,
    required RxString selection,
  }) {
    showAppBottomSheet(
      context,
      builder: (sheetCtx) {
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.75),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppSheetHeader(
                    title: title, onClose: () => Navigator.pop(sheetCtx)),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding:
                        const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    children: [
                      _orbOption(sheetCtx, isDark,
                          value: 'random',
                          name: 'Random',
                          description: 'Shuffle through every state',
                          icon: LucideIcons.shuffle,
                          slot: slot,
                          selection: selection),
                      for (final s in OrbState.values)
                        _orbOption(sheetCtx, isDark,
                            value: s.name,
                            name: s.label,
                            description: s.description,
                            orbState: s,
                            slot: slot,
                            selection: selection),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _orbOption(
    BuildContext sheetCtx,
    bool isDark, {
    required String value,
    required String name,
    required String description,
    IconData? icon,
    OrbState? orbState,
    required String slot,
    required RxString selection,
  }) {
    final selected = selection.value == value;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        Get.find<SettingsController>().setOrbAnim(slot, value);
        Navigator.pop(sheetCtx);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(children: [
          SizedBox(
            width: 34,
            height: 34,
            child: Center(
              child: orbState != null
                  ? ThinkingOrb(size: 24, state: orbState)
                  : Icon(icon,
                      size: 20, color: Theme.of(sheetCtx).hintColor),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.textPrimary
                              : Dt.textPrimary)),
                  const SizedBox(height: 2),
                  Text(description,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(sheetCtx).hintColor)),
                ]),
          ),
          if (selected)
            const Icon(LucideIcons.check, size: 20, color: Dt.accent),
        ]),
      ),
    );
  }

  // ── Shared Apple-style helpers ──

  Widget _appleGroupedCard(BuildContext context, bool isDark,
      {required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.02)
            : Dt.pillMuted.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

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
                          color: isDark
                              ? AppColors.textPrimary
                              : Dt.textPrimary)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).hintColor))
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
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.03)),
        ),
    ]);
  }

  Widget _appleSwitchTile(
    BuildContext context,
    bool isDark, {
    Widget? leading,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).hintColor)),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch.adaptive(
          value: value,
          activeThumbColor: Dt.accent,
          onChanged: onChanged,
        ),
      ]),
    );
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
}
