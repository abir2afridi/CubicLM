import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/inference_service.dart';

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomRight: Radius.circular(20),
            bottomLeft: Radius.circular(6),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (index) {
                    final delay = index * 0.2;
                    final t = ((_controller.value - delay) % 1.0).clamp(0.0, 1.0);
                    final pulse = (math.sin(t * math.pi) * 0.75).clamp(0.0, 1.0);

                    return Container(
                      margin: EdgeInsets.only(right: index < 2 ? 5 : 0),
                      child: Opacity(
                        opacity: 0.25 + pulse,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.6)
                                : Colors.black.withValues(alpha: 0.35),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
            const SizedBox(width: 10),
            Obx(() {
              final inference = Get.find<InferenceService>();
              if (inference.tokenCount.value > 0) {
                return Text(
                  '${inference.tokenCount.value} tokens',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: Theme.of(context).hintColor,
                    fontWeight: FontWeight.w400,
                  ),
                );
              }
              return Text(
                'thinking…',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Theme.of(context).hintColor,
                  fontWeight: FontWeight.w400,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
