import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../controllers/chat_controller.dart';
import '../../controllers/home_controller.dart';
import '../../controllers/model_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../core/colors.dart';
import '../../theme/design_tokens.dart';
import 'chat_widgets.dart';

/// Empty state + suggestion cards.
/// Extracted from views/chat_view.dart.

ChatController get _c => Get.find<ChatController>();

Widget emptyState(BuildContext context, bool isDark) {
  final suggestions = [
    {
      'text': 'Explain quantum computing simply',
      'icon': Icons.auto_awesome_rounded,
      'color': Colors.blue
    },
    {
      'text': 'Write a short poem about time',
      'icon': Icons.edit_note_rounded,
      'color': Colors.purple
    },
    {
      'text': 'What makes the Northern Lights happen?',
      'icon': Icons.light_mode_rounded,
      'color': Colors.teal
    },
    {
      'text': 'Give me a 5-minute healthy breakfast recipe',
      'icon': Icons.restaurant_rounded,
      'color': Colors.orange
    },
  ];
  return Center(
      child: SingleChildScrollView(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Image.asset(
        'assets/icons/CubicLM.png',
        width: 64,
        height: 64,
        fit: BoxFit.contain,
      ),
      const SizedBox(height: 16),
      AnimatedAppName(isDark: isDark),
      const SizedBox(height: 20),
      Text('chat_empty_title'.tr,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
              color: isDark ? AppColors.textPrimary : Dt.textPrimary)),
      const SizedBox(height: 8),
      Text('chat_empty_subtitle'.tr,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: Dt.textSecondary,
              fontWeight: FontWeight.w500)),
      const SizedBox(height: 28),
      Obx(() {
        final settings = Get.find<SettingsController>();
        final models = Get.find<ModelController>();
        final isLocal = settings.inferenceMode.value == 'local';
        if (isLocal && models.downloadedCount == 0) {
          return Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.2), width: 1.5),
            ),
            child: Column(children: [
              const Icon(Icons.cloud_download_rounded,
                  color: AppColors.warning, size: 48),
              const SizedBox(height: 16),
              Text('chat_no_local_models_title'.tr,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black)),
              const SizedBox(height: 10),
              Text('chat_no_local_models_desc'.tr,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      color: Theme.of(context).hintColor,
                      height: 1.5)),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: () => Get.find<HomeController>().changeTab(1),
                icon: const Icon(Icons.arrow_right_alt_rounded, size: 22),
                label: Text('chat_go_to_hub'.tr),
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.warning,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20))),
              ),
            ]),
          );
        }
        return LayoutBuilder(
          builder: (ctx, constraints) {
            final w = constraints.maxWidth;
            final cols = w >= 600 ? (w >= 900 ? 4 : 3) : 2;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                // Fixed dp height (not width-derived) so wrapped text on
                // narrow screens can never overflow the tile.
                mainAxisExtent: 136,
              ),
              itemCount: suggestions.length,
              itemBuilder: (ctx, i) {
                final s = suggestions[i];
                return suggestionCard(context, s['text'] as String,
                    s['icon'] as IconData, s['color'] as Color, isDark);
              },
            );
          },
        );
      }),
    ]),
  ));
}

Widget suggestionCard(BuildContext context, String text, IconData icon,
    Color color, bool isDark) {
  return InkWell(
    onTap: () {
      _c.createNewChat();
      _c.textController.text = text;
      _c.inputText.value = text;
      _c.sendMessage();
    },
    borderRadius: BorderRadius.circular(24),
    child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          Text(text,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: isDark ? AppColors.textPrimary : Dt.textPrimary,
                  fontWeight: FontWeight.w700,
                  height: 1.3),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    ),
  );
}
