import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../theme/design_tokens.dart';

class ResponsiveGridView extends StatelessWidget {
  final String url;
  final bool isDark;
  const ResponsiveGridView({super.key, required this.url, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.layoutGrid, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text('Preview not live yet',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey)),
            const SizedBox(height: 8),
            const Text('Build the project first to see responsive previews.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      );
    }

    return Container(
      color: isDark ? const Color(0xFF0D0D12) : const Color(0xFFF9FAFB),
      child: Column(
        children: [
          _header(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Wrap(
                spacing: 24,
                runSpacing: 24,
                alignment: WrapAlignment.center,
                children: [
                  _deviceFrame('Mobile', 375, 667, LucideIcons.smartphone),
                  _deviceFrame('Tablet', 768, 1024, LucideIcons.tablet),
                  _deviceFrame('Desktop', 1280, 800, LucideIcons.monitor),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
        border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Dt.hairline)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.layoutGrid, size: 18, color: Dt.accent),
          const SizedBox(width: 12),
          Text('Responsive Grid', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w800)),
          const Spacer(),
          Text(url, style: GoogleFonts.firaCode(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _deviceFrame(String label, double w, double h, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.grey),
            const SizedBox(width: 8),
            Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(width: 8),
            Text('${w.round()}x${h.round()}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: w * 0.6, // Scaled down for grid view
          height: h * 0.6,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? Colors.white10 : Dt.hairline, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
          ),
          clipBehavior: Clip.antiAlias,
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(url)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              supportZoom: false,
            ),
          ),
        ),
      ],
    );
  }
}
