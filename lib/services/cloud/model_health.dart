/// Per-model liveness state for cloud providers (pure Dart).
///
/// "Free" tags lie: only a real (tiny) chat call proves a model answers.
/// Health is informational — it never blocks selection, it only powers
/// the online/failed badges, Test-all and auto-hide.
library;

/// Liveness of one provider+model pair.
enum ModelHealthStatus {
  /// Never tested (or data cleared).
  unknown,

  /// A ping is in flight right now.
  testing,

  /// Answered a ping call.
  online,

  /// Ping failed (key/credits/gone — see [ModelHealth.error]).
  failed,
}

/// Short labels for UI badges.
String modelHealthLabel(ModelHealthStatus s) {
  switch (s) {
    case ModelHealthStatus.unknown:
      return 'Untested';
    case ModelHealthStatus.testing:
      return 'Testing…';
    case ModelHealthStatus.online:
      return 'Online';
    case ModelHealthStatus.failed:
      return 'Failed';
  }
}

/// One health record. Serialized to Hive as a plain map.
class ModelHealth {
  final String modelId;
  final ModelHealthStatus status;
  final int latencyMs;
  final String error;
  final int checkedAtMs;

  const ModelHealth({
    required this.modelId,
    required this.status,
    this.latencyMs = 0,
    this.error = '',
    this.checkedAtMs = 0,
  });

  Map<String, dynamic> toMap() => {
        'modelId': modelId,
        'status': status.name,
        'latencyMs': latencyMs,
        'error': error,
        'checkedAtMs': checkedAtMs,
      };

  factory ModelHealth.fromMap(Map m) {
    ModelHealthStatus status = ModelHealthStatus.unknown;
    try {
      status = ModelHealthStatus.values
          .firstWhere((e) => e.name == (m['status'] ?? '').toString());
      // A persisted "testing" means the app died mid-test.
      if (status == ModelHealthStatus.testing) {
        status = ModelHealthStatus.unknown;
      }
    } catch (_) {}
    int asInt(dynamic v) =>
        v is int ? v : int.tryParse('$v') ?? 0;
    return ModelHealth(
      modelId: (m['modelId'] ?? '').toString(),
      status: status,
      latencyMs: asInt(m['latencyMs']),
      error: (m['error'] ?? '').toString(),
      checkedAtMs: asInt(m['checkedAtMs']),
    );
  }
}

/// Compress a ping failure into one short human line.
///
/// Covers the cases users actually hit: bad key, spent credits / rate
/// limits, vanished model ids, timeouts, dead endpoints.
String summarizeModelError(Object e) {
  final raw = '$e';
  final lower = raw.toLowerCase();
  if (lower.contains('401') ||
      lower.contains('unauthorized') ||
      lower.contains('invalid api key') ||
      lower.contains('incorrect api key')) {
    return 'Invalid API key (401)';
  }
  // Zero allowance beats generic rate-limit: the key/project has NO
  // quota at all (wrong key type, billing off, free tier exhausted).
  // Must run before the credit/quota branch below ("quota exceeded"
  // appears in both payload shapes).
  if (RegExp(r'"quota_limit_value"\s*:\s*"0"').hasMatch(raw)) {
    return 'Quota is zero — this key/project has no allowance. Wrong key type, billing disabled, or free tier exhausted.';
  }
  if (lower.contains('402') ||
      lower.contains('payment required') ||
      lower.contains('insufficient') ||
      lower.contains('credit') ||
      lower.contains('quota')) {
    return 'No credits / quota spent (402)';
  }
  if (lower.contains('429') ||
      lower.contains('rate limit') ||
      lower.contains('too many requests')) {
    return 'Rate limited (429)';
  }
  if (lower.contains('403') || lower.contains('forbidden')) {
    return 'Forbidden (403)';
  }
  if (lower.contains('404') || lower.contains('not found')) {
    return 'Model not found (404)';
  }
  if (lower.contains('timeout') || lower.contains('timed out')) {
    return 'Timed out';
  }
  if (lower.contains('socket') ||
      lower.contains('network') ||
      lower.contains('connection refused') ||
      lower.contains('failed host lookup') ||
      lower.contains('network is unreachable')) {
    return 'Network unreachable';
  }
  final oneLine = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (oneLine.length <= 90) return oneLine;
  return '${oneLine.substring(0, 90)}…';
}

/// Should the model list auto-refresh now?
///
/// Pure (testable): [lastSyncIso] is the persisted ISO timestamp (null
/// = never), [intervalHours] the configured cadence, [now] injected.
bool shouldAutoSync({
  required String? lastSyncIso,
  required int intervalHours,
  required DateTime now,
}) {
  if (intervalHours <= 0) return false;
  if (lastSyncIso == null || lastSyncIso.isEmpty) return true;
  final last = DateTime.tryParse(lastSyncIso);
  if (last == null) return true;
  return now.difference(last).inHours >= intervalHours;
}

/// Models in [after] that were not in [before] (the "new imports").
List<String> findNewModels(List<String> before, List<String> after) {
  final known = before.toSet();
  return after.where((m) => !known.contains(m)).toList();
}

/// True for transient probe failures worth ONE retry after a short
/// backoff (rate limits from burst probing, overloaded / 5xx,
/// timeouts). Auth / not-found / quota-zero errors are permanent.
bool isRetryableProbeError(String raw) {
  final lower = raw.toLowerCase();
  if (RegExp(r'\b(429|408|500|502|503|504)\b').hasMatch(lower)) return true;
  const markers = [
    'rate limit',
    'too many requests',
    'overloaded',
    'try again',
    'timeout',
    'timed out',
    'temporarily',
    'connection reset',
    'socket',
  ];
  return markers.any(lower.contains);
}

/// Non-blocking key-shape hint ("does this look like provider X's
/// key?"). Returns null when fine or provider unknown — formats can
/// change, so this never blocks saving.
String? keyFormatHint(String providerId, String key) {
  final k = key.trim();
  if (k.isEmpty) return null;
  switch (providerId) {
    case 'google':
      if (!k.startsWith('AIza')) {
        return 'This doesn\'t look like a Google AI Studio key (they start with "AIza"). Grab a free one at aistudio.google.com — or check for a typo.';
      }
      return null;
    case 'openrouter':
      if (!k.startsWith('sk-or-')) {
        return 'OpenRouter keys usually start with "sk-or-". Double-check you pasted the right key.';
      }
      return null;
    case 'orcarouter':
      if (!k.startsWith('sk-orca-')) {
        return 'OrcaRouter keys usually start with "sk-orca-". Double-check you pasted the right key.';
      }
      return null;
    case 'anthropic':
      if (!k.startsWith('sk-ant-')) {
        return 'Anthropic keys usually start with "sk-ant-". Double-check you pasted the right key.';
      }
      return null;
    case 'openai':
      if (!k.startsWith('sk-')) {
        return 'OpenAI keys usually start with "sk-". Double-check you pasted the right key.';
      }
      return null;
    default:
      return null;
  }
}
