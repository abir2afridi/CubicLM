import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/colors.dart';

class ChatBranchTimeline extends StatelessWidget {
  final int total;
  final int current;
  final Function(int) onSelect;

  const ChatBranchTimeline({
    super.key,
    required this.total,
    required this.current,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (total <= 1) return const SizedBox.shrink();
    
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(total, (i) {
          final active = i == current;
          return GestureDetector(
            onTap: () => onSelect(i),
            child: Container(
              width: 24,
              height: 24,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? AppColors.primary : Colors.transparent,
                border: Border.all(
                  color: active ? AppColors.primary : AppColors.primary.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Text(
                  '${i + 1}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: active ? Colors.white : AppColors.primary,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
