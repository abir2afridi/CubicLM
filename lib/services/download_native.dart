import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

final Dio _dio = Dio();
final Map<String, CancelToken> _cancelTokens = {};
const _channel = MethodChannel('com.cubiclm.app/model_import');

Future<String> getModelsDir() async {
  final dir = await getApplicationDocumentsDirectory();
  final modelsPath = '${dir.path}/models';
  await Directory(modelsPath).create(recursive: true);
  return modelsPath;
}

Future<bool> isModelDownloaded(String path) async {
  return File(path).existsSync();
}

Future<List<String>> getDownloadedModels(String modelsDir) async {
  final dir = Directory(modelsDir);
  if (!await dir.exists()) return [];
  return dir
      .listSync()
      .where((f) =>
          f.path.endsWith('.gguf') ||
          f.path.endsWith('.litertlm') ||
          f.path.endsWith('.safetensors'))
      .map((f) => f.path.split('/').last)
      .toList();
}

Future<int> getModelSize(String path) async {
  final file = File(path);
  if (!await file.exists()) return 0;
  return await file.length();
}

Future<int> getRemoteFileSize(String url, {String? authToken}) async {
  final headers = <String, dynamic>{};
  if (authToken != null && authToken.isNotEmpty) {
    headers['Authorization'] = 'Bearer $authToken';
  }

  // 1. Try HEAD request
  try {
    final response = await _dio.head(
      url,
      options: Options(headers: headers, followRedirects: true),
    );
    final length = response.headers.value(Headers.contentLengthHeader);
    final size = int.tryParse(length ?? '') ?? 0;
    if (size > 0) return size;
  } catch (_) {
    // If HEAD fails, fall back to GET with Range
  }

  // 2. Try GET request with Range: bytes=0-0 (efficiently fetch metadata only)
  try {
    final response = await _dio.get(
      url,
      options: Options(
        headers: {
          ...headers,
          'Range': 'bytes=0-0',
        },
        followRedirects: true,
      ),
    );
    
    // Check Content-Range header first (e.g., bytes 0-0/12345678)
    final contentRange = response.headers.value('content-range');
    if (contentRange != null) {
      final parts = contentRange.split('/');
      if (parts.length > 1) {
        final size = int.tryParse(parts.last.trim());
        if (size != null && size > 0) return size;
      }
    }

    // Fallback to Content-Length (if the server ignored Range and returned the whole file)
    final length = response.headers.value(Headers.contentLengthHeader);
    final size = int.tryParse(length ?? '') ?? 0;
    if (size > 0) return size;
  } catch (_) {
    // Both failed
  }

  return 0;
}

Future<String> downloadModel({
  required String url,
  required String savePath,
  String? authToken,
  void Function(int received, int total)? onProgress,
}) async {
  final tempPath = '$savePath.part';
  final cancelToken = CancelToken();
  final filename = savePath.split('/').last;
  _cancelTokens[filename] = cancelToken;
  var expectedTotalBytes = 0;

  try {
    final tempFile = File(tempPath);
    final oldTempFile = File('$savePath.tmp');
    if (await oldTempFile.exists()) {
      await oldTempFile.delete();
    }
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    final headers = <String, dynamic>{};
    if (authToken != null && authToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $authToken';
    }

    await _dio.download(
      url,
      tempPath,
      cancelToken: cancelToken,
      deleteOnError: false,
      options: Options(
        headers: headers,
        responseType: ResponseType.stream,
        followRedirects: true,
      ),
      onReceiveProgress: (received, total) {
        if (total > 0) {
          expectedTotalBytes = total;
        }
        onProgress?.call(received, total > 0 ? total : 0);
      },
    );

    final downloadedBytes = await tempFile.length();
    if (expectedTotalBytes > 0 && downloadedBytes < expectedTotalBytes) {
      await tempFile.delete();
      throw Exception(
        'Downloaded file is incomplete: $downloadedBytes of $expectedTotalBytes bytes.',
      );
    }
    final finalFile = File(savePath);
    if (await finalFile.exists()) {
      await finalFile.delete();
    }
    await tempFile.rename(savePath);
    _cancelTokens.remove(filename);
    return savePath;
  } on DioException catch (e) {
    if (e.type == DioExceptionType.cancel) {
      _cancelTokens.remove(filename);
      return 'PAUSED';
    }
    _cancelTokens.remove(filename);
    throw Exception('Download failed: ${e.message}');
  } catch (e) {
    _cancelTokens.remove(filename);
    rethrow;
  }
}

void pauseDownload(String filename) {
  _cancelTokens[filename]?.cancel('paused');
}

// ── Resumable streaming downloader (HTTP Range based) ──

final Map<String, CancelToken> _streamTokens = {};
final Set<String> _activeStreams = {};

void cancelStreamDownload(String filename) {
  _streamTokens.remove(filename)?.cancel('paused');
}

/// Streams [url] to `[savePath].part`, automatically resuming from any
/// existing partial data using HTTP Range requests. Returns the final path
/// on success or 'PAUSED' when cancelled via [cancelStreamDownload].
Future<String> streamDownload({
  required String url,
  required String savePath,
  String? authToken,
  void Function(int received, int total, double bytesPerSecond)? onProgress,
}) async {
  final partFile = File('$savePath.part');
  final filename = savePath.split('/').last;
  if (_activeStreams.contains(filename)) {
    throw Exception('A download for $filename is already running.');
  }
  final cancelToken = CancelToken();
  _streamTokens[filename] = cancelToken;
  _activeStreams.add(filename);

  var start = 0;
  if (await partFile.exists()) {
    start = await partFile.length();
  }
  print('[DownloadNative] streamDownload start=$start $filename');

  try {
    final headers = <String, dynamic>{};
    if (authToken != null && authToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $authToken';
    }
    if (start > 0) headers['Range'] = 'bytes=$start-';

    final response = await _dio.get<ResponseBody>(
      url,
      options: Options(
        headers: headers,
        responseType: ResponseType.stream,
        followRedirects: true,
        validateStatus: (_) => true,
      ),
      cancelToken: cancelToken,
    );

    // Server ignored the Range header (200 instead of 206) → start over.
    final append = start > 0 && response.statusCode == 206;
    if (!append) start = 0;
    if (start > 0 && !append) {
      print('[DownloadNative] Server ignored Range (HTTP '
          '${response.statusCode}) — restarting from zero.');
    }
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw Exception('HTTP ${response.statusCode}');
    }
    print('[DownloadNative] HTTP ${response.statusCode} append=$append '
        '(resume offset=$start)');
    var received = start;

    var expectedTotal = 0;
    final contentRange = response.headers.value('content-range');
    var rangeFullTotal = 0;
    if (contentRange != null && contentRange.contains('/')) {
      rangeFullTotal = int.tryParse(contentRange.split('/').last.trim()) ?? 0;
    }
    final contentLength =
        int.tryParse(response.headers.value('content-length') ?? '') ?? 0;
    if (append) {
      // 206 Partial Content: Content-Range carries the FULL file total;
      // Content-Length is only the remaining chunk.
      if (rangeFullTotal > 0) {
        expectedTotal = rangeFullTotal;
      } else if (contentLength > 0) {
        expectedTotal = start + contentLength;
      }
    } else {
      if (contentLength > 0) {
        expectedTotal = contentLength;
      } else if (rangeFullTotal > 0) {
        expectedTotal = rangeFullTotal;
      }
    }

    final sink =
        partFile.openWrite(mode: append ? FileMode.append : FileMode.write);
    var lastTime = DateTime.now();
    var lastBytes = received;
    var lastSpeed = 0.0;
    onProgress?.call(received, expectedTotal, 0);

    try {
      await for (final chunk in response.data!.stream) {
        sink.add(chunk);
        received += chunk.length;
        final now = DateTime.now();
        final elapsedMs = now.difference(lastTime).inMilliseconds;
        if (elapsedMs >= 500) {
          lastSpeed = (received - lastBytes) / (elapsedMs / 1000);
          lastBytes = received;
          lastTime = now;
        }
        onProgress?.call(received, expectedTotal, lastSpeed);
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      rethrow;
    }

    final size = await partFile.length();
    if (expectedTotal > 0 && size < expectedTotal) {
      throw Exception('Incomplete download: $size of $expectedTotal bytes.');
    }

    _streamTokens.remove(filename);
    final finalFile = File(savePath);
    if (await finalFile.exists()) await finalFile.delete();
    await partFile.rename(savePath);
    return savePath;
  } on DioException catch (e) {
    _streamTokens.remove(filename);
    if (e.type == DioExceptionType.cancel) return 'PAUSED';
    rethrow;
  } catch (_) {
    _streamTokens.remove(filename);
    rethrow;
  } finally {
    _activeStreams.remove(filename);
  }
}

Future<void> deleteModel(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
  final partFile = File('$path.part');
  if (await partFile.exists()) await partFile.delete();
  final tempFile = File('$path.tmp');
  if (await tempFile.exists()) await tempFile.delete();
}

// ── Native MethodChannel bridges (Android DownloadManager) ──

// ── Native foreground-service streaming downloads (Range resume) ──

Future<Map<String, dynamic>?> startNativeStreamDownload({
  required String url,
  required String filename,
  required String modelsDir,
}) async {
  if (!Platform.isAndroid) return null;
  try {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'startStreamDownload',
      {
        'url': url,
        'filename': filename,
        'modelsDir': modelsDir,
      },
    );
    return result;
  } catch (e) {
    print('[DownloadNative] startNativeStreamDownload failed: $e');
    return null;
  }
}

void pauseNativeStream(String filename) {
  if (!Platform.isAndroid) return;
  _channel
      .invokeMethod('pauseStreamDownload', {'filename': filename})
      .catchError((_) {});
}

void cancelNativeStream(String filename) {
  if (!Platform.isAndroid) return;
  _channel
      .invokeMethod('cancelStreamDownload', {'filename': filename})
      .catchError((_) {});
}

Future<List<Map<String, dynamic>>> getNativeStreamDownloads() async {
  if (!Platform.isAndroid) return [];
  try {
    final List<dynamic>? result =
        await _channel.invokeListMethod<dynamic>('getStreamDownloads');
    if (result == null) return [];
    return result
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  } catch (e) {
    print('[DownloadNative] getNativeStreamDownloads failed: $e');
    return [];
  }
}

// ── Legacy Android DownloadManager bridges ──

Future<Map<String, dynamic>?> startNativeDownload({
  required String url,
  required String filename,
  required String modelsDir,
}) async {
  if (!Platform.isAndroid) return null;
  try {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'downloadModelInApp',
      {
        'url': url,
        'filename': filename,
        'modelsDir': modelsDir,
      },
    );
    return result;
  } catch (e) {
    print('[DownloadNative] startNativeDownload failed: $e');
    rethrow;
  }
}

Future<bool> cancelNativeDownload({
  required int downloadId,
  required String filename,
}) async {
  if (!Platform.isAndroid) return false;
  try {
    final result = await _channel.invokeMethod<bool>(
      'cancelDownloadInApp',
      {
        'downloadId': downloadId,
        'filename': filename,
      },
    );
    return result ?? false;
  } catch (e) {
    print('[DownloadNative] cancelNativeDownload failed: $e');
    return false;
  }
}

Future<List<Map<String, dynamic>>> getActiveNativeDownloads() async {
  if (!Platform.isAndroid) return [];
  try {
    final List<dynamic>? result = await _channel.invokeListMethod<dynamic>('getActiveDownloads');
    if (result == null) return [];
    return result.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  } catch (e) {
    print('[DownloadNative] getActiveNativeDownloads failed: $e');
    return [];
  }
}

/// Simple size/checksum validation helper.
///
/// Checks that [path] exists, has non-zero size, and optionally that its
/// size matches [expectedBytes] within a small tolerance (≈1%). When
/// [checkHeader] is true, also validates file header magic for known model
/// types (GGUF, LiteRT-LM, safetensors) to detect truncated / corrupt files.
Future<bool> validateDownloadedFile(
  String path, {
  int? expectedBytes,
  bool checkHeader = true,
}) async {
  final file = File(path);
  if (!await file.exists()) return false;
  final size = await file.length();
  if (size <= 0) return false;
  if (expectedBytes != null && expectedBytes > 0) {
    // Allow ~1% rounding tolerance for catalog sizes (decimal GB/MB).
    if (size < (expectedBytes * 0.99).round()) return false;
  }
  if (!checkHeader) return true;
  RandomAccessFile? raf;
  try {
    raf = await file.open();
    final header = await raf.read(16);
    if (header.length < 4) return false;
    final lower = path.toLowerCase();
    if (lower.endsWith('.gguf')) {
      // GGUF magic: 'GGUF' 0x47 0x47 0x55 0x46 at offset 0
      if (header.length < 4 ||
          header[0] != 0x47 ||
          header[1] != 0x47 ||
          header[2] != 0x55 ||
          header[3] != 0x46) {
        return false;
      }
    } else if (lower.endsWith('.litertlm')) {
      if (header.length < 8) return false;
      final isLlm = header[0] == 0x4C && // 'L'
          header[1] == 0x49 && // 'I'
          header[2] == 0x54 && // 'T'
          header[3] == 0x45 && // 'E'
          header[4] == 0x52 && // 'R'
          header[5] == 0x54 && // 'T'
          header[6] == 0x4C && // 'L'
          header[7] == 0x4D; // 'M'
      if (!isLlm) return false;
    } else if (lower.endsWith('.safetensors')) {
      if (header.length < 9) return false;
      var headerLen = 0;
      for (var i = 0; i < 8; i++) {
        headerLen += header[i] << (8 * i);
      }
      if (headerLen <= 2 || headerLen > size - 8) return false;
      if (headerLen > 64 * 1024 * 1024) return false;
      if (header[8] != 0x7B) return false; // '{'
    }
    return true;
  } catch (_) {
    return false;
  } finally {
    try {
      await raf?.close();
    } catch (_) {}
  }
}
