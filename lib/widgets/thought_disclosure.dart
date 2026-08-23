import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/colors.dart';

class ThoughtDisclosure extends StatefulWidget {
  final String thought;
  final bool isThinking;
  final int? durationSeconds;
  final MarkdownStyleSheet styleSheet;

  const ThoughtDisclosure({
    super.key,
    required this.thought,
    required this.styleSheet,
    this.isThinking = false,
    this.durationSeconds,
  });

  @override
  State<ThoughtDisclosure> createState() => _ThoughtDisclosureState();
}

class _ThoughtDisclosureState extends State<ThoughtDisclosure>
    with SingleTickerProviderStateMixin {
  late bool _expanded;
  late DateTime _startedAt;
  Timer? _timer;
  int _liveSeconds = 0;
  late AnimationController _animController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _expanded = widget.isThinking;
    _startedAt = DateTime.now();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: _expanded ? 1.0 : 0.0,
    );
    _expandAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutQuart,
    );
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant ThoughtDisclosure oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isThinking && !oldWidget.isThinking) {
      _expanded = true;
      _startedAt = DateTime.now();
      _liveSeconds = 0;
      _animController.forward();
    } else if (!widget.isThinking && oldWidget.isThinking) {
      // Don't auto-collapse when done thinking, let user decide
      _liveSeconds = widget.durationSeconds ?? _liveSeconds;
    }

    _syncTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  void _syncTimer() {
    if (!widget.isThinking) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _liveSeconds = DateTime.now().difference(_startedAt).inSeconds;
      });
    });
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _animController.forward();
    } else {
      _animController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = Theme.of(context).hintColor;
    const accentColor = AppColors.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.isThinking)
                  const Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accentColor,
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.terminal_rounded,
                      size: 16,
                      color: muted.withValues(alpha: 0.7),
                    ),
                  ),
                Text(
                  _label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: widget.isThinking ? accentColor : muted.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: _expanded ? 0.25 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: muted.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Content
        SizeTransition(
          sizeFactor: _expandAnimation,
          axisAlignment: -1.0,
          child: Container(
            margin: const EdgeInsets.only(top: 4, bottom: 12),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.03)
                  : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
              border: Border(
                left: BorderSide(
                  color: accentColor.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
            ),
            child: MarkdownBody(
              data: widget.thought.trim(),
              selectable: true,
              styleSheet: widget.styleSheet,
            ),
          ),
        ),
      ],
    );
  }

  String get _label {
    final seconds = widget.durationSeconds ?? _liveSeconds;
    if (widget.isThinking) {
      return seconds > 0 ? 'Analyzing Path (${seconds}s)…' : 'Initializing…';
    }
    return seconds > 0 ? 'Analysis Complete (${seconds}s)' : 'Process Logs';
  }
}
