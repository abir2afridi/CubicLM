import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/colors.dart';
import '../../theme/design_tokens.dart';

/// Pure chat formatting helpers (dates, numbers, stream cleanup).
/// Extracted from views/chat_view.dart.
bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String dayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  if (day == today) return 'chat_today'.tr;
  if (day == today.subtract(const Duration(days: 1)))
    return 'chat_yesterday'.tr;
  if (now.difference(day).inDays < 7 && now.isAfter(day)) {
    return weekday(d.weekday);
  }
  try {
    final locale = Get.locale?.languageCode ?? 'en';
    return DateFormat('yMMMd', locale).format(d);
  } catch (_) {
    return '${month(d.month)} ${d.day}, ${d.year}';
  }
}

String weekday(int w) {
  try {
    final locale = Get.locale?.languageCode ?? 'en';
    // 2024-01-01 is Monday, so offset w-1
    return DateFormat('EEE', locale).format(DateTime(2024, 1, w));
  } catch (_) {
    return ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][w - 1];
  }
}

String month(int m) {
  try {
    final locale = Get.locale?.languageCode ?? 'en';
    return DateFormat('MMM', locale).format(DateTime(2024, m, 1));
  } catch (_) {
    return [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ][m - 1];
  }
}

Widget dateChip(DateTime date, bool isDark) {
  return Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 10),
    child: Center(
      child: Text(dayLabel(date),
          style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: isDark ? AppColors.textMuted : Dt.textMuted)),
    ),
  );
}

String cleanStream(String t) => t
    .replaceAll(
        RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]'), '')
    .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
    .replaceAll('\uFFFD', '')
    .replaceAll('<|endoftext|>', '')
    .replaceAll('<|im_end|>', '')
    .replaceAll('<|end|>', '');

bool hasPrintable(String t) {
  for (final r in t.runes) {
    if (r > 32 &&
        r != 0x7F &&
        r != 0x200B &&
        r != 0x200C &&
        r != 0x200D &&
        r != 0xFEFF &&
        r != 0xFFFD) {
      return true;
    }
  }
  return false;
}

String fmtDate(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${d.day}/${d.month}/${d.year}';
}

String fmtK(int v) => v >= 1000000
    ? '${(v / 1000000).toStringAsFixed(1)}M'
    : v >= 1000
        ? '${(v / 1000).toStringAsFixed(1)}K'
        : v.toString();
