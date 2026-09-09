import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../controllers/agent_controller.dart';
import '../../theme/design_tokens.dart';

class ComponentPromotionCard extends StatelessWidget {
  final String name;
  final String code;
  final bool isDark;

  const ComponentPromotionCard({
    super.key,
    required this.name,
    required this.code,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Dt.accent.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(),
          _previewStub(),
          _actions(),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(LucideIcons.component, size: 18, color: Dt.accent),
          const SizedBox(width: 10),
          Text(
            name,
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const Spacer(),
          const Text('Reusable Component', style: TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _previewStub() {
    // In a real implementation, we could render this code in a mini WebView.
    // For now, we show a professional placeholder.
    return Container(
      height: 120,
      width: double.infinity,
      color: isDark ? Colors.black26 : Colors.grey[100],
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.eye, size: 24, color: Colors.grey),
            const SizedBox(height: 8),
            Text(
              'Interactive Preview Ready',
              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actions() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                // Show code in a dialog
                Get.dialog(
                  AlertDialog(
                    title: Text(name),
                    content: SingleChildScrollView(
                      child: Text(code, style: GoogleFonts.firaCode(fontSize: 11)),
                    ),
                    actions: [
                      TextButton(onPressed: () => Get.back(), child: const Text('Close')),
                    ],
                  ),
                );
              },
              icon: const Icon(LucideIcons.code, size: 14),
              label: const Text('View Code'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Dt.accent),
              onPressed: () {
                final ac = Get.find<AgentController>();
                ac.promoteComponent(name, code);
              },
              icon: const Icon(LucideIcons.plus, size: 14),
              label: const Text('Add to Project'),
            ),
          ),
        ],
      ),
    );
  }
}
