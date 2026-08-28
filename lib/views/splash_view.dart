import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/routes.dart';
import '../theme/design_tokens.dart';

class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView>
    with TickerProviderStateMixin {
  late final AnimationController _shimmer;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 760))
      ..forward();
    _fadeIn = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);

    // Smooth exit: fade out then instant switch (fade handled here, no route transition needed).
    Future.delayed(const Duration(milliseconds: 1380), () async {
      if (!mounted) return;
      try {
        await _fadeCtrl.reverse().orCancel;
      } catch (_) {}
      if (!mounted) return;
      Get.offAllNamed(AppRoutes.home);
    });
  }

  @override
  void dispose() {
    _shimmer.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Dt.canvasDark : Dt.canvas;

    return Scaffold(
      backgroundColor: bg,
      body: Center(
        child: FadeTransition(
          opacity: _fadeIn,
          child: RepaintBoundary(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated app name — no logo/icon (RepaintBoundary isolates shimmer)
                RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _shimmer,
                    builder: (context, child) {
                      final p = _shimmer.value;
                      final dx = -1.2 + 2.6 * p;
                      return ShaderMask(
                        shaderCallback: (bounds) {
                          final base = isDark ? Colors.white : Dt.textPrimary;
                          return LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [base, base, Dt.accent, base, base],
                            stops: [
                              (dx - 0.28).clamp(0.0, 1.0),
                              (dx - 0.08).clamp(0.0, 1.0),
                              dx.clamp(0.0, 1.0),
                              (dx + 0.08).clamp(0.0, 1.0),
                              (dx + 0.28).clamp(0.0, 1.0),
                            ],
                          ).createShader(bounds);
                        },
                        blendMode: BlendMode.srcIn,
                        child: child,
                      );
                    },
                    child: Text(
                      'CubicLM',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.8,
                        height: 1.0,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              // Subtitle with fade
              Text(
                'Think • Create • Explore',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.5)
                      : Dt.textSecondary.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 32),
              // Minimal loading indicator
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Dt.accent.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}
