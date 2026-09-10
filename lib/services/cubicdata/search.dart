/// CubicDataSheet workspace search — faithful port of the DataSheet
/// web `utils/search.ts`. Fuzzy match (exact/substring/typo/token) plus
/// a weighted coordinator over file names, tags, cells, formulas, notes,
/// doc blocks and hybrid blocks. Pure Dart, no I/O.
library;

import 'models.dart';

int levenshteinDistance(String a, String b) {
  final tmp = List.generate(a.length + 1, (i) => List.filled(b.length + 1, 0));
  for (var i = 0; i <= a.length; i++) {
    tmp[i][0] = i;
  }
  for (var j = 1; j <= b.length; j++) {
    tmp[0][j] = j;
  }
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      tmp[i][j] = [
        tmp[i - 1][j] + 1,
        tmp[i][j - 1] + 1,
        tmp[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
      ].reduce((x, y) => x < y ? x : y);
    }
  }
  return tmp[a.length][b.length];
}

class FuzzyHit {
  final bool matches;
  final double score;
  const FuzzyHit(this.matches, this.score);
}

FuzzyHit fuzzyMatch(String target, String query) {
  final t = target.toLowerCase().trim();
  final q = query.toLowerCase().trim();
  if (q.isEmpty) return const FuzzyHit(true, 1.0);
  if (t.isEmpty) return const FuzzyHit(false, 0);
  if (t == q) return const FuzzyHit(true, 2.0);
  final index = t.indexOf(q);
  if (index != -1) {
    return FuzzyHit(true, 1.0 + (1.0 - index / t.length) * 0.5);
  }
  if (q.length >= 3) {
    final distance = levenshteinDistance(t, q);
    if (distance <= q.length ~/ 3) {
      return FuzzyHit(true, 0.8 - distance / q.length);
    }
  }
  final qTokens = q.split(RegExp(r'\s+'));
  final tTokens = t.split(RegExp(r'\s+'));
  var matchedTokens = 0;
  for (final qt in qTokens) {
    if (tTokens.any((tt) => tt.contains(qt))) matchedTokens++;
  }
  if (matchedTokens > 0 && matchedTokens == qTokens.length) {
    return const FuzzyHit(true, 0.9);
  }
  return const FuzzyHit(false, 0);
}

class SearchResult {
  final String fileId;
  final String fileName;
  final WorkspaceType fileType;
  final String path;
  final String matchType; // title | content | formula | tag | comment
  final String matchSnippet;
  final String? targetAddress;

  const SearchResult({
    required this.fileId,
    required this.fileName,
    required this.fileType,
    required this.path,
    required this.matchType,
    required this.matchSnippet,
    this.targetAddress,
  });
}

String folderPathOf(String? folderId, List<Folder> folders) {
  if (folderId == null || folderId.isEmpty) return 'Root';
  final segs = <String>[];
  String? currentId = folderId;
  var safeguard = 0;
  final byId = {for (final f in folders) f.id: f};
  while (currentId != null && currentId.isNotEmpty && safeguard < 10) {
    final folder = byId[currentId];
    if (folder == null) break;
    segs.insert(0, folder.name);
    currentId = folder.parentId;
    safeguard++;
  }
  return segs.join('/');
}

List<SearchResult> searchWorkspace(
  String query,
  List<SmartFile> files,
  List<Folder> folders,
) {
  if (query.isEmpty) return [];
  final scored = <({SearchResult result, double score})>[];

  for (final file in files) {
    final parentPath = folderPathOf(file.folderId, folders);

    final nameMatch = fuzzyMatch(file.name, query);
    if (nameMatch.matches) {
      scored.add((
        result: SearchResult(
          fileId: file.id,
          fileName: file.name,
          fileType: file.type,
          path: parentPath,
          matchType: 'title',
          matchSnippet:
              'File: ${file.name} (${workspaceTypeToString(file.type).toUpperCase()})',
        ),
        score: nameMatch.score * 3.0,
      ));
    }

    for (final tag in file.tags) {
      final tagMatch = fuzzyMatch(tag, query);
      if (tagMatch.matches) {
        scored.add((
          result: SearchResult(
            fileId: file.id,
            fileName: file.name,
            fileType: file.type,
            path: parentPath,
            matchType: 'tag',
            matchSnippet: 'Matched Tag: #$tag',
          ),
          score: tagMatch.score * 2.0,
        ));
      }
    }

    if (file.type == WorkspaceType.spreadsheet && file.sheets != null) {
      for (final sheet in file.sheets!) {
        sheet.cells.forEach((address, cell) {
          final cellValMatch = fuzzyMatch(cell.value, query);
          if (cellValMatch.matches && cell.value.isNotEmpty) {
            scored.add((
              result: SearchResult(
                fileId: file.id,
                fileName: file.name,
                fileType: file.type,
                path: '$parentPath > ${sheet.name}',
                matchType: 'content',
                matchSnippet:
                    'Cell [$address] value: "${cell.value}"${cell.lockLevel != LockLevel.none ? ' (LOCKED)' : ''}',
                targetAddress: address,
              ),
              score: cellValMatch.score * 1.5,
            ));
          }
          if (cell.formula != null && cell.formula!.isNotEmpty) {
            final formulaMatch = fuzzyMatch(cell.formula!, query);
            if (formulaMatch.matches) {
              scored.add((
                result: SearchResult(
                  fileId: file.id,
                  fileName: file.name,
                  fileType: file.type,
                  path: '$parentPath > ${sheet.name}',
                  matchType: 'formula',
                  matchSnippet:
                      'Cell [$address] formula: ${cell.formula}',
                  targetAddress: address,
                ),
                score: formulaMatch.score * 1.8,
              ));
            }
          }
          if (cell.note != null && cell.note!.isNotEmpty) {
            final noteMatch = fuzzyMatch(cell.note!, query);
            if (noteMatch.matches) {
              scored.add((
                result: SearchResult(
                  fileId: file.id,
                  fileName: file.name,
                  fileType: file.type,
                  path: '$parentPath > ${sheet.name}',
                  matchType: 'comment',
                  matchSnippet:
                      'Cell [$address] note: "${cell.note}"',
                  targetAddress: address,
                ),
                score: noteMatch.score * 1.2,
              ));
            }
          }
        });
      }
    }

    if (file.type == WorkspaceType.document && file.docBlocks != null) {
      for (final block in file.docBlocks!) {
        final blockMatch = fuzzyMatch(block.content, query);
        if (blockMatch.matches && block.content.isNotEmpty) {
          final snippet = block.content.length > 80
              ? '${block.content.substring(0, 80)}...'
              : block.content;
          scored.add((
            result: SearchResult(
              fileId: file.id,
              fileName: file.name,
              fileType: file.type,
              path: parentPath,
              matchType: 'content',
              matchSnippet: 'Doc fragment: "$snippet"',
            ),
            score: blockMatch.score * 1.4,
          ));
        }
      }
    }

    if (file.type == WorkspaceType.hybrid && file.hybridBlocks != null) {
      for (var idx = 0; idx < file.hybridBlocks!.length; idx++) {
        final block = file.hybridBlocks![idx];
        final titleMatch = fuzzyMatch(block.title, query);
        if (titleMatch.matches) {
          scored.add((
            result: SearchResult(
              fileId: file.id,
              fileName: file.name,
              fileType: file.type,
              path: parentPath,
              matchType: 'content',
              matchSnippet:
                  'Hybrid Block [${idx + 1}]: "${block.title}"',
            ),
            score: titleMatch.score * 1.3,
          ));
        }
        if (block.docContent != null && block.docContent!.isNotEmpty) {
          final contentMatch = fuzzyMatch(block.docContent!, query);
          if (contentMatch.matches) {
            final snippet = block.docContent!.length > 80
                ? block.docContent!.substring(0, 80)
                : block.docContent!;
            scored.add((
              result: SearchResult(
                fileId: file.id,
                fileName: file.name,
                fileType: file.type,
                path: parentPath,
                matchType: 'content',
                matchSnippet: 'Hybrid snippet: "$snippet"',
              ),
              score: contentMatch.score * 1.1,
            ));
          }
        }
      }
    }
  }

  scored.sort((a, b) => b.score.compareTo(a.score));
  final seen = <String>{};
  final out = <SearchResult>[];
  for (final s in scored) {
    final key =
        '${s.result.fileId}|${s.result.matchSnippet}|${s.result.targetAddress}';
    if (seen.add(key)) out.add(s.result);
    if (out.length >= 15) break;
  }
  return out;
}
