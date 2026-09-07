import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/cloud/model_health.dart';

void main() {
  group('summarizeModelError', () {
    test('bad key', () {
      expect(summarizeModelError(Exception('401 Unauthorized')),
          'Invalid API key (401)');
      expect(summarizeModelError('incorrect api key provided'),
          'Invalid API key (401)');
    });

    test('spent credits / quota', () {
      expect(summarizeModelError('402 Payment Required'), contains('402'));
      expect(
          summarizeModelError('insufficient_quota: you exceeded'),
          contains('quota'));
      expect(summarizeModelError('No credits left'), contains('credits'));
    });

    test('rate limit / forbidden / gone', () {
      expect(summarizeModelError('429 too many requests'),
          'Rate limited (429)');
      expect(summarizeModelError('403 Forbidden'), 'Forbidden (403)');
      expect(summarizeModelError('404 model not found'),
          'Model not found (404)');
    });

    test('timeout / network', () {
      expect(summarizeModelError('TimeoutException after 20s'), 'Timed out');
      expect(summarizeModelError('SocketException: failed host lookup'),
          'Network unreachable');
    });

    test('long unknown errors are trimmed to one line', () {
      final e = Exception('weird\nmultiline   error ${'x' * 200}');
      final s = summarizeModelError(e);
      expect(s.contains('\n'), isFalse);
      expect(s.length, lessThanOrEqualTo(91));
    });
  });

  group('shouldAutoSync', () {
    final now = DateTime(2026, 9, 7, 12);

    test('never synced → sync', () {
      expect(
          shouldAutoSync(
              lastSyncIso: null, intervalHours: 24, now: now),
          isTrue);
    });

    test('recent sync → skip', () {
      expect(
          shouldAutoSync(
              lastSyncIso: '2026-09-07T06:00:00.000',
              intervalHours: 24,
              now: now),
          isFalse);
    });

    test('stale sync → sync', () {
      expect(
          shouldAutoSync(
              lastSyncIso: '2026-09-05T12:00:00.000',
              intervalHours: 24,
              now: now),
          isTrue);
    });

    test('custom interval respected', () {
      expect(
          shouldAutoSync(
              lastSyncIso: '2026-09-07T00:00:00.000',
              intervalHours: 6,
              now: now),
          isTrue);
      expect(
          shouldAutoSync(
              lastSyncIso: '2026-09-07T00:00:00.000',
              intervalHours: 48,
              now: now),
          isFalse);
    });

    test('bad timestamp → sync', () {
      expect(
          shouldAutoSync(
              lastSyncIso: 'garbage', intervalHours: 24, now: now),
          isTrue);
    });
  });

  group('findNewModels', () {
    test('returns only newcomers, order kept', () {
      expect(findNewModels(['a', 'b'], ['b', 'c', 'a', 'd']), ['c', 'd']);
    });

    test('empty before → everything is new', () {
      expect(findNewModels([], ['x']), ['x']);
    });

    test('nothing new → empty', () {
      expect(findNewModels(['a'], ['a']), isEmpty);
    });
  });

  group('ModelHealth serialization', () {
    test('round-trips', () {
      const h = ModelHealth(
          modelId: 'x/y',
          status: ModelHealthStatus.online,
          latencyMs: 812,
          checkedAtMs: 5);
      final back = ModelHealth.fromMap(h.toMap());
      expect(back.modelId, 'x/y');
      expect(back.status, ModelHealthStatus.online);
      expect(back.latencyMs, 812);
    });

    test('stale testing becomes unknown', () {
      final back = ModelHealth.fromMap(
          {'modelId': 'm', 'status': 'testing'});
      expect(back.status, ModelHealthStatus.unknown);
    });

    test('garbage status becomes unknown', () {
      final back =
          ModelHealth.fromMap({'modelId': 'm', 'status': 'zzz'});
      expect(back.status, ModelHealthStatus.unknown);
    });
  });
}
