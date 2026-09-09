import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/colors.dart';

class CitationChip extends StatelessWidget {
  final int index;
  final String source;
  final int? page;
  final VoidCallback? onTap;

  const CitationChip({
    super.key,
    required this.index,
    required this.source,
    this.page,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return InkWell(
      onTap: onTap ?? () => _showSourceDialog(context, isDark),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 0.5),
        ),
        child: Text(
          '[$index]',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }

  void _showSourceDialog(BuildContext context, bool isDark) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        title: Text(
          'Source [$index]',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'File: $source',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
            ),
            if (page != null) ...[
              const SizedBox(height: 4),
              Text(
                'Page: $page',
                style: GoogleFonts.plusJakartaSans(fontSize: 13),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
