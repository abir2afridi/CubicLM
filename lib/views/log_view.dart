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
          return const Color(0xFF8E8E93);
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
      backgroundColor: isDark ? Colors.black : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : const Color(0xFFF2F2F7),
        title: Text('Logs', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Share logs',
            icon: Icon(Icons.ios_share_rounded, size: 20, color: isDark ? const Color(0xFF0A84FF) : AppColors.primary),
            onPressed: () async {
              await logs.copyImportantLogs();
              Get.snackbar('Copied', 'Important logs copied to clipboard.', snackPosition: SnackPosition.BOTTOM);
            },
          ),
          IconButton(
            tooltip: 'Clear logs',
            icon: Icon(Icons.delete_outline_rounded, size: 20, color: Theme.of(context).hintColor),
            onPressed: logs.clear,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Obx(() => ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: filters.length,
              itemBuilder: (context, index) {
                final filter = filters[index];
                final isSelected = selectedFilter.value == filter;
                final color = filter == 'ALL'
                    ? (isDark ? Colors.white : Colors.black)
                    : levelColor(filter);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: ChoiceChip(
                    label: Text(filter),
                    labelStyle: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : color,
                    ),
                    selected: isSelected,
                    selectedColor: color,
                    backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: isSelected ? color : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA)),
                      ),
                    ),
                    onSelected: (_) => selectedFilter.value = filter,
                    visualDensity: VisualDensity.compact,
                  ),
                );
              },
            )),
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
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.check_circle_outline_rounded, size: 28, color: AppColors.success),
                    ),
                    const SizedBox(height: 16),
                    Text('All Clear', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black)),
                    const SizedBox(height: 6),
                    Text('No ${selectedFilter.value == 'ALL' ? '' : '${selectedFilter.value.toLowerCase()} '}logs captured yet.', style: GoogleFonts.inter(fontSize: 15, color: Theme.of(context).hintColor)),
                  ]),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final entry = filtered[index];
                  final color = levelColor(entry.level);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(
                          width: 24, height: 24,
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                          child: Icon(levelIcon(entry.level), color: color, size: 14),
                        ),
                        const SizedBox(width: 8),
                        Text(entry.level, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
                        const Spacer(),
                        Text(_formatTime(entry.timestamp), style: GoogleFonts.inter(fontSize: 12, color: Theme.of(context).hintColor)),
                      ]),
                      const SizedBox(height: 10),
                      SelectableText(entry.message, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: isDark ? Colors.white : Colors.black)),
                      if (entry.details != null && entry.details!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SelectableText(entry.details!, style: GoogleFonts.firaCode(fontSize: 11, color: Theme.of(context).hintColor)),
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
