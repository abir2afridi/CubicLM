import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/colors.dart';
import '../theme/design_tokens.dart';
import '../services/app_log_service.dart';

class LogView extends StatelessWidget {
  const LogView({super.key});

  @override
  Widget build(BuildContext context) {
    final logs = Get.find<AppLogService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showHealth = true.obs;

    Color levelColor(String level) {
      switch (level) {
        case 'ERROR':
          return AppColors.error;
        case 'WARNING':
          return AppColors.warning;
        case 'INFO':
          return AppColors.success;
        case 'DEBUG':
          return Dt.textMuted;
        default:
          return Theme.of(context).hintColor;
      }
    }

    IconData levelIcon(String level) {
      switch (level) {
        case 'ERROR':
          return Icons.error_outline_rounded;
        case 'WARNING':
          return Icons.warning_amber_rounded;
        case 'INFO':
          return Icons.info_outline_rounded;
        case 'DEBUG':
          return Icons.bug_report_outlined;
        default:
          return Icons.list_alt_rounded;
      }
    }

    return Scaffold(
      backgroundColor: isDark ? AppColors.bg : AppColors.bgLight,
      appBar: AppBar(
        backgroundColor:
            (isDark ? AppColors.bg : AppColors.bgLight).withValues(alpha: 0.8),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(color: Colors.transparent),
          ),
        ),
        title: Text('System Logs',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800, fontSize: 22)),
        actions: [
          IconButton(
            tooltip: 'Health Report',
            icon: Obx(() => Icon(
                  Icons.health_and_safety_rounded,
                  size: 20,
                  color: logs.detectedPatterns.isNotEmpty
                      ? AppColors.warning
                      : AppColors.success,
                )),
            onPressed: () => showHealth.value = !showHealth.value,
          ),
          IconButton(
            tooltip: 'Export Logs',
            icon: const Icon(Icons.ios_share_rounded,
                size: 20, color: AppColors.primary),
            onPressed: () async {
              final text = await logs.exportFullLogs();
              await Clipboard.setData(ClipboardData(text: text));
              Get.snackbar('Logs Copied',
                  'Full diagnostic report copied to clipboard.',
                  snackPosition: SnackPosition.BOTTOM,
                  backgroundColor: AppColors.primary,
                  colorText: Colors.white);
            },
          ),
          IconButton(
            tooltip: 'Clear',
            icon: Icon(Icons.delete_sweep_rounded,
                size: 22,
                color: AppColors.error.withValues(alpha: 0.6)),
            onPressed: logs.clear,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              onChanged: (v) => logs.searchQuery.value = v,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'Search logs...',
                hintStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).hintColor),
                prefixIcon: Icon(Icons.search_rounded,
                    size: 18, color: Theme.of(context).hintColor),
                suffixIcon: Obx(() => logs.searchQuery.value.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear_rounded,
                            size: 16, color: Theme.of(context).hintColor),
                        onPressed: () => logs.searchQuery.value = '',
                      )
                    : const SizedBox.shrink()),
                filled: true,
                fillColor: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Dt.pillMuted,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // Category chips (horizontal scroll)
          SizedBox(
            height: 44,
            child: Obx(() {
              final current = logs.selectedCategory.value;
              return ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _catChip(
                    context,
                    isDark,
                    label: 'All',
                    selected: current == null,
                    color: isDark ? Colors.white : Colors.black,
                    onTap: () => logs.selectedCategory.value = null,
                  ),
                  for (final cat in LogCategory.values)
                    _catChip(
                      context,
                      isDark,
                      label: cat.label,
                      selected: current == cat,
                      color: _catColor(cat),
                      onTap: () => logs.selectedCategory.value =
                          current == cat ? null : cat,
                    ),
                ],
              );
            }),
          ),

          // Level filter chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              height: 50,
              child: Obx(() {
                final current = logs.selectedLevel.value;
                final filters = ['ALL', 'ERROR', 'WARNING', 'INFO', 'DEBUG'];
                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: filters.length,
                  itemBuilder: (context, index) {
                    final filter = filters[index];
                    final isSelected = current == filter;
                    final color = filter == 'ALL'
                        ? (isDark ? Colors.white : Colors.black)
                        : levelColor(filter);
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 6),
                      child: ChoiceChip(
                        label: Text(filter),
                        labelStyle: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: isSelected ? Colors.white : color,
                        ),
                        selected: isSelected,
                        selectedColor: color,
                        backgroundColor:
                            isDark ? AppColors.surface : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: isSelected
                                ? color
                                : (isDark
                                    ? AppColors.border
                                    : AppColors.borderLightMode),
                          ),
                        ),
                        onSelected: (_) =>
                            logs.selectedLevel.value = filter,
                        visualDensity: VisualDensity.compact,
                        showCheckmark: false,
                      ),
                    );
                  },
                );
              }),
            ),
          ),

          // Health diagnostics panel
          Obx(() {
            if (!showHealth.value) return const SizedBox.shrink();
            final patterns = logs.detectedPatterns;
            final errCount = logs.errorCount;
            final warnCount = logs.warningCount;

            if (patterns.isEmpty && errCount == 0) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color:
                      AppColors.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.check_circle_rounded,
                          size: 18, color: AppColors.success),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('System Healthy',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.success)),
                          const SizedBox(height: 2),
                          Text(
                              'No issues detected. ${logs.entries.length} logs recorded.',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  color: Theme.of(context).hintColor)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.health_and_safety_rounded,
                          size: 16, color: AppColors.warning),
                      const SizedBox(width: 8),
                      Text('Diagnostics',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppColors.warning)),
                      const Spacer(),
                      Text(
                          '$errCount errors · $warnCount warnings',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: Theme.of(context).hintColor)),
                    ],
                  ),
                  if (patterns.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ...patterns.take(3).map((p) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: AppColors.error
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(Icons.bug_report_rounded,
                                    size: 12, color: AppColors.error),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        '${p.title} (${p.occurrences}x)',
                                        style: GoogleFonts.plusJakartaSans(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 2),
                                    Text(p.fix,
                                        style: GoogleFonts.plusJakartaSans(
                                            fontSize: 11,
                                            color: Theme.of(context)
                                                .hintColor)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )),
                    if (patterns.length > 3)
                      Text('+ ${patterns.length - 3} more patterns',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              color: Theme.of(context).hintColor)),
                  ],
                ],
              ),
            );
          }),

          // Log list
          Expanded(
            child: Obx(() {
              final filtered = logs.filteredEntries;

              if (filtered.isEmpty) {
                return Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color:
                                AppColors.success.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(Icons.verified_rounded,
                              size: 32, color: AppColors.success),
                        ),
                        const SizedBox(height: 20),
                        Text('System Nominal',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? Colors.white
                                    : Colors.black)),
                        const SizedBox(height: 8),
                        Text(
                            'No ${logs.selectedLevel.value == 'ALL' ? '' : '${logs.selectedLevel.value.toLowerCase()} '}logs recorded.',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                color: Theme.of(context).hintColor,
                                fontWeight: FontWeight.w600)),
                      ]),
                );
              }

              return ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final entry = filtered[index];
                  final color = levelColor(entry.level);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.02)
                          : Dt.pillMuted
                              .withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                  color:
                                      color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(7)),
                              child: Row(children: [
                                Icon(levelIcon(entry.level),
                                    color: color, size: 11),
                                const SizedBox(width: 5),
                                Text(entry.level,
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        color: color)),
                              ]),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _catColor(entry.category)
                                      .withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(entry.category.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color:
                                            _catColor(entry.category))),
                              ),
                            ),
                            const Spacer(),
                            Text(_formatTime(entry.timestamp),
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
                                    color:
                                        Theme.of(context).hintColor,
                                    fontWeight: FontWeight.w600)),
                          ]),
                          const SizedBox(height: 10),
                          SelectableText(entry.message,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white
                                      : Colors.black,
                                  height: 1.4)),
                          if (entry.details != null &&
                              entry.details!.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.black
                                        .withValues(alpha: 0.2)
                                    : Colors.white
                                        .withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: isDark
                                        ? Colors.white
                                            .withValues(alpha: 0.05)
                                        : Colors.black
                                            .withValues(alpha: 0.03)),
                              ),
                              child: SelectableText(entry.details!,
                                  style: GoogleFonts.firaCode(
                                      fontSize: 10,
                                      color: isDark
                                          ? AppColors.textSecondary
                                          : Dt.textSecondary)),
                            ),
                          ],
                        ]),
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _catChip(BuildContext context, bool isDark,
      {required String label,
      required bool selected,
      required Color color,
      required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? color : (isDark ? AppColors.border : AppColors.borderLightMode),
              width: 1,
            ),
          ),
          child: Text(label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected ? color : Theme.of(context).hintColor)),
        ),
      ),
    );
  }

  Color _catColor(LogCategory cat) {
    switch (cat) {
      case LogCategory.system:
        return const Color(0xFF6366F1);
      case LogCategory.model:
        return const Color(0xFFF59E0B);
      case LogCategory.cloud:
        return const Color(0xFF3B82F6);
      case LogCategory.chat:
        return const Color(0xFF10B981);
      case LogCategory.server:
        return const Color(0xFF8B5CF6);
      case LogCategory.image:
        return const Color(0xFFEC4899);
    }
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
