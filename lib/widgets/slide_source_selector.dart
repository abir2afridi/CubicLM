import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../controllers/slide_deck_controller.dart';
import '../core/colors.dart';
import '../services/cubicdata/controller.dart';
import '../services/cubicdata/models.dart';
import '../theme/design_tokens.dart';

class SlideSourceSelector extends StatelessWidget {
  final File? selectedFile;
  final bool useResearch;
  final Function(File?) onFileSelected;
  final Function(bool) onResearchToggled;

  const SlideSourceSelector({
    super.key,
    required this.selectedFile,
    required this.useResearch,
    required this.onFileSelected,
    required this.onResearchToggled,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = Get.find<SlideDeckController>();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Dt.pillMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // File Picker
              InkWell(
                onTap: _pickFile,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      selectedFile != null ? LucideIcons.fileCheck : LucideIcons.filePlus,
                      size: 16,
                      color: selectedFile != null ? Dt.accent : Dt.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      selectedFile != null
                          ? selectedFile!.path.split('/').last
                          : 'Add Source (PDF/Docx)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selectedFile != null ? Dt.accent : Dt.textPrimary,
                      ),
                    ),
                    if (selectedFile != null) ...[
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => onFileSelected(null),
                        child: const Icon(LucideIcons.x, size: 14, color: AppColors.error),
                      ),
                    ],
                  ],
                ),
              ),
              const Spacer(),
              // Research Toggle
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'AI Research',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: useResearch ? Dt.accent : Dt.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Switch(
                    value: useResearch,
                    onChanged: onResearchToggled,
                    activeThumbColor: Dt.accent,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 12),
          // DataSheet Picker
          Obx(() {
            // Registered at startup in main.dart; lazy fallback keeps
            // standalone/widget-test builds from throwing.
            final dc = Get.isRegistered<CubicDataController>()
                ? Get.find<CubicDataController>()
                : Get.put(CubicDataController());
            final sheets = dc.files.where((f) => f.type == WorkspaceType.spreadsheet).toList();
            if (sheets.isEmpty) return const SizedBox.shrink();
            
            final selected = sheets.firstWhereOrNull((s) => s.id == c.selectedDataSheetId.value);
            
            return Row(
              children: [
                const Icon(LucideIcons.database, size: 14, color: Dt.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: DropdownButton<String?>(
                    value: c.selectedDataSheetId.value,
                    hint: const Text('Link DataSheet', style: TextStyle(fontSize: 11)),
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    onChanged: (v) => c.selectedDataSheetId.value = v,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('None', style: TextStyle(fontSize: 11))),
                      for (final s in sheets)
                        DropdownMenuItem(value: s.id, child: Text(s.name, style: const TextStyle(fontSize: 11))),
                    ],
                  ),
                ),
                if (selected != null)
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 12, color: AppColors.error),
                    onPressed: () => c.selectedDataSheetId.value = null,
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'txt', 'md'],
    );
    if (result != null && result.files.single.path != null) {
      onFileSelected(File(result.files.single.path!));
    }
  }
}
