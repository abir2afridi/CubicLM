import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/app_log_service.dart';

/// Export-time secret scrubbing: nothing pasted to GitHub/chat may leak
/// a key, while the live list keeps full fidelity for debugging.
void main() {
  group('scrubExportSecrets', () {
    test('scrubs query-string keys (Gemini ?key= URLs)', () {
      const raw =
          'GET https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0:generateContent?key=AIzaSyD-secret123 failed: 400';
      final out = scrubExportSecrets(raw);
      expect(out.contains('AIzaSyD-secret123'), isFalse);
      expect(out.contains('key=***'), isTrue);
      expect(out.contains('gemini-2.0'), isTrue);
    });

    test('scrubs bearer tokens', () {
      const raw = "{'Authorization': 'Bearer sk-ant-abcdefgh12345678'}";
      final out = scrubExportSecrets(raw);
      expect(out.contains('sk-ant-abcdefgh12345678'), isFalse);
      expect(out.contains('Bearer ***'), isTrue);
    });

    test('scrubs bare vendor keys', () {
      expect(scrubExportSecrets('key xai-abc123XYZ_-9 here'), 'key *** here');
      expect(scrubExportSecrets('gsk_live_456 DEF'), isNot(contains('456')));
    });

    test('leaves ordinary text untouched', () {
      const raw =
          'Model loaded: CPU (6 threads), ctx=2048. No monkey business.';
      expect(scrubExportSecrets(raw), raw);
    });

    test('formatForExport scrubs message and details', () {
      final e = AppLogEntry(
        level: 'ERROR',
        message: 'Cloud failed',
        category: LogCategory.cloud,
        timestamp: DateTime(2026, 9, 10),
        details: 'url https://x.test/?key=SECRETVALUE123 rest',
      );
      final out = e.formatForExport();
      expect(out.contains('SECRETVALUE123'), isFalse);
      expect(out.contains('key=***'), isTrue);
    });
  });
}
