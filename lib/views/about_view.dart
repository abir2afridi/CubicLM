import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/settings_controller.dart';
import '../core/colors.dart';
import '../shared/constants/platform_links.dart';
import '../theme/design_tokens.dart';

/// Full about page — opens from App Settings › App Info. Surfaces the
/// project's key facts (features, stack, links, credits) from the README.
/// Cross-platform aware per docs/multiplatfrom.md §5.4: each platform
/// links to the other two + centralized changelog, never to itself.
class AboutView extends StatelessWidget {
  const AboutView({super.key});

  static const _repoUrl = 'https://github.com/abir2afridi/CubicLM';

  Future<void> _openUrl(String url) async {
    if (url.startsWith('REPLACE_ME')) {
      Get.snackbar(
        'Link not configured',
        'Edit shared/constants/platform_links.dart — see docs/PlatformLinks.md',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColors.warning.withValues(alpha: 0.9),
        colorText: Colors.white,
      );
      return;
    }
    final uri = Uri.parse(url);
    // Per §5.5.4: Web → _blank, Desktop → external browser, Android → Browser tab.
    // url_launcher with externalApplication does the right thing per platform.
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      Get.snackbar('Could not open link', url,
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _openRepo() => _openUrl(_repoUrl);
  Future<void> _openChangelog() => _openUrl(PlatformLinks.changelogUrl);

  String get _currentPlatformLabel {
    if (kIsWeb) return 'Web';
    if (defaultTargetPlatform == TargetPlatform.windows) return 'Windows Desktop';
    if (defaultTargetPlatform == TargetPlatform.android) return 'Android';
    if (defaultTargetPlatform == TargetPlatform.iOS) return 'iOS';
    if (defaultTargetPlatform == TargetPlatform.macOS) return 'macOS';
    if (defaultTargetPlatform == TargetPlatform.linux) return 'Linux';
    return 'Unknown';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = Get.find<SettingsController>();
    final version = settings.appVersion.value.isEmpty
        ? 'Engineering Build'
        : 'v${settings.appVersion.value}';

    return Scaffold(
      backgroundColor: isDark ? Dt.canvasDark : Dt.canvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft,
              size: 22,
              color: isDark ? Colors.white : Dt.iconDefault),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('about_title'.tr,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.textPrimary : Dt.textPrimary)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            // ── Identity ──
            Center(
              child: Column(children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset('assets/icons/CubicLM.png',
                      fit: BoxFit.cover),
                ),
                const SizedBox(height: 14),
                Text('CubicLM',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color:
                            isDark ? AppColors.textPrimary : Dt.textPrimary)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Dt.pillBg(isDark),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(version,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.textSecondary
                              : Dt.textSecondary)),
                ),
                const SizedBox(height: 8),
                // Current platform + version (per §5.5.5)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Dt.accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Dt.accent.withValues(alpha: 0.15)),
                  ),
                  child: Text('$_currentPlatformLabel • $version',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          color: Dt.accent)),
                ),
                const SizedBox(height: 14),
                Text(
                  'about_description'.tr,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13.5,
                      height: 1.55,
                      fontWeight: FontWeight.w500,
                      color:
                          isDark ? AppColors.textSecondary : Dt.textSecondary),
                ),
              ]),
            ),
            const SizedBox(height: 28),

            // ── Highlights ──
            _sectionLabel('about_highlights'.tr, isDark),
            _groupedCard(isDark: isDark, children: [
              for (final f in [
                (_Icons.brain, 'about_feat_local'.tr,
                    'about_feat_local_desc'.tr),
                (_Icons.zap, 'about_feat_litert'.tr,
                    'about_feat_litert_desc'.tr),
                (_Icons.cloud, 'about_feat_cloud'.tr,
                    'about_feat_cloud_desc'.tr),
                (_Icons.globe, 'about_feat_web'.tr,
                    'about_feat_web_desc'.tr),
                (_Icons.image, 'about_feat_image'.tr,
                    'about_feat_image_desc'.tr),
                (_Icons.eye, 'about_feat_vision'.tr,
                    'about_feat_vision_desc'.tr),
                (_Icons.plug, 'about_feat_server'.tr,
                    'about_feat_server_desc'.tr),
                (_Icons.activity, 'about_feat_diagnostics'.tr,
                    'about_feat_diagnostics_desc'.tr),
              ])
                _featureRow(f.$1, f.$2, f.$3, isDark),
            ]),
            const SizedBox(height: 24),

            // ── Cross-platform discoverability (per §5.4) ──
            _sectionLabel('about_available_on'.tr, isDark),
            _groupedCard(isDark: isDark, children: [
              if (kIsWeb) ...[
                // Web: link to Desktop + Android + changelog (no self)
                _platformLinkRow(
                  context, isDark,
                  icon: LucideIcons.monitor,
                  title: 'Windows Desktop',
                  subtitle: 'Download .exe / .msi',
                  url: PlatformLinks.desktopDownloadUrl,
                ),
                _divider(isDark),
                _platformLinkRow(
                  context, isDark,
                  icon: LucideIcons.smartphone,
                  title: 'Android',
                  subtitle: 'Download .apk / .aab',
                  url: PlatformLinks.androidDownloadUrl,
                ),
              ] else if (defaultTargetPlatform == TargetPlatform.windows) ...[
                // Desktop: link to Website + Android + changelog (no self)
                _platformLinkRow(
                  context, isDark,
                  icon: LucideIcons.globe,
                  title: 'Website',
                  subtitle: PlatformLinks.websiteUrl,
                  url: PlatformLinks.websiteUrl,
                ),
                _divider(isDark),
                _platformLinkRow(
                  context, isDark,
                  icon: LucideIcons.smartphone,
                  title: 'Android App',
                  subtitle: 'Get the APK',
                  url: PlatformLinks.androidDownloadUrl,
                ),
              ] else if (defaultTargetPlatform == TargetPlatform.android) ...[
                // Android: link to Website + Desktop + changelog (no self)
                _platformLinkRow(
                  context, isDark,
                  icon: LucideIcons.globe,
                  title: 'Website',
                  subtitle: PlatformLinks.websiteUrl,
                  url: PlatformLinks.websiteUrl,
                ),
                _divider(isDark),
                _platformLinkRow(
                  context, isDark,
                  icon: LucideIcons.monitor,
                  title: 'Windows Desktop',
                  subtitle: 'Download .exe / .msi',
                  url: PlatformLinks.desktopDownloadUrl,
                ),
              ] else ...[
                // Fallback: show all
                _platformLinkRow(
                  context, isDark,
                  icon: LucideIcons.globe,
                  title: 'Website',
                  subtitle: PlatformLinks.websiteUrl,
                  url: PlatformLinks.websiteUrl,
                ),
                _divider(isDark),
                _platformLinkRow(
                  context, isDark,
                  icon: LucideIcons.monitor,
                  title: 'Windows Desktop',
                  subtitle: PlatformLinks.desktopDownloadUrl,
                  url: PlatformLinks.desktopDownloadUrl,
                ),
                _divider(isDark),
                _platformLinkRow(
                  context, isDark,
                  icon: LucideIcons.smartphone,
                  title: 'Android',
                  subtitle: PlatformLinks.androidDownloadUrl,
                  url: PlatformLinks.androidDownloadUrl,
                ),
              ],
              _divider(isDark),
              // Changelog — centralized, never duplicated (§5.5.3)
              _platformLinkRow(
                context, isDark,
                icon: LucideIcons.sparkles,
                title: 'about_whats_new'.tr,
                subtitle: 'Changelog — single source of truth',
                url: PlatformLinks.changelogUrl,
                highlight: true,
              ),
            ]),
            const SizedBox(height: 24),

            // ── Tech stack ──
            _sectionLabel('about_tech_stack_label'.tr, isDark),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in const [
                  'Flutter', 'Dart', 'Kotlin', 'C++', 'GetX', 'Hive',
                  'llama.cpp', 'LiteRT-LM', 'Stable Diffusion', 'Firebase',
                  'window_manager',
                ])
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Dt.pillBg(isDark),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(t,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.textSecondary
                                : Dt.textSecondary)),
                  ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Links ──
            _sectionLabel('about_links'.tr, isDark),
            _groupedCard(isDark: isDark, children: [
              _linkRow(
                context,
                isDark,
                icon: LucideIcons.github,
                title: 'about_github_repo'.tr,
                subtitle: _repoUrl.replaceAll('https://', ''),
                onTap: _openRepo,
              ),
              _divider(isDark),
              _linkRow(
                context,
                isDark,
                icon: LucideIcons.scale,
                title: 'about_license'.tr,
                subtitle: 'about_license'.tr,
              ),
              _divider(isDark),
              _linkRow(
                context,
                isDark,
                icon: LucideIcons.messageSquare,
                title: 'about_issues'.tr,
                subtitle: 'Report bugs or request features on GitHub',
                onTap: _openRepo,
              ),
              _divider(isDark),
              _linkRow(
                context,
                isDark,
                icon: LucideIcons.fileText,
                title: 'about_changelog'.tr,
                subtitle: PlatformLinks.changelogUrl.replaceAll('https://', ''),
                onTap: _openChangelog,
              ),
            ]),
            const SizedBox(height: 24),

            // ── Developer ──
            _sectionLabel('about_developer'.tr, isDark),
            _groupedCard(isDark: isDark, children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                        color: Dt.accent, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text('A',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Abir Hasan Siam',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? AppColors.textPrimary
                                      : Dt.textPrimary)),
                          const SizedBox(height: 2),
                          Text('CodeCraftedStudio',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Dt.accent.withValues(alpha: 0.8))),
                        ]),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 28),
            Center(
              child: Text(
                'about_footer'.tr,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isDark ? AppColors.textMuted : Dt.textMuted),
              ),
            ),
            const SizedBox(height: 8),
            // Version footer per §5.5.5
            Center(
              child: Text(
                '$_currentPlatformLabel • $version • shared/constants/platform_links.dart',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: isDark ? AppColors.textMuted : Dt.textMuted),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Pieces ──

  Widget _sectionLabel(String text, bool isDark) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
                color: isDark ? AppColors.textMuted : Dt.textMuted)),
      );

  Widget _groupedCard(
          {required bool isDark, required List<Widget> children}) =>
      Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: isDark ? Dt.cardDark : Dt.card,
          border: Border.all(color: Dt.borderColor(isDark)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      );

  Widget _divider(bool isDark) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Divider(height: 1, color: Dt.borderColor(isDark)),
      );

  Widget _featureRow(IconData icon, String title, String subtitle,
      bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Dt.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 17, color: Dt.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppColors.textPrimary
                            : Dt.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? AppColors.textSecondary
                            : Dt.textSecondary)),
              ]),
        ),
      ]),
    );
  }

  Widget _platformLinkRow(
    BuildContext context,
    bool isDark, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String url,
    bool highlight = false,
  }) {
    final isPlaceholder = url.startsWith('REPLACE_ME');
    return InkWell(
      onTap: () => _openUrl(url),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: highlight
                  ? Dt.accent.withValues(alpha: 0.12)
                  : Dt.pillBg(isDark),
              borderRadius: BorderRadius.circular(8),
              border: highlight
                  ? Border.all(color: Dt.accent.withValues(alpha: 0.2))
                  : null,
            ),
            child: Icon(icon,
                size: 16,
                color: highlight ? Dt.accent : Dt.textSecondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: highlight
                              ? Dt.accent
                              : isDark
                                  ? AppColors.textPrimary
                                  : Dt.textPrimary)),
                  const SizedBox(height: 2),
                  Text(
                      isPlaceholder ? 'Configure in platform_links.dart' : subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: isPlaceholder
                              ? AppColors.warning
                              : isDark
                                  ? AppColors.textMuted
                                  : Dt.textMuted)),
                ]),
          ),
          const Icon(LucideIcons.externalLink,
              size: 16, color: Dt.textMuted),
        ]),
      ),
    );
  }

  Widget _linkRow(
    BuildContext context,
    bool isDark, {
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Icon(icon, size: 20, color: Dt.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.textPrimary
                              : Dt.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? AppColors.textMuted
                              : Dt.textMuted)),
                ]),
          ),
          if (onTap != null)
            const Icon(LucideIcons.externalLink,
                size: 16, color: Dt.textMuted),
        ]),
      ),
    );
  }
}

/// Lucide icon aliases kept local so the table above stays terse.
abstract class _Icons {
  static const brain = LucideIcons.brain;
  static const zap = LucideIcons.zap;
  static const cloud = LucideIcons.cloud;
  static const globe = LucideIcons.globe;
  static const image = LucideIcons.image;
  static const eye = LucideIcons.eye;
  static const plug = LucideIcons.plug;
  static const activity = LucideIcons.activity;
}
