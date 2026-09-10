import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../controllers/agent_controller.dart';
import '../../theme/design_tokens.dart';
import '../../core/colors.dart';

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
  final Map<String, Offset> _positions = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final ac = Get.find<AgentController>();
    final deps = await ac.getProjectDependencies();
    
    // Initial centering
    // ignore: deprecated_member_use
    _transform.value = Matrix4.identity()..translate(100.0, 100.0, 0.0);

    if (mounted) {
      setState(() {
        _deps = deps;
        _calculatePositions(ac.files.toList());
        _loading = false;
      });
    }
  }

  void _calculatePositions(List<String> files) {
    if (files.isEmpty) return;
    
    const center = Offset(1000, 1000);
    const radius = 400.0;
    
    // Find entry point
    String entry = files.firstWhere((f) => f.contains('index.html') || f.contains('main'), orElse: () => files.first);
    _positions[entry] = center;

    final others = files.where((f) => f != entry).toList();
    for (int i = 0; i < others.length; i++) {
      final angle = (i / others.length) * 2 * math.pi;
      _positions[others[i]] = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
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
            constrained: false,
            boundaryMargin: const EdgeInsets.all(2000),
            child: SizedBox(
              width: 2000,
              height: 2000,
              child: Stack(
                children: [
                  // Draw Lines (Background)
                  CustomPaint(
                    size: const Size(2000, 2000),
                    painter: ConnectionPainter(
                      deps: _deps,
                      positions: _positions,
                      isDark: widget.isDark,
                    ),
                  ),
                  // Draw Nodes (Interactive Widgets)
                  ...files.map((f) {
                    final pos = _positions[f] ?? const Offset(1000, 1000);
                    return Positioned(
                      left: pos.dx - 60,
                      top: pos.dy - 20,
                      child: _FileNodeWidget(
                        path: f,
                        isDark: widget.isDark,
                        onTap: () => widget.onFileClick(f),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          // Floating Header
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: widget.isDark ? Colors.black87 : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: widget.isDark ? Colors.white10 : Dt.hairline),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.gitBranch, size: 16, color: Colors.blueAccent),
                  const SizedBox(width: 8),
                  Text('Project Architecture', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
          // Zoom Controls
          Positioned(
            bottom: 24,
            right: 24,
            child: Column(
              children: [
                _zoomBtn(LucideIcons.plus, () {
                  // ignore: deprecated_member_use
                  _transform.value = _transform.value.clone()..scale(1.2, 1.2, 1.0);
                }),
                const SizedBox(height: 8),
                _zoomBtn(LucideIcons.minus, () {
                  // ignore: deprecated_member_use
                  _transform.value = _transform.value.clone()..scale(0.8, 0.8, 1.0);
                }),
                const SizedBox(height: 8),
                _zoomBtn(LucideIcons.maximize, () {
                  // ignore: deprecated_member_use
                  _transform.value = Matrix4.identity()..translate(100.0, 100.0, 0.0);
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _zoomBtn(IconData icon, VoidCallback onTap) {
    return FloatingActionButton.small(
      heroTag: null,
      onPressed: onTap,
      backgroundColor: widget.isDark ? AppColors.surface : Colors.white,
      child: Icon(icon, size: 18, color: widget.isDark ? Colors.white70 : Colors.black87),
    );
  }
}

class _FileNodeWidget extends StatelessWidget {
  final String path;
  final bool isDark;
  final VoidCallback onTap;

  const _FileNodeWidget({required this.path, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fileName = path.split('/').last;
    final isEntry = fileName == 'index.html' || fileName == 'main.jsx' || fileName == 'App.jsx';
    
    // Unique label if name is shared
    String label = fileName;
    if (fileName == 'index.html' && path.contains('/')) {
      final parts = path.split('/');
      if (parts.length >= 2) label = '${parts[parts.length-2]}/$fileName';
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        width: 130,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isEntry ? Colors.blueAccent : (isDark ? Colors.white10 : Colors.black12),
            width: isEntry ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isEntry ? Colors.blueAccent.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Row(
          children: [
            Icon(_iconFor(path), size: 14, color: _colorFor(path)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: isEntry ? FontWeight.w800 : FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.html')) return LucideIcons.globe;
    if (p.endsWith('.css')) return LucideIcons.palette;
    if (p.endsWith('.js') || p.endsWith('.jsx')) return LucideIcons.fileCode;
    return LucideIcons.file;
  }

  Color _colorFor(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.html')) return Colors.orangeAccent;
    if (p.endsWith('.css')) return Colors.blueAccent;
    if (p.endsWith('.js') || p.endsWith('.jsx')) return Colors.yellowAccent;
    return Colors.grey;
  }
}

class ConnectionPainter extends CustomPainter {
  final List<Map<String, String>> deps;
  final Map<String, Offset> positions;
  final bool isDark;

  ConnectionPainter({required this.deps, required this.positions, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final arrowPaint = Paint()
      ..color = isDark ? Colors.blueAccent.withValues(alpha: 0.4) : Colors.blueAccent.withValues(alpha: 0.3)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final d in deps) {
      final from = positions[d['from']];
      // Try to find the target file by fuzzy matching the imported name
      final toFile = positions.keys.cast<String?>().firstWhere((f) => f != null && f.contains(d['to']!), orElse: () => null);
      final to = positions[toFile];

      if (from != null && to != null) {
        final path = Path();
        path.moveTo(from.dx, from.dy);
        
        // Control point for a nice curve
        final cp1 = Offset(from.dx, (from.dy + to.dy) / 2);
        final cp2 = Offset(to.dx, (from.dy + to.dy) / 2);
        
        path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, to.dx, to.dy);
        canvas.drawPath(path, arrowPaint);
        
        // Optional: Draw a small dot at the target
        canvas.drawCircle(to, 4, arrowPaint..style = PaintingStyle.fill);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}


