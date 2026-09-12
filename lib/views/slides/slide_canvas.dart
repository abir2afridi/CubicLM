/// Shared slide renderer: the exact canvas the editor previews,
/// reused by Present mode. Pure params in (slide, palette, logo) — no
/// controllers, so it stays widget-testable.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../theme/design_tokens.dart';
import '../../utils/slide_deck.dart';
import '../../utils/slide_palette.dart';
import 'slide_charts.dart';
import 'slide_painters.dart';

class SlideCanvas extends StatelessWidget {
  final Slide slide;
  final int index;
  final SlidePalette pal;
  final List<int>? logoBytes;
  final double aspect;
  final bool interactive;

  const SlideCanvas({
    super.key,
    required this.slide,
    required this.index,
    required this.pal,
    this.logoBytes,
    this.aspect = 4 / 3,
    this.interactive = true,
  });

  @override
  Widget build(BuildContext context) {
    final Slide s = slide;
    final hasImage = s.imageBytes != null && s.imageBytes!.isNotEmpty;
    final hasUrl = s.imageUrl != null && s.imageUrl!.isNotEmpty;
    final showPoints = s.points.take(4).toList();
    final hidden = s.points.length - showPoints.length;
    final logo = logoBytes;

    return AspectRatio(
      aspectRatio: aspect,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [pal.bg, pal.bgDeep],
          ),
          border: Border.all(color: pal.cardBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: s.freeLayout
            ? LayoutBuilder(
                builder: (_, cons) => freeStack(
                  context,
                  s,
                  cons.maxWidth,
                  cons.maxHeight,
                  titleColor: pal.title,
                  bodyColor: pal.body,
                  titleBase: 17,
                  bodyBase: 11.5,
                  accent: pal.accent,
                  interactive: interactive,
                ),
              )
            : Stack(
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (hasImage)
                      SizedBox(
                        height: 110,
                        child: Image.memory(
                          Uint8List.fromList(s.imageBytes!),
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox(height: 110),
                        ),
                      )
                    else if (hasUrl)
                      SizedBox(
                        height: 110,
                        child: Image.network(
                          s.imageUrl!,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox(height: 110),
                        ),
                      )
                      else if (s.wantsImage)
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: pal.accent.withValues(alpha: 0.12),
                          border: Border(
                            bottom: BorderSide(color: pal.accent, width: 1),
                          ),
                        ),
                        child: Row(children: [
                          Icon(LucideIcons.imagePlus,
                              size: 13, color: pal.accent),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              s.imagePrompt.trim().isEmpty
                                  ? 'IMAGE SPACE'
                                  : s.imagePrompt.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _st(pal, false,
                                  size: 10.5,
                                  weight: FontWeight.w600,
                                  color: pal.body),
                            ),
                          ),
                        ]),
                      ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                        child: Stack(
                          children: [
                            _pptContentByLayout(
                                s, index, showPoints, hidden, pal),
                            Align(
                              alignment: Alignment.bottomRight,
                              child: Text('${index + 1}',
                                  style: _st(pal, true,
                                      size: 10,
                                      weight: FontWeight.w800,
                                      color: pal.muted)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ]),
                  if (logo != null)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Image.memory(
                        Uint8List.fromList(logo),
                        height: 20,
                        fit: BoxFit.contain,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
  /// Theme-aware slide text: heading/body family from the active preset,
  /// whitelisted + guarded so model-invented or offline-missing families
  /// fall back instead of breaking the canvas.
  TextStyle _st(SlidePalette pal, bool heading,
      {double? size,
      FontWeight? weight,
      double? height,
      Color? color,
      FontStyle? style}) {
    final fam = heading ? pal.headingFont : pal.bodyFont;
    try {
      return GoogleFonts.getFont(fam,
          fontSize: size,
          fontWeight: weight,
          height: height,
          color: color,
          fontStyle: style);
    } catch (_) {
      return GoogleFonts.plusJakartaSans(
          fontSize: size,
          fontWeight: weight,
          height: height,
          color: color,
          fontStyle: style);
    }
  }

  Widget _pptContentByLayout(
      Slide s, int index, List<String> showPoints, int hidden, SlidePalette pal) {
    switch (s.layout) {
      case 'title':
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                s.title.isEmpty ? 'Untitled' : s.title,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: _st(pal, true,
                    size: 19,
                    weight: FontWeight.w800,
                    height: 1.25,
                    color: pal.title),
              ),
              if (s.subtitle.isNotEmpty || showPoints.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                    width: 36,
                    height: 2.5,
                    decoration: BoxDecoration(
                        color: pal.accent,
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 8),
                Text(
                  s.subtitle.isNotEmpty ? s.subtitle : showPoints.first,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _st(pal, false,
                      size: 12,
                      weight: FontWeight.w500,
                      color: pal.body),
                ),
              ],
            ],
          ),
        );

      case 'quote':
        final quoteText = s.points.isNotEmpty ? s.points.first : s.title;
        final author = s.quoteAuthor.isNotEmpty
            ? s.quoteAuthor
            : (s.points.length > 1 ? s.points[1] : '');
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(LucideIcons.quote, size: 24, color: pal.accent),
              const SizedBox(height: 8),
              Text(
                '"$quoteText"',
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: _st(pal, true,
                    size: 14.5,
                    style: FontStyle.italic,
                    weight: FontWeight.w600,
                    height: 1.35,
                    color: pal.title),
              ),
              if (author.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '- $author',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: _st(pal, false,
                      size: 11.5,
                      weight: FontWeight.w700,
                      color: pal.accent),
                ),
              ],
            ],
          ),
        );

      case 'stats':
        final statsItems = s.stats.isNotEmpty
            ? s.stats
            : s.points.take(3).map((p) {
                final match =
                    RegExp(r'^([\d%+\$\.\s\w]+)[:\-–]\s*(.+)$').firstMatch(p);
                if (match != null) {
                  return {
                    'value': match.group(1)!.trim(),
                    'label': match.group(2)!.trim()
                  };
                }
                return {'value': '•', 'label': p};
              }).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.title.isEmpty ? 'Key Statistics' : s.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _st(pal, true,
                  size: 15, weight: FontWeight.w800, color: pal.title),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Row(
                children: [
                  for (final item in statsItems.take(3))
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2.5),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: pal.card,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: pal.accentBorder),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              item['value'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _st(pal, true,
                                  size: 17,
                                  weight: FontWeight.w900,
                                  color: pal.accent),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              item['label'] ?? '',
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: _st(pal, false,
                                  size: 9.5, color: pal.body),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );

      case 'comparison':
        final col1 = s.columns.isNotEmpty
            ? s.columns[0]
            : s.points.take((s.points.length / 2).ceil()).toList();
        final col2 = s.columns.length > 1
            ? s.columns[1]
            : s.points.skip((s.points.length / 2).ceil()).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.title.isEmpty ? 'Comparison' : s.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _st(pal, true,
                  size: 15, weight: FontWeight.w800, color: pal.title),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: pal.card,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: pal.cardBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final p in col1.take(3))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text('• $p',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: _st(pal, false,
                                      size: 10, color: pal.body)),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: pal.accent.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: pal.accentBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final p in col2.take(3))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text('✓ $p',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: _st(pal, false,
                                      size: 10, color: pal.body)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

      case 'timeline':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.title.isEmpty ? 'Timeline' : s.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _st(pal, true,
                  size: 15, weight: FontWeight.w800, color: pal.title),
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < showPoints.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: pal.accent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${i + 1}',
                        style: _st(pal, true,
                            size: 9.5,
                            weight: FontWeight.w800,
                            color: pal.onAccent),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        showPoints[i],
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _st(pal, false,
                            size: 10.5, color: pal.body),
                      ),
                    ),
                  ],
                ),
              ),
            if (hidden > 0)
              Text('+$hidden more steps',
                  style: _st(pal, false,
                      size: 9.5,
                      weight: FontWeight.w700,
                      color: pal.muted)),
          ],
        );

      case 'summary':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.checkCircle2,
                    size: 15, color: pal.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    s.title.isEmpty ? 'Key Takeaways' : s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _st(pal, true,
                        size: 15,
                        weight: FontWeight.w800,
                        color: pal.title),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final p in showPoints)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('✓ ',
                        style: TextStyle(
                            color: pal.accent,
                            fontWeight: FontWeight.w900,
                            fontSize: 10.5)),
                    Expanded(
                      child: Text(p,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: _st(pal, false,
                              size: 10.5,
                              height: 1.35,
                              color: pal.body)),
                    ),
                  ],
                ),
              ),
            if (hidden > 0)
              Text('+$hidden more',
                  style: _st(pal, false,
                      size: 9.5,
                      weight: FontWeight.w700,
                      color: pal.muted)),
          ],
        );

      case 'chart':
        return chartContent(s, pal);

      case 'diagram':
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                s.title.isEmpty ? 'Process Flow' : s.title,
                style: _st(pal, true,
                    size: 15,
                    weight: FontWeight.w800,
                    color: pal.title),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: CustomPaint(
                  painter: DiagramPainter(s.diagram ?? '', pal.isDark),
                  size: Size.infinite,
                ),
              ),
            ],
          ),
        );

      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.title.isEmpty ? 'Untitled' : s.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _st(pal, true,
                  size: 16.5,
                  weight: FontWeight.w800,
                  height: 1.2,
                  color: pal.title),
            ),
            const SizedBox(height: 6),
            for (var j = 0; j < showPoints.length; j++)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (s.icons != null && j < s.icons!.length)
                      Padding(
                        padding: const EdgeInsets.only(top: 2, right: 6),
                        child: Icon(_getIcon(s.icons![j]), size: 12, color: pal.accent),
                      )
                    else
                      Text('▸ ',
                          style: TextStyle(
                              color: pal.accent,
                              fontWeight: FontWeight.w800,
                              fontSize: 11)),
                    Expanded(
                      child: Text(showPoints[j],
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: _st(pal, false,
                              size: 11,
                              height: 1.35,
                              color: pal.body)),
                    ),
                  ],
                ),
              ),
            if (hidden > 0)
              Text('+$hidden more',
                  style: _st(pal, false,
                      size: 10,
                      weight: FontWeight.w700,
                      color: pal.muted)),
          ],
        );
    }
  }
  IconData _getIcon(String name) {
    switch (name.toLowerCase()) {
      case 'zap': return LucideIcons.zap;
      case 'check': return LucideIcons.check;
      case 'star': return LucideIcons.star;
      case 'bar-chart': return LucideIcons.barChart;
      case 'users': return LucideIcons.users;
      case 'palette': return LucideIcons.palette;
      case 'image': return LucideIcons.image;
      case 'link': return LucideIcons.link;
      case 'search': return LucideIcons.search;
      case 'settings': return LucideIcons.settings;
      case 'info': return LucideIcons.info;
      case 'alert-circle': return LucideIcons.alertCircle;
      default: return LucideIcons.chevronRight;
    }
  }
  /// Free-layout stack shared by PPT canvas, PDF canvas and Present mode:
  /// title / body / image boxes positioned by fractional offsets.
  /// [interactive] false renders statically (Present mode).
  static Widget freeStack(
    BuildContext context,
    Slide s,
    double w,
    double h, {
    required Color titleColor,
    required Color bodyColor,
    required double titleBase,
    required double bodyBase,
    Color? accent,
    bool interactive = true,
  }) {
    final ac = accent ?? Dt.accent;
    final hasImage = s.imageBytes != null && s.imageBytes!.isNotEmpty;
    return Stack(children: [
      FreeBox(enabled: interactive,
        dx: s.tDx,
        dy: s.tDy,
        scale: s.tS,
        canvasW: w,
        canvasH: h,
        onCommit: (dx, dy, sc) {
          s.tDx = dx;
          s.tDy = dy;
          s.tS = sc;
        },
        builder: (_, sc) => Text(
          s.title.isEmpty ? 'Untitled' : s.title,
          style: GoogleFonts.plusJakartaSans(
              fontSize: titleBase * sc,
              fontWeight: FontWeight.w800,
              height: 1.2,
              color: titleColor),
        ),
      ),
      FreeBox(enabled: interactive,
        dx: s.bDx,
        dy: s.bDy,
        scale: s.bS,
        canvasW: w,
        canvasH: h,
        onCommit: (dx, dy, sc) {
          s.bDx = dx;
          s.bDy = dy;
          s.bS = sc;
        },
        builder: (_, sc) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final p in s.points.take(6))
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text('▸ $p',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: bodyBase * sc,
                          height: 1.35,
                          color: bodyColor)),
                ),
            ]),
      ),
      if (hasImage || s.wantsImage)
        FreeBox(enabled: interactive,
          dx: s.iDx,
          dy: s.iDy,
          scale: s.iS,
          canvasW: w,
          canvasH: h,
          boxH: 84,
          onCommit: (dx, dy, sc) {
            s.iDx = dx;
            s.iDy = dy;
            s.iS = sc;
          },
          builder: (_, sc) => hasImage
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    Uint8List.fromList(s.imageBytes!),
                    height: 84 * sc,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                )
              : Container(
                  height: 52 * sc,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: ac, width: 1),
                    color: ac.withValues(alpha: 0.1),
                  ),
                  child: Text('IMAGE',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 10 * sc,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: ac)),
                ),
        ),
    ]);
  }
}
