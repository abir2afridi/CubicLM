import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/settings_controller.dart';
import '../core/colors.dart';
import '../theme/design_tokens.dart';

/// Full about page — opens from App Settings › App Info. Surfaces the
/// project's key facts (features, stack, links, credits) from the README.
class AboutView extends StatelessWidget {
  const AboutView({super.key});

  static const _repoUrl = 'https://github.com/abir2afridi/CubicLM';

  Future<void> _openRepo() async {
    final uri = Uri.parse(_repoUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      Get.snackbar('Could not open link', _repoUrl,
          snackPosition: SnackPosition.BOTTOM);
    }
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
        title: Text('About',
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
                const SizedBox(height: 14),
                Text(
                  'A cross-platform AI chat app with local on-device '
                  'inference and multi-provider cloud AI — LLMs run '
                  'directly on your phone via GPU-accelerated llama.cpp '
                  'and Google LiteRT-LM, with a built-in OpenAI-compatible '
                  'API server.',
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
            _sectionLabel('HIGHLIGHTS', isDark),
            _groupedCard(isDark: isDark, children: [
              for (final f in const [
                (_Icons.brain, 'Local AI Inference',
                    'GGUF models on llama.cpp with Vulkan/OpenCL GPU acceleration'),
                (_Icons.zap, 'LiteRT-LM Engine',
                    "Google's on-device runtime for .litertlm models"),
                (_Icons.cloud, '20+ Cloud Providers',
                    'OpenRouter, OpenAI, Anthropic, Gemini, Groq, DeepSeek and more'),
                (_Icons.globe, 'Web Access',
                    'Live web pages fetched into chat context — no API keys needed'),
                (_Icons.image, 'Image Generation',
                    'Stable Diffusion 1.5 on-device, plus cloud SD3.5'),
                (_Icons.eye, 'Vision Models',
                    'Understand images with Qwen2-VL and Gemma'),
                (_Icons.plug, 'OpenAI-Compatible Server',
                    'Expose local models on your network at port 8080'),
                (_Icons.activity, 'System Diagnostics',
                    'Health dashboard, crash patterns and searchable logs'),
              ])
                _featureRow(f.$1, f.$2, f.$3, isDark),
            ]),
            const SizedBox(height: 24),

            // ── Tech stack ──
            _sectionLabel('TECH STACK', isDark),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in const [
                  'Flutter', 'Dart', 'Kotlin', 'C++', 'GetX', 'Hive',
                  'llama.cpp', 'LiteRT-LM', 'Stable Diffusion', 'Firebase',
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
            _sectionLabel('LINKS', isDark),
            _groupedCard(isDark: isDark, children: [
              _linkRow(
                context,
                isDark,
                icon: LucideIcons.github,
                title: 'GitHub Repository',
                subtitle: _repoUrl.replaceAll('https://', ''),
                onTap: _openRepo,
              ),
              _divider(isDark),
              _linkRow(
                context,
                isDark,
                icon: LucideIcons.scale,
                title: 'License',
                subtitle: 'MIT — free to use, modify and distribute',
              ),
              _divider(isDark),
              _linkRow(
                context,
                isDark,
                icon: LucideIcons.messageSquare,
                title: 'Issues & Feedback',
                subtitle: 'Report bugs or request features on GitHub',
                onTap: _openRepo,
              ),
            ]),
            const SizedBox(height: 24),

            // ── Developer ──
            _sectionLabel('DEVELOPER', isDark),
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
                'Built with Flutter · Runs AI entirely on your device',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
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
