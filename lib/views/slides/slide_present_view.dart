/// Present mode: fullscreen slideshow over the shared [SlideCanvas].
///
/// - Swipe / tap zones / keyboard & D-pad arrows move, Esc closes.
/// - Speaker-notes toggle overlays presenter notes (never exported).
/// - Read-only: free-layout boxes render statically ([SlideCanvas]
///   interactive:false), so presenting can never corrupt the deck.
/// - Slides + theme are snapshots taken at entry.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../utils/slide_deck.dart';
import '../../utils/slide_palette.dart';
import 'slide_canvas.dart';

class SlidePresentView extends StatefulWidget {
  final List<Slide> slides;
  final SlideDeckTheme theme;
  final int initialIndex;

  const SlidePresentView({
    super.key,
    required this.slides,
    required this.theme,
    this.initialIndex = 0,
  });

  /// Pure navigation helper (test seam): next index for [dir] (+1/-1).
  static int stepIndex(int current, int total, int dir) {
    if (total <= 0) return 0;
    return (current + dir).clamp(0, total - 1);
  }

  @override
  State<SlidePresentView> createState() => _SlidePresentViewState();
}

class _SlidePresentViewState extends State<SlidePresentView> {
  late final PageController _pageCtrl;
  late int _page;
  late final SlidePalette _pal;
  bool _showNotes = false;
  bool _showChrome = true;

  @override
  void initState() {
    super.initState();
    _page = widget.initialIndex.clamp(0, widget.slides.length - 1);
    _pageCtrl = PageController(initialPage: _page);
    _pal = SlidePalette.fromTheme(widget.theme);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _go(int dir) {
    final next = SlidePresentView.stepIndex(_page, widget.slides.length, dir);
    if (next == _page) return;
    _pageCtrl.animateToPage(
      next,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      _go(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _go(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Get.back();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.slides.length;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: () => setState(() => _showChrome = !_showChrome),
          child: Stack(children: [
            PageView.builder(
              controller: _pageCtrl,
              itemCount: total,
              onPageChanged: (i) => setState(() {
                _page = i;
                _showNotes = false;
              }),
              itemBuilder: (_, i) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SlideCanvas(
                    slide: widget.slides[i],
                    index: i,
                    pal: _pal,
                    logoBytes: widget.theme.logoBytes,
                    aspect: isLandscape ? 16 / 9 : 4 / 3,
                    interactive: false,
                  ),
                ),
              ),
            ),
            // Edge tap zones (swipe also works).
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 56,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => _go(-1),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 56,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => _go(1),
              ),
            ),
            if (_showChrome) ...[
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 8,
                    left: 12,
                    right: 12,
                    bottom: 12,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.6),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Row(children: [
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(LucideIcons.x,
                          size: 20, color: Colors.white),
                      onPressed: () => Get.back(),
                    ),
                    const SizedBox(width: 4),
                    Text('${_page + 1} / $total',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: total <= 1 ? 1 : _page / (total - 1),
                          minHeight: 3,
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.2),
                          valueColor: AlwaysStoppedAnimation<Color>(
                              _pal.accent),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      tooltip: _showNotes
                          ? 'Hide speaker notes'
                          : 'Show speaker notes',
                      icon: Icon(
                          _showNotes
                              ? LucideIcons.micOff
                              : LucideIcons.mic,
                          size: 20,
                          color: _showNotes ? _pal.accent : Colors.white),
                      onPressed: () =>
                          setState(() => _showNotes = !_showNotes),
                    ),
                  ]),
                ),
              ),
              if (_showNotes) _notesPanel(),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _notesPanel() {
    final s = widget.slides[_page];
    final notes = [
      if (s.speakerNotes.trim().isNotEmpty) s.speakerNotes.trim(),
      if (s.notes.trim().isNotEmpty) s.notes.trim(),
    ].join('\n\n');
    return Positioned(
      left: 12,
      right: 12,
      bottom: MediaQuery.of(context).padding.bottom + 12,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Text(
          notes.isEmpty ? 'No notes for this slide.' : notes,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 13, height: 1.5, color: Colors.white),
        ),
      ),
    );
  }
}
