import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../controllers/slide_deck_controller.dart';
import '../../core/colors.dart';
import '../../theme/design_tokens.dart';
import '../../utils/slide_deck.dart';

class SlideOutlineView extends StatelessWidget {
  final SlideDeckController c = Get.find<SlideDeckController>();

  SlideOutlineView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Presentation Outline',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => c.showingOutline.value = false,
                icon: const Icon(LucideIcons.x),
              ),
            ],
          ),
          const Divider(),
          Expanded(
            child: Obx(() => ListView.builder(
                  itemCount: c.outline.length,
                  itemBuilder: (context, index) {
                    final item = c.outline[index];
                    return _outlineItem(context, isDark, index, item);
                  },
                )),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: c.generating.value ? null : c.generateFromOutline,
              icon: const Icon(LucideIcons.presentation),
              label: const Text('Generate Full Deck'),
              style: FilledButton.styleFrom(
                backgroundColor: Dt.accent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _outlineItem(
      BuildContext context, bool isDark, int index, SlideOutline item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Dt.pillMuted.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.07) : Dt.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: Dt.accent,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.title,
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.pencil, size: 14),
                onPressed: () => _editOutlineItem(context, isDark, index, item),
              ),
              IconButton(
                icon: const Icon(LucideIcons.trash2, size: 14, color: AppColors.error),
                onPressed: () => c.outline.removeAt(index),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Text(
              item.description,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).hintColor,
              ),
            ),
          ),
          if (item.keyPoints.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 32, top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: item.keyPoints
                    .map((p) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Dt.accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            p,
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Dt.accent),
                          ),
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  void _editOutlineItem(
      BuildContext context, bool isDark, int index, SlideOutline item) {
    final titleCtrl = TextEditingController(text: item.title);
    final descCtrl = TextEditingController(text: item.description);
    final pointsCtrl = TextEditingController(text: item.keyPoints.join('\n'));
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.surface : Colors.white,
        title: const Text('Edit Slide Outline'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title')),
            TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description')),
            TextField(
              controller: pointsCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Key Points (one per line)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              c.outline[index] = SlideOutline(
                title: titleCtrl.text,
                description: descCtrl.text,
                keyPoints: pointsCtrl.text.split('\n').where((s) => s.trim().isNotEmpty).toList(),
                layout: item.layout,
              );
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
