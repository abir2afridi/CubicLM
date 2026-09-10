import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/inference_gguf.dart';

/// Low-RAM load profile: small phones (4–6GB) die when two GGUF models
/// sit resident at once or when thread/context footprint is too big.
/// These pure helpers decide eviction, thread clamps and the one-shot
/// reduced retry — the native call itself can't be unit-tested.
void main() {
  group('shouldEvictPoolForRam', () {
    test('evicts below 3GB free', () {
      expect(GgufEngine.shouldEvictPoolForRam(1.2), isTrue);
      expect(GgufEngine.shouldEvictPoolForRam(2.9), isTrue);
    });

    test('keeps pool on roomy phones and unknown RAM', () {
      expect(GgufEngine.shouldEvictPoolForRam(3.0), isFalse);
      expect(GgufEngine.shouldEvictPoolForRam(4.7), isFalse);
      expect(GgufEngine.shouldEvictPoolForRam(0), isFalse);
      expect(GgufEngine.shouldEvictPoolForRam(-1), isFalse);
    });
  });

  group('clampThreadsForRam', () {
    test('caps at 2 threads below 2GB free', () {
      expect(
          GgufEngine.clampThreadsForRam(threads: 6, availGb: 1.5), 2);
      expect(
          GgufEngine.clampThreadsForRam(threads: 1, availGb: 1.5), 1);
    });

    test('caps at 3 threads below 3GB free', () {
      expect(
          GgufEngine.clampThreadsForRam(threads: 6, availGb: 2.5), 3);
      expect(
          GgufEngine.clampThreadsForRam(threads: 2, availGb: 2.5), 2);
    });

    test('untouched on roomy phones and unknown RAM', () {
      expect(
          GgufEngine.clampThreadsForRam(threads: 6, availGb: 4.7), 6);
      expect(GgufEngine.clampThreadsForRam(threads: 4, availGb: 0), 4);
    });
  });

  group('reducedContextForRetry', () {
    test('halves until the 512 floor', () {
      expect(GgufEngine.reducedContextForRetry(2048), 1024);
      expect(GgufEngine.reducedContextForRetry(1024), 512);
      expect(GgufEngine.reducedContextForRetry(768), 512);
    });

    test('already-minimal context is unchanged', () {
      expect(GgufEngine.reducedContextForRetry(512), 512);
      expect(GgufEngine.reducedContextForRetry(256), 256);
    });
  });
}
