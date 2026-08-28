import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../controllers/settings_controller.dart';
import '../core/colors.dart';
import '../core/languages.dart';
import '../theme/design_tokens.dart';

/// Language picker page — opens from App Settings › Language.
/// Apple-style grouped list with native flag icons.
class LanguagePickerView extends GetView<SettingsController> {
  const LanguagePickerView({super.key});

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
        title: Text('language_title'.tr,
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800,
                fontSize: 24,
                letterSpacing: -1)),
        toolbarHeight: 70,
        centerTitle: false,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('language_subtitle'.tr,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).hintColor)),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Obx(() {
              final currentCode = controller.locale.value.code;
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: AppLanguage.supported.length,
                itemBuilder: (context, index) {
                  final lang = AppLanguage.supported[index];
                  final isSelected = lang.code == currentCode;
                  final isFirst = index == 0;
                  final isLast = index == AppLanguage.supported.length - 1;

                  return Column(
                    children: [
                      if (isFirst)
                        Container(
                          height: 10,
                          decoration: BoxDecoration(
                            color: Dt.pillBg(isDark),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(16),
                            ),
                          ),
                        ),
                      Material(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.02)
                            : Dt.pillMuted.withValues(alpha: 0.5),
                        child: InkWell(
                          onTap: () => _selectLanguage(context, isDark, lang),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                            child: Row(
                              children: [
                                // Flag
                                Text(lang.flag,
                                    style: const TextStyle(fontSize: 24)),
                                const SizedBox(width: 16),
                                // Language names
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        lang.nativeName,
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: isDark
                                              ? AppColors.textPrimary
                                              : Dt.textPrimary,
                                        ),
                                      ),
                                      if (lang.name != lang.nativeName) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          lang.name,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: Theme.of(context)
                                                .hintColor,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                // Check
                                if (isSelected)
                                  const Icon(LucideIcons.check,
                                      size: 20, color: Dt.accent),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (!isLast)
                        Padding(
                          padding: const EdgeInsets.only(left: 60),
                          child: Divider(
                            height: 1,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.black.withValues(alpha: 0.03),
                          ),
                        ),
                      if (isLast)
                        Container(
                          height: 10,
                          decoration: BoxDecoration(
                            color: Dt.pillBg(isDark),
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(16),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              );
            }),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _selectLanguage(BuildContext context, bool isDark, AppLanguage lang) {
    final previousCode = controller.locale.value.code;

    // Apply immediately
    controller.setLocale(lang);

    // Show confirmation toast
    GetSnackBar snackbar;
    if (lang.code == previousCode) {
      // No change
      return;
    }

    snackbar = GetSnackBar(
      messageText: Row(
        children: [
          Text(lang.flag, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${'language_changed'.tr} — ${lang.nativeName}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
      snackPosition: SnackPosition.TOP,
      backgroundColor: Dt.accent,
      margin: const EdgeInsets.all(16),
      borderRadius: 14,
      duration: const Duration(seconds: 2),
      animationDuration: const Duration(milliseconds: 300),
      barBlur: 12,
    );
    snackbar.show();
  }
}
