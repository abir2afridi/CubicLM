import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/cubicdata/controller.dart';
import 'package:cubiclm/services/cubicdata/models.dart';

/// The 8 SELECT CORE ARCHETYPE seeds must match the DataSheet web app:
/// Grid Spreadsheet, Document Memo Notes, Micro Spreadsheet,
/// Developer Script File, Bento Task Checker, Automated Prompt File,
/// Reference URL link, Multi Module Canvas.
void main() {
  group('new-file seeds (web parity)', () {
    test('grid spreadsheet seeds pivot sheet', () {
      final c = CubicDataController();
      final f = c.createFile(WorkspaceType.spreadsheet, 'Budget');
      expect(f.sheets!.first.name, 'Grid Workspace Pivot');
      expect(f.sheets!.first.cells['A1']!.value,
          'Initialized workspace: Budget');
      expect(f.tags, contains('quick'));
    });

    test('document memo seeds heading + hint', () {
      final c = CubicDataController();
      final f = c.createFile(WorkspaceType.document, 'Memo');
      expect(f.docBlocks!.length, 2);
      expect(f.docBlocks!.first.type, 'heading1');
      expect(f.docBlocks!.first.content, 'Memo');
      expect(f.docBlocks![1].content, contains('/'));
    });

    test('micro spreadsheet archetype is 20x8 with Start here', () {
      final c = CubicDataController();
      final f = c.createHybridWith('spreadsheet', 'Micro', folderId: null);
      final b = f.hybridBlocks!.single;
      expect(b.rows, 20);
      expect(b.cols, 8);
      expect(b.spreadsheetCells!['A1']!.value, 'Start here');
      expect(b.title, 'Micro');
    });

    test('other archetype seeds', () {
      final code = CubicDataController.buildHybridBlock('code', 'X',
          archetype: true);
      expect(code.codeLanguage, 'javascript');

      final check = CubicDataController.buildHybridBlock('checklist', 'X',
          archetype: true);
      expect(check.checklistItems!.single.text, 'First task');

      final prompt = CubicDataController.buildHybridBlock('prompt', 'X',
          archetype: true);
      expect(prompt.promptTemplate, 'Write your prompt here...');

      final ref = CubicDataController.buildHybridBlock('reference', 'X',
          archetype: true);
      expect(ref.referenceUrl, 'https://');

      final multi = CubicDataController.buildHybridBlock('multi', 'X',
          archetype: true);
      expect(multi.docContent, contains('Append'));
    });

    test('append-menu seeds differ (sample table)', () {
      final b =
          CubicDataController.buildHybridBlock('spreadsheet', 'Mini sheet');
      expect(b.rows, 5);
      expect(b.spreadsheetCells!['B4']!.value, '470');
    });
  });
}
