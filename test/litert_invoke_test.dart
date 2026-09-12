import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/inference_litert.dart';

/// LiteRT executor invoke failures (Status 13 / JNI): the session is
/// poisoned, so the engine retries once fresh — and the user gets
/// guidance instead of a raw native dump.
void main() {
  const reported =
      'Status Code: 13. Message: ERROR: [third_party/odml/litert_lm/runtime/executor/llm_litert_compiled_model_executor.cc:756]\n'
      '└ Failed to invoke the compiled model, com.google.ai.edge.litertlm.LiteRtLmJniException: Status Code: 13.';

  group('isInvokeFailure', () {
    test('detects the reported executor failure', () {
      expect(LiteRtEngine.isInvokeFailure(reported), isTrue);
      expect(
          LiteRtEngine.isInvokeFailure(
              'LiteRtLmJniException: boom'),
          isTrue);
    });

    test('ignores ordinary errors', () {
      expect(
          LiteRtEngine.isInvokeFailure('network timeout'), isFalse);
      expect(LiteRtEngine.isInvokeFailure(''), isFalse);
    });
  });

  group('friendlyInvokeError', () {
    test('invoke failure gets guidance, not the dump', () {
      final msg =
          LiteRtEngine.friendlyInvokeError(reported, multimodal: true);
      expect(msg.startsWith('ERROR:'), isTrue);
      expect(msg.contains('working memory'), isTrue);
      expect(msg.contains('without the image'), isTrue);
      expect(msg.contains('llm_litert_compiled_model_executor'), isFalse);
    });

    test('plain failures keep the raw detail', () {
      final msg =
          LiteRtEngine.friendlyInvokeError('network timeout');
      expect(msg.contains('network timeout'), isTrue);
    });
  });
}
