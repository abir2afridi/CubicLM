import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/cubicdata/controller.dart';
import 'package:cubiclm/services/cubicdata/models.dart';

/// Folder-tree integrity: nothing may dangle. A file or folder whose
/// parent is missing would vanish from the tree (neither root nor
/// listed anywhere), so every path must reparent to a valid node.
void main() {
  CubicDataController fresh() => CubicDataController();

  group('folder integrity', () {
    test('deleteFolder reparents child folders, not just files', () {
      final c = fresh();
      final parent = c.createFolder('Parent');
      final child = c.createFolder('Child', parentId: parent.id);
      final grandchild =
          c.createFolder('Grandchild', parentId: child.id);
      final file = c.createFile(WorkspaceType.spreadsheet, 'Sheet',
          folderId: child.id);

      c.deleteFolder(child.id);

      // Child subtree moves up one level instead of dangling.
      expect(
          c.folders
              .firstWhere((f) => f.id == grandchild.id)
              .parentId,
          parent.id);
      expect(c.byId(file.id)!.folderId, parent.id);
      // The deleted folder itself went to trash.
      expect(c.trash.any((t) => t.originalId == child.id), isTrue);
    });

    test('moveFile to an unknown folder falls back to root', () {
      final c = fresh();
      final file = c.createFile(WorkspaceType.spreadsheet, 'Sheet');
      c.moveFile(file.id, 'no-such-folder');
      expect(c.byId(file.id)!.folderId, isNull);
    });

    test('trash restore with missing parent falls back to root', () {
      final c = fresh();
      final file = c.createFile(WorkspaceType.spreadsheet, 'Sheet',
          folderId: 'ghost-parent');
      c.deleteFile(file.id);
      final trashId = c.trash.first.id;
      expect(c.restoreTrash(trashId), isTrue);
      final restored =
          c.files.firstWhere((f) => f.name == 'Sheet');
      expect(restored.folderId, isNull);
    });

    test('folderPath tolerates cycles and gaps', () {
      final c = fresh();
      final a = c.createFolder('A');
      final b = c.createFolder('B', parentId: a.id);
      expect(c.folderPath(b.id), 'A/B');
      expect(c.folderPath('missing'), '');
      expect(c.folderPath(null), 'Root');
    });
  });
}
