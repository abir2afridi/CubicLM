/// Pure Battle Arena scoring — no GetX, no I/O, unit-tested.
///
/// Each contender is ranked on three axes (1 = best):
/// - finish: who completed first (errors always rank last)
/// - speed: estimated tokens/sec (chars/4 ÷ seconds)
/// - length: most output characters
/// Overall score = 0.4·finish + 0.3·speed + 0.3·length (lowest wins).
/// Ties share the better rank (competition ranking: 1,2,2,4).
library;

class BattleScoreInput {
  final String id;
  final bool failed;
  final int elapsedMs;
  final int chars;

  const BattleScoreInput({
    required this.id,
    required this.failed,
    required this.elapsedMs,
    required this.chars,
  });

  double get tokensPerSec {
    if (failed || elapsedMs <= 0) return 0;
    return (chars / 4) / (elapsedMs / 1000);
  }
}

class BattleRowResult {
  final String id;
  final int finishRank;
  final int speedRank;
  final int lengthRank;
  final double score;

  const BattleRowResult({
    required this.id,
    required this.finishRank,
    required this.speedRank,
    required this.lengthRank,
    required this.score,
  });
}

class BattleVerdict {
  /// Row ids ordered best → worst.
  final List<String> order;

  /// Per-id breakdown.
  final Map<String, BattleRowResult> rows;

  const BattleVerdict({required this.order, required this.rows});

  String get winnerId => order.isEmpty ? '' : order.first;
}

/// Competition ranking: equal values share a rank, next rank skips.
/// [rankedIds] must be pre-sorted best-first.
Map<String, int> competitionRanks(
    List<String> rankedIds, Map<String, double> keyOf) {
  final ranks = <String, int>{};
  var rank = 0;
  var pos = 0;
  double? prev;
  for (final id in rankedIds) {
    pos++;
    final v = keyOf[id]!;
    if (prev == null || v != prev) {
      rank = pos;
      prev = v;
    }
    ranks[id] = rank;
  }
  return ranks;
}

BattleVerdict scoreContenders(List<BattleScoreInput> inputs) {
  if (inputs.isEmpty) return const BattleVerdict(order: [], rows: {});
  final ok = inputs.where((e) => !e.failed).toList();
  final failed = inputs.where((e) => e.failed).toList();

  // Finish: ok sorted by elapsed, then all failures tied last.
  final finishSorted = [
    ...ok..sort((a, b) => a.elapsedMs.compareTo(b.elapsedMs)),
    ...failed,
  ];
  final finishRanks = competitionRanks(
    finishSorted.map((e) => e.id).toList(),
    {for (final e in inputs) e.id: e.failed ? double.infinity : e.elapsedMs.toDouble()},
  );

  // Speed: tokens/sec desc (failures score 0 → naturally last).
  final speedSorted = [...inputs]
    ..sort((a, b) => b.tokensPerSec.compareTo(a.tokensPerSec));
  final speedRanks = competitionRanks(
    speedSorted.map((e) => e.id).toList(),
    {for (final e in inputs) e.id: -e.tokensPerSec},
  );

  // Length: chars desc among finishers; failures rank after all ok.
  final lengthSorted = [
    ...ok..sort((a, b) => b.chars.compareTo(a.chars)),
    ...failed,
  ];
  final lengthRanks = competitionRanks(
    lengthSorted.map((e) => e.id).toList(),
    {
      for (final e in inputs)
        e.id: e.failed ? double.infinity : -e.chars.toDouble()
    },
  );

  final rows = <String, BattleRowResult>{};
  for (final e in inputs) {
    final f = finishRanks[e.id]!;
    final s = speedRanks[e.id]!;
    final l = lengthRanks[e.id]!;
    rows[e.id] = BattleRowResult(
      id: e.id,
      finishRank: f,
      speedRank: s,
      lengthRank: l,
      score: f * 0.4 + s * 0.3 + l * 0.3,
    );
  }
  final order = inputs.map((e) => e.id).toList()
    ..sort((a, b) => rows[a]!.score.compareTo(rows[b]!.score));
  return BattleVerdict(order: order, rows: rows);
}
