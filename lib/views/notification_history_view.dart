import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/colors.dart';
import '../models/notification_entry.dart';
import '../services/notification_history_service.dart';
import '../theme/design_tokens.dart';

class NotificationHistoryView extends StatelessWidget {
  const NotificationHistoryView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final svc = Get.find<NotificationHistoryService>();

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
        title: Text('Notifications',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800,
                fontSize: 22,
                letterSpacing: -0.5)),
        centerTitle: false,
        actions: [
          Obx(() {
            if (svc.notifications.isEmpty) return const SizedBox.shrink();
            return PopupMenuButton<String>(
              icon: Icon(LucideIcons.moreVertical,
                  size: 20,
                  color: isDark ? Colors.white70 : Dt.textSecondary),
              onSelected: (v) {
                if (v == 'mark_read') svc.markAllRead();
                if (v == 'clear') _confirmClear(context, isDark, svc);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                    value: 'mark_read', child: Text('Mark all read')),
                const PopupMenuItem(value: 'clear', child: Text('Clear all')),
              ],
            );
          }),
        ],
      ),
      body: Obx(() {
        final list = svc.notifications;
        if (list.isEmpty) return _empty(context, isDark);

        // Group by day label.
        final groups = <String, List<NotificationEntry>>{};
        for (final n in list) {
          final label = _dayLabel(n.timestamp);
          groups.putIfAbsent(label, () => []).add(n);
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: groups.length,
          itemBuilder: (_, idx) {
            final label = groups.keys.elementAt(idx);
            final items = groups[label]!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                  child: Text(label,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: Theme.of(context).hintColor)),
                ),
                for (final n in items) _card(context, isDark, n, svc),
              ],
            );
          },
        );
      }),
    );
  }

  Widget _card(BuildContext context, bool isDark, NotificationEntry n,
      NotificationHistoryService svc) {
    return Dismissible(
      key: ValueKey(n.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(LucideIcons.trash2,
            size: 18, color: AppColors.error),
      ),
      onDismissed: (_) => svc.delete(n.id),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => svc.markRead(n.id),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: n.isRead ? 0.03 : 0.06)
                : (n.isRead
                    ? Colors.white.withValues(alpha: 0.7)
                    : Colors.white),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: n.isRead
                  ? (isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.04))
                  : Dt.accent.withValues(alpha: 0.18),
              width: 1,
            ),
            boxShadow: n.isRead
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _iconBg(n.type).withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(_iconFor(n.iconName),
                    size: 18, color: _iconBg(n.type)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(n.title,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: isDark
                                      ? Colors.white
                                      : Dt.textPrimary)),
                        ),
                        if (!n.isRead)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Dt.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(n.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? Colors.white70
                                : Dt.textSecondary,
                            height: 1.35)),
                    const SizedBox(height: 6),
                    Text(_timeAgo(n.timestamp),
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).hintColor)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(BuildContext context, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Dt.accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.bellOff,
                  size: 32, color: Dt.accent),
            ),
            const SizedBox(height: 18),
            Text('No notifications yet',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : Dt.textPrimary)),
            const SizedBox(height: 8),
            Text(
              'Model switches will appear here with time.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: Theme.of(context).hintColor,
                  height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmClear(
      BuildContext context, bool isDark, NotificationHistoryService svc) {
    Get.dialog(
      AlertDialog(
        backgroundColor: isDark ? Dt.cardDark : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Clear all?',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        content: Text('This will permanently delete all notifications.',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14, color: Theme.of(context).hintColor)),
        actions: [
          TextButton(
              onPressed: () => Get.back(),
              child: Text('Cancel',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Get.back();
              svc.clearAll();
            },
            child: Text('Clear',
                style:
                    GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ── Helpers ──

  static IconData _iconFor(String name) => switch (name) {
        'layers' => LucideIcons.layers,
        'cloud' => LucideIcons.cloud,
        'cpu' => LucideIcons.cpu,
        'image' => LucideIcons.image,
        _ => LucideIcons.sparkles,
      };

  static Color _iconBg(String type) => switch (type) {
        'model_switched' => Dt.accent,
        'cloud_active' => const Color(0xFF3B82F6),
        'local_active' => const Color(0xFF10B981),
        _ => Dt.accent,
      };

  static String _timeAgo(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '${t.day}/${t.month}/${t.year} $hh:$mm';
  }

  static String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    if (now.difference(day).inDays < 7 && now.isAfter(day)) {
      return ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];
    }
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}
