import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/constants.dart';
import '../services/hive_service.dart';
import '../core/routes.dart';
import '../theme/design_tokens.dart';

class OnboardingView extends StatefulWidget {
  const OnboardingView({super.key});

  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<OnboardingView> {
  final _page = PageController();
  int _index = 0;

  void _next() {
    if (_index < 2) {
      _page.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    try {
      if (Get.isRegistered<HiveService>()) {
        await Get.find<HiveService>().setSetting(AppConstants.keyOnboardingDone, true);
      }
    } catch (_) {}
    Get.offAllNamed(AppRoutes.home);
  }

  Future<void> _skip() async {
    try {
      if (Get.isRegistered<HiveService>()) {
        await Get.find<HiveService>().setSetting(AppConstants.keyOnboardingDone, true);
      }
    } catch (_) {}
    Get.offAllNamed(AppRoutes.home);
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Dt.canvasDark : Dt.canvas;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Spacer(),
                  if (_index < 2)
                    TextButton(
                      onPressed: _skip,
                      child: Text('onboarding_skip'.tr,
                          style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w600, color: Theme.of(context).hintColor)),
                    )
                  else
                    const SizedBox(height: 48),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _page,
                onPageChanged: (i) => setState(() => _index = i),
                children: [
                  _OnboardPage(
                    icon: LucideIcons.shieldCheck,
                    title: 'onboarding_page1_title'.tr,
                    desc: 'onboarding_page1_desc'.tr,
                    isDark: isDark,
                  ),
                  _OnboardPage(
                    icon: LucideIcons.cloud,
                    title: 'onboarding_page2_title'.tr,
                    desc: 'onboarding_page2_desc'.tr,
                    isDark: isDark,
                  ),
                  _OnboardPage(
                    icon: LucideIcons.download,
                    title: 'onboarding_page3_title'.tr,
                    desc: 'onboarding_page3_desc'.tr,
                    isDark: isDark,
                    extra: Column(
                      children: [
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Dt.accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Dt.accent.withValues(alpha: 0.15)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(LucideIcons.sparkles, size: 16, color: Dt.accent),
                              const SizedBox(width: 8),
                              Text('onboarding_recommended'.tr,
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12, fontWeight: FontWeight.w700, color: Dt.accent)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (i) {
                final sel = i == _index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: sel ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: sel ? Dt.accent : Theme.of(context).hintColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Dt.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  onPressed: _next,
                  child: Text(_index == 2 ? 'onboarding_start'.tr : 'onboarding_next'.tr),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_index == 2)
              TextButton(
                onPressed: () async {
                  await _finish();
                  // After finish, user will be on home; Model Hub is Explore tab. No direct deep link needed.
                },
                child: Text('onboarding_open_hub'.tr,
                    style: GoogleFonts.plusJakartaSans(color: Dt.accent, fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _OnboardPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  final bool isDark;
  final Widget? extra;
  const _OnboardPage({required this.icon, required this.title, required this.desc, required this.isDark, this.extra});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: Dt.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(icon, size: 44, color: Dt.accent),
          ),
          const SizedBox(height: 32),
          Text(title,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.1)),
          const SizedBox(height: 12),
          Text(desc,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 15, height: 1.5, fontWeight: FontWeight.w500, color: Theme.of(context).hintColor)),
          if (extra != null) extra!,
        ],
      ),
    );
  }
}
