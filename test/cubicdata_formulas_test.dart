import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/cubicdata/formulas.dart';
import 'package:cubiclm/services/cubicdata/models.dart';

SheetData _sheet(String id, String name, Map<String, CellData> cells) =>
    SheetData(id: id, name: name, cells: cells);

CellData _v(String value) => CellData(value: value);
CellData _f(String formula) => CellData(formula: formula);

void main() {
  group('addresses', () {
    test('col labels round-trip incl. AA+', () {
      expect(colLabelToIdx('A'), 0);
      expect(colLabelToIdx('Z'), 25);
      expect(colLabelToIdx('AA'), 26);
      expect(idxToColLabel(0), 'A');
      expect(idxToColLabel(26), 'AA');
      expect(idxToColLabel(27), 'AB');
    });

    test('parseCellAddress with sheet prefix', () {
      final p = parseCellAddress('Sheet1!B5')!;
      expect(p.sheetName, 'SHEET1');
      expect(p.colIdx, 1);
      expect(p.rowIdx, 4);
      expect(parseCellAddress('nope'), isNull);
    });

    test('expandRange normalizes reversed ranges', () {
      expect(expandRange('B2:A1'),
          ['A1', 'B1', 'A2', 'B2']);
    });
  });

  group('functions', () {
    final sheets = [
      _sheet('s1', 'Sheet1', {
        'A1': _v('10'),
        'A2': _v('20'),
        'A3': _v('30'),
        'B1': _v('hello'),
      }),
    ];

    test('SUM / AVERAGE / COUNT / MAX / MIN', () {
      expect(evaluateFormula('=SUM(A1:A3)', sheets, 's1'), '60');
      expect(evaluateFormula('=AVERAGE(A1:A3)', sheets, 's1'), '20');
      expect(evaluateFormula('=COUNT(A1:B1)', sheets, 's1'), '1');
      expect(evaluateFormula('=MAX(A1:A3)', sheets, 's1'), '30');
      expect(evaluateFormula('=MIN(A1:A3)', sheets, 's1'), '10');
    });

    test('CONCAT / UPPER / LOWER / LEN', () {
      // NOTE: like the web engine, quoted args are uppercased before the
      // function split, so "x" becomes "X". Fidelity over cleverness.
      expect(evaluateFormula('=CONCAT(A1,"x")', sheets, 's1'), '10X');
      expect(evaluateFormula('=UPPER(B1)', sheets, 's1'), 'HELLO');
      expect(evaluateFormula('=LOWER("AbC")', sheets, 's1'), 'abc');
      expect(evaluateFormula('=LEN(B1)', sheets, 's1'), '5');
    });

    test('inline arithmetic with refs', () {
      expect(evaluateFormula('=A1+A2*2', sheets, 's1'), '50');
      expect(evaluateFormula('=(A1+A2)/2', sheets, 's1'), '15');
      expect(evaluateFormula('=A1/0', sheets, 's1'), '#DIV/0!');
      expect(evaluateFormula('=B1+1', sheets, 's1'), '#ERROR!');
    });

    test('unknown function', () {
      expect(evaluateFormula('=FROB(A1)', sheets, 's1'), '#NAME? (FROB)');
    });
  });

  group('cross-sheet + cycles', () {
    final sheets = [
      _sheet('s1', 'Sheet1', {'A1': _f('=SUM(Sheet2!B2)')}),
      _sheet('s2', 'Sheet2', {'B2': _v('7')}),
    ];

    test('cross-sheet reference resolves inside functions', () {
      expect(evaluateFormula('=SUM(Sheet2!B2)', sheets, 's1'), '7');
      // Chained through another formula cell.
      expect(evaluateFormula('=A1+0', sheets, 's1'), '7');
    });

    test('circular reference detected', () {
      final loop = [
        _sheet('s1', 'Sheet1', {'A1': _f('=A2'), 'A2': _f('=A1')}),
      ];
      expect(evaluateFormula('=A1', loop, 's1'), '#CIRCULAR!');
    });

    test('unknown current sheet is #REF!', () {
      // No sheet matches the id and none matches by name either.
      expect(evaluateFormula('=A1', sheets, 'nope'), '#REF!');
    });

    test('missing cell is empty (not an error)', () {
      expect(evaluateFormula('=SUM(Z9)', sheets, 's1'), '0');
    });
  });

  group('detectFormulaError', () {
    test('flags unbalanced parens and static /0', () {
      expect(detectFormulaError('=SUM(A1'), 'Unclosed Parentheses');
      expect(detectFormulaError('=SUM(A1))'), 'Mismatched Parentheses');
      expect(detectFormulaError('=A1/0'), 'Potential division by zero');
      expect(detectFormulaError('=SUM(A1:A3)'), isNull);
      expect(detectFormulaError('plain'), isNull);
    });
  });
}
