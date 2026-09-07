/// Real OS process execution for CubicLM (no simulation).
///
/// - Works wherever `dart:io` Process is available (desktop + Android).
/// - Unavailable on Web builds ([isSupported] == false) — callers must
///   surface that honestly instead of faking output.
/// - One-shot commands AND long-running sessions (dev servers) with
///   streamed stdout/stderr, stdin, kill, exit codes, working directory.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

/// Result of a finished one-shot command.
class RunResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  const RunResult(this.exitCode, this.stdout, this.stderr);

  bool get ok => exitCode == 0;
}

/// A live process with streamed output.
class ProcessSession {
  final Process _proc;
  final String commandLabel;
  final _stdoutCtrl = StreamController<String>.broadcast();
  final _stderrCtrl = StreamController<String>.broadcast();

  Stream<String> get stdoutLines => _stdoutCtrl.stream;
  Stream<String> get stderrLines => _stderrCtrl.stream;

  /// Merged stdout+stderr lines in arrival order (best effort).
  Stream<String> get allLines async* {
    yield* StreamGroupX.merge([stdoutLines, stderrLines]);
  }

  Future<int> get exitCode => _proc.exitCode;
  int get pid => _proc.pid;

  ProcessSession(this._proc, this.commandLabel) {
    _proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_stdoutCtrl.add,
            onError: (_) {}, onDone: () => _stdoutCtrl.close());
    _proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_stderrCtrl.add,
            onError: (_) {}, onDone: () => _stderrCtrl.close());
  }

  /// Write to process stdin (append '\n' yourself for line input).
  void writeStdin(String data) {
    try {
      _proc.stdin.write(data);
    } catch (_) {}
  }

  /// SIGTERM (false) or SIGKILL (true). Returns true if signaled.
  Future<bool> kill([bool force = false]) async {
    try {
      return _proc.kill(force ? ProcessSignal.sigkill : ProcessSignal.sigterm);
    } catch (_) {
      return false;
    }
  }

  /// Ctrl+C equivalent: SIGINT on POSIX (lets CLIs handle it), graceful
  /// terminate on Windows. Returns true if the signal was delivered.
  Future<bool> interrupt() async {
    try {
      if (Platform.isWindows) {
        return _proc.kill(ProcessSignal.sigterm);
      }
      return _proc.kill(ProcessSignal.sigint);
    } catch (_) {
      return false;
    }
  }
}

/// Minimal stream merge (avoids adding package:async dependency).
class StreamGroupX {
  static Stream<T> merge<T>(List<Stream<T>> streams) {
    final ctrl = StreamController<T>.broadcast();
    var remaining = streams.length;
    for (final s in streams) {
      s.listen(ctrl.add, onError: ctrl.addError, onDone: () {
        remaining--;
        if (remaining <= 0) ctrl.close();
      });
    }
    return ctrl.stream;
  }
}

class ProcessRunner {
  /// False on Web builds where dart:io Process does not exist.
  static bool get isSupported => !kIsWeb;

  static void throwIfUnsupported() {
    if (!isSupported) {
      throw const ProcessException(
          'shell', [], 'Process execution is unavailable on Web builds.');
    }
  }

  /// Resolve [name] to something Process can launch.
  /// On Windows, npm-style shims need `.cmd`.
  static Future<String?> resolveExecutable(String name) async {
    if (!isSupported) return null;
    if (Platform.isWindows &&
        !name.endsWith('.exe') &&
        !name.endsWith('.cmd') &&
        !name.endsWith('.bat')) {
      for (final c in ['$name.cmd', '$name.exe', '$name.bat', name]) {
        if (await _onPath(c)) return c;
      }
      return null;
    }
    if (await _onPath(name)) return name;
    // Absolute/relative path given directly.
    try {
      if (await File(name).exists()) return name;
    } catch (_) {}
    return null;
  }

  static Future<bool> _onPath(String name) async {
    try {
      final probe = Platform.isWindows ? 'where' : 'which';
      final r = await Process.run(probe, [name]);
      return r.exitCode == 0 &&
          (r.stdout as String).toString().trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Run once, capture all output. Throws on spawn failure (never fakes).
  static Future<RunResult> runOneShot(
    String executable,
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration timeout = const Duration(minutes: 10),
  }) async {
    throwIfUnsupported();
    final proc = await Process.start(
      executable,
      args,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: false,
    );
    final outBuf = StringBuffer();
    final errBuf = StringBuffer();
    proc.stdout.transform(utf8.decoder).listen(outBuf.write);
    proc.stderr.transform(utf8.decoder).listen(errBuf.write);
    final code = await proc.exitCode.timeout(timeout, onTimeout: () {
      try {
        proc.kill(ProcessSignal.sigkill);
      } catch (_) {}
      return -1;
    });
    return RunResult(code, outBuf.toString(), errBuf.toString());
  }

  /// Start a long-running process with live streamed output.
  static Future<ProcessSession> startSession(
    String executable,
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
    required String commandLabel,
  }) async {
    throwIfUnsupported();
    final proc = await Process.start(
      executable,
      args,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: false,
    );
    return ProcessSession(proc, commandLabel);
  }
}
