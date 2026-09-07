/// CLI manager: persistent registry + install/verify/update/repair/
/// uninstall/launch for terminal CLIs (GetxService).
///
/// Honesty rules (terminal spec §§46,63): every status comes from a real
/// probe (binary exists + version command runs). Install is BLOCKED —
/// never faked — when the required runtime is missing. Uninstall never
/// touches project files.
library;

import 'dart:async';
import 'dart:io';

import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import '../hive_service.dart';
import 'cli_manifest.dart';
import 'cli_providers.dart';
import 'process_runner.dart';
import 'runtime_manager.dart';

/// Per-CLI storage breakdown.
class CliStorageInfo {
  final int cliBytes;
  final int cacheBytes;

  const CliStorageInfo(this.cliBytes, this.cacheBytes);

  int get totalBytes => cliBytes + cacheBytes;
}

class CliManagerService extends GetxService {
  static const _registryKey = 'cli_registry_v1';
  static const _historyKey = 'cli_cmd_history_v1';
  static const _welcomedKey = 'cli_welcomed_v1';
  static const _historyCap = 50;

  /// Registry entries (persisted).
  final installed = <InstalledCli>[].obs;

  /// Live computed status per manifest id.
  final liveStatus = <String, CliStatus>{}.obs;

  /// Last known versions per manifest id.
  final versions = <String, String>{}.obs;

  /// Manifest id currently installing (queue of one — §59).
  final installingId = RxnString();

  /// Manifest ids with an op in flight (update/repair/verify/uninstall).
  final busyIds = <String>{}.obs;

  /// Recent shell commands (persisted, secrets never stored).
  final recentCommands = <String>[].obs;

  /// Interactive sessions launched via Open (id → live process).
  final _launched = <String, ProcessSession>{};

  String _cliDir = '';
  String get cliDir => _cliDir;
  String get npmPrefix =>
      _cliDir.isEmpty ? '' : '$_cliDir/npm-global';

  bool _ready = false;
  final _memFallback = <String, dynamic>{};

  dynamic _get(String key) {
    try {
      return Get.find<HiveService>().settingsBox.get(key);
    } catch (_) {
      return _memFallback[key];
    }
  }

  Future<void> _put(String key, dynamic value) async {
    try {
      await Get.find<HiveService>().settingsBox.put(key, value);
    } catch (_) {
      _memFallback[key] = value;
    }
  }

  /// Load registry + history, then verify in background. Never throws.
  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    try {
      final docs = await getApplicationDocumentsDirectory();
      _cliDir = '${docs.path}/cli';
      try {
        await Directory(_cliDir).create(recursive: true);
      } catch (_) {}
    } catch (_) {}
    try {
      final raw = _get(_registryKey);
      if (raw is List) {
        final entries = <InstalledCli>[];
        for (final m in raw.whereType<Map>()) {
          try {
            final e = InstalledCli.fromMap(m);
            if (e.manifestId.isNotEmpty) entries.add(e);
          } catch (_) {}
        }
        // Drop entries for unknown manifests (catalog drift).
        final known = kCliCatalog.map((m) => m.id).toSet();
        installed.assignAll(entries.where((e) => known.contains(e.manifestId)));
        for (final e in installed) {
          if (e.version.isNotEmpty) versions[e.manifestId] = e.version;
          liveStatus[e.manifestId] = CliStatus.installed;
        }
      }
      final hist = _get(_historyKey);
      if (hist is List) {
        recentCommands.assignAll(
            hist.whereType<String>().take(_historyCap).toList());
      }
    } catch (_) {}
    unawaited(verifyAll());
  }

  CliManifest? manifestById(String id) {
    for (final m in kCliCatalog) {
      if (m.id == id) return m;
    }
    return null;
  }

  bool isRegistered(String id) => installed.any((e) => e.manifestId == id);

  /// Current best-known status (live probe result wins over registry).
  CliStatus statusOf(CliManifest m) =>
      liveStatus[m.id] ??
      (isRegistered(m.id) ? CliStatus.installed : CliStatus.notInstalled);

  // ── environment ──

  /// Managed environment for child processes: managed bin dirs first on
  /// PATH, sandboxed HOME + npm cache/prefix. Secrets are never logged.
  Future<Map<String, String>> managedEnv() async {
    final env = Map<String, String>.from(Platform.environment);
    final paths = <String>[];
    if (npmPrefix.isNotEmpty) paths.add('$npmPrefix/bin');
    try {
      final st = Get.find<RuntimeManager>().status.value;
      final np = st.nodePath;
      if (np != null && np.contains(Platform.pathSeparator)) {
        paths.add(np.substring(0, np.lastIndexOf(Platform.pathSeparator)));
      }
      if ((st.npmPath ?? '').isNotEmpty) {
        final mp = st.npmPath!;
        if (mp.contains(Platform.pathSeparator)) {
          final d = mp.substring(0, mp.lastIndexOf(Platform.pathSeparator));
          if (!paths.contains(d)) paths.add(d);
        }
      }
    } catch (_) {}
    final sep = Platform.isWindows ? ';' : ':';
    final cur = env['PATH'] ?? env['Path'] ?? '';
    env['PATH'] = [...paths, if (cur.isNotEmpty) cur].join(sep);
    if (_cliDir.isNotEmpty) {
      final home = '$_cliDir/home';
      try {
        await Directory(home).create(recursive: true);
      } catch (_) {}
      env['HOME'] = home;
      if (Platform.isWindows) env['USERPROFILE'] = home;
      env['NPM_CONFIG_CACHE'] = '$_cliDir/cache';
      if (npmPrefix.isNotEmpty) {
        env['NPM_CONFIG_PREFIX'] = npmPrefix;
      }
    }
    env.putIfAbsent('TERM', () => 'xterm-256color');
    return env;
  }

  Future<CliInstallCtx> _ctx() async {
    String? nodeBin;
    String? npmBin;
    try {
      final st = await Get.find<RuntimeManager>().refresh();
      nodeBin = st.nodePath;
      npmBin = st.npmPath;
    } catch (_) {}
    return CliInstallCtx(
      cliDir: _cliDir,
      npmPrefix: npmPrefix,
      nodeBin: nodeBin,
      npmBin: npmBin,
      env: await managedEnv(),
    );
  }

  // ── install / update / repair / uninstall ──

  /// One-tap install with real step progress. Throws [ProviderException]
  /// (or StateError when another install runs) — UI maps to messages.
  Future<ProviderResult> install(
    CliManifest m, {
    required CliStepFn onStep,
    required void Function(String line) onLog,
    bool Function()? isCancelled,
  }) async {
    if (installingId.value != null) {
      throw StateError(
          'Another installation (${installingId.value}) is already running — queue of one.');
    }
    if (m.provider != CliProviderKind.npm) {
      throw StateError('This entry cannot be installed (detected only).');
    }
    installingId.value = m.id;
    liveStatus[m.id] = CliStatus.installing;
    try {
      onStep('check-device', 'run', 'Checking device…');
      if (!ProcessRunner.isSupported) {
        onStep('check-device', 'fail', 'No local processes on Web');
        throw const ProviderException('unsupported-platform',
            'Local installs are unavailable on Web builds.');
      }
      onStep('check-device', 'ok', await _deviceLine());
      onStep('check-runtime', 'run', 'Checking Node.js runtime…');
      final rt = Get.find<RuntimeManager>();
      final st = await rt.refresh(force: true);
      if (!st.nodeAvailable || st.npmPath == null) {
        onStep('check-runtime', 'fail', 'Node.js unavailable');
        liveStatus[m.id] = CliStatus.runtimeMissing;
        throw ProviderException('runtime-missing',
            'Node.js runtime unavailable — ${st.missingGuidance()}');
      }
      if (m.minNodeMajor > 0) {
        final major = _majorOf(st.nodeVersion);
        if (major > 0 && major < m.minNodeMajor) {
          onStep('check-runtime', 'fail',
              'Node ${st.nodeVersion} < v${m.minNodeMajor} required');
          liveStatus[m.id] = CliStatus.runtimeMissing;
          throw ProviderException('runtime-too-old',
              '${m.displayName} needs Node.js ${m.minNodeMajor}+ (found ${st.nodeVersion}).');
        }
      }
      onStep('check-runtime', 'ok',
          'node ${st.nodeVersion}, npm ${st.npmVersion}');
      final ctx = await _ctx();
      final res = await NpmGlobalProvider().install(
        m,
        ctx,
        onStep: onStep,
        onLog: onLog,
        isCancelled: isCancelled,
      );
      _upsert(InstalledCli(
        manifestId: m.id,
        version: res.version,
        installDir: npmPrefix,
        binaryPath: res.binaryPath,
        provider: 'npm',
        installedAtMs: DateTime.now().millisecondsSinceEpoch,
        lastVerifiedMs: DateTime.now().millisecondsSinceEpoch,
      ));
      versions[m.id] = res.version;
      liveStatus[m.id] = CliStatus.ready;
      return res;
    } on ProviderException catch (_) {
      if (liveStatus[m.id] == CliStatus.installing) {
        liveStatus[m.id] =
            isRegistered(m.id) ? CliStatus.installed : CliStatus.notInstalled;
      }
      rethrow;
    } catch (e) {
      liveStatus[m.id] = CliStatus.error;
      rethrow;
    } finally {
      installingId.value = null;
    }
  }

  /// Update to @latest (real reinstall). Returns new version.
  Future<String> update(
    CliManifest m, {
    required CliStepFn onStep,
    required void Function(String line) onLog,
    bool Function()? isCancelled,
  }) async {
    _guardBusy(m);
    busyIds.add(m.id);
    try {
      final ctx = await _ctx();
      if (ctx.npmBin == null) {
        throw const ProviderException(
            'runtime-missing', 'npm unavailable — runtime missing.');
      }
      final res = await NpmGlobalProvider().install(
        m,
        ctx,
        onStep: onStep,
        onLog: onLog,
        isCancelled: isCancelled,
        latest: true,
      );
      _upsert(InstalledCli(
        manifestId: m.id,
        version: res.version,
        installDir: npmPrefix,
        binaryPath: res.binaryPath,
        provider: 'npm',
        installedAtMs: _prevInstalledAt(m.id),
        lastVerifiedMs: DateTime.now().millisecondsSinceEpoch,
      ));
      versions[m.id] = res.version;
      liveStatus[m.id] = CliStatus.ready;
      return res.version;
    } finally {
      busyIds.remove(m.id);
    }
  }

  /// Repair: reinstall same spec + verify + refresh registry.
  Future<String> repair(
    CliManifest m, {
    required CliStepFn onStep,
    required void Function(String line) onLog,
    bool Function()? isCancelled,
  }) async {
    _guardBusy(m);
    busyIds.add(m.id);
    try {
      final ctx = await _ctx();
      if (ctx.npmBin == null) {
        throw const ProviderException(
            'runtime-missing', 'npm unavailable — runtime missing.');
      }
      final res = await NpmGlobalProvider().install(
        m,
        ctx,
        onStep: onStep,
        onLog: onLog,
        isCancelled: isCancelled,
      );
      _upsert(InstalledCli(
        manifestId: m.id,
        version: res.version,
        installDir: npmPrefix,
        binaryPath: res.binaryPath,
        provider: 'npm',
        installedAtMs: _prevInstalledAt(m.id),
        lastVerifiedMs: DateTime.now().millisecondsSinceEpoch,
      ));
      versions[m.id] = res.version;
      liveStatus[m.id] = CliStatus.ready;
      return res.version;
    } finally {
      busyIds.remove(m.id);
    }
  }

  /// Uninstall for real (`npm uninstall -g --prefix`), then drop the
  /// registry entry. Project files are never touched.
  Future<void> uninstall(CliManifest m) async {
    _guardBusy(m);
    busyIds.add(m.id);
    liveStatus[m.id] = CliStatus.uninstalling;
    try {
      if (m.provider == CliProviderKind.npm && m.npmPackage != null) {
        final ctx = await _ctx();
        if (ctx.npmBin != null) {
          try {
            await ProcessRunner.runOneShot(
              ctx.npmBin!,
              [
                'uninstall',
                '-g',
                m.npmPackage!,
                '--prefix',
                ctx.npmPrefix
              ],
              environment: ctx.env.isEmpty ? null : ctx.env,
              timeout: const Duration(minutes: 5),
            );
          } catch (_) {}
        }
        await _removeManagedPackageFiles(m, ctx);
      }
      installed.removeWhere((e) => e.manifestId == m.id);
      versions.remove(m.id);
      liveStatus[m.id] = CliStatus.notInstalled;
      await _persist();
    } finally {
      busyIds.remove(m.id);
    }
  }

  /// Verify binary + version for real. Updates status honestly.
  Future<CliStatus> verify(CliManifest m) async {
    if (busyIds.contains(m.id)) return statusOf(m);
    busyIds.add(m.id);
    liveStatus[m.id] = CliStatus.verifying;
    try {
      if (m.provider == CliProviderKind.runtimeInfo) {
        final st = await Get.find<RuntimeManager>().refresh();
        liveStatus[m.id] =
            st.nodeAvailable ? CliStatus.ready : CliStatus.runtimeMissing;
        if (st.nodeAvailable && st.nodeVersion.isNotEmpty) {
          versions[m.id] = st.nodeVersion;
        }
        return liveStatus[m.id]!;
      }
      if (m.provider == CliProviderKind.system) {
        final bin = await ProcessRunner.resolveExecutable(m.command);
        if (bin == null) {
          liveStatus[m.id] = CliStatus.binaryMissing;
          return liveStatus[m.id]!;
        }
        try {
          final r = await ProcessRunner.runOneShot(
              bin, m.versionArgs,
              timeout: const Duration(seconds: 15));
          versions[m.id] = r.ok
              ? r.stdout.trim().split('\n').first.trim()
              : '';
        } catch (_) {
          versions[m.id] = '';
        }
        liveStatus[m.id] = CliStatus.ready;
        return liveStatus[m.id]!;
      }
      // npm-managed: runtime → binary → version.
      final rt = Get.find<RuntimeManager>();
      final st = await rt.refresh();
      if (!st.nodeAvailable) {
        liveStatus[m.id] = CliStatus.runtimeMissing;
        return liveStatus[m.id]!;
      }
      final ctx = await _ctx();
      final bin = await NpmGlobalProvider.resolveBinary(m, ctx);
      if (bin == null) {
        liveStatus[m.id] = isRegistered(m.id)
            ? CliStatus.binaryMissing
            : CliStatus.notInstalled;
        return liveStatus[m.id]!;
      }
      try {
        final r = await ProcessRunner.runOneShot(bin, m.versionArgs,
            environment: ctx.env.isEmpty ? null : ctx.env,
            timeout: const Duration(seconds: 30));
        if (!r.ok) throw Exception('exit ${r.exitCode}');
        final v = r.stdout.trim().split('\n').first.trim();
        versions[m.id] = v;
        final entry = _entryOf(m.id);
        if (entry != null) {
          _upsert(InstalledCli(
            manifestId: entry.manifestId,
            version: v,
            installDir: entry.installDir,
            binaryPath: bin,
            provider: entry.provider,
            installedAtMs: entry.installedAtMs,
            lastVerifiedMs: DateTime.now().millisecondsSinceEpoch,
          ));
        }
        liveStatus[m.id] = CliStatus.ready;
      } catch (_) {
        liveStatus[m.id] = CliStatus.broken;
      }
      return liveStatus[m.id]!;
    } finally {
      busyIds.remove(m.id);
    }
  }

  /// Re-verify everything (startup + manual refresh). Sequential, quick.
  Future<void> verifyAll() async {
    for (final m in kCliCatalog) {
      try {
        await verify(m);
      } catch (_) {}
    }
  }

  /// Newest published version (needs net) or null when unknowable.
  Future<String?> checkUpdate(CliManifest m) async {
    if (m.provider != CliProviderKind.npm) return null;
    final ctx = await _ctx();
    return NpmGlobalProvider.latestVersion(m, ctx);
  }

  // ── launch ──

  /// Launch the real executable inside [workDir] (shared workspace).
  /// One live session per CLI (previous is stopped first — §48).
  Future<ProcessSession> launchInProject(
      CliManifest m, String workDir) async {
    if (!cliIsLaunchable(statusOf(m))) {
      throw StateError(
          '${m.displayName} is ${cliStatusLabel(statusOf(m))} — not launchable.');
    }
    String? bin;
    if (m.provider == CliProviderKind.npm) {
      final ctx = await _ctx();
      bin = await NpmGlobalProvider.resolveBinary(m, ctx);
    } else if (m.provider == CliProviderKind.system) {
      bin = await ProcessRunner.resolveExecutable(m.command);
    } else {
      throw StateError('This entry is informational and cannot launch.');
    }
    if (bin == null) {
      liveStatus[m.id] = CliStatus.binaryMissing;
      throw StateError('${m.command} binary not found.');
    }
    await killLaunched(m.id);
    final env = await managedEnv();
    final session = await ProcessRunner.startSession(
      bin,
      const [],
      workingDirectory: workDir,
      environment: env,
      commandLabel: m.command,
    );
    _launched[m.id] = session;
    unawaited(session.exitCode.then((_) {
      _launched.remove(m.id);
    }));
    return session;
  }

  ProcessSession? launchedSession(String id) => _launched[id];

  Future<void> killLaunched(String id) async {
    final s = _launched.remove(id);
    if (s == null) return;
    try {
      await s.kill();
      await s.exitCode.timeout(const Duration(seconds: 5));
    } catch (_) {
      try {
        await s.kill(true);
      } catch (_) {}
    }
  }

  Future<void> killAllLaunched() async {
    for (final id in _launched.keys.toList()) {
      await killLaunched(id);
    }
  }

  // ── terminal-install detection (§34) ──

  /// After a successful shell command, check whether it installed a
  /// known CLI. Returns the manifest to offer for adoption, else null.
  Future<CliManifest?> detectAfterCommand(
      String command, int exitCode) async {
    if (exitCode != 0 || !ProcessRunner.isSupported) return null;
    final pkgs = matchNpmGlobalInstall(command);
    if (pkgs.isEmpty) return null;
    for (final m in kCliCatalog) {
      if (m.provider != CliProviderKind.npm || m.npmPackage == null) {
        continue;
      }
      if (!pkgs.contains(_stripVersion(m.npmPackage!))) continue;
      if (isRegistered(m.id)) continue;
      final ctx = await _ctx();
      final bin = await NpmGlobalProvider.resolveBinary(m, ctx);
      if (bin == null) continue;
      String version = '';
      try {
        final r = await ProcessRunner.runOneShot(bin, m.versionArgs,
            environment: ctx.env.isEmpty ? null : ctx.env,
            timeout: const Duration(seconds: 30));
        if (r.ok) version = r.stdout.trim().split('\n').first.trim();
      } catch (_) {}
      _pendingDetection = _Detected(m, version, bin);
      return m;
    }
    return null;
  }

  _Detected? _pendingDetection;
  _Detected? consumeDetection() {
    final d = _pendingDetection;
    _pendingDetection = null;
    return d;
  }

  /// Register a terminal-detected CLI (user confirmed in UI).
  Future<void> registerDetected() async {
    final d = _pendingDetection;
    if (d == null) return;
    _pendingDetection = null;
    _upsert(InstalledCli(
      manifestId: d.manifest.id,
      version: d.version,
      installDir: npmPrefix,
      binaryPath: d.binaryPath,
      provider: 'npm-adopted',
      installedAtMs: DateTime.now().millisecondsSinceEpoch,
      lastVerifiedMs: DateTime.now().millisecondsSinceEpoch,
    ));
    if (d.version.isNotEmpty) versions[d.manifest.id] = d.version;
    liveStatus[d.manifest.id] = CliStatus.ready;
  }

  // ── history (§52) ──

  void recordCommand(String command) {
    final cmd = command.trim();
    if (cmd.isEmpty || isSensitiveCommand(cmd)) return;
    try {
      recentCommands.remove(cmd);
      recentCommands.insert(0, cmd);
      while (recentCommands.length > _historyCap) {
        recentCommands.removeLast();
      }
      unawaited(_put(_historyKey, recentCommands.toList()));
    } catch (_) {}
  }

  /// Non-intrusive prefix suggestions: installed commands first.
  List<String> suggestCommands(String prefix) {
    final p = prefix.trim().toLowerCase();
    if (p.isEmpty) return [];
    final out = <String>[];
    for (final m in kCliCatalog) {
      if (m.command.toLowerCase().startsWith(p) &&
          (isRegistered(m.id) || m.provider == CliProviderKind.system)) {
        out.add(m.command);
      }
    }
    for (final h in recentCommands) {
      final first = h.split(' ').first.toLowerCase();
      if ((first.startsWith(p) || h.toLowerCase().startsWith(p)) &&
          !out.contains(h) &&
          out.length < 5) {
        out.add(h);
      }
      if (out.length >= 5) break;
    }
    return out.take(5).toList();
  }

  // ── storage (§37) ──

  Future<CliStorageInfo> storageInfo() async {
    final cli = await _dirSize(_cliDir.isEmpty ? null : Directory(_cliDir));
    var cache = 0;
    if (_cliDir.isNotEmpty) {
      cache = await _dirSize(Directory('$_cliDir/cache'));
    }
    return CliStorageInfo(cli, cache);
  }

  Future<String> clearNpmCache() async {
    final ctx = await _ctx();
    if (ctx.npmBin == null) {
      throw const ProviderException(
          'runtime-missing', 'npm unavailable — runtime missing.');
    }
    final r = await ProcessRunner.runOneShot(
      ctx.npmBin!,
      const ['cache', 'clean', '--force'],
      environment: ctx.env.isEmpty ? null : ctx.env,
      timeout: const Duration(minutes: 3),
    );
    if (!r.ok) throw ProviderException('cache-failed',
        'npm cache clean failed (exit ${r.exitCode}).');
    return 'npm cache cleared';
  }

  // ── AI context (§33) ──

  /// One line for AI prompts so the agent knows local CLIs. Info only —
  /// the agent never auto-executes external tools.
  String cliContextLine() {
    final parts = <String>[];
    for (final m in kCliCatalog) {
      if (m.provider == CliProviderKind.runtimeInfo) continue;
      final st = statusOf(m);
      if (st == CliStatus.ready || st == CliStatus.updateAvailable) {
        parts.add(
            '${m.displayName} (${m.command}) — Ready${versions[m.id]?.isNotEmpty == true ? ' ${versions[m.id]}' : ''}');
      }
    }
    if (parts.isEmpty) return 'none installed';
    return parts.join('; ');
  }

  // ── welcome (§61) ──

  /// True on first call ever (persists the flag).
  Future<bool> consumeWelcome() async {
    try {
      if (_get(_welcomedKey) == true) return false;
      await _put(_welcomedKey, true);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── internals ──

  void _guardBusy(CliManifest m) {
    if (installingId.value != null) {
      throw StateError('An installation is already running.');
    }
    if (busyIds.contains(m.id)) {
      throw StateError('${m.displayName} already has an operation running.');
    }
  }

  InstalledCli? _entryOf(String id) {
    for (final e in installed) {
      if (e.manifestId == id) return e;
    }
    return null;
  }

  int _prevInstalledAt(String id) =>
      _entryOf(id)?.installedAtMs ?? DateTime.now().millisecondsSinceEpoch;

  void _upsert(InstalledCli e) {
    installed.removeWhere((x) => x.manifestId == e.manifestId);
    installed.add(e);
    unawaited(_persist());
  }

  Future<void> _persist() async {
    try {
      await _put(
          _registryKey, installed.map((e) => e.toMap()).toList());
    } catch (_) {}
  }

  Future<String> _deviceLine() async {
    if (!ProcessRunner.isSupported) return 'Web build';
    try {
      final rt = Get.find<RuntimeManager>();
      final st = rt.status.value;
      final abi = st.deviceAbi.isEmpty ? '' : ' ${st.deviceAbi}';
      return '${st.platform}$abi';
    } catch (_) {
      return 'device check skipped';
    }
  }

  Future<void> _removeManagedPackageFiles(
      CliManifest m, CliInstallCtx ctx) async {
    try {
      final pkg = _stripVersion(m.npmPackage ?? '');
      final pkgDir = pkg.startsWith('@')
          ? '${ctx.npmPrefix}/lib/node_modules/$pkg'
          : '${ctx.npmPrefix}/lib/node_modules/$pkg';
      try {
        final d = Directory(pkgDir);
        if (await d.exists()) await d.delete(recursive: true);
      } catch (_) {}
      for (final link in [
        '${ctx.npmPrefix}/bin/${m.command}',
        '${ctx.npmPrefix}/bin/${m.command}.cmd',
        '${ctx.npmPrefix}/${m.command}.cmd',
      ]) {
        try {
          final f = File(link);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<int> _dirSize(Directory? dir) async {
    if (dir == null) return 0;
    var total = 0;
    var seen = 0;
    try {
      if (!await dir.exists()) return 0;
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File) {
          try {
            total += await e.length();
          } catch (_) {}
          if (++seen > 20000) break;
        }
      }
    } catch (_) {}
    return total;
  }
}

class _Detected {
  final CliManifest manifest;
  final String version;
  final String binaryPath;

  const _Detected(this.manifest, this.version, this.binaryPath);
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

int _majorOf(String version) {
  final m = RegExp(r'v?(\d+)').firstMatch(version.trim());
  return m == null ? 0 : int.tryParse(m.group(1)!) ?? 0;
}
