import 'dart:io' show Platform;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../controllers/settings_controller.dart';
import '../controllers/chat_controller.dart';
import '../core/routes.dart';
import '../core/colors.dart';
import '../services/tts_service.dart';
import '../services/update_service.dart';
import '../utils/app_snackbar.dart';
import 'about_view.dart';
import 'language_picker_view.dart';
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

  // ── Backup / Restore ──
  Future<void> _exportAllChats() async {
    final opts = await _showBackupOptionsDialog();
    if (opts == null) return; // cancelled
    try {
      if (!Get.isRegistered<ChatController>()) {
        Get.put(ChatController());
      }
      final chat = Get.find<ChatController>();
      final err = await chat.exportAllChats(
        includeImages: opts.includeImages,
        passphrase: opts.passphrase.isEmpty ? null : opts.passphrase,
      );
      if (err == 'empty') {
        AppSnackbar.showTop('Nothing to export',
            'No chats found. Start a conversation first.',
            icon: LucideIcons.info, type: 'general', logHistory: false);
      } else if (err == 'cancelled') {
        // User dismissed the desktop save dialog — stay silent.
        return;
      } else if (err != null) {
        AppSnackbar.showTop('Export failed',
            'Something went wrong while creating the backup.',
            icon: LucideIcons.alertTriangle,
            type: 'error',
            iconName: 'alert');
      } else if (opts.passphrase.isNotEmpty) {
        AppSnackbar.showTop('Encrypted backup saved',
            'Keep your passphrase safe — it cannot be recovered.',
            icon: LucideIcons.lock, type: 'success', iconName: 'lock');
      }
    } catch (_) {
      AppSnackbar.showTop('Export failed',
          'Something went wrong while creating the backup.',
          icon: LucideIcons.alertTriangle, type: 'error', iconName: 'alert');
    }
  }

  /// Export options: include images + optional passphrase encryption.
  Future<_BackupOptions?> _showBackupOptionsDialog() async {
    var includeImages = false;
    final passCtrl = TextEditingController();
    try {
      return await Get.dialog<_BackupOptions>(
        AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Export backup'),
          content: StatefulBuilder(
            builder: (ctx, setState) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CheckboxListTile(
                  value: includeImages,
                  onChanged: (v) =>
                      setState(() => includeImages = v ?? false),
                  title: const Text('Include images'),
                  subtitle: const Text(
                      'Much larger file. Needed to restore pictures.'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Passphrase (optional)',
                    hintText: 'Encrypts the backup (AES-256)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Get.back(
                result: _BackupOptions(
                  includeImages: includeImages,
                  passphrase: passCtrl.text,
                ),
              ),
              child: const Text('Export'),
            ),
          ],
        ),
      );
    } finally {
      passCtrl.dispose();
    }
  }

  Future<void> _exportSettings() async {
    try {
      if (!Get.isRegistered<ChatController>()) Get.put(ChatController());
      final err = await Get.find<ChatController>().exportSettings();
      if (err == null) {
        AppSnackbar.showTop('Settings exported',
            'API keys were excluded. Import them manually on the new device.',
            icon: LucideIcons.check, type: 'general', logHistory: false);
      } else if (err != 'cancelled') {
        AppSnackbar.showTop('Export failed', err,
            icon: LucideIcons.alertTriangle, type: 'error', iconName: 'alert');
      }
    } catch (_) {}
  }

  Future<void> _importSettings() async {
    try {
      if (!Get.isRegistered<ChatController>()) Get.put(ChatController());
      final err = await Get.find<ChatController>().importSettings();
      if (err == null) {
        AppSnackbar.showTop('Settings imported',
            'Applied. Restart the app if something looks stale.',
            icon: LucideIcons.check, type: 'general', logHistory: false);
      } else if (err != 'cancelled') {
        AppSnackbar.showTop('Import failed', err,
            icon: LucideIcons.alertTriangle, type: 'error', iconName: 'alert');
      }
    } catch (_) {}
  }

  Future<void> _importChats() async {
    try {
      if (!Get.isRegistered<ChatController>()) {
        Get.put(ChatController());
      }
      final chat = Get.find<ChatController>();
      final err = await chat.importChats();
      switch (err) {
        case 'cancelled':
          return;
        case 'locked':
          // Encrypted backup — ask passphrase and retry once.
          final pass = await _showPassphraseDialog();
          if (pass == null || pass.isEmpty) return;
          final retry = await chat.importChats(passphrase: pass);
          if (retry == null || retry.startsWith('ok:')) {
            _showRestoreDone(retry);
          } else {
            _showImportError(retry);
          }
          return;
        case 'invalid':
          AppSnackbar.showTop('Invalid file',
              'Not a CubicLM backup — or the passphrase is wrong.',
              icon: LucideIcons.alertTriangle,
              type: 'error',
              iconName: 'alert');
          return;
        case 'nothing':
          AppSnackbar.showTop('Nothing new',
              'All chats in that backup already exist here.',
              icon: LucideIcons.info, type: 'general', logHistory: false);
          return;
        case 'error':
          AppSnackbar.showTop('Import failed',
              'Something went wrong while reading the backup.',
              icon: LucideIcons.alertTriangle,
              type: 'error',
              iconName: 'alert');
          return;
        default:
          if (err != null && err.startsWith('ok:')) {
            _showRestoreDone(err);
          }
      }
    } catch (_) {
      AppSnackbar.showTop('Import failed',
          'Something went wrong while reading the backup.',
          icon: LucideIcons.alertTriangle, type: 'error', iconName: 'alert');
    }
  }

  void _showRestoreDone(String? err) {
    final parts = (err ?? '').split(':');
    final sessions = parts.length > 1 ? parts[1] : '0';
    final messages = parts.length > 2 ? parts[2] : '0';
    AppSnackbar.showTop(
        'Backup restored',
        '$sessions chats and $messages messages imported.',
        icon: LucideIcons.checkCircle2,
        type: 'success',
        iconName: 'check');
  }

  void _showImportError(String err) {
    if (err == 'invalid') {
      AppSnackbar.showTop('Invalid file',
          'Not a CubicLM backup — or the passphrase is wrong.',
          icon: LucideIcons.alertTriangle,
          type: 'error',
          iconName: 'alert');
    } else {
      AppSnackbar.showTop('Import failed',
          'Something went wrong while reading the backup.',
          icon: LucideIcons.alertTriangle,
          type: 'error',
          iconName: 'alert');
    }
  }

  Future<String?> _showPassphraseDialog() async {
    final c = TextEditingController();
    try {
      return await Get.dialog<String>(
        AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Encrypted backup'),
          content: TextField(
            controller: c,
            autofocus: true,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Passphrase',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => Get.back(result: c.text),
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Get.back(result: c.text),
              child: const Text('Unlock'),
            ),
          ],
        ),
      );
    } finally {
      c.dispose();
    }
  }

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
        title: Text('settings_title'.tr,
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
              _sectionLabel(context, 'settings_appearance'.tr),
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
              _sectionLabel(context, 'settings_thinking_orbs'.tr),
              _appleGroupedCard(context, isDark, children: [
                _orbTile(context, isDark,
                    icon: LucideIcons.messageSquare,
                    title: 'orb_while_chatting'.tr,
                    subtitle: 'orb_chat_subtitle'.tr,
                    slot: 'chat',
                    selection: controller.orbChatAnim),
                _orbTile(context, isDark,
                    icon: LucideIcons.image,
                    title: 'orb_image_gen'.tr,
                    subtitle: 'orb_image_subtitle'.tr,
                    slot: 'image',
                    selection: controller.orbImageAnim),
                _orbTile(context, isDark,
                    icon: LucideIcons.brain,
                    title: 'orb_analyzing'.tr,
                    subtitle: 'orb_analysis_subtitle'.tr,
                    slot: 'analysis',
                    selection: controller.orbAnalysisAnim,
                    showDivider: false),
              ]),
              const SizedBox(height: 28),
              _sectionLabel(context, 'READ ALOUD'),
              _appleGroupedCard(context, isDark, children: [
                Obx(() => _appleSwitchTile(
                      context,
                      isDark,
                      leading: const Icon(LucideIcons.volume2,
                          size: 20, color: Dt.accent),
                      title: 'Read aloud',
                      subtitle: controller.readAloudEnabled.value
                          ? 'Tap speaker on assistant messages to hear them'
                          : 'Text-to-speech is off',
                      value: controller.readAloudEnabled.value,
                      onChanged: (v) {
                        controller.setReadAloudEnabled(v);
                        // Stop any ongoing speech when turning off (web stub is no-op).
                        if (!v) {
                          try {
                            if (Get.isRegistered<TtsService>()) {
                              Get.find<TtsService>().stop();
                            }
                          } catch (_) {}
                        }
                      },
                    )),
              ]),
              const SizedBox(height: 28),
              _sectionLabel(context, 'settings_startup'.tr),
              _appleGroupedCard(context, isDark, children: [
                Obx(() => _appleSwitchTile(
                      context,
                      isDark,
                      leading: const Icon(LucideIcons.rocket,
                          size: 20, color: Dt.accent),
                      title: 'startup_auto_load'.tr,
                      subtitle: controller.autoLoadLastModel.value
                          ? 'startup_auto_load_on'.tr
                          : 'startup_auto_load_off'.tr,
                      value: controller.autoLoadLastModel.value,
                      onChanged: (v) =>
                          controller.setAutoLoadLastModel(v),
                    )),
              ]),
              const SizedBox(height: 28),
              _sectionLabel(context, 'SECURITY'),
              _appleGroupedCard(context, isDark, children: [
                Obx(() => _appleSwitchTile(
                      context,
                      isDark,
                      leading: const Icon(LucideIcons.fingerprint,
                          size: 20, color: Dt.accent),
                      title: 'App Lock',
                      subtitle: !controller.biometricsAvailable.value
                          ? 'No biometric hardware detected on this device'
                          : !controller.hasEnrolledBiometrics.value
                              ? 'Nothing enrolled — device PIN will be used'
                              : (controller.appLockEnabled.value
                                  ? 'Biometrics or device PIN required to open the app'
                                  : 'Require biometrics or device PIN to open the app'),
                      value: controller.appLockEnabled.value,
                      onChanged: (v) => controller.setAppLockEnabled(v),
                    )),
                Obx(() {
                  if (!controller.appLockEnabled.value) {
                    return const SizedBox.shrink();
                  }
                  final t = controller.lockTimeoutMinutes.value;
                  final label = t <= 0
                      ? 'Immediately'
                      : t == 1
                          ? 'After 1 min'
                          : 'After $t min';
                  return _appleListTile(
                    context,
                    isDark,
                    leading: const Icon(LucideIcons.timer,
                        size: 20, color: Dt.accent),
                    title: 'Re-lock',
                    subtitle: 'Lock again $label in background',
                    onTap: () => _pickLockTimeout(context, controller),
                  );
                }),
                Obx(() {
                  if (!controller.appLockEnabled.value) {
                    return const SizedBox.shrink();
                  }
                  return _appleSwitchTile(
                    context,
                    isDark,
                    leading: const Icon(LucideIcons.scanFace,
                        size: 20, color: Dt.accent),
                    title: 'Biometric only',
                    subtitle: controller.lockBiometricOnly.value
                        ? 'Device PIN will NOT unlock the app'
                        : 'Allow device PIN as fallback',
                    value: controller.lockBiometricOnly.value,
                    onChanged: (v) =>
                        controller.setLockBiometricOnly(v),
                  );
                }),
              ]),
              const SizedBox(height: 28),
              _sectionLabel(context, 'DATA'),
              _appleGroupedCard(context, isDark, children: [
                _appleListTile(
                  context,
                  isDark,
                  leading: const Icon(LucideIcons.download,
                      size: 20, color: Dt.accent),
                  title: 'Export all chats',
                  subtitle: 'Save every conversation as a JSON backup',
                  onTap: () => _exportAllChats(),
                ),
                _appleListTile(
                  context,
                  isDark,
                  leading: const Icon(LucideIcons.upload,
                      size: 20, color: Dt.accent),
                  title: 'Import chats',
                  subtitle: 'Restore from a CubicLM backup file',
                  onTap: () => _importChats(),
                ),
                Obx(() {
                  final chat = Get.isRegistered<ChatController>()
                      ? Get.find<ChatController>()
                      : Get.put(ChatController());
                  return _appleSwitchTile(
                    context,
                    isDark,
                    leading: const Icon(LucideIcons.history,
                        size: 20, color: Dt.accent),
                    title: 'Auto backup',
                    subtitle: chat.autoBackupEnabled.value
                        ? 'Silent JSON every ${chat.autoBackupDays.value}d (last 3 kept)'
                        : 'Off — only manual exports',
                    value: chat.autoBackupEnabled.value,
                    onChanged: (v) => chat.setAutoBackup(v),
                  );
                }),
                Obx(() {
                  final chat = Get.isRegistered<ChatController>()
                      ? Get.find<ChatController>()
                      : Get.put(ChatController());
                  if (!chat.autoBackupEnabled.value) {
                    return const SizedBox.shrink();
                  }
                  return _appleListTile(
                    context,
                    isDark,
                    leading: const Icon(LucideIcons.calendarClock,
                        size: 20, color: Dt.accent),
                    title: 'Backup every',
                    subtitle:
                        'Every ${chat.autoBackupDays.value} days (unencrypted)',
                    onTap: () => _pickAutoBackupDays(context, chat),
                  );
                }),
                _appleListTile(
                  context,
                  isDark,
                  leading: const Icon(LucideIcons.settings2,
                      size: 20, color: Dt.accent),
                  title: 'Export settings',
                  subtitle: 'Preferences without API keys',
                  onTap: () => _exportSettings(),
                ),
                _appleListTile(
                  context,
                  isDark,
                  leading: const Icon(LucideIcons.settings,
                      size: 20, color: Dt.accent),
                  title: 'Import settings',
                  subtitle: 'Restore preferences (keys never transfer)',
                  onTap: () => _importSettings(),
                ),
                _appleListTile(
                  context,
                  isDark,
                  leading: const Icon(LucideIcons.graduationCap,
                      size: 20, color: Dt.accent),
                  title: 'Replay onboarding',
                  subtitle: 'Walk through setup again',
                  showDivider: false,
                  onTap: () async {
                    await controller.resetOnboarding();
                    // Push (don't offAllNamed): keeps the home stack and its
                    // controllers alive underneath. offAllNamed from here
                    // would dispose lazy controllers (Chat/Home/Model) and
                    // break the return trip. Onboarding finishes with its
                    // own offAllNamed(home), which rebuilds cleanly.
                    Get.toNamed(AppRoutes.onboarding);
                  },
                ),
              ]),
              const SizedBox(height: 28),
              _sectionLabel(context, 'settings_language'.tr),
              _appleGroupedCard(context, isDark, children: [
                _appleListTile(
                  context,
                  isDark,
                  leading: const Icon(LucideIcons.globe,
                      size: 20, color: Dt.accent),
                  title: 'settings_language'.tr,
                  subtitle: '${controller.locale.value.flag}  ${controller.locale.value.nativeName}',
                  trailing: Icon(LucideIcons.chevronRight,
                      size: 18, color: Theme.of(context).hintColor),
                  showDivider: false,
                  onTap: () => Get.to(() => const LanguagePickerView()),
                ),
              ]),
              const SizedBox(height: 28),
              _sectionLabel(context, 'Updates'),
              _appleGroupedCard(context, isDark, children: [
                Obx(() {
                  final svc = Get.isRegistered<UpdateService>()
                      ? Get.find<UpdateService>()
                      : Get.put(UpdateService());
                  final bool canInstall = Platform.isAndroid &&
                      svc.updateAvailable.value &&
                      !svc.isDownloading.value;
                  return Column(
                    children: [
                      _appleListTile(
                        context,
                        isDark,
                        leading: const Icon(LucideIcons.download,
                            size: 20, color: Dt.accent),
                        title: 'Check for updates',
                        subtitle: 'Poll GitHub Releases for a newer version',
                        trailing: Icon(LucideIcons.chevronRight,
                            size: 18, color: Theme.of(context).hintColor),
                        showDivider: canInstall ? true : false,
                        onTap: () async {
                          final s = Get.isRegistered<UpdateService>()
                              ? Get.find<UpdateService>()
                              : Get.put(UpdateService());
                          await s.check(force: true, silent: false);
                        },
                      ),
                      if (canInstall)
                        _appleListTile(
                          context,
                          isDark,
                          leading: const Icon(LucideIcons.arrowDownToLine,
                              size: 20, color: Colors.white),
                          title:
                              'Install v${svc.lastKnownVersion.value}',
                          subtitle: 'Download and install update in-app',
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Dt.accent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'UPDATE',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white),
                            ),
                          ),
                          showDivider: false,
                          onTap: () => svc.downloadAndInstallAPK(),
                        ),
                      if (svc.isDownloading.value)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 8),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: svc
                                      .downloadProgress.value,
                                  minHeight: 4,
                                  backgroundColor: Colors
                                      .grey
                                      .withValues(alpha: 0.2),
                                  valueColor:
                                      const AlwaysStoppedAnimation(
                                          Dt.accent),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Downloading... ${(svc.downloadProgress.value * 100).toInt()}%',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Dt.accent),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                }),
              ]),
              const SizedBox(height: 28),
              _sectionLabel(context, 'settings_app_info'.tr),
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
      if (v <= 0.85) return 'typography_compact'.tr;
      if (v <= 0.95) return 'typography_default'.tr;
      if (v <= 1.05) return 'typography_comfortable'.tr;
      if (v <= 1.25) return 'typography_large'.tr;
      return 'typography_accessible'.tr;
    }

    return _appleGroupedCard(context, isDark, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(LucideIcons.type,
                size: 16, color: Dt.accent),
            const SizedBox(width: 10),
            Text('typography_scale'.tr,
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
      ? 'theme_light'.tr
      : m == ThemeMode.dark
          ? 'theme_dark'.tr
          : 'theme_system'.tr;

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
                          name: 'orb_random'.tr,
                          description: 'orb_random_desc'.tr,
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

  Future<void> _pickAutoBackupDays(
      BuildContext context, ChatController chat) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (dlgCtx) => SimpleDialog(
        title: const Text('Auto backup every'),
        children: [
          for (final d in ChatController.autoBackupDayOptions)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dlgCtx, d),
              child: Text(d == 1 ? 'Every day' : 'Every $d days'),
            ),
        ],
      ),
    );
    if (picked != null) await chat.setAutoBackup(true, picked);
  }

  Future<void> _pickLockTimeout(
      BuildContext context, SettingsController controller) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (dlgCtx) => SimpleDialog(
        title: const Text('Re-lock after'),
        children: [
          for (final m in SettingsController.lockTimeoutOptions)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dlgCtx, m),
              child: Text(m <= 0
                  ? 'Immediately'
                  : m == 1
                      ? 'After 1 minute'
                      : 'After $m minutes'),
            ),
        ],
      ),
    );
    if (picked != null) await controller.setLockTimeoutMinutes(picked);
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

/// Backup export choices from the export-options dialog.
class _BackupOptions {
  final bool includeImages;
  final String passphrase;
  const _BackupOptions({required this.includeImages, required this.passphrase});
}
