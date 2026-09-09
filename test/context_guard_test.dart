import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/inference_gguf.dart';

/// Guards the native KV-cache overflow: once cumulative session tokens
/// pass the context size, llama_decode fails with "Failed to decode
/// prompt" and every later call fails the same way. The app must clear
/// the native session BEFORE that point.
void main() {
  group('needsContextClear', () {
    test('false when plenty of room', () {
      expect(
          GgufEngine.needsContextClear(
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
          GgufEngine.needsContextClear(
            tokensUsed: 1566,
            contextSize: 2048,
            promptChars: 400,
            maxTokens: 512,
          ),
          isTrue);
    });

    test('true when already over capacity', () {
      expect(
          GgufEngine.needsContextClear(
            tokensUsed: 2100,
            contextSize: 2048,
            promptChars: 40,
            maxTokens: 128,
          ),
          isTrue);
    });

    test('false on unknown context size', () {
      expect(
          GgufEngine.needsContextClear(
            tokensUsed: 99999,
            contextSize: 0,
            promptChars: 100,
            maxTokens: 512,
          ),
          isFalse);
    });

    test('huge single prompt triggers clear even on fresh session', () {
      expect(
          GgufEngine.needsContextClear(
            tokensUsed: 0,
            contextSize: 2048,
            promptChars: 8000, // ~2000 tokens (big system prompt)
            maxTokens: 512,
          ),
          isTrue);
    });
  });

  group('trimHistoryToFit', () {
    List<Map<String, String>> hist(int n, [int chars = 400]) => [
          for (var i = 0; i < n; i++)
            {'role': i.isEven ? 'user' : 'assistant', 'content': 'x' * chars}
        ];

    test('keeps history when it fits', () {
      final h = hist(4);
      expect(
          GgufEngine.trimHistoryToFit(
            history: h,
            fixedChars: 500,
            maxPromptChars: 6000,
          ),
          same(h));
    });

    test('drops oldest turns until it fits', () {
      final trimmed = GgufEngine.trimHistoryToFit(
        history: hist(10),
        fixedChars: 500,
        maxPromptChars: 2000,
      )!;
      expect(trimmed.length, lessThan(10));
      expect(trimmed.length, greaterThanOrEqualTo(2));
      // Newest turns survive (last content marker differs by construction)
      expect(trimmed.last['content'], 'x' * 400);
    });

    test('never drops below 2 turns', () {
      final trimmed = GgufEngine.trimHistoryToFit(
        history: hist(6, 2000),
        fixedChars: 500,
        maxPromptChars: 100,
      )!;
      expect(trimmed.length, 2);
    });

    test('null/empty passes through', () {
      expect(
          GgufEngine.trimHistoryToFit(
            history: null,
            fixedChars: 1,
            maxPromptChars: 1,
          ),
          isNull);
      expect(
          GgufEngine.trimHistoryToFit(
            history: [],
            fixedChars: 1,
            maxPromptChars: 1,
          ),
          isEmpty);
    });
  });
}
