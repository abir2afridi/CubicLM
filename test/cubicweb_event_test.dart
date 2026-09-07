import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/cubicweb/cubicweb_event.dart';

void main() {
  group('classifyFailure — code path stays out of System Logs', () {
    test('JS syntax error → CODE, no code', () {
      final r = classifyFailure(
          stderr: 'SyntaxError: Unexpected token < in JSON');
      expect(r.category, CwCategory.code);
      expect(r.errorCode, isNull);
      expect(r.aiCanFix, isTrue);
    });

    test('unclosed JSX tag → CODE, no code', () {
      final r = classifyFailure(
          stderr: 'JSX element has no corresponding closing tag');
      expect(r.category, CwCategory.code);
      expect(r.errorCode, isNull);
    });

    test('TypeError → CODE', () {
      final r = classifyFailure(
          stderr: 'TypeError: Cannot read properties of undefined');
      expect(r.category, CwCategory.code);
      expect(r.errorCode, isNull);
    });
  });

  group('classifyFailure — runtime/platform (§32 B–E)', () {
    test('node missing → CW-RUNTIME-001, aiCanFix false', () {
      final r = classifyFailure(
        command: 'npm run dev',
        processSpawnFailed: true,
        stderr: 'node: command not found',
        platform: 'android',
      );
      expect(r.errorCode, CwCodes.nodeUnavailable);
      expect(r.category, CwCategory.runtime);
      expect(r.aiCanFix, isFalse);
      expect(r.fallbackAvailable, isNotEmpty);
    });

    test('python missing → CW-RUNTIME-002', () {
      final r = classifyFailure(
          stderr: 'python: command not found', processSpawnFailed: true);
      expect(r.errorCode, CwCodes.pythonUnavailable);
      expect(r.aiCanFix, isFalse);
    });

    test('exec format error → CW-NATIVE-001', () {
      final r = classifyFailure(
          stderr: 'cannot execute binary file: Exec format error');
      expect(r.errorCode, CwCodes.nativeIncompatible);
      expect(r.category, CwCategory.native);
      expect(r.aiCanFix, isFalse);
    });

    test('permission denied → CW-PERM-001', () {
      final r = classifyFailure(stderr: 'npm ERR! EACCES: permission denied');
      expect(r.errorCode, CwCodes.permissionDenied);
      expect(r.aiCanFix, isFalse);
    });

    test('localhost refused with server expected → CW-PREVIEW-002', () {
      final r = classifyFailure(
        stderr: 'net::ERR_CONNECTION_REFUSED http://127.0.0.1:5173/',
        localhostExpected: true,
      );
      expect(r.errorCode, CwCodes.localhostUnavailable);
      expect(r.aiCanFix, isFalse);
    });

    test('same refusal WITHOUT server context is not compatibility', () {
      final r = classifyFailure(
          stderr: 'Error: connect ECONNREFUSED 93.184.216.34:443');
      // No localhostExpected and no plain-compat signal → not a code.
      expect(r.errorCode, isNull);
    });
  });

  group('classifyFailure — dependency/network/resource', () {
    test('npm 404 version → DEPENDENCY, AI may fix, no code', () {
      final r = classifyFailure(
        command: 'npm install',
        stderr: 'npm ERR! 404 Not Found - GET foo@99.99.99 - not found',
        exitCode: 1,
      );
      expect(r.category, CwCategory.dependency);
      expect(r.errorCode, isNull);
      expect(r.aiCanFix, isTrue);
    });

    test('offline install → CW-NET-001', () {
      final r = classifyFailure(
        command: 'npm install',
        stderr: 'npm ERR! network request failed: ENOTFOUND registry.npmjs.org',
      );
      expect(r.errorCode, CwCodes.networkFailed);
      expect(r.aiCanFix, isFalse);
    });

    test('OOM kill → CW-RESOURCE-001', () {
      final r = classifyFailure(
          stderr: 'Killed: out of memory', exitCode: 137);
      expect(r.errorCode, CwCodes.resourceExhausted);
      expect(r.aiCanFix, isFalse);
    });

    test('timeout → process failure with retry', () {
      final r = classifyFailure(
          stderr: 'TimeoutException after 0:10:00.000000');
      expect(r.errorCode, CwCodes.processFailed);
      expect(r.fallbackAvailable, 'RETRY');
    });
  });

  group('classifyFailure — conservative fallthrough (§28)', () {
    test('plain exit 1 is NOT a system event', () {
      final r = classifyFailure(
          command: 'ls /nonexistent', exitCode: 1, stderr: 'No such file');
      expect(r.errorCode, isNull);
      expect(r.aiCanFix, isTrue);
    });

    test('grep-style empty result is NOT compatibility', () {
      final r = classifyFailure(command: 'grep foo bar.txt', exitCode: 1);
      expect(r.errorCode, isNull);
    });

    test('npm build compiler error → CODE path', () {
      final r = classifyFailure(
        command: 'npm run build',
        stderr: 'Failed to compile: Unexpected token (18:4)',
        exitCode: 1,
      );
      expect(r.errorCode, isNull);
      expect(r.aiCanFix, isTrue);
    });
  });

  group('devServerCodeToCw', () {
    test('node-missing maps to runtime code', () {
      expect(devServerCodeToCw('node-missing', 'x'),
          CwCodes.nodeUnavailable);
    });

    test('dependency-flavored install failure maps to null (AI path)', () {
      expect(
          devServerCodeToCw(
              'install-failed', 'npm ERR! 404 foo@9.9.9 not found'),
          isNull);
    });

    test('network-flavored install failure maps to network', () {
      expect(
          devServerCodeToCw(
              'install-failed', 'ENOTFOUND registry.npmjs.org'),
          CwCodes.networkFailed);
    });

    test('start timeout maps to preview code', () {
      expect(devServerCodeToCw('start-timeout', 'no url'),
          CwCodes.devServerFailed);
    });
  });

  group('redactSecrets (§36)', () {
    test('doc example: OPENAI_API_KEY masked', () {
      expect(redactSecrets('OPENAI_API_KEY=sk-xxxxxxxx'),
          'OPENAI_API_KEY=[REDACTED]');
    });

    test('bearer + key=value forms', () {
      expect(redactSecrets('Authorization: Bearer abc.def.ghi'),
          contains('[REDACTED]'));
      expect(redactSecrets('--token hunter2 run'), contains('[REDACTED]'));
      expect(redactSecrets('password=hunter2'), contains('[REDACTED]'));
      expect(redactSecrets('cookie: session=abc'), contains('[REDACTED]'));
    });

    test('clean text untouched', () {
      expect(redactSecrets('npm run dev -- --port 5173'),
          'npm run dev -- --port 5173');
    });
  });

  group('SystemLogEvent', () {
    test('round-trips through maps', () {
      final e = SystemLogEvent(
        id: 'CW-EV-1',
        traceId: 'CW-ABC123',
        timestampMs: 10,
        severity: CwSeverity.error,
        category: CwCategory.runtime,
        component: 'PREVIEW',
        errorCode: CwCodes.nodeUnavailable,
        title: 't',
        message: 'm',
        aiCanFix: false,
      );
      final back = SystemLogEvent.fromMap(e.toMap());
      expect(back.id, 'CW-EV-1');
      expect(back.severity, CwSeverity.error);
      expect(back.aiCanFix, isFalse);
      expect(back.occurrenceCount, 1);
    });

    test('aiContextBlock carries the §16 shape', () {
      final e = SystemLogEvent(
        id: 'x',
        traceId: 'CW-1',
        timestampMs: 1,
        severity: CwSeverity.error,
        category: CwCategory.runtime,
        component: 'PREVIEW',
        errorCode: CwCodes.nodeUnavailable,
        title: 't',
        message: 'm',
        aiCanFix: false,
        fallbackAvailable: 'USE_CLOUD_RUNTIME',
      );
      final b = e.aiContextBlock();
      expect(b, contains('CW-RUNTIME-001'));
      expect(b, contains('aiCanFix: false'));
      expect(b, contains('USE_CLOUD_RUNTIME'));
    });

    test('trace ids look like CW-XXXXXX', () {
      final t = newTraceId();
      expect(RegExp(r'^CW-[0-9A-F]{6}$').hasMatch(t), isTrue);
    });
  });
}
