/// Pure history-budget helpers for chat context trimming.
///
/// Extracted from ChatController so they are unit-testable without GetX or
/// Hive. Semantics: oversized single turns are middle-truncated (head +
/// tail kept) instead of dropped, so a long code answer never wipes
/// context entirely. The current + previous turn are always kept.
library;

/// Marker inserted where middle content was trimmed.
const historyTrimMarker = '\n…(middle trimmed for context)…\n';

int historyChars(List<Map<String, String>> msgs, [int start = 0]) {
  var total = 0;
  for (var i = start; i < msgs.length; i++) {
    total += (msgs[i]['content'] ?? '').length;
  }
  return total;
}

Map<String, String> capMiddle(Map<String, String> m, int cap) {
  final c = m['content'] ?? '';
  if (c.length <= cap) return m;
  if (cap <= historyTrimMarker.length + 100) {
    return {'role': m['role'] ?? '', 'content': c.substring(0, cap)};
  }
  final keep = cap - historyTrimMarker.length;
  final head = (keep * 0.6).floor();
  return {
    'role': m['role'] ?? '',
    'content': c.substring(0, head) +
        historyTrimMarker +
        c.substring(c.length - (keep - head)),
  };
}

List<Map<String, String>> fitHistoryToBudget(
    List<Map<String, String>> history, int maxChars) {
  if (history.length <= 1) return history;
  // No single turn may eat more than half the budget.
  final perMsg = (maxChars / 2).ceil();
  final capped = history.map((m) => capMiddle(m, perMsg)).toList();
  // Drop oldest first, but always keep current + previous turn.
  var start = 0;
  while (start < capped.length - 2 &&
      historyChars(capped, start) > maxChars) {
    start++;
  }
  var out = capped.sublist(start);
  // Still over with just two turns: squeeze the older one further.
  if (out.length == 2 && historyChars(out) > maxChars) {
    final newestLen = (out[1]['content'] ?? '').length;
    final allowOlder = maxChars - newestLen - historyTrimMarker.length;
    if (allowOlder > 200) {
      out = [capMiddle(out[0], allowOlder), out[1]];
    }
  }
  return out;
}
