import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../controllers/agent_controller.dart';
import '../../services/agent_workspace.dart';
import '../../theme/design_tokens.dart';
import '../../utils/app_snackbar.dart';

class VersionTimeline extends StatelessWidget {
  final bool isDark;
  const VersionTimeline({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<AgentController>();
    final ws = Get.find<AgentWorkspaceService>();

    return Obx(() {
      final p = c.project.value;
      if (p == null) return const SizedBox.shrink();

      return FutureBuilder<List<ProjectCheckpoint>>(
        future: ws.listCheckpoints(p.id),
        builder: (context, snapshot) {
          final checkpoints = snapshot.data ?? [];
          
          return Container(
            width: 60,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF16161E) : const Color(0xFFF9FAFB),
              border: Border(right: BorderSide(color: isDark ? Colors.white10 : Dt.hairline)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                const Icon(LucideIcons.history, size: 18, color: Colors.grey),
                const SizedBox(height: 12),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: checkpoints.length,
                    itemBuilder: (context, i) {
                      final cp = checkpoints[i];
                      final isLatest = i == 0;
                      
                      return Tooltip(
                        message: '${cp.label}\n${cp.fileCount} files',
                        child: InkWell(
                          onTap: isLatest ? null : () async {
                            await ws.rollbackToCheckpoint(p.id, cp.id);
                            await c.refreshFiles();
                            c.revision.value++;
                            AppSnackbar.showTop('Rolled back', 'Restored to ${cp.label}');
                          },
                          child: Container(
                            height: 48,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isLatest ? Dt.accent : (isDark ? Colors.white10 : Colors.black12),
                                    border: isLatest ? null : Border.all(color: Dt.accent.withValues(alpha: 0.3)),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${checkpoints.length - i}',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: isLatest ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                      ),
                                    ),
                                  ),
                                ),
                                if (i < checkpoints.length - 1)
                                  Positioned(
                                    bottom: 0,
                                    child: Container(width: 1, height: 12, color: isDark ? Colors.white10 : Dt.hairline),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );
    });
  }
}
