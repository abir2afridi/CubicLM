import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/runtime/runtime_manager.dart';

void main() {
  group('firstVersionLine', () {
    test('takes the first non-empty trimmed line', () {
      expect(firstVersionLine('v22.14.0\nnpm bundled\n'), 'v22.14.0');
      expect(firstVersionLine('\n  10.8.2  \n'), '10.8.2');
      expect(firstVersionLine(''), '');
      expect(firstVersionLine('\n\n'), '');
    });

    test('caps pathological single lines', () {
      final long = 'v${'1' * 200}';
      expect(firstVersionLine(long).length, 64);
    });
  });

  group('runningSummary registry', () {
    test('empty registry reports idle', () {
      expect(RuntimeManager().runningSummary(), 'No runtimes running.');
    });

    test('runners describe, empty ones skipped, unregister works', () {
      final m = RuntimeManager();
      m.registerRunner('a', () => '• Vite dev server http://x (project p)');
      m.registerRunner('b', () => '  ');
      m.registerRunner('boom', () => throw Exception('x'));
      final s = m.runningSummary();
      expect(s, contains('Vite dev server'));
      expect(s, isNot(contains('boom')));
      m.unregisterRunner('a');
      expect(m.runningSummary(), 'No runtimes running.');
    });
  });
}
