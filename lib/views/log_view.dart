import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/colors.dart';
import '../services/app_log_service.dart';

class LogView extends StatelessWidget {
  const LogView({super.key});

  @override
  Widget build(BuildContext context) {
    final logs = Get.find<AppLogService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedFilter = 'ALL'.obs;
    final filters = ['ALL', 'ERROR', 'WARNING', 'INFO', 'DEBUG'];

    Color levelColor(String level) {
      switch (level) {
        case 'ERROR':
          return AppColors.error;
        case 'WARNING':
          return AppColors.warning;
        case 'INFO':
          return AppColors.success;
        case 'DEBUG':
          return const Color(0xFF94A3B8);
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
        backgroundColor: (isDark ? AppColors.bg : AppColors.bgLight).withValues(alpha: 0.8),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(color: Colors.transparent),
          ),
        ),
        title: Text('System Logs', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 22)),
        actions: [
          IconButton(
            tooltip: 'Export Logs',
            icon: const Icon(Icons.ios_share_rounded, size: 20, color: AppColors.primary),
            onPressed: () async {
              await logs.copyImportantLogs();
              Get.snackbar('Logs Copied', 'Engineering logs are now in your clipboard.', 
                snackPosition: SnackPosition.BOTTOM,
                backgroundColor: AppColors.primary,
                colorText: Colors.white);
            },
          ),
          IconButton(
            tooltip: 'Clear',
            icon: Icon(Icons.delete_sweep_rounded, size: 22, color: AppColors.error.withValues(alpha: 0.6)),
            onPressed: logs.clear,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Obx(() {
              // Read the observable eagerly: itemBuilder runs during layout,
              // after Obx has already checked for registered observables.
              final current = selectedFilter.value;
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
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                  child: ChoiceChip(
                    label: Text(filter),
                    labelStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: isSelected ? Colors.white : color,
                    ),
                    selected: isSelected,
                    selectedColor: color,
                    backgroundColor: isDark ? AppColors.surface : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isSelected ? color : (isDark ? AppColors.border : AppColors.borderLightMode),
                      ),
                    ),
                    onSelected: (_) => selectedFilter.value = filter,
                    visualDensity: VisualDensity.compact,
                    showCheckmark: false,
                  ),
                );
              },
              );
            }),
          ),
          // Log list
          Expanded(
            child: Obx(() {
              final all = logs.entries;
              final filtered = selectedFilter.value == 'ALL'
                  ? all
                  : all.where((e) => e.level == selectedFilter.value).toList();

              if (filtered.isEmpty) {
                return Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.verified_rounded, size: 32, color: AppColors.success),
                    ),
                    const SizedBox(height: 20),
                    Text('System Nominal', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black)),
                    const SizedBox(height: 8),
                    Text('No ${selectedFilter.value == 'ALL' ? '' : '${selectedFilter.value.toLowerCase()} '}logs recorded.', style: GoogleFonts.plusJakartaSans(fontSize: 14, color: Theme.of(context).hintColor, fontWeight: FontWeight.w600)),
                  ]),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final entry = filtered[index];
                  final color = levelColor(entry.level);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.surface : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isDark ? AppColors.border : AppColors.borderLightMode),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04), blurRadius: 6, offset: const Offset(0, 2))
                      ],
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                          child: Row(children: [
                            Icon(levelIcon(entry.level), color: color, size: 12),
                            const SizedBox(width: 6),
                            Text(entry.level, style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w800, color: color)),
                          ]),
                        ),
                        const Spacer(),
                        Text(_formatTime(entry.timestamp), style: GoogleFonts.plusJakartaSans(fontSize: 11, color: Theme.of(context).hintColor, fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 12),
                      SelectableText(entry.message, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black, height: 1.4)),
                      if (entry.details != null && entry.details!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.bg : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isDark ? AppColors.border : AppColors.borderLightMode),
                          ),
                          child: SelectableText(entry.details!, style: GoogleFonts.firaCode(fontSize: 11, color: isDark ? AppColors.textSecondary : const Color(0xFF475569))),
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

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
