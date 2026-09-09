import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../controllers/agent_controller.dart';
import '../../theme/design_tokens.dart';

class KnowledgeGraphView extends StatefulWidget {
  final bool isDark;
  final Function(String) onFileClick;
  const KnowledgeGraphView({super.key, required this.isDark, required this.onFileClick});

  @override
  State<KnowledgeGraphView> createState() => _KnowledgeGraphViewState();
}

class _KnowledgeGraphViewState extends State<KnowledgeGraphView> {
  final TransformationController _transform = TransformationController();
  List<Map<String, String>> _deps = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDeps();
  }

  Future<void> _loadDeps() async {
    final ac = Get.find<AgentController>();
    final deps = await ac.getProjectDependencies();
    if (mounted) {
      setState(() {
        _deps = deps;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final ac = Get.find<AgentController>();
    final files = ac.files.toList();

    return Container(
      color: widget.isDark ? const Color(0xFF0D0D12) : const Color(0xFFF9FAFB),
      child: Stack(
        children: [
          InteractiveViewer(
            transformationController: _transform,
            minScale: 0.1,
            maxScale: 2.0,
            boundaryMargin: const EdgeInsets.all(500),
            child: CustomPaint(
              size: const Size(2000, 2000),
              painter: GraphPainter(
                files: files,
                deps: _deps,
                isDark: widget.isDark,
                onNodeClick: widget.onFileClick,
              ),
            ),
          ),
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: widget.isDark ? Colors.black54 : Colors.white70,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: widget.isDark ? Colors.white10 : Dt.hairline),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.gitBranch, size: 14, color: Colors.blueAccent),
                  const SizedBox(width: 8),
                  Text('Project Mind-Map', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GraphPainter extends CustomPainter {
  final List<String> files;
  final List<Map<String, String>> deps;
  final bool isDark;
  final Function(String) onNodeClick;

  GraphPainter({required this.files, required this.deps, required this.isDark, required this.onNodeClick});

  @override
  void paint(Canvas canvas, Size size) {
    final Map<String, Offset> positions = {};
    final paint = Paint()
      ..color = isDark ? Colors.blueAccent.withValues(alpha: 0.3) : Colors.blueAccent.withValues(alpha: 0.2)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Simple grid-like layout
    final center = Offset(size.width / 2, size.height / 2);
    for (int i = 0; i < files.length; i++) {
      positions[files[i]] = Offset(center.dx + (i % 5 - 2) * 250, center.dy + (i ~/ 5 - 2) * 200);
    }

    // Draw Edges
    for (final d in deps) {
      final from = positions[d['from']];
      final toFile = files.firstWhereOrNull((f) => f.contains(d['to']!));
      final to = positions[toFile];
      if (from != null && to != null) {
        canvas.drawLine(from, to, paint);
      }
    }

    // Draw Nodes
    for (final f in files) {
      final pos = positions[f]!;
      final textPainter = TextPainter(
        text: TextSpan(
          text: f.split('/').last,
          style: GoogleFonts.firaCode(fontSize: 10, color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final bgPaint = Paint()..color = isDark ? const Color(0xFF1E1E2E) : Colors.white;
      final borderPaint = Paint()
        ..color = Dt.accent.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;

      final rect = Rect.fromCenter(center: pos, width: textPainter.width + 20, height: 30);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)), bgPaint);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)), borderPaint);
      
      textPainter.paint(canvas, pos - Offset(textPainter.width / 2, textPainter.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
