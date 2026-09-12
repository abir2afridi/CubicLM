import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/design_tokens.dart';
import 'explore/toolkit_tab.dart';

/// Standalone Toolkit page (Battle Arena, Slide Maker, …).
/// Moved out of Model Hub into its own bottom-navigation destination.
class ToolkitView extends StatelessWidget {
  const ToolkitView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? Dt.canvasDark : Dt.canvas,
      appBar: AppBar(
        backgroundColor:
            (isDark ? Dt.canvasDark : Dt.canvas).withValues(alpha: 0.8),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(color: Colors.transparent),
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.wrench, size: 22),
            const SizedBox(width: 10),
            Text('nav_toolkit'.tr,
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800,
                    fontSize: 24,
                    letterSpacing: -0.5)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'About Toolkit',
            icon: const Icon(LucideIcons.info, size: 20),
            onPressed: () => _showToolkitInfo(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          buildToolkitTab(context),
        ],
      ),
    );
  }

  void _showToolkitInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Toolkit'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _toolkitInfoRow('Battle Arena',
                  'Race cloud models on one prompt and compare answers side by side.'),
              _toolkitInfoRow('Slide Maker',
                  'Turn any topic into slides; export Markdown, PDF or presentation files.'),
              _toolkitInfoRow('CubicWeb Builder',
                  'Describe a website and the agent builds it with live preview.'),
              _toolkitInfoRow('CubicDataSheet',
                  'Personal sheets and docs workspace stored only on this device.'),
              _toolkitInfoRow('CubicWeb Browser',
                  'Private browser with built-in ad-block and no history; extract pages into chat.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _toolkitInfoRow(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(body,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5, height: 1.45)),
        ],
      ),
    );
  }
}
