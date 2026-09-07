/// CubicWebLogger — the central system-diagnostics service (§6).
///
/// Every subsystem that can fail for runtime/platform reasons reports
/// structured [SystemLogEvent]s here instead of inventing its own
/// classification. Features:
/// - occurrence dedup (§24) — repeats collapse with first/last/count
/// - trace/correlation ids (§23)
/// - Hive persistence with retention caps (§25)
/// - secret redaction before store AND display (§26)
/// - unread-error badge counter
/// - AI guards: [hasBlockingIssue] / [recentForAi] (§5/16/17)
/// - one-line forward into AppLogService (reuses existing infra)
library;

import 'dart:async';

import 'package:get/get.dart';

import '../../services/app_log_service.dart';
import '../../services/hive_service.dart';
import 'cubicweb_event.dart';

class CubicWebLogger extends GetxService {
  static const _storeKey = 'cubicweb_logs_v1';
  static const _memoryCap = 200;
  static const _persistCap = 100;

  /// Newest last (UI reverses). Capped at [_memoryCap].
  final events = <SystemLogEvent>[].obs;

  /// Unread error-severity count for the badge.
  final unreadErrors = 0.obs;

  bool _ready = false;
  int _lastSaveMs = 0;
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

  /// Load persisted events. Never throws.
  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    try {
      final raw = _get(_storeKey);
      if (raw is List) {
        final loaded = <SystemLogEvent>[];
        for (final m in raw.whereType<Map>().take(_persistCap)) {
          try {
            final e = SystemLogEvent.fromMap(m);
            if (e.id.isNotEmpty) loaded.add(e);
          } catch (_) {}
        }
        // Stored oldest-first; keep the newest [_memoryCap].
        events.assignAll(loaded.length > _memoryCap
            ? loaded.sublist(loaded.length - _memoryCap)
            : loaded);
      }
    } catch (_) {}
  }

  /// Record a structured event. Applies redaction, dedup, caps,
  /// persistence and AppLog forwarding. Never throws. Returns the
  /// (possibly merged) event.
  SystemLogEvent log({
    required CwSeverity severity,
    required CwCategory category,
    required String component,
    String errorCode = '',
    required String title,
    required String message,
    String technicalDetails = '',
    String operation = '',
    String command = '',
    int? exitCode,
    String projectId = '',
    String traceId = '',
    String platform = '',
    String runtime = '',
    required bool aiCanFix,
    String fallbackAvailable = '',
    String fallbackUsed = '',
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final event = SystemLogEvent(
      id: newEventId(),
      traceId: traceId.isEmpty ? newTraceId() : traceId,
      timestampMs: now,
      severity: severity,
      category: category,
      component: component,
      errorCode: errorCode,
      title: title,
      message: redactSecrets(message),
      technicalDetails: redactSecrets(technicalDetails),
      operation: operation,
      command: redactSecrets(command),
      exitCode: exitCode,
      projectId: projectId,
      platform: platform,
      runtime: runtime,
      aiCanFix: aiCanFix,
      fallbackAvailable: fallbackAvailable,
      fallbackUsed: fallbackUsed,
    );
    try {
      // Dedup (§24): same code+category+component+project+operation
      // collapses into first/last/count instead of flooding the UI.
      SystemLogEvent? twin;
      for (var i = events.length - 1; i >= 0; i--) {
        final e = events[i];
        if (e.errorCode == event.errorCode &&
            e.category == event.category &&
            e.component == event.component &&
            e.projectId == event.projectId &&
            e.operation == event.operation) {
          twin = e;
          break;
        }
      }
      if (twin != null) {
        twin.occurrenceCount++;
        twin.lastAtMs = now;
        events.refresh();
        unawaited(_saveThrottled());
        if (severity == CwSeverity.error) unreadErrors.value++;
        return twin;
      }
      events.add(event);
      while (events.length > _memoryCap) {
        events.removeAt(0);
      }
      if (severity == CwSeverity.error) unreadErrors.value++;
      unawaited(_saveThrottled());
    } catch (_) {}
    // Reuse existing infra: one line into the app log stream.
    try {
      final line =
          '${errorCode.isEmpty ? title : '$errorCode — $title'}${projectId.isEmpty ? '' : ' [$projectId]'}';
      if (severity == CwSeverity.error) {
        Get.find<AppLogService>()
            .error(line, category: LogCategory.system);
      } else if (severity == CwSeverity.warning) {
        Get.find<AppLogService>()
            .warning(line, category: LogCategory.system);
      } else {
        Get.find<AppLogService>()
            .info(line, category: LogCategory.system);
      }
    } catch (_) {}
    return event;
  }

  /// Convenience: classify + log in one call. Returns the event, or
  /// null when the classifier says "not a system event" (code path).
  SystemLogEvent? logClassified({
    required String component,
    String operation = '',
    String command = '',
    int? exitCode,
    String stderr = '',
    String stdout = '',
    Object? exception,
    String platform = '',
    bool processSpawnFailed = false,
    bool localhostExpected = false,
    String projectId = '',
    String traceId = '',
    String runtime = '',
    CwSeverity severity = CwSeverity.error,
  }) {
    ClassificationResult c;
    try {
      c = classifyFailure(
        command: command,
        exitCode: exitCode,
        stderr: stderr,
        stdout: stdout,
        exception: exception,
        platform: platform,
        processSpawnFailed: processSpawnFailed,
        localhostExpected: localhostExpected,
      );
    } catch (_) {
      return null;
    }
    if (c.errorCode == null) return null;
    return log(
      severity: severity,
      category: c.category,
      component: component,
      errorCode: c.errorCode!,
      title: c.title,
      message: c.explanation,
      technicalDetails: _evidence(stderr, stdout, exception),
      operation: operation,
      command: command,
      exitCode: exitCode,
      projectId: projectId,
      traceId: traceId,
      platform: platform,
      runtime: runtime,
      aiCanFix: c.aiCanFix,
      fallbackAvailable: c.fallbackAvailable,
    );
  }

  String _evidence(String stderr, String stdout, Object? exception) {
    final buf = StringBuffer();
    if (exception != null) buf.writeln('$exception');
    final err = stderr.trim();
    if (err.isNotEmpty) {
      buf.writeln(err.length > 1200 ? err.substring(0, 1200) : err);
    }
    return buf.toString().trim();
  }

  /// True when an error-severity, aiCanFix=false event exists —
  /// optionally scoped to a project. AI guards consult this before
  /// rewriting files (§5: stop the infinite fix loop).
  bool hasBlockingIssue({String projectId = ''}) {
    try {
      for (var i = events.length - 1; i >= 0; i--) {
        final e = events[i];
        if (e.severity != CwSeverity.error) continue;
        if (!e.aiCanFix) {
          if (projectId.isEmpty || e.projectId.isEmpty || e.projectId == projectId) {
            return true;
          }
        }
      }
    } catch (_) {}
    return false;
  }

  /// Newest blocking event for a project (for explanations), if any.
  SystemLogEvent? blockingIssue({String projectId = ''}) {
    try {
      for (var i = events.length - 1; i >= 0; i--) {
        final e = events[i];
        if (e.severity != CwSeverity.error || e.aiCanFix) continue;
        if (projectId.isEmpty || e.projectId.isEmpty || e.projectId == projectId) {
          return e;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Structured diagnostics for AI prompts (§16/17), newest first.
  String recentForAi({String projectId = '', int limit = 3}) {
    try {
      final out = <String>[];
      for (var i = events.length - 1;
          i >= 0 && out.length < limit;
          i--) {
        final e = events[i];
        if (e.severity != CwSeverity.error) continue;
        if (projectId.isNotEmpty &&
            e.projectId.isNotEmpty &&
            e.projectId != projectId) {
          continue;
        }
        out.add(e.aiContextBlock());
      }
      return out.join('\n');
    } catch (_) {
      return '';
    }
  }

  void markAllRead() {
    try {
      unreadErrors.value = 0;
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      events.clear();
      unreadErrors.value = 0;
      await _put(_storeKey, []);
    } catch (_) {}
  }

  Future<void> _saveThrottled() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSaveMs < 5000) return;
    _lastSaveMs = now;
    try {
      final tail = events.length > _persistCap
          ? events.sublist(events.length - _persistCap)
          : events.toList();
      await _put(_storeKey, tail.map((e) => e.toMap()).toList());
    } catch (_) {}
  }
}
