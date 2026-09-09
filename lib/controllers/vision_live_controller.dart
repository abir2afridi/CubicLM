import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:get/get.dart';
import 'chat_controller.dart';
import 'settings_controller.dart';
import '../services/app_log_service.dart';

class VisionLiveController extends GetxController {
  CameraController? cameraController;
  final isLive = false.obs;
  Timer? _snapshotTimer;
  
  @override
  void onInit() {
    super.onInit();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    
    cameraController = CameraController(cameras.first, ResolutionPreset.medium, enableAudio: false);
    await cameraController!.initialize();
  }

  void toggleLive() {
    if (!isLive.value) {
      // Basic support check before starting
      final settings = Get.find<SettingsController>();
      final isCloud = settings.inferenceMode.value == 'cloud';
      if (isCloud) {
        final model = settings.selectedCloudModelName.toLowerCase();
        final isVision = model.contains('vision') ||
            model.contains('-vl') ||
            model.contains('gpt-4o') ||
            model.contains('claude-3') ||
            model.contains('gemini') ||
            model.contains('pixtral') ||
            model.contains('llava') ||
            model.contains('omni');
            
        if (!isVision) {
          Get.snackbar(
            'Model might not support Vision',
            'You are starting Live Vision with a text-only model. Switch to Gemini, GPT-4o, or Claude 3 for best results.',
            snackPosition: SnackPosition.TOP,
            backgroundColor: const Color(0xFFFF9500).withValues(alpha: 0.9),
            colorText: Colors.white,
          );
        }
      }
      
      _startSnapshotLoop();
    } else {
      _stopSnapshotLoop();
    }
    isLive.value = !isLive.value;
  }

  void _startSnapshotLoop() {
    _snapshotTimer?.cancel();
    _snapshotTimer = Timer.periodic(const Duration(seconds: 5), (_) => _captureAndSend());
    Get.find<AppLogService>().info('Live Vision loop started', category: LogCategory.chat);
  }

  void _stopSnapshotLoop() {
    _snapshotTimer?.cancel();
    _snapshotTimer = null;
    Get.find<AppLogService>().info('Live Vision loop stopped', category: LogCategory.chat);
  }

  Future<void> _captureAndSend() async {
    if (cameraController == null || !cameraController!.value.isInitialized) return;
    if (Get.find<ChatController>().isLoading.value) return;

    try {
      final image = await cameraController!.takePicture();
      final chat = Get.find<ChatController>();
      
      // Auto-attach and send if live
      chat.selectedImagePath.value = image.path;
      chat.selectedFileType.value = 'image';
      chat.selectedFileName.value = 'live_vision.jpg';
      
      // Send without modifying textController (silent multimodal turn)
      await chat.sendMessage();
    } catch (e) {
      Get.find<AppLogService>().error('Live Vision capture failed', details: e, category: LogCategory.chat);
    }
  }

  @override
  void onClose() {
    _stopSnapshotLoop();
    cameraController?.dispose();
    super.onClose();
  }
}
