import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/inference_android.dart';

/// Guards the native KV-cache overflow: once cumulative session tokens
/// pass the context size, llama_decode fails with "Failed to decode
/// prompt" and every later call fails the same way. The app must clear
/// the native session BEFORE that point.
void main() {
  group('needsContextClear', () {
    test('false when plenty of room', () {
      expect(
          InferenceEngine.needsContextClear(
            tokensUsed: 100,
            contextSize: 2048,
            promptChars: 400, // ~100 tokens
            maxTokens: 512,
          ),
          isFalse);
    });

    test('true when call would overflow (the reported bug)', () {
      // Mirrors the user log: ~1566 cumulative tokens, ctx 2048.
      expect(
          InferenceEngine.needsContextClear(
            tokensUsed: 1566,
            contextSize: 2048,
            promptChars: 400,
            maxTokens: 512,
          ),
          isTrue);
    });

    test('true when already over capacity', () {
      expect(
          InferenceEngine.needsContextClear(
            tokensUsed: 2100,
            contextSize: 2048,
            promptChars: 40,
            maxTokens: 128,
          ),
          isTrue);
    });

    test('false on unknown context size', () {
      expect(
          InferenceEngine.needsContextClear(
            tokensUsed: 99999,
            contextSize: 0,
            promptChars: 100,
            maxTokens: 512,
          ),
          isFalse);
    });

    test('huge single prompt triggers clear even on fresh session', () {
      expect(
          InferenceEngine.needsContextClear(
            tokensUsed: 0,
            contextSize: 2048,
            promptChars: 8000, // ~2000 tokens (big system prompt)
            maxTokens: 512,
          ),
          isTrue);
    });
  });
}
