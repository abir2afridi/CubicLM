import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';

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
      duration: const Duration(milliseconds: 250),
      value: _expanded ? 1.0 : 0.0,
    );
    _expandAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
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
      _expanded = false;
      _liveSeconds = widget.durationSeconds ?? _liveSeconds;
      _animController.reverse();
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
    final accentColor = isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.isThinking)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: accentColor,
                        ),
                      ),
                    ),
                  if (!widget.isThinking)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(
                        Icons.lightbulb_outline_rounded,
                        size: 14,
                        color: muted,
                      ),
                    ),
                  Text(
                    _label,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: widget.isThinking ? accentColor : muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _expanded ? 0.25 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: muted,
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: MarkdownBody(
                data: widget.thought.trim(),
                selectable: true,
                styleSheet: widget.styleSheet,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _label {
    final seconds = widget.durationSeconds ?? _liveSeconds;
    if (widget.isThinking) {
      return seconds > 0 ? 'Thinking for ${seconds}s…' : 'Thinking…';
    }
    return seconds > 0 ? 'Thought for ${seconds}s' : 'Thought';
  }
}
