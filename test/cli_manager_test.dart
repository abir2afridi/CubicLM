import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/runtime/ansi.dart';
import 'package:cubiclm/services/runtime/cli_manager.dart';
import 'package:cubiclm/services/runtime/cli_manifest.dart';
import 'package:cubiclm/services/runtime/cli_providers.dart';

void main() {
  group('matchNpmGlobalInstall', () {
    test('matches npm install -g', () {
      expect(matchNpmGlobalInstall('npm install -g @anthropic-ai/claude-code'),
          ['@anthropic-ai/claude-code']);
    });

    test('matches short forms and strips versions', () {
      expect(matchNpmGlobalInstall('npm i -g opencode-ai@latest'),
          ['opencode-ai']);
      expect(
          matchNpmGlobalInstall(
              'npm install --global cline@2.0.0'),
          ['cline']);
    });

    test('rejects non-global and non-npm commands', () {
      expect(matchNpmGlobalInstall('npm install lodash'), isEmpty);
      expect(matchNpmGlobalInstall('npm run dev'), isEmpty);
      expect(matchNpmGlobalInstall('pip install -g foo'), isEmpty);
      expect(matchNpmGlobalInstall(''), isEmpty);
    });

    test('matches multiple packages', () {
      expect(
          matchNpmGlobalInstall('npm i -g opencode-ai cline'),
          ['opencode-ai', 'cline']);
    });
  });

  group('redactCommand / isSensitiveCommand', () {
    test('masks token args', () {
      expect(redactCommand('cmd --token abc123'), contains('[redacted]'));
      expect(redactCommand('cmd --token abc123'), isNot(contains('abc123')));
      expect(redactCommand('x --key=Y password=secret'), isNot(contains('secret')));
    });

    test('flags auth commands as sensitive', () {
      expect(isSensitiveCommand('cline auth'), isTrue);
      expect(isSensitiveCommand('npm login'), isTrue);
      expect(isSensitiveCommand('npm run dev'), isFalse);
      expect(isSensitiveCommand('ls -la'), isFalse);
    });
  });

  group('npmInstallArgs', () {
    test('builds managed global install argv', () {
      expect(
          npmInstallArgs('@anthropic-ai/claude-code', '/p'),
          ['install', '-g', '@anthropic-ai/claude-code', '--prefix', '/p',
           '--no-audit', '--no-fund']);
    });

    test('latest flag appends @latest without breaking scopes', () {
      final args = npmInstallArgs('@kilocode/cli', '/p', latest: true);
      expect(args[2], '@kilocode/cli@latest');
      expect(npmInstallArgs('cline', '/p', latest: true)[2], 'cline@latest');
    });
  });

  group('catalog + models', () {
    test('catalog uses verified npm packages only', () {
      final npmOnes = kCliCatalog.where(
          (m) => m.provider == CliProviderKind.npm);
      expect(npmOnePkgs(npmOnes), containsAll([
        '@anthropic-ai/claude-code',
        'opencode-ai',
        'cline',
        '@kilocode/cli',
      ]));
    });

    test('InstalledCli round-trips through maps', () {
      const e = InstalledCli(
        manifestId: 'opencode',
        version: '1.2.3',
        installDir: '/d',
        binaryPath: '/d/bin/opencode',
        provider: 'npm',
        installedAtMs: 1,
        lastVerifiedMs: 2,
      );
      final back = InstalledCli.fromMap(e.toMap());
      expect(back.manifestId, 'opencode');
      expect(back.version, '1.2.3');
      expect(back.binaryPath, '/d/bin/opencode');
    });

    test('launchable states are honest', () {
      expect(cliIsLaunchable(CliStatus.ready), isTrue);
      expect(cliIsLaunchable(CliStatus.updateAvailable), isTrue);
      expect(cliIsLaunchable(CliStatus.runtimeMissing), isFalse);
      expect(cliIsLaunchable(CliStatus.broken), isFalse);
      expect(cliIsLaunchable(CliStatus.notInstalled), isFalse);
    });
  });

  group('stripAnsi', () {
    test('removes colors and cursor codes, keeps text', () {
      expect(stripAnsi('\x1B[32m✓ ok\x1B[0m'), '✓ ok');
      expect(stripAnsi('\x1B[1;34mclaude\x1B[0m'), 'claude');
      expect(stripAnsi('\x1B[?1049h\x1B[Htitle'), 'title');
    });

    test('plain text untouched', () {
      expect(stripAnsi('npm run dev'), 'npm run dev');
      expect(stripAnsi(''), '');
    });
  });

  group('command history', () {
    test('records, dedups, caps and skips secrets', () {
      final mgr = CliManagerService();
      for (var i = 0; i < 60; i++) {
        mgr.recordCommand('cmd-$i');
      }
      expect(mgr.recentCommands.length, 50);
      expect(mgr.recentCommands.first, 'cmd-59');
      mgr.recordCommand('cmd-59');
      expect(mgr.recentCommands.length, 50);
      expect(mgr.recentCommands.first, 'cmd-59');
      mgr.recordCommand('run --token abc123');
      expect(mgr.recentCommands.contains('run --token abc123'), isFalse);
      mgr.recordCommand('cline auth');
      expect(mgr.recentCommands.contains('cline auth'), isFalse);
      mgr.recordCommand('   ');
      expect(mgr.recentCommands.length, 50);
    });

    test('suggests installed commands by prefix', () {
      final mgr = CliManagerService();
      mgr.recordCommand('npm run dev');
      // git is a system entry → suggested even when unregistered.
      expect(suggestContains(mgr.suggestCommands('gi'), 'git'), isTrue);
      expect(
          suggestContains(
              mgr.suggestCommands('npm'), 'npm run dev'),
          isTrue);
      expect(mgr.suggestCommands(''), isEmpty);
      expect(mgr.suggestCommands('zzz'), isEmpty);
    });
  });
}

bool suggestContains(List<String> sug, String want) =>
    sug.any((s) => s == want || s.startsWith('$want '));

List<String> npmOnePkgs(Iterable<CliManifest> ms) =>
    ms.map((m) => m.npmPackage ?? '').toList();
