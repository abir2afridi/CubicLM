import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../controllers/chat_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../core/colors.dart';
import '../../ffi/sd_ffi_bindings.dart';
import '../../services/local_image_service.dart';
import '../../theme/design_tokens.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/thinking_orb.dart';

/// Small reusable chat widgets (tiles, pulsing dots, step buttons).
/// Extracted from views/chat_view.dart.
// ── Add-to-chat tile (56dp muted circle + label) ──
class AddTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const AddTile(
      {super.key,
      required this.icon,
      required this.label,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? Theme.of(context).cardColor : Dt.card,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(children: [
            AppIconCircle(icon: icon, diameter: Dt.circleIconDiameter),
            const SizedBox(height: 8),
            Text(label,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Dt.textSecondary)),
          ]),
        ),
      ),
    );
  }
}

// ── Pulsing Dot ──
class PulsingDot extends StatefulWidget {
  const PulsingDot({super.key});

  @override
  State<PulsingDot> createState() => PulsingDotState();
}

class PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.8, end: 1.2)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 10,
        height: 10,
        decoration:
            const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
      ),
    );
  }
}

class PulsingTimerDot extends StatefulWidget {
  const PulsingTimerDot({super.key});

  @override
  State<PulsingTimerDot> createState() => PulsingTimerDotState();
}

class PulsingTimerDotState extends State<PulsingTimerDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _c,
      child: Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
            color: AppColors.primary, shape: BoxShape.circle),
      ),
    );
  }
}

class StepButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const StepButton(
      {super.key,
      required this.icon,
      required this.enabled,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? AppColors.primary
        : Theme.of(context).hintColor.withValues(alpha: 0.3);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 34,
        height: 34,
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}

// ── Image Generation Indicator ──
class ImageGenIndicator extends StatefulWidget {
  final ChatController controller;
  final bool isDark;
  const ImageGenIndicator(
      {super.key, required this.controller, required this.isDark});

  @override
  State<ImageGenIndicator> createState() => ImageGenIndicatorState();
}

class ImageGenIndicatorState extends State<ImageGenIndicator> {
  late Timer _timer;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final start = widget.controller.imageGenStartTime.value;
      if (start != null) {
        setState(() {
          _elapsedSeconds = DateTime.now().difference(start).inSeconds;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String _fmtEta(int seconds) {
    if (seconds <= 0) return '';
    if (seconds < 60) return '~$seconds s remaining';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s > 0 ? '~$m m $s s remaining' : '~$m m remaining';
  }

  String _fmtElapsed(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s > 0 ? '${m}m ${s}s' : '${m}m';
  }

  Widget _backendChip(BuildContext context) {
    final localImage = Get.find<LocalImageService>();
    final backend = localImage.currentBackend.value;
    final isCpu = backend == Backend.cpu;
    final color = isCpu ? AppColors.warning : AppColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Text(
        isCpu
            ? 'CPU · Extended'
            : backend.displayName.split(' ').first.toUpperCase(),
        style: GoogleFonts.plusJakartaSans(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final step = widget.controller.imageGenStep.value;
      final total = widget.controller.imageGenTotal.value;
      final eta = widget.controller.imageGenEstimatedSecs.value;
      final decoding = widget.controller.imageGenDecoding.value;
      final hasProgress = total > 0;
      final pct = hasProgress ? (step / total).clamp(0.0, 1.0) : 0.0;
      final isDone = decoding || (hasProgress && step >= total);

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Image synthesis orb — user-selected state (default Composing).
          Builder(builder: (_) {
            final sel = Get.find<SettingsController>().orbImageAnim.value;
            final fixed = orbStateFromName(sel);
            return fixed != null
                ? ThinkingOrb(size: 48, state: fixed)
                : const ThinkingOrb(size: 48, autoCycle: true);
          }),
          const SizedBox(height: 12),
          Text(
            isDone ? 'chat_decoding'.tr : 'chat_synthesizing'.tr,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: widget.isDark ? Colors.white : Colors.black,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (hasProgress) ...[
            const SizedBox(height: 12),
            Container(
              width: 180,
              height: 6,
              decoration: BoxDecoration(
                color: (widget.isDark ? Colors.white : Colors.black)
                    .withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(3),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: isDone ? 1.0 : pct,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: AppColors.userGradient,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isDone
                  ? 'chat_reconstructing'.tr
                  : '${(pct * 100).toStringAsFixed(0)}% · Step $step / $total',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: Theme.of(context).hintColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            _backendChip(context),
            const SizedBox(height: 5),
            Text(
              'Runtime: ${_fmtElapsed(_elapsedSeconds)}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                color: Theme.of(context).hintColor.withValues(alpha: 0.5),
                fontWeight: FontWeight.w600,
              ),
            ),
            if (eta > 0 && step >= 2 && !isDone) ...[
              const SizedBox(height: 4),
              Text(
                _fmtEta(eta),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  color: AppColors.primary.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 16),
            GestureDetector(
              onTap: widget.controller.stopGenerating,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.close_rounded,
                        size: 14, color: AppColors.error),
                    const SizedBox(width: 6),
                    Text(
                      'chat_abort'.tr,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: AppColors.error,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      );
    });
  }
}

// ── Animated App Name (splash/empty state) ──
class AnimatedAppName extends StatefulWidget {
  final bool isDark;
  const AnimatedAppName({super.key, required this.isDark});
  @override
  State<AnimatedAppName> createState() => AnimatedAppNameState();
}

class AnimatedAppNameState extends State<AnimatedAppName>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - t)),
            child: Transform.scale(
              scale: 0.96 + 0.04 * t,
              child: child,
            ),
          ),
        );
      },
      child: AnimatedBuilder(
        animation: _shimmer,
        builder: (context, child) {
          final p = _shimmer.value;
          // shimmer travels left -> right, subtle
          final dx = -1.2 + 2.6 * p;
          return ShaderMask(
            shaderCallback: (bounds) {
              final base = widget.isDark ? Colors.white : Dt.textPrimary;
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
            fontSize: 44,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.8,
            height: 1.0,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// ── Blinking Cursor ──
class BlinkingCursor extends StatefulWidget {
  final Color color;
  const BlinkingCursor({super.key, required this.color});
  @override
  State<BlinkingCursor> createState() => BlinkingCursorState();
}

class BlinkingCursorState extends State<BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Opacity(
            opacity: _c.value,
            child: Container(
                width: 3,
                height: 18,
                margin: const EdgeInsets.only(left: 4, bottom: 2),
                decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(2)))));
  }
}
