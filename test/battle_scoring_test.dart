import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/utils/battle_scoring.dart';

void main() {
  group('scoreContenders', () {
    test('clear winner ranks first on all axes', () {
      final v = scoreContenders([
        const BattleScoreInput(
            id: 'fast', failed: false, elapsedMs: 1000, chars: 4000),
        const BattleScoreInput(
            id: 'slow', failed: false, elapsedMs: 4000, chars: 1000),
      ]);
      expect(v.winnerId, 'fast');
      expect(v.order, ['fast', 'slow']);
      expect(v.rows['fast']!.finishRank, 1);
      expect(v.rows['fast']!.speedRank, 1);
      expect(v.rows['fast']!.lengthRank, 1);
    });

    test('failures always rank last', () {
      final v = scoreContenders([
        const BattleScoreInput(
            id: 'dead', failed: true, elapsedMs: 500, chars: 0),
        const BattleScoreInput(
            id: 'alive', failed: false, elapsedMs: 9000, chars: 100),
      ]);
      expect(v.winnerId, 'alive');
      expect(v.rows['dead']!.finishRank, 2);
      expect(v.rows['dead']!.speedRank, 2);
      expect(v.rows['dead']!.lengthRank, 2);
    });

    test('mixed axes produce weighted winner + ties share rank', () {
      // sprinter: finishes first but thin + slowest rate.
      // marathon: last to finish, but fastest rate (250 tok/s) + longest.
      final v = scoreContenders([
        const BattleScoreInput(
            id: 'sprinter', failed: false, elapsedMs: 1000, chars: 400),
        const BattleScoreInput(
            id: 'marathon', failed: false, elapsedMs: 8000, chars: 8000),
        const BattleScoreInput(
            id: 'mid', failed: false, elapsedMs: 4000, chars: 2000),
      ]);
      // marathon: 3,1,1 → 1.8 · mid: 2,2,2 → 2.0 · sprinter: 1,3,3 → 2.2
      expect(v.winnerId, 'marathon');
      expect(v.order, ['marathon', 'mid', 'sprinter']);
    });

    test('empty input gives empty verdict', () {
      final v = scoreContenders([]);
      expect(v.order, isEmpty);
      expect(v.winnerId, '');
    });

    test('single finisher wins outright', () {
      final v = scoreContenders([
        const BattleScoreInput(
            id: 'solo', failed: false, elapsedMs: 2000, chars: 500),
      ]);
      expect(v.winnerId, 'solo');
      expect(v.rows['solo']!.score, 1.0);
    });
  });
}
