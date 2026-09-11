import 'package:flutter/material.dart';
import '../../theme/design_tokens.dart';

/// Freehand drag box + chart painters for slides.
/// Extracted from views/slide_deck_view.dart.
/// Draggable + scalable overlay box for freehand slide layout.
///
/// - Drag anywhere on the box to move (fractional canvas offsets).
/// - Drag the corner handle to scale content.
/// - State lives locally during the gesture; [onCommit] persists to the
///   slide on every change (plain field writes — no list rebuild, so the
///   drag stays smooth).
class FreeBox extends StatefulWidget {
  final double dx;
  final double dy;
  final double scale;
  final double canvasW;
  final double canvasH;
  final double boxH;
  final Widget Function(BuildContext, double scale) builder;
  final void Function(double dx, double dy, double scale) onCommit;

  const FreeBox({
    super.key,
    required this.dx,
    required this.dy,
    required this.scale,
    required this.canvasW,
    required this.canvasH,
    required this.builder,
    required this.onCommit,
    this.boxH = 0,
  });

  @override
  State<FreeBox> createState() => FreeBoxState();
}

class FreeBoxState extends State<FreeBox> {
  late double _dx;
  late double _dy;
  late double _scale;

  @override
  void initState() {
    super.initState();
    _dx = widget.dx;
    _dy = widget.dy;
    _scale = widget.scale.clamp(0.5, 2.5);
  }

  void _commit() => widget.onCommit(_dx, _dy, _scale);

  @override
  Widget build(BuildContext context) {
    const widthFrac = 0.86;
    final w = widget.canvasW * widthFrac;
    final left = (_dx * widget.canvasW).clamp(0.0, widget.canvasW - w);
    final top = (_dy * widget.canvasH).clamp(0.0, widget.canvasH - 30);
    return Positioned(
      left: left,
      top: top,
      width: w,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanUpdate: (d) {
          setState(() {
            var newX = (_dx * widget.canvasW + d.delta.dx) / widget.canvasW;
            var newY = (_dy * widget.canvasH + d.delta.dy) / widget.canvasH;
            
            // Snap to 5% grid
            newX = (newX * 20).round() / 20.0;
            newY = (newY * 20).round() / 20.0;

            _dx = newX.clamp(0.0, 1.0 - widthFrac);
            _dy = newY.clamp(0.0, 0.95);
          });
          _commit();
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: Dt.accent.withValues(alpha: 0.55),
              width: 1,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: const EdgeInsets.all(5),
                child: widget.boxH > 0
                    ? SizedBox(
                        height: widget.boxH * _scale,
                        width: double.infinity,
                        child: widget.builder(context, _scale),
                      )
                    : widget.builder(context, _scale),
              ),
              Positioned(
                right: -11,
                bottom: -11,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (d) {
                    setState(() {
                      _scale = (_scale + d.delta.dx / 120).clamp(0.5, 2.5);
                    });
                    _commit();
                  },
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: Dt.accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.open_in_full_rounded,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Draws a donut chart for the chart layout.
class DonutPainter extends CustomPainter {
  final List<double> values;
  final double total;
  final List<Color> colors;
  DonutPainter(this.values, this.total, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14;
    double start = -3.14159 / 2;
    for (var i = 0; i < values.length && i < 6; i++) {
      final sweep = total > 0 ? (values[i] / total) * 3.14159 * 2 : 0.0;
      paint.color = colors[i % colors.length];
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), start,
          sweep.toDouble(), false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Draws a line chart with dots and area fill for the chart layout.
class LineChartPainter extends CustomPainter {
  final List<Offset> points;
  final List<Map<String, String>> items;
  final List<double> nums;
  LineChartPainter(this.points, this.items, this.nums);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final linePaint = Paint()
      ..color = Dt.accent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final dotPaint = Paint()
      ..color = Dt.accent
      ..style = PaintingStyle.fill;
    final areaPaint = Paint()
      ..color = Dt.accent.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    // Draw area fill
    final areaPath = Path()..moveTo(points.first.dx, size.height);
    for (final p in points) {
      areaPath.lineTo(p.dx, p.dy);
    }
    areaPath.lineTo(points.last.dx, size.height);
    areaPath.close();
    canvas.drawPath(areaPath, areaPaint);

    // Draw line
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      linePath.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(linePath, linePaint);

    // Draw dots + labels
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(points[i], 4, dotPaint);
      // Value above dot
      tp.text = TextSpan(
          text: items[i]['value'] ?? '',
          style: const TextStyle(
              fontSize: 9, fontWeight: FontWeight.w700, color: Dt.accent));
      tp.layout();
      tp.paint(canvas, Offset(points[i].dx - tp.width / 2, points[i].dy - 16));
      // Label below x-axis
      tp.text = TextSpan(
          text: items[i]['label'] ?? '',
          style: const TextStyle(fontSize: 8.5, color: Color(0xFFB0ADA6)));
      tp.layout();
      tp.paint(canvas, Offset(points[i].dx - tp.width / 2, size.height - 12));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Simple flowchart diagram painter for "Gemma Level" slides.
class DiagramPainter extends CustomPainter {
  final String mermaid;
  final bool isDark;
  DiagramPainter(this.mermaid, this.isDark);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Dt.accent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = Dt.accent.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    final tp = TextPainter(textDirection: TextDirection.ltr);

    final w = size.width;
    final h = size.height;

    void drawNode(String text, double x, double y, {bool diamond = false}) {
      if (diamond) {
        final path = Path()
          ..moveTo(x, y - 25)
          ..lineTo(x + 45, y)
          ..lineTo(x, y + 25)
          ..lineTo(x - 45, y)
          ..close();
        canvas.drawPath(path, fillPaint);
        canvas.drawPath(path, paint);
      } else {
        final rect = Rect.fromCenter(center: Offset(x, y), width: 90, height: 40);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)), fillPaint);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)), paint);
      }

      tp.text = TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : Colors.black,
        ),
      );
      tp.layout(maxWidth: 80);
      tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
    }

    if (mermaid.contains('-->') || mermaid.contains('graph')) {
      drawNode("Input Data", w * 0.5, h * 0.15);
      drawNode("Decision?", w * 0.5, h * 0.45, diamond: true);
      drawNode("Success Path", w * 0.25, h * 0.8);
      drawNode("Failure Path", w * 0.75, h * 0.8);

      canvas.drawLine(Offset(w * 0.5, h * 0.15 + 20), Offset(w * 0.5, h * 0.45 - 25), paint);
      canvas.drawLine(Offset(w * 0.5 - 22, h * 0.45 + 12), Offset(w * 0.25 + 10, h * 0.8 - 20), paint);
      canvas.drawLine(Offset(w * 0.5 + 22, h * 0.45 + 12), Offset(w * 0.75 - 10, h * 0.8 - 20), paint);
    } else {
      drawNode("Start", w * 0.2, h * 0.5);
      drawNode("Process", w * 0.5, h * 0.5);
      drawNode("End", w * 0.8, h * 0.5);
      canvas.drawLine(Offset(w * 0.2 + 45, h * 0.5), Offset(w * 0.5 - 45, h * 0.5), paint);
      canvas.drawLine(Offset(w * 0.5 + 45, h * 0.5), Offset(w * 0.8 - 45, h * 0.5), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
