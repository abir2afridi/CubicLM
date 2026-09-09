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
            width: 100,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF16161E) : const Color(0xFFF9FAFB),
              border: Border(
                  right: BorderSide(
                      color: isDark ? Colors.white10 : Dt.hairline)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                const Icon(LucideIcons.history, size: 18, color: Colors.grey),
                const SizedBox(height: 4),
                Text('VERSIONS',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Colors.grey)),
                const SizedBox(height: 12),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    itemCount: checkpoints.length,
                    itemBuilder: (context, i) {
                      final cp = checkpoints[i];
                      final isLatest = i == 0;
                      final dt =
                          DateTime.fromMillisecondsSinceEpoch(cp.timestampMs);
                      final timeStr =
                          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

                      return Tooltip(
                        message: '${cp.label}\n${cp.fileCount} files',
                        child: InkWell(
                          onTap: isLatest
                              ? null
                              : () async {
                                  await ws.rollbackToCheckpoint(p.id, cp.id);
                                  await c.refreshFiles();
                                  c.revision.value++;
                                  AppSnackbar.showTop('Rolled back',
                                      'Restored to ${cp.label}');
                                },
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              children: [
                                Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Obx(() {
                                      final thumb =
                                          c.checkpointThumbnails[cp.id];
                                      return Container(
                                        width: 60,
                                        height: 60,
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          color: isLatest
                                              ? Dt.accent.withValues(alpha: 0.1)
                                              : (isDark
                                                  ? Colors.white10
                                                  : Colors.black.withValues(
                                                      alpha: 0.05)),
                                          border: Border.all(
                                            color: isLatest
                                                ? Dt.accent
                                                : (isDark
                                                    ? Colors.white10
                                                    : Colors.black12),
                                            width: isLatest ? 2 : 1,
                                          ),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: thumb != null
                                            ? Image.memory(thumb,
                                                fit: BoxFit.cover)
                                            : Center(
                                                child: Text(
                                                  'V${checkpoints.length - i}',
                                                  style: GoogleFonts
                                                      .plusJakartaSans(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: isLatest
                                                        ? Dt.accent
                                                        : (isDark
                                                            ? Colors.white70
                                                            : Colors.black87),
                                                  ),
                                                ),
                                              ),
                                      );
                                    }),
                                    if (i < checkpoints.length - 1)
                                      Positioned(
                                        bottom: -12,
                                        child: Container(
                                            width: 1,
                                            height: 12,
                                            color: isDark
                                                ? Colors.white10
                                                : Dt.hairline),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(timeStr,
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey)),
                                if (cp.insertions > 0 || cp.deletions > 0)
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (cp.insertions > 0)
                                        Text('+${cp.insertions}',
                                            style: const TextStyle(
                                                fontSize: 8,
                                                color: Colors.green,
                                                fontWeight: FontWeight.bold)),
                                      if (cp.insertions > 0 && cp.deletions > 0)
                                        const SizedBox(width: 2),
                                      if (cp.deletions > 0)
                                        Text('-${cp.deletions}',
                                            style: const TextStyle(
                                                fontSize: 8,
                                                color: Colors.red,
                                                fontWeight: FontWeight.bold)),
                                    ],
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
