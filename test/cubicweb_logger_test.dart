import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/cubicweb/cubicweb_event.dart';
import 'package:cubiclm/services/cubicweb/cubicweb_logger.dart';

CubicWebLogger _logger() => CubicWebLogger();

void main() {
  group('dedup (§24)', () {
    test('repeats collapse with occurrence count', () {
      final log = _logger();
      for (var i = 0; i < 30; i++) {
        log.log(
          severity: CwSeverity.error,
          category: CwCategory.runtime,
          component: 'PREVIEW',
          errorCode: CwCodes.nodeUnavailable,
          title: 't',
          message: 'm',
          operation: 'preview-serve',
          projectId: 'p1',
          aiCanFix: false,
        );
      }
      expect(log.events.length, 1);
      expect(log.events.single.occurrenceCount, 30);
      expect(log.unreadErrors.value, 30);
    });

    test('different operations stay separate', () {
      final log = _logger();
      log.log(
          severity: CwSeverity.error,
          category: CwCategory.runtime,
          component: 'PREVIEW',
          errorCode: CwCodes.nodeUnavailable,
          title: 't',
          message: 'm',
          operation: 'preview-serve',
          aiCanFix: false);
      log.log(
          severity: CwSeverity.error,
          category: CwCategory.runtime,
          component: 'CLI',
          errorCode: CwCodes.nodeUnavailable,
          title: 't',
          message: 'm',
          operation: 'cli-install',
          aiCanFix: false);
      expect(log.events.length, 2);
    });

    test('memory cap enforced', () {
      final log = _logger();
      for (var i = 0; i < 250; i++) {
        log.log(
          severity: CwSeverity.info,
          category: CwCategory.unknown,
          component: 'T',
          title: 't$i',
          message: 'm',
          operation: 'op$i',
          aiCanFix: true,
        );
      }
      expect(log.events.length, 200);
    });
  });

  group('AI guards (§5)', () {
    test('hasBlockingIssue true only for aiCanFix=false errors', () {
      final log = _logger();
      expect(log.hasBlockingIssue(), isFalse);
      log.log(
          severity: CwSeverity.error,
          category: CwCategory.dependency,
          component: 'T',
          title: 't',
          message: 'm',
          aiCanFix: true);
      expect(log.hasBlockingIssue(), isFalse);
      log.log(
          severity: CwSeverity.error,
          category: CwCategory.runtime,
          component: 'T',
          errorCode: CwCodes.nodeUnavailable,
          title: 't',
          message: 'm',
          aiCanFix: false);
      expect(log.hasBlockingIssue(), isTrue);
    });

    test('blocking lookup scopes to project', () {
      final log = _logger();
      log.log(
          severity: CwSeverity.error,
          category: CwCategory.runtime,
          component: 'T',
          errorCode: CwCodes.nodeUnavailable,
          title: 't',
          message: 'm',
          projectId: 'p1',
          aiCanFix: false);
      expect(log.hasBlockingIssue(projectId: 'p1'), isTrue);
      expect(log.hasBlockingIssue(projectId: 'p2'), isFalse);
      expect(log.blockingIssue(projectId: 'p2'), isNull);
    });

    test('recentForAi carries structured blocks', () {
      final log = _logger();
      log.log(
          severity: CwSeverity.error,
          category: CwCategory.runtime,
          component: 'PREVIEW',
          errorCode: CwCodes.nodeUnavailable,
          title: 't',
          message: 'm',
          aiCanFix: false);
      final ctx = log.recentForAi();
      expect(ctx, contains('CW-RUNTIME-001'));
      expect(ctx, contains('aiCanFix: false'));
    });
  });

  group('redaction before store (§26)', () {
    test('secrets masked in stored event', () {
      final log = _logger();
      final e = log.log(
        severity: CwSeverity.error,
        category: CwCategory.network,
        component: 'T',
        title: 't',
        message: 'key OPENAI_API_KEY=sk-secret123 failed',
        command: 'curl --token abc123',
        aiCanFix: false,
      );
      expect(e.message, contains('[REDACTED]'));
      expect(e.message, isNot(contains('sk-secret123')));
      expect(e.command, isNot(contains('abc123')));
    });
  });

  group('clear + read', () {
    test('clear empties and resets badge', () async {
      final log = _logger();
      log.log(
          severity: CwSeverity.error,
          category: CwCategory.runtime,
          component: 'T',
          title: 't',
          message: 'm',
          aiCanFix: false);
      expect(log.unreadErrors.value, 1);
      log.markAllRead();
      expect(log.unreadErrors.value, 0);
      await log.clear();
      expect(log.events, isEmpty);
    });
  });
}
