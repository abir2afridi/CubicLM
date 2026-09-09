import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../controllers/agent_controller.dart';
import '../../core/colors.dart';
import '../../theme/design_tokens.dart';

/// Live build activity timeline card (v0-style).
/// Extracted from views/agent_ide_view.dart.
IconData stepIcon(String? kind) {
    switch (kind) {
      case 'thinking':
        return LucideIcons.brain;
      case 'file':
        return LucideIcons.fileCode2;
      case 'error':
        return LucideIcons.alertTriangle;
      case 'fix':
        return LucideIcons.wrench;
      case 'done':
        return LucideIcons.checkCircle2;
      default:
        return LucideIcons.info;
    }
  }

Color stepColor(String? kind, BuildContext context) {
    switch (kind) {
      case 'error':
        return AppColors.error;
      case 'fix':
        return Dt.accent;
      case 'done':
        return AppColors.success;
      case 'file':
        return AppColors.info;
      default:
        return Theme.of(context).hintColor;
    }
  }

  /// Live build activity timeline (v0-style): thinking → files → fixes.
Widget activityCard(BuildContext context, bool isDark) {
    final c = Get.find<AgentController>();
    final steps = c.buildSteps.toList();
    final shown =
        steps.length > 12 ? steps.sublist(steps.length - 12) : steps;
    final live = c.generating.value || c.fixing.value;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : const Color(0xFFF1EFE9),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: Dt.accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            if (live) ...[
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 6),
            ],
            Text('BUILD ACTIVITY',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    color: Theme.of(context).hintColor)),
            const Spacer(),
            if (steps.length > 12)
              Text('+${steps.length - 12} earlier',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      color: Theme.of(context).hintColor)),
          ]),
          const SizedBox(height: 6),
          for (final s in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(stepIcon(s['kind']),
                        size: 13,
                        color: stepColor(s['kind'], context)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(s['text'] ?? '',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            height: 1.4,
                            color: isDark
                                ? AppColors.textPrimary
                                : Dt.textPrimary)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

Widget planCard(BuildContext context, bool isDark) {
    final c = Get.find<AgentController>();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Row(children: [
          const Icon(LucideIcons.map,
              size: 15, color: Color(0xFFF59E0B)),
          const SizedBox(width: 7),
          Expanded(
            child: Text('Plan Ready',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFF59E0B))),
          ),
        ]),
        const SizedBox(height: 10),
        // Plan content — scrollable, max height
        Container(
          constraints: const BoxConstraints(maxHeight: 260),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: SingleChildScrollView(
            child: Text(
              c.pendingPlan.value ?? '',
              style: GoogleFonts.firaCode(
                  fontSize: 11.5, height: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () => c.buildFromPlan(),
              icon: const Icon(LucideIcons.hammer, size: 15),
              label: Text('Build',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(
                  backgroundColor: Dt.accent),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => c.pendingPlan.value = null,
            child: Text('Dismiss',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5)),
          ),
        ]),
      ]),
    );
  }

  /// Diff card — shows file-by-file changes (added/removed lines).
Widget diffCard(BuildContext context, bool isDark) {
    final c = Get.find<AgentController>();
    final diffs = c.lastDiffs;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.07)
                : Dt.hairline),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Row(children: [
          Icon(LucideIcons.gitCompare,
              size: 15,
              color: Theme.of(context).hintColor),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
                '${diffs.length} file${diffs.length == 1 ? '' : 's'} changed',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w800)),
          ),
          GestureDetector(
            onTap: () => c.lastDiffs.clear(),
            child: Icon(LucideIcons.x,
                size: 14,
                color: Theme.of(context).hintColor),
          ),
        ]),
        const SizedBox(height: 8),
        for (final entry in diffs.entries) ...[
          Text(entry.key,
              style: GoogleFonts.firaCode(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Dt.accent)),
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 160),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2E),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              child: diffLines(entry.value['old'] ?? '',
                  entry.value['new'] ?? ''),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ]),
    );
  }

  /// Build colored diff lines (green = added, red = removed).
Widget diffLines(String oldText, String newText) {
    final oldLines = oldText.split('\n');
    final newLines = newText.split('\n');
    final spans = <TextSpan>[];

    // Simple line-by-line diff ( LCS would be better but this is fast).
    final oldSet = oldLines.toSet();
    final newSet = newLines.toSet();
    final removed = oldLines.where((l) => !newSet.contains(l)).toList();
    final added = newLines.where((l) => !oldSet.contains(l)).toList();

    for (final line in removed.take(30)) {
      spans.add(TextSpan(
        text: '- $line\n',
        style: const TextStyle(
            color: Color(0xFFF48771), fontFamily: 'FiraCode', fontSize: 11, height: 1.5),
      ));
    }
    for (final line in added.take(30)) {
      spans.add(TextSpan(
        text: '+ $line\n',
        style: const TextStyle(
            color: Color(0xFFA6E3A1), fontFamily: 'FiraCode', fontSize: 11, height: 1.5),
      ));
    }
    if (spans.isEmpty) {
      spans.add(const TextSpan(
        text: '(no line changes)',
        style: TextStyle(
            color: Color(0xFF6C7086), fontFamily: 'FiraCode', fontSize: 11),
      ));
    }
    return RichText(text: TextSpan(children: spans));
  }
