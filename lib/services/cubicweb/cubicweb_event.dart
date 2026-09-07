/// CubicWeb System Logs — structured event model, stable error-code
/// registry, evidence-based classifier, and secret redaction.
///
/// Pure Dart (unit-tested). The classifier is deliberately
/// conservative (§28): ordinary command failures and application
/// errors yield NO error code, which means "not a system event" —
/// those stay on the AI-debugging path instead of becoming
/// compatibility noise.
library;

import 'dart:math';

/// Severity levels for the System Logs UI filters.
enum CwSeverity { debug, info, warning, error }

/// Failure layers (§8). CODE/DEPENDENCY issues route to the AI
/// debugger; everything else with a code routes to System Logs.
enum CwCategory {
  code,
  runtime,
  platform,
  compatibility,
  dependency,
  permission,
  filesystem,
  network,
  webview,
  process,
  native,
  resource,
  preview,
  cloud,
  security,
  unknown,
}

/// Stable CubicWeb error-code registry (§9). Extensible: add a const +
/// title here, never reuse a retired code for a new meaning.
abstract final class CwCodes {
  static const nodeUnavailable = 'CW-RUNTIME-001';
  static const pythonUnavailable = 'CW-RUNTIME-002';
  static const runtimeArchMismatch = 'CW-RUNTIME-003';
  static const executableUnavailable = 'CW-RUNTIME-004';

  static const devServerFailed = 'CW-PREVIEW-001';
  static const localhostUnavailable = 'CW-PREVIEW-002';
  static const frameworkNeedsRuntime = 'CW-PREVIEW-003';

  static const processFailed = 'CW-TERMINAL-001';
  static const ptyUnavailable = 'CW-TERMINAL-002';
  static const commandUnavailable = 'CW-TERMINAL-003';

  static const webviewCapability = 'CW-WEBVIEW-001';
  static const webviewNavFailed = 'CW-WEBVIEW-002';
  static const webviewApiMissing = 'CW-WEBVIEW-003';

  static const fsDenied = 'CW-FS-001';
  static const permissionDenied = 'CW-PERM-001';

  static const nativeIncompatible = 'CW-NATIVE-001';
  static const nativeDepMissing = 'CW-NATIVE-002';

  static const networkFailed = 'CW-NET-001';
  static const resourceExhausted = 'CW-RESOURCE-001';

  static const cloudUnavailable = 'CW-CLOUD-001';
  static const cloudExecFailed = 'CW-CLOUD-002';

  static const Map<String, String> titles = {
    nodeUnavailable: 'Node.js runtime unavailable',
    pythonUnavailable: 'Python runtime unavailable',
    runtimeArchMismatch: 'Unsupported runtime architecture',
    executableUnavailable: 'Required executable unavailable',
    devServerFailed: 'Development server failed to start',
    localhostUnavailable: 'Localhost server unavailable',
    frameworkNeedsRuntime: 'Framework requires unavailable runtime',
    processFailed: 'Process execution failed',
    ptyUnavailable: 'PTY unavailable',
    commandUnavailable: 'Command unavailable',
    webviewCapability: 'WebView capability unavailable',
    webviewNavFailed: 'WebView navigation failed',
    webviewApiMissing: 'Required browser API unavailable',
    fsDenied: 'Filesystem operation denied',
    permissionDenied: 'Required permission unavailable',
    nativeIncompatible: 'Native binary incompatible',
    nativeDepMissing: 'Native dependency unavailable',
    networkFailed: 'Network operation failed',
    resourceExhausted: 'Insufficient device resources',
    cloudUnavailable: 'Cloud fallback unavailable',
    cloudExecFailed: 'Cloud runtime execution failed',
  };

  static String titleFor(String code) => titles[code] ?? code;
}

/// One structured diagnostics event (§7).
class SystemLogEvent {
  /// Unique event id (`CW-xxxxxx`), distinct from [traceId].
  final String id;

  /// Correlation id shared by one user operation's events (§23).
  final String traceId;

  final int timestampMs;
  final CwSeverity severity;
  final CwCategory category;

  /// Originating subsystem: AGENT, TERMINAL, PREVIEW, WEBVIEW,
  /// DEV_SERVER, RUNTIME, WORKSPACE, CLOUD, NETWORK…
  final String component;

  /// Stable code from [CwCodes] (empty for pure info events).
  final String errorCode;
  final String title;
  final String message;

  /// Collapsible raw evidence (redacted before store).
  final String technicalDetails;

  final String operation;
  final String command;
  final int? exitCode;
  final String projectId;
  final String platform;
  final String runtime;

  /// False → code changes cannot fix this; AI must not loop rewrites.
  final bool aiCanFix;

  final String fallbackAvailable;
  final String fallbackUsed;

  int occurrenceCount;
  int firstAtMs;
  int lastAtMs;

  SystemLogEvent({
    required this.id,
    required this.traceId,
    required this.timestampMs,
    required this.severity,
    required this.category,
    required this.component,
    this.errorCode = '',
    required this.title,
    required this.message,
    this.technicalDetails = '',
    this.operation = '',
    this.command = '',
    this.exitCode,
    this.projectId = '',
    this.platform = '',
    this.runtime = '',
    required this.aiCanFix,
    this.fallbackAvailable = '',
    this.fallbackUsed = '',
    this.occurrenceCount = 1,
    int? firstAtMs,
    int? lastAtMs,
  })  : firstAtMs = firstAtMs ?? timestampMs,
        lastAtMs = lastAtMs ?? timestampMs;

  Map<String, dynamic> toMap() => {
        'id': id,
        'traceId': traceId,
        'ts': timestampMs,
        'sev': severity.name,
        'cat': category.name,
        'comp': component,
        'code': errorCode,
        'title': title,
        'msg': message,
        'tech': technicalDetails,
        'op': operation,
        'cmd': command,
        'exit': exitCode,
        'proj': projectId,
        'plat': platform,
        'rt': runtime,
        'fix': aiCanFix,
        'fbA': fallbackAvailable,
        'fbU': fallbackUsed,
        'n': occurrenceCount,
        'first': firstAtMs,
        'last': lastAtMs,
      };

  factory SystemLogEvent.fromMap(Map m) {
    int asInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
    return SystemLogEvent(
      id: (m['id'] ?? '').toString(),
      traceId: (m['traceId'] ?? '').toString(),
      timestampMs: asInt(m['ts']),
      severity: _severityOf(m['sev']?.toString()),
      category: _categoryOf(m['cat']?.toString()),
      component: (m['comp'] ?? '').toString(),
      errorCode: (m['code'] ?? '').toString(),
      title: (m['title'] ?? '').toString(),
      message: (m['msg'] ?? '').toString(),
      technicalDetails: (m['tech'] ?? '').toString(),
      operation: (m['op'] ?? '').toString(),
      command: (m['cmd'] ?? '').toString(),
      exitCode: m['exit'] == null ? null : asInt(m['exit']),
      projectId: (m['proj'] ?? '').toString(),
      platform: (m['plat'] ?? '').toString(),
      runtime: (m['rt'] ?? '').toString(),
      aiCanFix: m['fix'] != false,
      fallbackAvailable: (m['fbA'] ?? '').toString(),
      fallbackUsed: (m['fbU'] ?? '').toString(),
      occurrenceCount: asInt(m['n']) <= 0 ? 1 : asInt(m['n']),
      firstAtMs: asInt(m['first']),
      lastAtMs: asInt(m['last']),
    );
  }

  static CwSeverity _severityOf(String? name) {
    for (final v in CwSeverity.values) {
      if (v.name == name) return v;
    }
    return CwSeverity.info;
  }

  static CwCategory _categoryOf(String? name) {
    for (final v in CwCategory.values) {
      if (v.name == name) return v;
    }
    return CwCategory.unknown;
  }

  /// Structured snippet for AI prompts (§16/17).
  String aiContextBlock() {
    final b = StringBuffer()
      ..writeln('{')
      ..writeln('  errorCode: "$errorCode",')
      ..writeln('  category: "${category.name.toUpperCase()}",')
      ..writeln('  component: "$component",')
      ..writeln('  aiCanFix: $aiCanFix,');
    if (fallbackAvailable.isNotEmpty) {
      b.writeln('  fallbackAvailable: "$fallbackAvailable",');
    }
    if (projectId.isNotEmpty) b.writeln('  projectId: "$projectId",');
    if (command.isNotEmpty) b.writeln('  command: "$command",');
    b.writeln('  occurrences: $occurrenceCount,');
    b.write('}');
    return b.toString();
  }
}

/// Fresh correlation id: `CW-` + 6 uppercase hex (§23).
String newTraceId([Random? random]) {
  final r = random ?? Random();
  final buf = StringBuffer('CW-');
  for (var i = 0; i < 6; i++) {
    buf.write(r.nextInt(16).toRadixString(16).toUpperCase());
  }
  return buf.toString();
}

/// Unique event id (heavier entropy than trace ids).
String newEventId([Random? random]) {
  final r = random ?? Random();
  final micros = DateTime.now().microsecondsSinceEpoch;
  return 'CW-EV-${micros.toRadixString(16).toUpperCase()}${r.nextInt(0xFFFF).toRadixString(16).toUpperCase().padLeft(4, '0')}';
}

// ── Secret redaction (§26) ──

final _secretValueRe = RegExp(
    r'((?:api[_-]?key|access[_-]?token|auth[_-]?token|token|secret|password|passwd|authorization|cookie|set-cookie)(?:\s*[:=]\s*|\s+))([^\s;,\)\]]+)',
    caseSensitive: false);
final _bearerRe =
    RegExp(r'(Bearer\s+)[A-Za-z0-9\-._~+/=]+', caseSensitive: false);
final _skRe = RegExp(r'\bsk-[A-Za-z0-9\-_]{4,}');
// Idempotent: [ and ] excluded so already-redacted values never match.
final _envSecretRe = RegExp(
    r'\b([A-Z_0-9]*(?:KEY|TOKEN|SECRET|PASSWORD|COOKIE)[A-Z_0-9]*)=([^\s;,\(\)\[\]]+)');

/// Mask secrets before persistence AND display. Never throws.
String redactSecrets(String s) {
  if (s.isEmpty) return s;
  try {
    var out = s.replaceAllMapped(
        _secretValueRe, (m) => '${m.group(1)}[REDACTED]');
    out = out.replaceAllMapped(
        _bearerRe, (m) => '${m.group(1)}[REDACTED]');
    out = out.replaceAllMapped(_skRe, (_) => 'sk-[REDACTED]');
    out = out.replaceAllMapped(
        _envSecretRe, (m) => '${m.group(1)}=[REDACTED]');
    return out;
  } catch (_) {
    return s;
  }
}

// ── Classifier (§8) ──

/// Outcome of classifying one failure. A null [errorCode] means "not
/// a system event" — route to the AI debugger / terminal output only.
class ClassificationResult {
  final CwCategory category;
  final String? errorCode;
  final bool aiCanFix;
  final String title;
  final String explanation;
  final String fallbackAvailable;

  const ClassificationResult({
    required this.category,
    this.errorCode,
    required this.aiCanFix,
    required this.title,
    required this.explanation,
    this.fallbackAvailable = '',
  });
}

const _fbCloud = 'USE_CLOUD_RUNTIME';
const _fbRetry = 'RETRY';

/// Evidence-based failure classification. Order matters: specific
/// platform evidence first, generic non-zero exits last (never
/// compatibility). Never throws.
ClassificationResult classifyFailure({
  String command = '',
  int? exitCode,
  String stderr = '',
  String stdout = '',
  Object? exception,
  String platform = '',
  bool processSpawnFailed = false,
  bool localhostExpected = false,
  bool ptyRequested = false,
}) {
  final cmd = command.toLowerCase();
  final text = '${exception ?? ''}\n$stderr\n$stdout'.toLowerCase();
  bool has(List<String> needles) =>
      needles.any((n) => text.contains(n));

  // 1. Application source errors → CODE path, never a system event.
  if (has([
    'syntaxerror',
    'typeerror',
    'referenceerror',
    'has no corresponding closing tag',
    'unexpected token',
    'cannot read propert',
    'is not a function',
    'is not defined',
    'ts2',
    'ts1',
    'error ts',
  ])) {
    return const ClassificationResult(
      category: CwCategory.code,
      aiCanFix: true,
      title: 'Application source error',
      explanation:
          'The failure looks like a bug in the project source itself — route it to the AI debugger, not System Logs.',
    );
  }

  // 2. Dependency resolution (registry/semver) → AI may fix config.
  if (has([
    'etagtarget',
    'err! 404',
    ' 404 not found',
    'not found - get',
    'no matching version',
    'version not found',
    'could not resolve dependency',
    'eresolve',
    'peer dep',
  ])) {
    return const ClassificationResult(
      category: CwCategory.dependency,
      aiCanFix: true,
      title: 'Dependency resolution failed',
      explanation:
          'The package manager could not resolve a dependency (name/version). The AI may fix the package manifest.',
    );
  }

  // 3. Native binary incompatibility (exec format, ELF, bad CPU).
  if (has([
    'exec format error',
    'cannot execute binary file',
    'bad cpu type',
    'elf',
    'wrong architecture',
  ])) {
    return ClassificationResult(
      category: CwCategory.native,
      errorCode: CwCodes.nativeIncompatible,
      aiCanFix: false,
      title: CwCodes.titles[CwCodes.nativeIncompatible]!,
      explanation:
          'The binary cannot execute on this device CPU/OS (e.g. desktop Linux binary on Android/$platform). No source change can fix this.',
      fallbackAvailable: _fbCloud,
    );
  }

  // 4. Permission / sandbox denial.
  if (has([
    'permission denied',
    'eacces',
    'operation not permitted',
    'access is denied',
  ])) {
    return ClassificationResult(
      category: CwCategory.permission,
      errorCode: CwCodes.permissionDenied,
      aiCanFix: false,
      title: CwCodes.titles[CwCodes.permissionDenied]!,
      explanation:
          'The OS refused the operation (Android sandbox/permissions). Retrying the same code will not help.',
      fallbackAvailable: _fbRetry,
    );
  }

  // 5. Missing executables / runtimes.
  final missingExe = processSpawnFailed ||
      has([
        'command not found',
        'is not recognized as',
        'no such executable',
        'spawn ',
        'processexception',
      ]);
  final mentionsNode =
      has(['node', 'npm', 'npx']) && (missingExe || has(['enoent']));
  final mentionsPython =
      has(['python', 'pip']) && (missingExe || has(['enoent']));
  if (mentionsNode && !mentionsPython) {
    return ClassificationResult(
      category: CwCategory.runtime,
      errorCode: CwCodes.nodeUnavailable,
      aiCanFix: false,
      title: CwCodes.titles[CwCodes.nodeUnavailable]!,
      explanation:
          'Node.js is not available in this execution environment. AI code changes cannot make a runtime exist.',
      fallbackAvailable: _fbCloud,
    );
  }
  if (mentionsPython && !mentionsNode) {
    return ClassificationResult(
      category: CwCategory.runtime,
      errorCode: CwCodes.pythonUnavailable,
      aiCanFix: false,
      title: CwCodes.titles[CwCodes.pythonUnavailable]!,
      explanation:
          'Python is not available in this execution environment.',
      fallbackAvailable: _fbCloud,
    );
  }
  if (missingExe) {
    return ClassificationResult(
      category: CwCategory.runtime,
      errorCode: CwCodes.executableUnavailable,
      aiCanFix: false,
      title: CwCodes.titles[CwCodes.executableUnavailable]!,
      explanation:
          'The required executable could not be started on this device.',
      fallbackAvailable: _fbCloud,
    );
  }

  // 6. PTY requested but unavailable.
  if (ptyRequested &&
      has(['pty', 'inappropriate ioctl', 'not a tty', 'no terminal'])) {
    return ClassificationResult(
      category: CwCategory.process,
      errorCode: CwCodes.ptyUnavailable,
      aiCanFix: false,
      title: CwCodes.titles[CwCodes.ptyUnavailable]!,
      explanation: 'No pseudo-terminal is available in this environment.',
    );
  }

  // 7. Localhost expected but refused → dev server never came up.
  if (localhostExpected &&
      has([
        'connection refused',
        'econnrefused',
        'err_connection_refused',
        'connection reset',
      ])) {
    return ClassificationResult(
      category: CwCategory.preview,
      errorCode: CwCodes.localhostUnavailable,
      aiCanFix: false,
      title: CwCodes.titles[CwCodes.localhostUnavailable]!,
      explanation:
          'Nothing is listening on the expected localhost address — the development server did not come up.',
      fallbackAvailable: _fbRetry,
    );
  }

  // 8. Timeouts.
  if (has(['timed out', 'timeoutexception', 'etimedout'])) {
    return const ClassificationResult(
      category: CwCategory.process,
      errorCode: CwCodes.processFailed,
      aiCanFix: false,
      title: 'Operation timed out',
      explanation:
          'The operation did not finish in time. Check the network connection and retry.',
      fallbackAvailable: _fbRetry,
    );
  }

  // 9. Resource exhaustion (OOM killer, SIGKILL/137).
  if (has([
        'out of memory',
        'cannot allocate memory',
        'killed',
        'sigkill',
      ]) ||
      exitCode == 137) {
    return ClassificationResult(
      category: CwCategory.resource,
      errorCode: CwCodes.resourceExhausted,
      aiCanFix: false,
      title: CwCodes.titles[CwCodes.resourceExhausted]!,
      explanation:
          'The process was killed — the device is out of memory/resources. Rewriting code will not help.',
      fallbackAvailable: _fbRetry,
    );
  }

  // 10. Network evidence.
  if (has([
    'enotfound',
    'eai_again',
    'failed host lookup',
    'network is unreachable',
    'econnreset',
    'econnaborted',
    'socketexception',
    'no internet',
    'offline',
  ])) {
    return ClassificationResult(
      category: CwCategory.network,
      errorCode: CwCodes.networkFailed,
      aiCanFix: false,
      title: CwCodes.titles[CwCodes.networkFailed]!,
      explanation:
          'A network operation failed. Connect and retry — no code change required.',
      fallbackAvailable: _fbRetry,
    );
  }

  // 11. Port conflicts on server start.
  if (has(['eaddrinuse', 'address already in use', 'port'] ) &&
      (cmd.contains('dev') ||
          cmd.contains('serve') ||
          cmd.contains('start'))) {
    return ClassificationResult(
      category: CwCategory.preview,
      errorCode: CwCodes.devServerFailed,
      aiCanFix: false,
      title: CwCodes.titles[CwCodes.devServerFailed]!,
      explanation:
          'The development server could not bind its port — another process may hold it.',
      fallbackAvailable: _fbRetry,
    );
  }

  // 12. WebView capability evidence (only with explicit signals).
  if (has([
    'websocket is not supported',
    'service workers are not supported',
    'not supported in this webview',
    'webview',
  ])) {
    return ClassificationResult(
      category: CwCategory.webview,
      errorCode: CwCodes.webviewCapability,
      aiCanFix: false,
      title: CwCodes.titles[CwCodes.webviewCapability]!,
      explanation:
          'The embedded WebView lacks a capability the page needs.',
    );
  }

  // 13. Fallthrough: ordinary failure — NOT a system event (§28).
  return const ClassificationResult(
    category: CwCategory.unknown,
    aiCanFix: true,
    title: 'Command failed',
    explanation:
        'No runtime/platform evidence — treat as an ordinary failure on the terminal/AI path.',
  );
}

/// Map an existing DevServerException code to a CubicWeb code (§18).
/// Returns null when the failure is dependency-flavored (AI-fixable).
String? devServerCodeToCw(String code, String message) {
  switch (code) {
    case 'node-missing':
      return CwCodes.nodeUnavailable;
    case 'unsupported-platform':
      return CwCodes.frameworkNeedsRuntime;
    case 'install-failed':
    case 'install-timeout':
    case 'install-spawn-failed':
      // Dependency-flavored (bad version) stays on the AI path;
      // anything else is a process/network-level failure.
      final c = classifyFailure(command: 'npm install', stderr: message);
      if (c.category == CwCategory.dependency) return null;
      if (c.category == CwCategory.network) return CwCodes.networkFailed;
      return CwCodes.devServerFailed;
    case 'start-timeout':
    case 'unhealthy':
    case 'start-failed':
    case 'spawn-failed':
      return CwCodes.devServerFailed;
    default:
      return CwCodes.devServerFailed;
  }
}
