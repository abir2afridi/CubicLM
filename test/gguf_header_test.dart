import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/inference_service.dart';

/// Guards against native SIGABRT: malformed GGUF headers must be rejected
/// in Dart before reaching the FFI boundary.
void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gguf_test_');
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  File writeGguf(String name,
      {int version = 3, int tensors = 100, int totalSize = 2 * 1024 * 1024}) {
    final f = File('${tmp.path}/$name');
    final head = ByteData(32);
    head.setUint8(0, 0x47); // G
    head.setUint8(1, 0x47); // G
    head.setUint8(2, 0x55); // U
    head.setUint8(3, 0x46); // F
    head.setUint32(4, version, Endian.little);
    head.setUint64(8, tensors, Endian.little);
    head.setUint64(16, 10, Endian.little); // meta count
    head.setUint64(24, 0, Endian.little);
    final raf = f.openSync(mode: FileMode.write);
    raf.writeFromSync(head.buffer.asUint8List());
    // Pad to totalSize so the >=1MB check passes
    var left = totalSize - 32;
    final chunk = Uint8List(65536);
    while (left > 0) {
      final n = left > chunk.length ? chunk.length : left;
      raf.writeFromSync(chunk, 0, n);
      left -= n;
    }
    raf.closeSync();
    return f;
  }

  group('validateGgufHeader', () {
    test('accepts a sane GGUF v2/v3 header', () {
      expect(
          InferenceService.validateGgufHeader(writeGguf('good.gguf')),
          isNull);
      expect(
          InferenceService.validateGgufHeader(
              writeGguf('good2.gguf', version: 2)),
          isNull);
    });

    test('rejects bad magic', () {
      final f = writeGguf('bad.gguf');
      final bytes = f.readAsBytesSync();
      bytes[0] = 1;
      bytes[1] = 2;
      bytes[2] = 3;
      bytes[3] = 4;
      f.writeAsBytesSync(bytes, flush: true);
      expect(InferenceService.validateGgufHeader(f), contains('magic'));
    });

    test('rejects unknown version', () {
      final f = writeGguf('v9.gguf', version: 9);
      expect(InferenceService.validateGgufHeader(f), contains('version'));
    });

    test('rejects zero tensor count', () {
      final f = writeGguf('zero.gguf', tensors: 0);
      expect(
          InferenceService.validateGgufHeader(f), contains('tensor'));
    });

    test('rejects tiny files (truncated download)', () {
      final f = writeGguf('tiny.gguf', totalSize: 512);
      expect(
          InferenceService.validateGgufHeader(f), contains('too small'));
    });

    test('rejects missing file', () {
      final f = File('${tmp.path}/nope.gguf');
      expect(InferenceService.validateGgufHeader(f), isNotNull);
    });
  });
}
