import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/hive_service.dart';
import '../services/inference_service.dart';
import '../services/local_image_service.dart';
import '../services/download_service.dart';
import '../core/constants.dart';

class HomeController extends GetxController {
  final currentTab = 0.obs;
  bool _resumeDialogShown = false;

  void changeTab(int index) {
    currentTab.value = index;
  }

  /// Shows a one-time dialog on startup asking if the user wants to reload
  /// the last used model (text or image). Does not auto-load anything.
  void checkResumeModel(BuildContext context) async {
    if (_resumeDialogShown) return;
    _resumeDialogShown = true;

    final hive = Get.find<HiveService>();
    final downloadService = Get.find<DownloadService>();

    // Check text model
    final textName = hive.getSetting<String>(AppConstants.keyLocalModelName);
    final textPath = hive.getSetting<String>(AppConstants.keyLocalModelPath);
    final textRuntime = hive.getSetting<String>(AppConstants.keyLocalModelRuntime);
    bool hasText = textName != null &&
        textName.isNotEmpty &&
        textPath != null &&
        textPath.isNotEmpty &&
        await downloadService.isModelDownloaded(textName);

    // Check image model
    final imageName = hive.getSetting<String>(AppConstants.keyImageModelName);
    final imagePath = hive.getSetting<String>(AppConstants.keyImageModelPath);
    bool hasImage = imageName != null &&
        imageName.isNotEmpty &&
        imagePath != null &&
        imagePath.isNotEmpty &&
        await downloadService.isModelDownloaded(imageName);

    if (!hasText && !hasImage) return;
    if (!context.mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final label = hasText && hasImage
        ? '$textName & $imageName'
        : (hasText ? textName : imageName);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Resume Session?',
            style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.w600)),
        content: Text(
            'Load your last model${hasImage && hasText ? 's' : ''}?\n\n$label',
            style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Skip',
                style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.of(context).pop();
              if (hasText) {
                Get.find<InferenceService>().loadModel(textPath,
                    modelName: textName, modelRuntime: textRuntime);
              }
              if (hasImage) {
                Get.find<LocalImageService>().loadModel(imagePath,
                    modelName: imageName);
              }
            },
            child: const Text('Load'),
          ),
        ],
      ),
    );
  }
}
