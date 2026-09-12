import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/colors.dart';
import '../../theme/design_tokens.dart';
import '../agent_ide_view.dart';
import '../battle_arena_view.dart';
import '../cubicdata/datasheet_home_view.dart';
import '../cubicweb/browser_view.dart';
import '../slide_deck_view.dart';

/// Explore Toolkit tab cards.
/// Extracted from views/model_view.dart (one responsibility per file).

Widget buildToolkitTab(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'AI power tools — same engine as chat, focused workspaces.',
        style: GoogleFonts.plusJakartaSans(
          fontSize: 12.5,
          color: Theme.of(context).hintColor,
          height: 1.45,
        ),
      ),
      const SizedBox(height: 12),
      _toolkitCard(
        context,
        isDark,
        icon: LucideIcons.swords,
        title: 'Battle Arena',
        description:
            'Race up to 4 cloud models on one prompt — same-time or one-by-one (on-device allowed). Live monitor ranks finish, speed and length, then declares an overall winner.',
        onTap: () => Get.to(() => const BattleArenaView()),
      ),
      const SizedBox(height: 10),
      _toolkitCard(
        context,
        isDark,
        icon: LucideIcons.presentation,
        title: 'Slide Maker',
        description:
            'AI designs every slide from a topic — Docs / Slides / PDF views, freehand move + resize, manual photos, per-slide regen. Exports Markdown, PDF and web slides.',
        onTap: () => Get.to(() => const SlideDeckView()),
      ),
      const SizedBox(height: 10),
      _toolkitCard(
        context,
        isDark,
        icon: LucideIcons.terminalSquare,
        title: 'CubicWeb Builder',
        description:
            'Agent IDE: tell AI what to build — websites in any framework, live preview, console-error auto-fix, file explorer. Static + ESM runs on-device.',
        onTap: () => Get.to(() => const AgentIdeView()),
      ),
      const SizedBox(height: 10),
      _toolkitCard(
        context,
        isDark,
        icon: LucideIcons.tableProperties,
        title: 'CubicDataSheet',
        description:
            'Personal sheets + docs workspace: formulas, cell locks with unlock mode, per-cell copy, notes and history. Stored on this device only.',
        onTap: () => Get.to(() => const DataSheetHomeView()),
      ),
      const SizedBox(height: 10),
      _toolkitCard(
        context,
        isDark,
        icon: LucideIcons.globe,
        title: 'CubicWeb Browser',
        description:
            'Private in-app browser: ads and trackers blocked from a built-in list, no history saved. Extract any page into chat for the local model.',
        onTap: () => Get.to(() => const BrowserView()),
      ),
    ],
  );
}

Widget _toolkitCard(
  BuildContext context,
  bool isDark, {
  required IconData icon,
  required String title,
  required String description,
  required VoidCallback onTap,
}) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.07) : Dt.hairline,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Dt.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, size: 22, color: Dt.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(description,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12.5,
                        height: 1.45,
                        color: Theme.of(context).hintColor)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(LucideIcons.chevronRight,
              size: 18, color: Theme.of(context).hintColor),
        ],
      ),
    ),
  );
}
