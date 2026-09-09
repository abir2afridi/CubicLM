import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/controllers/model_controller.dart';
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

  /// Craft a minimal but structurally valid GGUF: v3, 0 metadata KVs,
  /// 1 F32 tensor, real tensor payload, padded to [fileBytes].
  File writeTensorGguf(String name,
      {required int dim, required int fileBytes}) {
    final f = File('${tmp.path}/$name');
    const nameBytes = [0x77]; // "w"
    // header 32 + namelen(8)+1 + ndims(4) + dim(8) + type(4) + offset(8)
    const tableEnd = 32 + 8 + 1 + 4 + 8 + 4 + 8;
    const dataBase = ((tableEnd + 31) ~/ 32) * 32;
    assert(dataBase == 96);
    final raf = f.openSync(mode: FileMode.write);
    final head = ByteData(32);
    head.setUint8(0, 0x47);
    head.setUint8(1, 0x47);
    head.setUint8(2, 0x55);
    head.setUint8(3, 0x46);
    head.setUint32(4, 3, Endian.little);
    head.setUint64(8, 1, Endian.little); // 1 tensor
    head.setUint64(16, 0, Endian.little); // 0 metadata
    head.setUint64(24, 0, Endian.little);
    raf.writeFromSync(head.buffer.asUint8List());
    final tb = ByteData(8 + nameBytes.length + 4 + 8 + 4 + 8);
    var o = 0;
    tb.setUint64(o, nameBytes.length, Endian.little);
    o += 8;
    for (final b in nameBytes) {
      tb.setUint8(o++, b);
    }
    tb.setUint32(o, 1, Endian.little); // n_dims
    o += 4;
    tb.setUint64(o, dim, Endian.little); // dim
    o += 8;
    tb.setUint32(o, 0, Endian.little); // F32
    o += 4;
    tb.setUint64(o, 0, Endian.little); // offset
    raf.writeFromSync(tb.buffer.asUint8List());
    // Pad from current pos to fileBytes.
    var left = fileBytes - tableEnd;
    final chunk = Uint8List(65536);
    while (left > 0) {
      final n = left > chunk.length ? chunk.length : left;
      raf.writeFromSync(chunk, 0, n);
      left -= n;
    }
    raf.closeSync();
    return f;
  }

  group('validateGgufHeader tensor table', () {
    test('accepts a complete tensor payload', () {
      // 32 floats = 128B payload, 2MB file.
      final f =
          writeTensorGguf('valid.gguf', dim: 32, fileBytes: 2 * 1024 * 1024);
      expect(InferenceService.validateGgufHeader(f), isNull);
    });

    test('rejects tensor data cut short (truncated download)', () {
      // Claims 1M floats (4MB) but file holds only 2MB.
      final f = writeTensorGguf('cut.gguf',
          dim: 1000000, fileBytes: 2 * 1024 * 1024);
      expect(InferenceService.validateGgufHeader(f), contains('truncated'));
    });
  });

  group('isRamInsufficient', () {
    const gb = 1024 * 1024 * 1024;

    test('blocks big model on tight RAM (the reported crash)', () {
      // 3GB model, 4GB free: mmap pressure + KV + headroom exceeds.
      expect(
          ModelController.isRamInsufficient(
            availableBytes: 4 * gb,
            fileBytes: 3 * gb,
            kvBytes: 300 * 1024 * 1024,
          ),
          isTrue);
    });

    test('allows small model with headroom', () {
      expect(
          ModelController.isRamInsufficient(
            availableBytes: 5 * gb,
            fileBytes: 146 * 1024 * 1024,
            kvBytes: 100 * 1024 * 1024,
          ),
          isFalse);
    });

    test('unmeasurable memory never blocks (warn path handles it)', () {
      expect(
          ModelController.isRamInsufficient(
            availableBytes: 0,
            fileBytes: 3 * gb,
            kvBytes: 0,
          ),
          isFalse);
    });
  });
}
