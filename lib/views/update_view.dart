import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/settings_controller.dart';
import '../core/colors.dart';
import '../services/update_service.dart';
import '../shared/constants/platform_links.dart';
import '../theme/design_tokens.dart';
import 'update_settings_view.dart';

/// Update center status page (App Settings → App info → View Update).
///
/// Centered layout: app icon → "CubicLM" → status line → current version
/// → Feature Highlights (website changelog) → Check for updates.
/// The ⋮ menu holds Update Settings, What's New, and More
/// (Feedback / Privacy Policy).
class UpdateView extends StatelessWidget {
  const UpdateView({super.key});

  UpdateService get _svc => Get.isRegistered<UpdateService>()
      ? Get.find<UpdateService>()
      : Get.put(UpdateService());

  Future<void> _openUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _showMoreSheet(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.surface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.messageSquarePlus, size: 22),
              title: Text('Feedback',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              subtitle: Text('Report a bug or suggest a feature',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12)),
              onTap: () {
                Navigator.pop(context);
                _openUrl(PlatformLinks.issuesUrl);
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.shieldCheck, size: 22),
              title: Text('Privacy Policy',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              subtitle: Text('How CubicLM handles your data',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12)),
              onTap: () {
                Navigator.pop(context);
                _showPrivacyDialog(context, isDark);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showPrivacyDialog(BuildContext context, bool isDark) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.surface : Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Privacy Policy',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: Text(
            'CubicLM is private by default.\n\n'
            '• Chats stay on your device in AES-256 encrypted storage.\n'
            '• No accounts, no telemetry, no analytics.\n'
            '• API keys live in your device keystore / keychain — '
            'settings export never includes them.\n'
            '• Cloud mode sends prompts only to the provider you '
            'explicitly chose — nothing else leaves the device.\n'
            '• Update checks query the public GitHub Releases feed; '
            'no identity is attached.',
            style: GoogleFonts.plusJakartaSans(fontSize: 13, height: 1.5),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final svc = _svc;
    return Scaffold(
      appBar: AppBar(
        title: Text('Update',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More options',
            icon: Icon(LucideIcons.moreVertical,
                color: isDark ? AppColors.textPrimary : Dt.iconDefault),
            onSelected: (v) {
              if (v == 'settings') {
                Get.to(() => const UpdateSettingsView());
              } else if (v == 'whatsnew') {
                _openUrl(PlatformLinks.websiteChangelogUrl);
              } else if (v == 'more') {
                _showMoreSheet(context, isDark);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'settings',
                child: Row(children: [
                  const Icon(LucideIcons.settings, size: 16),
                  const SizedBox(width: 10),
                  Text('Update Settings',
                      style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                ]),
              ),
              PopupMenuItem(
                value: 'whatsnew',
                child: Row(children: [
                  const Icon(LucideIcons.sparkles, size: 16),
                  const SizedBox(width: 10),
                  Text("What's New",
                      style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                ]),
              ),
              PopupMenuItem(
                value: 'more',
                child: Row(children: [
                  const Icon(LucideIcons.moreHorizontal, size: 16),
                  const SizedBox(width: 10),
                  Text('More',
                      style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                ]),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Obx(() {
          final available = svc.updateAvailable.value;
          final downloading = svc.isDownloading.value;
          final latest =
              svc.lastKnownVersion.value.isEmpty ? '' : svc.lastKnownVersion.value;
          String current = '';
          try {
            if (Get.isRegistered<SettingsController>()) {
              current = Get.find<SettingsController>().appVersion.value;
            }
          } catch (_) {}
          final canInstall = Platform.isAndroid &&
              available &&
              !downloading;
          final hasSavedApk = canInstall && svc.downloadedApkReady();

          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            children: [
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(
                    'assets/icons/CubicLM.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                        LucideIcons.box,
                        size: 48),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text('CubicLM',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 24, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 8),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      downloading
                          ? LucideIcons.loader
                          : available
                              ? LucideIcons.arrowDownToLine
                              : LucideIcons.checkCircle2,
                      size: 16,
                      color: downloading
                          ? Dt.accent
                          : available
                              ? AppColors.warning
                              : AppColors.success,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      downloading
                          ? 'Downloading… ${(svc.downloadProgress.value * 100).toInt()}%'
                          : available
                              ? 'Update available${latest.isEmpty ? '' : ': v$latest'}'
                              : "You're up to date",
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: downloading
                              ? Dt.accent
                              : available
                                  ? AppColors.warning
                                  : AppColors.success),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  current.isEmpty
                      ? 'Current version'
                      : 'Current version $current',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).hintColor),
                ),
              ),
              const SizedBox(height: 24),
              Card(
                child: ListTile(
                  leading: const Icon(LucideIcons.sparkles,
                      size: 22, color: Dt.accent),
                  title: Text('Feature Highlights',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  subtitle: Text('See what\'s new in the changelog',
                      style: GoogleFonts.plusJakartaSans(fontSize: 12)),
                  trailing: Icon(LucideIcons.chevronRight,
                      size: 18, color: Theme.of(context).hintColor),
                  onTap: () =>
                      _openUrl(PlatformLinks.websiteChangelogUrl),
                ),
              ),
              const SizedBox(height: 12),
              if (canInstall)
                FilledButton.icon(
                  onPressed: () => hasSavedApk
                      ? svc.installSavedApk()
                      : svc.downloadAndInstallAPK(),
                  icon: const Icon(LucideIcons.arrowDownToLine, size: 18),
                  label: Text(hasSavedApk
                      ? 'Install v$latest'
                      : 'Download & install v$latest'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Dt.accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              if (canInstall) const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: downloading
                    ? null
                    : () => svc.check(force: true, silent: false),
                icon: const Icon(LucideIcons.refreshCw, size: 18),
                label: const Text('Check for updates'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Dt.accent,
                  side: BorderSide(
                      color: Dt.accent.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
              if (downloading) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: svc.downloadProgress.value,
                    minHeight: 5,
                    backgroundColor: Colors.grey.withValues(alpha: 0.2),
                    valueColor:
                        const AlwaysStoppedAnimation(Dt.accent),
                  ),
                ),
              ],
            ],
          );
        }),
      ),
    );
  }
}
