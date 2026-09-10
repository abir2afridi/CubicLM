import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/cubicdata/models.dart';
import 'package:cubiclm/services/cubicdata/search.dart';

void main() {
  group('fuzzyMatch', () {
    test('exact beats substring beats typo', () {
      expect(fuzzyMatch('budget', 'budget').score, 2.0);
      expect(fuzzyMatch('my budget sheet', 'budget').matches, isTrue);
      expect(fuzzyMatch('budjet', 'budget').matches, isTrue);
      expect(fuzzyMatch('zzz', 'budget').matches, isFalse);
    });

    test('empty query matches everything', () {
      expect(fuzzyMatch('anything', '').matches, isTrue);
    });
  });

  group('searchWorkspace', () {
    final folders = [Folder(id: 'fo1', name: 'Work')];
    final files = [
      SmartFile(
        id: 'f1',
        name: 'Budget 2026',
        folderId: 'fo1',
        type: WorkspaceType.spreadsheet,
        tags: ['finance'],
        sheets: [
          SheetData(id: 'sh1', name: 'Sheet1', cells: {
            'A1': CellData(value: 'Rent'),
            'B1': CellData(formula: '=SUM(A1:A3)'),
          }),
        ],
      ),
      SmartFile(
        id: 'f2',
        name: 'Meeting notes',
        type: WorkspaceType.document,
        docBlocks: [
          DocumentBlock(id: 'b1', type: 'paragraph', content: 'Rent review on Friday'),
        ],
      ),
    ];

    test('title matches rank first', () {
      final res = searchWorkspace('budget', files, folders);
      expect(res, isNotEmpty);
      expect(res.first.matchType, 'title');
      expect(res.first.path, 'Work');
    });

    test('tags, cells, formulas and docs are found', () {
      expect(
          searchWorkspace('finance', files, folders)
              .any((r) => r.matchType == 'tag'),
          isTrue);
      expect(
          searchWorkspace('rent', files, folders)
              .any((r) => r.targetAddress == 'A1'),
          isTrue);
      expect(
          searchWorkspace('sum', files, folders)
              .any((r) => r.matchType == 'formula'),
          isTrue);
      expect(
          searchWorkspace('friday', files, folders).length, 1);
    });

    test('empty query and cap', () {
      expect(searchWorkspace('', files, folders), isEmpty);
      expect(searchWorkspace('e', files, folders).length,
          lessThanOrEqualTo(15));
    });
  });

  group('model round-trip', () {
    test('SmartFile with locked styled cell survives JSON', () {
      final file = SmartFile(
        id: 'f1',
        name: 'Sheet',
        type: WorkspaceType.spreadsheet,
        tags: ['a'],
        sheets: [
          SheetData(id: 'sh1', name: 'S1', cells: {
            'A1': CellData(
              value: '10',
              formula: '=A2*2',
              style: const CellStyle(bold: true, align: 'center'),
              lockLevel: LockLevel.vault,
              lockPassword: 'pw',
              history: const [
                CellHistoryEntry(
                    timestamp: 1,
                    user: 'u',
                    oldValue: '',
                    newValue: '10'),
              ],
            ),
          }),
        ],
        activeSheetId: 'sh1',
      );
      final back = SmartFile.fromJson(file.toJson());
      expect(back.name, 'Sheet');
      expect(back.sheets!.first.cells['A1']!.lockLevel, LockLevel.vault);
      expect(back.sheets!.first.cells['A1']!.style!.bold, isTrue);
      expect(back.sheets!.first.cells['A1']!.history!.length, 1);
      expect(back.activeSheetId, 'sh1');
    });
  });
}
