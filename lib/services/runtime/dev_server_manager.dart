/// Long-running dev-server manager (GetxService).
///
/// Real pipeline for framework projects:
///   Node probe → npm install (if node_modules missing) → spawn
///   `npm run dev -- --host 127.0.0.1 --port <free>` → parse the actual
///   `Local: http://…` URL from stdout (never assume 5173) → HTTP
///   health-check → hand the URL to Preview.
///
/// One server per project (reused, never duplicated). Servers are
/// stopped explicitly or with [stopAll].
library;

import 'dart:async';
import 'dart:io';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import 'dev_url_parser.dart';
import 'process_runner.dart';
import 'project_detector.dart';
import 'runtime_manager.dart';

/// Machine-readable dev-server failure.
class DevServerException implements Exception {
  /// e.g. 'node-missing', 'install-failed', 'start-timeout', 'unhealthy'.
  final String code;
  final String message;

  const DevServerException(this.code, this.message);

  @override
  String toString() => message;
}

/// A running dev server for one project.
class DevServerSession {
  final String projectId;
  final ProjectKind kind;
  final ProcessSession proc;
  final String url;
  final DateTime startedAt;
  final List<String> recentLogs;

  DevServerSession({
    required this.projectId,
    required this.kind,
    required this.proc,
    required this.url,
    required this.startedAt,
    List<String>? recentLogs,
  }) : recentLogs = recentLogs ?? [];
}

class DevServerManager extends GetxService {
  final _sessions = <String, DevServerSession>{};

  /// Active servers (projectId → session).
  Map<String, DevServerSession> get sessions => Map.unmodifiable(_sessions);

  DevServerSession? sessionFor(String projectId) => _sessions[projectId];

  bool isRunning(String projectId) => _sessions.containsKey(projectId);

  /// Start (or reuse) the dev server for [projectId].
  ///
  /// [workDir] is the SHARED project workspace dir — the same files the
  /// AI agent writes, so `npm install` sees exactly those files.
  /// All progress streams through [onLog] for the terminal UI.
  Future<DevServerSession> start({
    required String projectId,
    required String workDir,
    required ProjectKind kind,
    required void Function(String line) onLog,
  }) async {
    final existing = _sessions[projectId];
    if (existing != null) {
      onLog('↻ reusing running dev server ${existing.url}');
      return existing;
    }
    if (!ProcessRunner.isSupported) {
      throw const DevServerException(
          'unsupported-platform', 'Local processes are unavailable on Web builds.');
    }
    final rt = Get.find<RuntimeManager>();
    final st = await rt.refresh();
    if (!st.nodeAvailable || st.npmPath == null) {
      throw DevServerException('node-missing',
          'Node.js runtime unavailable — ${st.missingGuidance()}');
    }
    final npm = st.npmPath!;

    await _ensureDeps(npm: npm, workDir: workDir, onLog: onLog);

    final port = await _freePort();
    final args = _devArgs(kind, port);
    onLog('> ${args.join(' ')}  (in project dir)');
    ProcessSession proc;
    try {
      proc = await ProcessRunner.startSession(
        npm,
        args,
        workingDirectory: workDir,
        commandLabel: 'npm run dev',
      );
    } catch (e) {
      throw DevServerException('spawn-failed', 'Could not start dev server: $e');
    }

    final logs = <String>[];
    void keep(String line) {
      logs.add(line);
      if (logs.length > 300) logs.removeAt(0);
      onLog(line);
    }

    final sub1 = proc.stdoutLines.listen(keep);
    final sub2 = proc.stderrLines.listen(keep);

    try {
      final url = await _waitForUrl(logs,
          timeout: const Duration(seconds: 60));
      if (url == null) {
        await _killQuietly(proc);
        throw const DevServerException('start-timeout',
            'Dev server printed no Local URL within 60s — see terminal log.');
      }
      final healthy = await _waitHealthy(url);
      if (!healthy) {
        await _killQuietly(proc);
        throw DevServerException('unhealthy',
            'Dev server printed $url but it never answered HTTP — see terminal log.');
      }
      final session = DevServerSession(
        projectId: projectId,
        kind: kind,
        proc: proc,
        url: url,
        startedAt: DateTime.now(),
        recentLogs: logs,
      );
      _sessions[projectId] = session;
      // Detach listeners (session streams stay live for log viewers).
      unawaited(sub1.cancel());
      unawaited(sub2.cancel());
      onLog('✓ dev server live at $url');
      return session;
    } catch (e) {
      try {
        await sub1.cancel();
      } catch (_) {}
      try {
        await sub2.cancel();
      } catch (_) {}
      if (e is DevServerException) rethrow;
      await _killQuietly(proc);
      throw DevServerException('start-failed', 'Dev server failed: $e');
    }
  }

  /// Stop one project's server (no-op when absent). Never throws.
  Future<void> stop(String projectId) async {
    final s = _sessions.remove(projectId);
    if (s == null) return;
    await _killQuietly(s.proc);
  }

  /// Stop everything (app lifecycle). Never throws.
  Future<void> stopAll() async {
    final ids = _sessions.keys.toList();
    for (final id in ids) {
      await stop(id);
    }
  }

  // ── internals ──

  List<String> _devArgs(ProjectKind kind, int port) {
    if (kind == ProjectKind.nextjs) {
      return [
        'run', 'dev', '--', '-H', '127.0.0.1', '-p', '$port',
      ];
    }
    return [
      'run',
      'dev',
      '--',
      '--host',
      '127.0.0.1',
      '--port',
      '$port',
      '--strictPort',
    ];
  }

  Future<void> _ensureDeps({
    required String npm,
    required String workDir,
    required void Function(String line) onLog,
  }) async {
    final pkg = File('$workDir/package.json');
    if (!await pkg.exists()) return; // nothing to install
    final modules = Directory('$workDir/node_modules');
    if (await modules.exists()) {
      onLog('✓ node_modules present — skipping install');
      return;
    }
    onLog('> npm install  (first run — downloads dependencies…)');
    ProcessSession proc;
    try {
      proc = await ProcessRunner.startSession(
        npm,
        const ['install', '--no-audit', '--no-fund'],
        workingDirectory: workDir,
        commandLabel: 'npm install',
      );
    } catch (e) {
      throw DevServerException(
          'install-spawn-failed', 'Could not run npm install: $e');
    }
    final sub1 = proc.stdoutLines.listen(onLog);
    final sub2 = proc.stderrLines.listen(onLog);
    int code;
    try {
      code = await proc.exitCode
          .timeout(const Duration(minutes: 10), onTimeout: () => -1);
    } finally {
      try {
        await sub1.cancel();
      } catch (_) {}
      try {
        await sub2.cancel();
      } catch (_) {}
    }
    if (code == -1) {
      await _killQuietly(proc);
      throw const DevServerException('install-timeout',
          'npm install timed out after 10 minutes — check network and retry.');
    }
    if (code != 0) {
      throw DevServerException('install-failed',
          'npm install failed (exit $code) — see terminal log above.');
    }
    onLog('✓ dependencies installed');
  }

  Future<int> _freePort() async {
    ServerSocket? s;
    try {
      s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      return s.port;
    } finally {
      try {
        await s?.close();
      } catch (_) {}
    }
  }

  Future<String?> _waitForUrl(List<String> logs,
      {required Duration timeout}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final url = parseDevServerUrl(logs.join('\n'));
      if (url != null) return url;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return parseDevServerUrl(logs.join('\n'));
  }

  Future<bool> _waitHealthy(String url) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final r = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 3));
        if (r.statusCode < 500) return true;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }
    return false;
  }

  Future<void> _killQuietly(ProcessSession proc) async {
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
