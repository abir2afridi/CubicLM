import 'package:flutter_test/flutter_test.dart';

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
}

List<String> npmOnePkgs(Iterable<CliManifest> ms) =>
    ms.map((m) => m.npmPackage ?? '').toList();
