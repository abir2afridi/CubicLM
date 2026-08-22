import 'package:flutter/services.dart';

class SdFlutterAndroid {
  static const MethodChannel _channel = MethodChannel('sd_flutter_android');

  Future<String?> getPlatformVersion() {
    return _channel.invokeMethod<String>('getPlatformVersion');
  }

  static Future<String> detectGpuVendor() async {
    final result = await _channel.invokeMethod<String>('detectGpuVendor');
    return result ?? 'unknown';
  }

  static Future<int> getDeviceMemory() async {
    final result = await _channel.invokeMethod<int>('getDeviceMemory');
    return result ?? 4096; // fallback: assume 4GB
  }

  static Future<int> getAvailableMemory() async {
    final result = await _channel.invokeMethod<int>('getAvailableMemory');
    return result ?? 0;
  }

  static Future<dynamic> initModelRaw(String path, {bool useGpu = true}) async {
    final result = await _channel.invokeMethod<dynamic>('initModel', {
      'path': path,
      'useGpu': useGpu,
    });
    return result;
  }

  static Future<bool> initModel(String path, {bool useGpu = true}) async {
    final result = await initModelRaw(path, useGpu: useGpu);
    if (result is bool) {
      return result;
    }
    if (result is String && result == 'true') {
      return true;
    }
    return false;
  }

  static Function(int step, int total)? _onProgress;

  static void _ensureInitialized() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onProgress') {
        final step = call.arguments['step'] as int;
        final total = call.arguments['total'] as int;
        _onProgress?.call(step, total);
      }
    });
  }

  static Future<Uint8List?> generateImage(
    String prompt, {
    int steps = 20,
    Function(int step, int total)? onProgress,
  }) async {
    _ensureInitialized();
    _onProgress = onProgress;

    final bytes = await _channel.invokeMethod<Uint8List>('generateImage', {
      'prompt': prompt,
      'steps': steps,
    });
    return bytes;
  }

  static Future<void> unloadModel() async {
    await _channel.invokeMethod('unloadModel');
  }
}
