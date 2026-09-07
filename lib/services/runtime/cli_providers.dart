/// Install providers for managed CLIs (real operations only).
///
/// GUI installs perform the same real operations an experienced user
/// would type — never a fake shortcut. Cancellation stops processes.
library;

import 'dart:async';
import 'dart:io';

import 'cli_manifest.dart';
import 'process_runner.dart';

/// Step callback: (stepId, state, detail). States: 'run' | 'ok' | 'fail'.
typedef CliStepFn = void Function(String stepId, String state, String detail);

/// Context every provider install runs with.
class CliInstallCtx {
  /// Managed root: <docs>/cli
  final String cliDir;

  /// Global npm prefix: <cliDir>/npm-global
  final String npmPrefix;

  /// Resolved node binary (null when runtime missing).
  final String? nodeBin;

  /// Resolved npm entry (null when runtime missing).
  final String? npmBin;

  /// Extra environment for child processes (managed PATH/HOME/cache).
  final Map<String, String> env;

  const CliInstallCtx({
    required this.cliDir,
    required this.npmPrefix,
    this.nodeBin,
    this.npmBin,
    this.env = const {},
  });
}

/// Outcome of a successful provider install.
class ProviderResult {
  final String binaryPath;
  final String version;

  const ProviderResult(this.binaryPath, this.version);
}

class ProviderException implements Exception {
  final String code;
  final String message;

  const ProviderException(this.code, this.message);

  @override
  String toString() => message;
}

/// Build the exact npm install argv (pure — unit-tested).
List<String> npmInstallArgs(String npmPackage, String prefix,
    {bool latest = false}) {
  final spec =
      latest && !npmPackage.contains('@', 1) ? '$npmPackage@latest' : (latest
          ? '${_stripVersion(npmPackage)}@latest'
          : npmPackage);
  return ['install', '-g', spec, '--prefix', prefix, '--no-audit', '--no-fund'];
}

String _stripVersion(String pkg) {
  if (pkg.startsWith('@')) {
    final rest = pkg.substring(1);
    final at = rest.indexOf('@');
    return at < 0 ? pkg : '@${rest.substring(0, at)}';
  }
  final at = pkg.indexOf('@');
  return at < 0 ? pkg : pkg.substring(0, at);
}

/// Install-provider abstraction (§16). New mechanisms (binary,
/// archive, git…) plug in here without touching the manager or UI.
abstract class CliInstallProvider {
  /// Human id, e.g. 'npm'.
  String get id;

  /// Real install. Throws [ProviderException] on failure.
  Future<ProviderResult> install(
    CliManifest manifest,
    CliInstallCtx ctx, {
    required CliStepFn onStep,
    required void Function(String line) onLog,
    bool Function()? isCancelled,
    bool latest = false,
  });

  /// Real verification (binary exists + version runs).
  Future<ProviderResult> verify(
    CliManifest manifest,
    CliInstallCtx ctx, {
    required CliStepFn onStep,
  });
}

/// Real `npm install -g <pkg> --prefix <managed>` provider.
class NpmGlobalProvider implements CliInstallProvider {
  /// Install [manifest] for real, streaming progress through [onStep]
  /// and raw lines through [onLog]. [isCancelled] is polled; the npm
  /// process is killed on cancel. Throws [ProviderException] on failure.
  @override
  String get id => 'npm';

  @override
  Future<ProviderResult> install(
    CliManifest manifest,
    CliInstallCtx ctx, {
    required CliStepFn onStep,
    required void Function(String line) onLog,
    bool Function()? isCancelled,
    bool latest = false,
  }) async {
    final pkg = manifest.npmPackage;
    if (pkg == null || pkg.isEmpty) {
      throw const ProviderException(
          'no-package', 'This CLI has no npm package definition.');
    }
    final npm = ctx.npmBin;
    if (npm == null || npm.isEmpty) {
      throw const ProviderException(
          'runtime-missing', 'npm is unavailable — runtime missing.');
    }
    bool cancelled() => isCancelled?.call() ?? false;

    onStep('prepare', 'run', 'Preparing ${manifest.displayName}…');
    try {
      await Directory(ctx.npmPrefix).create(recursive: true);
    } catch (e) {
      onStep('prepare', 'fail', 'Cannot create install dir: $e');
      throw ProviderException(
          'storage-error', 'Cannot create install dir: $e');
    }
    if (cancelled()) {
      throw const ProviderException('cancelled', 'Cancelled.');
    }
    onStep('prepare', 'ok', 'Install dir ready');

    final args = npmInstallArgs(pkg, ctx.npmPrefix, latest: latest);
    onStep('install-package', 'run', 'npm ${args.join(' ')}');
    ProcessSession proc;
    try {
      proc = await ProcessRunner.startSession(
        npm,
        args,
        environment: ctx.env.isEmpty ? null : ctx.env,
        commandLabel: 'npm install -g $pkg',
      );
    } catch (e) {
      onStep('install-package', 'fail', 'Could not start npm: $e');
      throw ProviderException(
          'spawn-failed', 'Could not start npm: $e');
    }
    final sub1 = proc.stdoutLines.listen(onLog);
    final sub2 = proc.stderrLines.listen(onLog);
    int code;
    try {
      while (true) {
        if (cancelled()) {
          await _killQuietly(proc);
          onStep('install-package', 'fail', 'Cancelled by user');
          throw const ProviderException('cancelled', 'Cancelled by user.');
        }
        try {
          code = await proc.exitCode
              .timeout(const Duration(seconds: 2));
          break;
        } on TimeoutException {
          continue;
        }
      }
    } finally {
      try {
        await sub1.cancel();
      } catch (_) {}
      try {
        await sub2.cancel();
      } catch (_) {}
    }
    if (code != 0) {
      onStep('install-package', 'fail', 'npm exited with code $code');
      throw ProviderException('install-failed',
          'npm install failed (exit $code) — see terminal log. If you are offline, connect and Retry.');
    }
    onStep('install-package', 'ok', 'Package installed');

    return verify(manifest, ctx, onStep: onStep);
  }

  /// Verify the binary exists + runs its version command for real.
  @override
  Future<ProviderResult> verify(
    CliManifest manifest,
    CliInstallCtx ctx, {
    required CliStepFn onStep,
  }) async {
    onStep('verify-binary', 'run', 'Verifying ${manifest.command}…');
    final bin = await resolveBinary(manifest, ctx);
    if (bin == null) {
      onStep('verify-binary', 'fail', 'Binary not found after install');
      throw ProviderException('binary-missing',
          '${manifest.command} binary not found after install — see terminal log.');
    }
    onStep('verify-binary', 'ok', bin);
    onStep('detect-version', 'run', '${manifest.command} ${manifest.versionArgs.join(' ')}');
    String version;
    try {
      final r = await ProcessRunner.runOneShot(
        bin,
        manifest.versionArgs,
        environment: ctx.env.isEmpty ? null : ctx.env,
        timeout: const Duration(seconds: 30),
      );
      if (!r.ok) {
        throw Exception(r.stderr.trim().isEmpty
            ? 'exit ${r.exitCode}'
            : r.stderr.trim().split('\n').first);
      }
      version = r.stdout
          .trim()
          .split('\n')
          .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '')
          .trim();
      if (version.length > 64) version = version.substring(0, 64);
      if (version.isEmpty) version = 'installed';
    } catch (e) {
      onStep('detect-version', 'fail', '$e');
      throw ProviderException(
          'version-failed', 'Version check failed: $e');
    }
    onStep('detect-version', 'ok', version);
    return ProviderResult(bin, version);
  }

  /// Locate the managed binary (PATH fallback for adopted installs).
  static Future<String?> resolveBinary(
      CliManifest manifest, CliInstallCtx ctx) async {
    final cmd = manifest.command;
    final binDir = '${ctx.npmPrefix}/bin';
    final cands = <String>[
      '$binDir/$cmd',
      '${ctx.npmPrefix}/$cmd${Platform.isWindows ? '.cmd' : ''}',
    ];
    if (Platform.isWindows) cands.add('$binDir/$cmd.cmd');
    for (final c in cands) {
      try {
        if (await File(c).exists()) return c;
      } catch (_) {}
    }
    // Adopted/system-wide install fallback (PATH).
    try {
      return await ProcessRunner.resolveExecutable(cmd);
    } catch (_) {
      return null;
    }
  }

  /// Ask the registry what the newest published version is (needs net).
  /// Returns null when offline/unknown — never an error state by itself.
  static Future<String?> latestVersion(
      CliManifest manifest, CliInstallCtx ctx) async {
    final pkg = manifest.npmPackage;
    final npm = ctx.npmBin;
    if (pkg == null || npm == null) return null;
    try {
      final r = await ProcessRunner.runOneShot(
        npm,
        ['view', _stripVersion(pkg), 'version'],
        environment: ctx.env.isEmpty ? null : ctx.env,
        timeout: const Duration(seconds: 20),
      );
      if (!r.ok) return null;
      final v = r.stdout.trim().split('\n').first.trim();
      return v.isEmpty ? null : v;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _killQuietly(ProcessSession proc) async {
    try {
      await proc.kill();
      await proc.exitCode.timeout(const Duration(seconds: 5));
    } catch (_) {
      try {
        await proc.kill(true);
      } catch (_) {}
    }
  }
}
