/// Web stub — model downloads are not supported on web.
library;

Future<String> getModelsDir() async => '/web/models';

Future<bool> isModelDownloaded(String path) async => false;

Future<List<String>> getDownloadedModels(String modelsDir) async => [];

Future<int> getModelSize(String path) async => 0;

Future<int> getRemoteFileSize(String url, {String? authToken}) async => 0;

Future<String> downloadModel({
  required String url,
  required String savePath,
  String? authToken,
  void Function(int received, int total)? onProgress,
}) async {
  return 'ERROR: Downloads not supported on web.';
}

void pauseDownload(String filename) {}

void cancelStreamDownload(String filename) {}

Future<Map<String, dynamic>?> startNativeStreamDownload({
  required String url,
  required String filename,
  required String modelsDir,
}) async =>
    null;

void pauseNativeStream(String filename) {}

void cancelNativeStream(String filename) {}

Future<List<Map<String, dynamic>>> getNativeStreamDownloads() async => [];

Future<String> streamDownload({
  required String url,
  required String savePath,
  String? authToken,
  void Function(int received, int total, double bytesPerSecond)? onProgress,
}) async {
  return 'ERROR: Downloads not supported on web.';
}

Future<void> deleteModel(String path) async {}
