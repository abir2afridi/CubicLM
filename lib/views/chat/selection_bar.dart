import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import '../../controllers/chat_controller.dart';
import '../../core/colors.dart';
import '../../models/chat_message.dart';
import '../../theme/design_tokens.dart';

/// Message selection row + bar.
/// Extracted from views/chat_view.dart.

ChatController get _c => Get.find<ChatController>();

Widget selectableRow(
    BuildContext context, ChatMessage msg, Widget child, bool isDark) {
  return GestureDetector(
    onLongPress: () {
      _c.toggleSelectionMode(true);
      _c.toggleSelected(msg.id);
    },
    onTap: () {
      if (_c.selectionMode.value) {
        _c.toggleSelected(msg.id);
      }
    },
    child: Obx(() {
      final selected =
          _c.selectionMode.value && _c.selectedIds.contains(msg.id);
      if (!selected) return child;
      return Container(
        decoration: const BoxDecoration(
          color: Color(0x14D97757),
          border: Border(left: BorderSide(color: Dt.accent, width: 3)),
        ),
        child: child,
      );
    }),
  );
}

Widget selectionBar(BuildContext context, bool isDark) {
  return Container(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
    decoration: BoxDecoration(
      color: isDark ? Dt.cardDark : Dt.card,
      border: Border(
          top: BorderSide(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06))),
    ),
    child: SafeArea(
      top: false,
      child: Obx(() {
        final n = _c.selectedIds.length;
        return Row(
          children: [
            Text('$n selected',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800, fontSize: 14)),
            const Spacer(),
            IconButton(
              tooltip: 'Copy selected',
              icon: const Icon(LucideIcons.copy, size: 20),
              onPressed: n == 0
                  ? null
                  : () => Clipboard.setData(
                      ClipboardData(text: _c.selectedAsMarkdown())),
            ),
            IconButton(
              tooltip: 'Share selected',
              icon: const Icon(LucideIcons.share2, size: 20),
              onPressed:
                  n == 0 ? null : () => Share.share(_c.selectedAsMarkdown()),
            ),
            IconButton(
              tooltip: 'Delete selected',
              icon: const Icon(LucideIcons.trash2,
                  size: 20, color: AppColors.error),
              onPressed: n == 0 ? null : () => _c.deleteSelected(),
            ),
            IconButton(
              tooltip: 'Done',
              icon: const Icon(LucideIcons.x, size: 20),
              onPressed: () => _c.toggleSelectionMode(false),
            ),
          ],
        );
      }),
    ),
  );
}
