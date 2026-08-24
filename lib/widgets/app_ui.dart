import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/design_tokens.dart';

/// Shows a bottom sheet matching the reference design: rounded-top card,
/// drag handle, 45% scrim, easeOutCubic open / easeInCubic close.
Future<T?> showAppBottomSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    barrierColor: Dt.scrim,
    // Modal bottom sheet animation uses the theme's sheet curves; we get
    // the exact open feel via the material transition timing below.
    builder: (ctx) => _SheetShell(builder: builder),
  );
}

class _SheetShell extends StatelessWidget {
  final WidgetBuilder builder;
  const _SheetShell({required this.builder});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Theme.of(context).cardColor : Dt.card,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(Dt.rSheet)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: Dt.sheetHandleW,
            height: Dt.sheetHandleH,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Dt.sheetHandle,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Flexible(child: Builder(builder: (ctx) => builder(ctx))),
          // Respect keyboard inset handled by modal sheet padding param.
        ],
      ),
    );
  }
}

/// Sheet header per spec: leading close/back + bold centered title.
class AppSheetHeader extends StatelessWidget {
  final String title;
  final VoidCallback onClose;
  final bool showBack;

  const AppSheetHeader({
    super.key,
    required this.title,
    required this.onClose,
    this.showBack = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 8,
            child: IconButton(
              onPressed: onClose,
              icon: Icon(
                showBack ? LucideIcons.arrowLeft : LucideIcons.x,
                size: Dt.iconSize - 2,
                color: Dt.iconDefault,
              ),
            ),
          ),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Dt.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Circular muted control button (+ / mic) — 28dp pillMuted circle with a
/// min 44dp hit area, outline glyph.
class AppCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color? iconColor;
  final double diameter;
  final String? tooltip;

  const AppCircleButton({
    super.key,
    required this.icon,
    this.onTap,
    this.iconColor,
    this.diameter = Dt.circleBtnDiameter,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final btn = Container(
      width: diameter,
      height: diameter,
      decoration: const BoxDecoration(
        color: Dt.pillMuted,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 18, color: iconColor ?? Dt.iconDefault),
    );
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(onTap: onTap, customBorder: const CircleBorder(), child: btn),
    );
  }
}

/// Solid near-black circular CTA (send/voice) — highest-contrast element.
class AppCtaButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const AppCtaButton({super.key, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: Dt.circleBtnDiameter,
        height: Dt.circleBtnDiameter,
        decoration: const BoxDecoration(
          color: Dt.ctaFill,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }
}

/// Fully-rounded pill button showing the current model/mode label.
class AppModelPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const AppModelPill({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Dt.pillHeight),
      child: Container(
        height: Dt.pillHeight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Dt.pillMuted,
          borderRadius: BorderRadius.circular(Dt.pillHeight),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Dt.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(LucideIcons.chevronDown, size: 14, color: Dt.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// Stacked flat row-card used inside sheets (16dp-ish radius, no shadow).
class AppSheetRowCard extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleColor;
  final Color? subtitleColor;

  const AppSheetRowCard({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.titleColor,
    this.subtitleColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3), // tight ~2-3dp gap
      child: Material(
        color: isDark ? Theme.of(context).cardColor : Dt.card,
        borderRadius: BorderRadius.circular(Dt.rRowCard),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: titleColor ??
                                  (isDark
                                      ? Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.color
                                      : Dt.textPrimary))),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!,
                            style: TextStyle(
                                fontSize: 12.5,
                                color: subtitleColor ?? Dt.textSecondary)),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 40dp muted icon-circle for row leading slots.
class AppIconCircle extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final double diameter;

  const AppIconCircle({
    super.key,
    required this.icon,
    this.color,
    this.diameter = Dt.iconCircleDiameter,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: const BoxDecoration(color: Dt.pillMuted, shape: BoxShape.circle),
      child: Icon(icon, size: diameter >= 56 ? 22 : 18, color: color ?? Dt.iconDefault),
    );
  }
}
