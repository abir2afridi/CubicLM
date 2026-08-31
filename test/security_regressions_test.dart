import 'package:flutter_test/flutter_test.dart';
import 'package:cubiclm/services/secure_key_store.dart';

void main() {
  group('SecureKeyStore', () {
    test('in-memory cache read/write', () async {
      final store = SecureKeyStore();
      await store.init();
      await store.write('openai_api_key', 'sk-test-123');
      expect(store.read('openai_api_key'), 'sk-test-123');
      expect(store.has('openai_api_key'), isTrue);

      await store.write('openai_api_key', '');
      expect(store.read('openai_api_key'), '');
      expect(store.has('openai_api_key'), isFalse);
    });

    test(' trims whitespace on write', () async {
      final store = SecureKeyStore();
      await store.init();
      await store.write('google_api_key', '  abc  ');
      expect(store.read('google_api_key'), 'abc');
    });

    test('returns empty for unknown key', () async {
      final store = SecureKeyStore();
      await store.init();
      expect(store.read('nonexistent'), '');
    });
  });
}
