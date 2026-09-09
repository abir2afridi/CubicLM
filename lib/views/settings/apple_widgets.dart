import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/colors.dart';
import '../../theme/design_tokens.dart';

/// Apple-style grouped cards, tiles, icon boxes, section labels.
/// Extracted from views/settings_view.dart.
Widget appleGroupedCard(BuildContext context, bool isDark,
    {required List<Widget> children}) {
  return Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: isDark ? Dt.cardDark : Dt.card,
      border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.07) : Dt.hairline),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: children),
  );
}

// ── Apple-style list tile ──
Widget appleListTile(
  BuildContext context,
  bool isDark, {
  Widget? leading,
  required String title,
  String? subtitle,
  Widget? trailing,
  bool showDivider = true,
  VoidCallback? onTap,
}) {
  return Column(children: [
    InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Row(children: [
          if (leading != null) ...[leading, const SizedBox(width: 16)],
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                Text(title,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color:
                            isDark ? AppColors.textPrimary : Dt.textPrimary)),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).hintColor))
                ],
              ])),
          if (trailing != null) trailing,
        ]),
      ),
    ),
    if (showDivider)
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Divider(
            height: 1,
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.03)),
      ),
  ]);
}

Widget iconBox(Color color, IconData icon) {
  return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, size: 18, color: color));
}

Widget sectionLabel(BuildContext context, String title) {
  return Padding(
    padding: const EdgeInsets.only(left: 20, bottom: 8),
    child: Text(title,
        style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: Theme.of(context).hintColor)),
  );
}
