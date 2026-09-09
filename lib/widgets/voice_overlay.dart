import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../core/colors.dart';

/// A full-screen overlay for the immersive voice mode.
class VoiceOverlay extends StatefulWidget {
  final VoidCallback onStop;
  final bool isListening;
  final bool isSpeaking;
  final String text;

  const VoiceOverlay({
    super.key,
    required this.onStop,
    required this.isListening,
    required this.isSpeaking,
    this.text = '',
  });

  @override
  State<VoiceOverlay> createState() => _VoiceOverlayState();
}

class _VoiceOverlayState extends State<VoiceOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Gradient Background
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 1.5,
                      colors: [
                        AppColors.primary.withValues(alpha: 0.15 + sin(_controller.value * pi) * 0.05),
                        Colors.black,
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated Orb/Waveform
                _AnimatedVoiceOrb(
                  animation: _controller,
                  isActive: widget.isListening || widget.isSpeaking,
                ),
                const SizedBox(height: 60),
                // Text Status
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      widget.text.isEmpty
                          ? (widget.isListening
                              ? 'Listening...'
                              : (widget.isSpeaking ? 'Speaking...' : 'CubicLM'))
                          : widget.text,
                      key: ValueKey(widget.text + widget.isListening.toString()),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Close Button
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: widget.onStop,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: Color(0xFF222222),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.x, color: Colors.white, size: 28),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedVoiceOrb extends StatelessWidget {
  final Animation<double> animation;
  final bool isActive;

  const _AnimatedVoiceOrb({required this.animation, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: List.generate(3, (i) {
            final scale = 1.0 + (isActive ? sin(animation.value * 2 * pi + i) * 0.2 : 0.0);
            final opacity = 0.3 - (i * 0.1);
            return Container(
              width: 120 + (i * 40),
              height: 120 + (i * 40),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: opacity),
                  width: 2,
                ),
              ),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: opacity * 0.5),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
