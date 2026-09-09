import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../controllers/chat_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../core/colors.dart';
import '../../services/inference_service.dart';
import '../../services/notification_history_service.dart';
import '../../theme/design_tokens.dart';
import '../notification_history_view.dart';
import 'chat_format.dart';

/// Top bars (find, bell, loading, context).
/// Extracted from views/chat_view.dart.

ChatController get _c => Get.find<ChatController>();

Widget findBar(BuildContext context, bool isDark) {
  return Container(
    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: isDark ? Dt.cardDark : Dt.card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.06),
      ),
    ),
    child: Row(
      children: [
        Icon(LucideIcons.search,
            size: 18, color: isDark ? AppColors.textPrimary : Dt.iconDefault),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _c.findController,
            autofocus: true,
            onChanged: _c.updateFind,
            onSubmitted: (_) => _c.stepFind(1),
            style: GoogleFonts.plusJakartaSans(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Find in this chat…',
              hintStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 14, color: Theme.of(context).hintColor),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        Obx(() {
          final n = _c.findMatches.length;
          final q = _c.findQuery.value;
          final label = q.isEmpty
              ? ''
              : n == 0
                  ? '0'
                  : '${_c.findIndex.value + 1}/$n';
          return Text(label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).hintColor));
        }),
        IconButton(
          tooltip: 'Previous',
          icon: const Icon(LucideIcons.chevronUp, size: 20),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: () => _c.stepFind(-1),
        ),
        IconButton(
          tooltip: 'Next',
          icon: const Icon(LucideIcons.chevronDown, size: 20),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: () => _c.stepFind(1),
        ),
        IconButton(
          tooltip: 'Close find',
          icon: const Icon(LucideIcons.x, size: 20),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: () => _c.toggleFind(false),
        ),
      ],
    ),
  );
}

Widget notificationBell(BuildContext context, bool isDark) {
  // Never throw if DI isn't ready yet (cold-start race) — bell just
  // shows no badge until the service lands.
  if (!Get.isRegistered<NotificationHistoryService>()) {
    return IconButton(
      tooltip: 'Notifications',
      icon: Icon(LucideIcons.bell,
          size: Dt.iconSize - 2,
          color: isDark ? AppColors.textPrimary : Dt.iconDefault),
      onPressed: () => Get.to(() => const NotificationHistoryView(),
          transition: Transition.rightToLeft,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic),
    );
  }
  final svc = Get.find<NotificationHistoryService>();
  return Obx(() {
    final unread = svc.unreadCount;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: 'Notifications',
          icon: Icon(LucideIcons.bell,
              size: Dt.iconSize - 2,
              color: isDark ? AppColors.textPrimary : Dt.iconDefault),
          onPressed: () {
            svc.markAllRead();
            Get.to(() => const NotificationHistoryView(),
                transition: Transition.rightToLeft,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic);
          },
        ),
        if (unread > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              decoration: BoxDecoration(
                color: Dt.accent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: isDark ? Dt.canvasDark : Dt.canvas, width: 1.5),
              ),
              child: Center(
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1),
                ),
              ),
            ),
          ),
      ],
    );
  });
}

// ── Model Loading ──
Widget modelLoadingBar(BuildContext context, bool isDark) {
  return Obx(() {
    final inf = Get.find<InferenceService>();
    if (!inf.isLoadingModel.value) return const SizedBox.shrink();
    final pct = (inf.modelLoadProgress.value * 100).toStringAsFixed(0);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
          decoration: BoxDecoration(
            color: (isDark ? AppColors.surface : Colors.white)
                .withValues(alpha: 0.8),
            border: Border(
                bottom: BorderSide(
                    color:
                        isDark ? AppColors.border : AppColors.borderLightMode,
                    width: 1)),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: AppColors.primary)),
              const SizedBox(width: 12),
              Expanded(
                child: Text("${'chat_sync_intelligence'.tr} $pct%",
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        color: isDark ? AppColors.textPrimary : Dt.textPrimary,
                        fontWeight: FontWeight.w800)),
              ),
            ]),
            const SizedBox(height: 14),
            Stack(
              children: [
                ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                        value: inf.modelLoadProgress.value,
                        backgroundColor:
                            isDark ? Dt.pillMutedDark : Dt.pillMuted,
                        color: AppColors.primary,
                        minHeight: 6)),
                if (inf.modelLoadProgress.value > 0.05)
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: inf.modelLoadProgress.value,
                        child: Container(
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.4),
                                blurRadius: 10,
                                spreadRadius: 1,
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ]),
        ),
      ),
    );
  });
}

// ── Context Bar ──
Widget contextBar(BuildContext context, bool isDark) {
  return Obx(() {
    final settings = Get.find<SettingsController>();
    final inf = Get.find<InferenceService>();
    final active =
        _c.currentSessionId.value.isNotEmpty && _c.messages.isNotEmpty;
    if (!active || settings.inferenceMode.value != 'local') {
      return const SizedBox.shrink();
    }
    final total = inf.contextTokensTotal.value > 0
        ? inf.contextTokensTotal.value
        : settings.contextSize.value;
    final est = _c.messages.fold<int>(0, (s, m) => s + m.content.length);
    final used = (inf.contextTokensUsed.value > 0
            ? inf.contextTokensUsed.value
            : (est / 4).ceil())
        .clamp(0, total)
        .toInt();
    final pct = total == 0 ? 0.0 : (used / total).clamp(0.0, 1.0).toDouble();
    final warn = pct >= 0.75;
    final accent = warn ? AppColors.warning : AppColors.primary;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Row(children: [
        Icon(Icons.query_stats_rounded, size: 14, color: accent),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('chat_context_usage'.tr,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          color: Theme.of(context).hintColor,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2)),
                  Text('${fmtK(used)} / ${fmtK(total)} ${'chat_tokens'.tr}',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          color: accent,
                          fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                      value: pct,
                      backgroundColor: isDark ? Dt.cardDark : Dt.card,
                      color: accent,
                      minHeight: 3)),
            ],
          ),
        ),
      ]),
    );
  });
}
