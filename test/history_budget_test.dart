import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/utils/history_budget.dart';

Map<String, String> msg(String role, String content) =>
    {'role': role, 'content': content};

void main() {
  group('historyChars', () {
    test('sums content lengths from start offset', () {
      final h = [msg('user', 'ab'), msg('assistant', 'cde')];
      expect(historyChars(h), 5);
      expect(historyChars(h, 1), 3);
      expect(historyChars([]), 0);
    });
  });

  group('capMiddle', () {
    test('short content passes through identical', () {
      final m = msg('user', 'hello');
      expect(capMiddle(m, 100), same(m));
    });

    test('long content keeps head + marker + tail', () {
      final c = 'H' * 400 + 'M' * 400 + 'T' * 400;
      final out = capMiddle(msg('assistant', c), 500);
      expect(out['content']!.length, 500);
      expect(out['content']!.startsWith('H' * 10), isTrue);
      expect(out['content']!.contains(historyTrimMarker), isTrue);
      expect(out['content']!.endsWith('T' * 10), isTrue);
      expect(out['role'], 'assistant');
    });

    test('tiny cap falls back to plain prefix cut', () {
      final out = capMiddle(msg('user', 'x' * 500), 50);
      expect(out['content']!.length, 50);
      expect(out['content']!.contains(historyTrimMarker), isFalse);
    });
  });

  group('fitHistoryToBudget', () {
    test('short history untouched', () {
      final h = [msg('user', 'q'), msg('assistant', 'a')];
      expect(fitHistoryToBudget(h, 1000).length, 2);
    });

    test('drops oldest but always keeps current + previous', () {
      final h = [
        msg('user', 'old1'),
        msg('assistant', 'oldA1'),
        msg('user', 'q'),
        msg('assistant', 'a'),
      ];
      final out = fitHistoryToBudget(h, 10);
      // old1 (oldest) is gone, but current + previous always survive.
      expect(out.length, greaterThanOrEqualTo(2));
      expect(out[out.length - 1]['content'], 'a');
      expect(out[out.length - 2]['content'], 'q');
      expect(out.any((m) => m['content'] == 'old1'), isFalse);
      expect(historyChars(out) <= 10, isTrue);
    });

    test('single huge assistant turn is truncated, not dropped', () {
      final big = 'C' * 20000; // full HTML answer
      final h = [
        msg('user', 'build a snake game'),
        msg('assistant', big),
        msg('user', 'make it better'),
      ];
      final out = fitHistoryToBudget(h, 500);
      // Everything fits after truncation: the huge middle turn carries
      // the marker instead of wiping the other turns.
      expect(out.length, 3);
      expect(out[1]['content']!.contains(historyTrimMarker), isTrue);
      expect(out.last['content'], 'make it better');
      expect(historyChars(out) <= 500, isTrue);
    });

    test('over-budget history still keeps current + previous', () {
      final big = 'C' * 20000;
      final h = [
        msg('user', 'build a snake game'),
        msg('assistant', big),
        msg('user', 'make it better'),
      ];
      final out = fitHistoryToBudget(h, 60);
      expect(out.length, 2);
      expect(out.last['content'], 'make it better');
      expect(historyChars(out) <= 60, isTrue);
    });

    test('single message history returned as-is', () {
      final h = [msg('user', 'hi')];
      expect(fitHistoryToBudget(h, 1).length, 1);
    });
  });
}
