/// Managed local runtime status for CubicLM (GetxService).
///
/// CubicLM never assumes Node.js exists. This service PROBES for it:
/// app-managed runtime dir first, then PATH — on every platform where
/// `dart:io` Process works (desktop + Android). Web builds report
/// unavailable. Nothing is faked: versions come from real `--version`
/// output, and install state stays `notInstalled` until a probe passes.
///
/// Managed layout (created on demand, never requiring root):
///   <app-documents>/runtime/node/bin/{node,npm}
///
/// Dropping a compatible Node distribution there (matching
/// [deviceAbi]) lights the runtime up with zero code changes.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import 'process_runner.dart';

/// Install/readiness state of the managed Node runtime.
enum NodeInstallState {
  /// Haven't probed yet this session.
  unknown,

  /// Probe in flight.
  checking,

  /// `node --version` + `npm --version` both succeeded.
  ready,

  /// No usable Node found (honest — not an error to hide).
  notInstalled,
}

/// Snapshot of what the device can actually execute.
class RuntimeStatus {
  final bool nodeAvailable;
  final String nodeVersion;
  final String npmVersion;
  final String? nodePath;
  final String? npmPath;
  final String platform;
  final String deviceAbi;
  final String managedDir;
  final NodeInstallState installState;
  final String? lastError;
  final DateTime checkedAt;

  const RuntimeStatus({
    required this.nodeAvailable,
    this.nodeVersion = '',
    this.npmVersion = '',
    this.nodePath,
    this.npmPath,
    this.platform = '',
    this.deviceAbi = '',
    this.managedDir = '',
    this.installState = NodeInstallState.unknown,
    this.lastError,
    required this.checkedAt,
  });

  /// Guidance text for the "runtime missing" UI state.
  String missingGuidance() {
    if (kIsWeb) {
      return 'Web builds cannot run local processes. Export the ZIP and run `npm run dev` on a machine with Node.js.';
    }
    return 'No Node.js found on this device (checked app runtime dir + PATH${deviceAbi.isNotEmpty ? ', ABI $deviceAbi' : ''}). '
        'Static sites still preview. For Vite/Next.js: place a compatible Node distribution in:\n$managedDir\nthen tap Recheck — or export the ZIP and run it where Node exists.';
  }
}

class RuntimeManager extends GetxService {
  final status = Rx<RuntimeStatus>(
    RuntimeStatus(nodeAvailable: false, checkedAt: DateTime.now()),
  );

  bool _checking = false;

  /// Probe node + npm. Safe to call repeatedly (guarded + cached 30s).
  Future<RuntimeStatus> refresh({bool force = false}) async {
    final cur = status.value;
    if (_checking) return cur;
    if (!force &&
        cur.installState != NodeInstallState.unknown &&
        DateTime.now().difference(cur.checkedAt).inSeconds < 30) {
      return cur;
    }
    _checking = true;
    status.value = RuntimeStatus(
      nodeAvailable: false,
      platform: cur.platform,
      deviceAbi: cur.deviceAbi,
      managedDir: cur.managedDir,
      installState: NodeInstallState.checking,
      checkedAt: DateTime.now(),
    );
    try {
      final s = await _probe();
      status.value = s;
      return s;
    } finally {
      _checking = false;
    }
  }

  Future<RuntimeStatus> _probe() async {
    final now = DateTime.now();
    final platform = kIsWeb
        ? 'web'
        : '${Platform.operatingSystem}'
            '${Platform.isAndroid ? ' (Android)' : ''}';
    String managedDir = '';
    if (!kIsWeb) {
      try {
        final docs = await getApplicationDocumentsDirectory();
        managedDir = '${docs.path}/runtime/node';
      } catch (_) {}
    }
    if (kIsWeb || !ProcessRunner.isSupported) {
      return RuntimeStatus(
        nodeAvailable: false,
        platform: platform,
        deviceAbi: '',
        managedDir: managedDir,
        installState: NodeInstallState.notInstalled,
        lastError: 'Process execution unavailable on this platform.',
        checkedAt: now,
      );
    }

    // Candidate node binaries: managed dir first, then PATH.
    final bin = '$managedDir/bin';
    final exe = Platform.isWindows ? 'node.exe' : 'node';
    String? nodePath;
    if (managedDir.isNotEmpty) {
      try {
        if (await File('$bin/$exe').exists()) nodePath = '$bin/$exe';
      } catch (_) {}
    }
    nodePath ??= await ProcessRunner.resolveExecutable('node');
    if (nodePath == null) {
      return RuntimeStatus(
        nodeAvailable: false,
        platform: platform,
        deviceAbi: await _deviceAbi(),
        managedDir: managedDir,
        installState: NodeInstallState.notInstalled,
        lastError: 'node binary not found.',
        checkedAt: now,
      );
    }

    // Real version output — never assumed.
    String nodeVer = '';
    try {
      final r = await ProcessRunner.runOneShot(
          nodePath, const ['--version'],
          timeout: const Duration(seconds: 15));
      if (!r.ok) throw Exception(r.stderr.trim());
      nodeVer = r.stdout.trim().split('\n').first.trim();
    } catch (e) {
      return RuntimeStatus(
        nodeAvailable: false,
        platform: platform,
        deviceAbi: await _deviceAbi(),
        managedDir: managedDir,
        nodePath: nodePath,
        installState: NodeInstallState.notInstalled,
        lastError: 'node exists but --version failed: $e',
        checkedAt: now,
      );
    }

    String? npmPath;
    if (managedDir.isNotEmpty) {
      final npmExe = Platform.isWindows ? 'npm.cmd' : 'npm';
      try {
        if (await File('$bin/$npmExe').exists()) npmPath = '$bin/$npmExe';
      } catch (_) {}
    }
    npmPath ??= await ProcessRunner.resolveExecutable('npm');
    String npmVer = '';
    if (npmPath != null) {
      try {
        final r = await ProcessRunner.runOneShot(
            npmPath, const ['--version'],
            timeout: const Duration(seconds: 15));
        if (r.ok) npmVer = r.stdout.trim().split('\n').first.trim();
      } catch (_) {}
    }

    return RuntimeStatus(
      nodeAvailable: true,
      nodeVersion: nodeVer,
      npmVersion: npmVer,
      nodePath: nodePath,
      npmPath: npmPath,
      platform: platform,
      deviceAbi: await _deviceAbi(),
      managedDir: managedDir,
      installState: NodeInstallState.ready,
      checkedAt: now,
    );
  }

  Future<String> _deviceAbi() async {
    if (kIsWeb) return '';
    if (!Platform.isAndroid) return Platform.operatingSystem;
    try {
      final r = await ProcessRunner.runOneShot(
          'getprop', const ['ro.product.cpu.abi'],
          timeout: const Duration(seconds: 5));
      final abi = r.stdout.trim();
      return abi.isEmpty ? 'android' : 'android/$abi';
    } catch (_) {
      return 'android';
    }
  }
}
