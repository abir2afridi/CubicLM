/// CubicDataSheet data models — faithful port of the DataSheet web
/// project's types (cells, sheets, docs, hybrid blocks, files, folders,
/// trash, activity). Database/auth/sharing concepts are excluded on
/// purpose: everything persists as JSON in device storage.
/// All models round-trip through JSON for the vault file.
library;

/// Cell lock strictness (mirrors the web LockLevel).
enum LockLevel {
  none,
  soft, // single-click unlock
  protected, // yes/no confirmation dialog
  vault, // password confirmation
  permanent, // explicit recovery phrase required
}

LockLevel lockLevelFromInt(int v) {
  if (v < 0 || v >= LockLevel.values.length) return LockLevel.none;
  return LockLevel.values[v];
}

enum WorkspaceType { spreadsheet, document, hybrid }

WorkspaceType workspaceTypeFromString(String s) {
  switch (s) {
    case 'document':
      return WorkspaceType.document;
    case 'hybrid':
      return WorkspaceType.hybrid;
    default:
      return WorkspaceType.spreadsheet;
  }
}

String workspaceTypeToString(WorkspaceType t) {
  switch (t) {
    case WorkspaceType.document:
      return 'document';
    case WorkspaceType.hybrid:
      return 'hybrid';
    case WorkspaceType.spreadsheet:
      return 'spreadsheet';
  }
}

class CellStyle {
  final bool bold;
  final bool italic;
  final bool underline;
  final String? color;
  final String? bg;
  final String align; // left | center | right
  final double? fontSize;

  const CellStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.color,
    this.bg,
    this.align = 'left',
    this.fontSize,
  });

  bool get isEmpty =>
      !bold &&
      !italic &&
      !underline &&
      color == null &&
      bg == null &&
      align == 'left' &&
      fontSize == null;

  Map<String, dynamic> toJson() => {
        if (bold) 'bold': true,
        if (italic) 'italic': true,
        if (underline) 'underline': true,
        if (color != null) 'color': color,
        if (bg != null) 'bg': bg,
        if (align != 'left') 'align': align,
        if (fontSize != null) 'fontSize': fontSize,
      };

  factory CellStyle.fromJson(Map<String, dynamic> j) => CellStyle(
        bold: j['bold'] == true,
        italic: j['italic'] == true,
        underline: j['underline'] == true,
        color: j['color'] as String?,
        bg: j['bg'] as String?,
        align: (j['align'] as String?) ?? 'left',
        fontSize: (j['fontSize'] as num?)?.toDouble(),
      );
}

class CellComment {
  final String id;
  final String author;
  final String text;
  final int timestamp;

  const CellComment({
    required this.id,
    required this.author,
    required this.text,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'author': author,
        'text': text,
        'timestamp': timestamp,
      };

  factory CellComment.fromJson(Map<String, dynamic> j) => CellComment(
        id: '${j['id'] ?? ''}',
        author: '${j['author'] ?? ''}',
        text: '${j['text'] ?? ''}',
        timestamp: (j['timestamp'] as num? ?? 0).toInt(),
      );
}

class CellHistoryEntry {
  final int timestamp;
  final String user;
  final String oldValue;
  final String newValue;
  final String? oldFormula;
  final String? newFormula;

  const CellHistoryEntry({
    required this.timestamp,
    required this.user,
    required this.oldValue,
    required this.newValue,
    this.oldFormula,
    this.newFormula,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'user': user,
        'oldValue': oldValue,
        'newValue': newValue,
        if (oldFormula != null) 'oldFormula': oldFormula,
        if (newFormula != null) 'newFormula': newFormula,
      };

  factory CellHistoryEntry.fromJson(Map<String, dynamic> j) =>
      CellHistoryEntry(
        timestamp: (j['timestamp'] as num? ?? 0).toInt(),
        user: '${j['user'] ?? ''}',
        oldValue: '${j['oldValue'] ?? ''}',
        newValue: '${j['newValue'] ?? ''}',
        oldFormula: j['oldFormula'] as String?,
        newFormula: j['newFormula'] as String?,
      );
}

class CellData {
  String value;
  String? formula;
  CellStyle? style;
  LockLevel lockLevel;
  String? lockPassword;
  List<String>? dropdownOptions;
  bool isCheckbox;
  bool isChecked;
  String? note;
  List<CellComment>? comments;
  List<CellHistoryEntry>? history;

  CellData({
    this.value = '',
    this.formula,
    this.style,
    this.lockLevel = LockLevel.none,
    this.lockPassword,
    this.dropdownOptions,
    this.isCheckbox = false,
    this.isChecked = false,
    this.note,
    this.comments,
    this.history,
  });

  bool get locked => lockLevel != LockLevel.none;

  Map<String, dynamic> toJson() => {
        'value': value,
        if (formula != null) 'formula': formula,
        if (style != null && !style!.isEmpty) 'style': style!.toJson(),
        'lockLevel': lockLevel.index,
        if (lockPassword != null) 'lockPassword': lockPassword,
        if (dropdownOptions != null) 'dropdownOptions': dropdownOptions,
        if (isCheckbox) 'isCheckbox': true,
        if (isChecked) 'isChecked': true,
        if (note != null) 'note': note,
        if (comments != null)
          'comments': comments!.map((c) => c.toJson()).toList(),
        if (history != null)
          'history': history!.map((h) => h.toJson()).toList(),
      };

  factory CellData.fromJson(Map<String, dynamic> j) => CellData(
        value: '${j['value'] ?? ''}',
        formula: j['formula'] as String?,
        style: j['style'] is Map
            ? CellStyle.fromJson(Map<String, dynamic>.from(j['style']))
            : null,
        lockLevel: lockLevelFromInt((j['lockLevel'] as num? ?? 0).toInt()),
        lockPassword: j['lockPassword'] as String?,
        dropdownOptions: j['dropdownOptions'] is List
            ? (j['dropdownOptions'] as List).map((e) => '$e').toList()
            : null,
        isCheckbox: j['isCheckbox'] == true,
        isChecked: j['isChecked'] == true,
        note: j['note'] as String?,
        comments: j['comments'] is List
            ? (j['comments'] as List)
                .whereType<Map>()
                .map((e) =>
                    CellComment.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : null,
        history: j['history'] is List
            ? (j['history'] as List)
                .whereType<Map>()
                .map((e) => CellHistoryEntry.fromJson(
                    Map<String, dynamic>.from(e)))
                .toList()
            : null,
      );
}

class SheetData {
  final String id;
  String name;
  int rows;
  int cols;
  Map<String, CellData> cells;
  int frozenRows;
  int frozenCols;

  SheetData({
    required this.id,
    required this.name,
    this.rows = 40,
    this.cols = 16,
    Map<String, CellData>? cells,
    this.frozenRows = 0,
    this.frozenCols = 0,
  }) : cells = cells ?? {};

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'rows': rows,
        'cols': cols,
        'cells': cells.map((k, v) => MapEntry(k, v.toJson())),
        'frozenRows': frozenRows,
        'frozenCols': frozenCols,
      };

  factory SheetData.fromJson(Map<String, dynamic> j) {
    final cells = <String, CellData>{};
    final raw = j['cells'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is Map) {
          cells['$k'] = CellData.fromJson(Map<String, dynamic>.from(v));
        }
      });
    }
    return SheetData(
      id: '${j['id'] ?? ''}',
      name: '${j['name'] ?? 'Sheet'}',
      rows: (j['rows'] as num? ?? 40).toInt(),
      cols: (j['cols'] as num? ?? 16).toInt(),
      cells: cells,
      frozenRows: (j['frozenRows'] as num? ?? 0).toInt(),
      frozenCols: (j['frozenCols'] as num? ?? 0).toInt(),
    );
  }
}

class DocumentBlock {
  final String id;
  String type; // heading1 | heading2 | paragraph | bullet_list_item |
  // numbered_list_item | checklist_item | code_block | quote | callout
  String content;
  bool checked;
  String? language;

  DocumentBlock({
    required this.id,
    required this.type,
    this.content = '',
    this.checked = false,
    this.language,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'content': content,
        if (checked) 'checked': true,
        if (language != null) 'language': language,
      };

  factory DocumentBlock.fromJson(Map<String, dynamic> j) => DocumentBlock(
        id: '${j['id'] ?? ''}',
        type: '${j['type'] ?? 'paragraph'}',
        content: '${j['content'] ?? ''}',
        checked: j['checked'] == true,
        language: j['language'] as String?,
      );
}

class HybridChecklistItem {
  final String id;
  String text;
  bool done;

  HybridChecklistItem({required this.id, this.text = '', this.done = false});

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'done': done};

  factory HybridChecklistItem.fromJson(Map<String, dynamic> j) =>
      HybridChecklistItem(
        id: '${j['id'] ?? ''}',
        text: '${j['text'] ?? ''}',
        done: j['done'] == true,
      );
}

class HybridDescriptionTab {
  final String id;
  String title;
  String content;

  HybridDescriptionTab({required this.id, this.title = '', this.content = ''});

  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'content': content};

  factory HybridDescriptionTab.fromJson(Map<String, dynamic> j) =>
      HybridDescriptionTab(
        id: '${j['id'] ?? ''}',
        title: '${j['title'] ?? ''}',
        content: '${j['content'] ?? ''}',
      );
}

class HybridBlock {
  final String id;
  String type; // spreadsheet | document | code | checklist | prompt |
  // reference | multi
  String title;
  bool locked;
  int? rows;
  int? cols;
  Map<String, CellData>? spreadsheetCells;
  String? docContent;
  String? codeLanguage;
  List<HybridChecklistItem>? checklistItems;
  String? promptTemplate;
  String? referenceUrl;
  List<HybridDescriptionTab>? descriptionTabs;

  HybridBlock({
    required this.id,
    required this.type,
    this.title = '',
    this.locked = false,
    this.rows,
    this.cols,
    this.spreadsheetCells,
    this.docContent,
    this.codeLanguage,
    this.checklistItems,
    this.promptTemplate,
    this.referenceUrl,
    this.descriptionTabs,
  });

  Map<String, dynamic> toJson() {
    final cells = <String, dynamic>{};
    spreadsheetCells?.forEach((k, v) => cells[k] = v.toJson());
    return {
      'id': id,
      'type': type,
      'title': title,
      if (locked) 'locked': true,
      if (rows != null) 'rows': rows,
      if (cols != null) 'cols': cols,
      if (spreadsheetCells != null) 'spreadsheetCells': cells,
      if (docContent != null) 'docContent': docContent,
      if (codeLanguage != null) 'codeLanguage': codeLanguage,
      if (checklistItems != null)
        'checklistItems': checklistItems!.map((e) => e.toJson()).toList(),
      if (promptTemplate != null) 'promptTemplate': promptTemplate,
      if (referenceUrl != null) 'referenceUrl': referenceUrl,
      if (descriptionTabs != null)
        'descriptionTabs': descriptionTabs!.map((e) => e.toJson()).toList(),
    };
  }

  factory HybridBlock.fromJson(Map<String, dynamic> j) {
    Map<String, CellData>? cells;
    if (j['spreadsheetCells'] is Map) {
      cells = {};
      (j['spreadsheetCells'] as Map).forEach((k, v) {
        if (v is Map) {
          cells!['$k'] = CellData.fromJson(Map<String, dynamic>.from(v));
        }
      });
    }
    // Web shape nests rows/cols/cells under spreadsheetData.
    final sd = j['spreadsheetData'];
    if (sd is Map) {
      cells ??= {};
      final raw = sd['cells'];
      if (raw is Map) {
        raw.forEach((k, v) {
          if (v is Map) {
            cells!['$k'] = CellData.fromJson(Map<String, dynamic>.from(v));
          }
        });
      }
    }
    List<HybridChecklistItem>? items;
    if (j['checklistItems'] is List) {
      items = (j['checklistItems'] as List)
          .whereType<Map>()
          .map((e) =>
              HybridChecklistItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    List<HybridDescriptionTab>? tabs;
    if (j['descriptionTabs'] is List) {
      tabs = (j['descriptionTabs'] as List)
          .whereType<Map>()
          .map((e) =>
              HybridDescriptionTab.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return HybridBlock(
      id: '${j['id'] ?? ''}',
      type: '${j['type'] ?? 'document'}',
      title: '${j['title'] ?? ''}',
      locked: j['locked'] == true,
      rows: (j['rows'] as num?)?.toInt() ?? (sd is Map ? (sd['rows'] as num?)?.toInt() : null),
      cols: (j['cols'] as num?)?.toInt() ?? (sd is Map ? (sd['cols'] as num?)?.toInt() : null),
      spreadsheetCells: cells,
      docContent: j['docContent'] as String?,
      codeLanguage: j['codeLanguage'] as String?,
      checklistItems: items,
      promptTemplate: j['promptTemplate'] as String?,
      referenceUrl: j['referenceUrl'] as String?,
      descriptionTabs: tabs,
    );
  }
}

class Folder {
  final String id;
  String name;
  String? parentId;
  String? color;
  String? icon;
  bool isPinned;
  bool isFavorite;
  bool isArchived;

  Folder({
    required this.id,
    required this.name,
    this.parentId,
    this.color,
    this.icon,
    this.isPinned = false,
    this.isFavorite = false,
    this.isArchived = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (parentId != null) 'parentId': parentId,
        if (color != null) 'color': color,
        if (icon != null) 'icon': icon,
        if (isPinned) 'isPinned': true,
        if (isFavorite) 'isFavorite': true,
        if (isArchived) 'isArchived': true,
      };

  factory Folder.fromJson(Map<String, dynamic> j) => Folder(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? 'Folder'}',
        parentId: j['parentId'] as String?,
        color: j['color'] as String?,
        icon: j['icon'] as String?,
        isPinned: j['isPinned'] == true,
        isFavorite: j['isFavorite'] == true,
        isArchived: j['isArchived'] == true,
      );
}

class SmartFile {
  final String id;
  String name;
  String? folderId;
  WorkspaceType type;
  List<String> tags;
  int createdAt;
  int updatedAt;
  bool isFavorite;
  bool isPinned;
  bool isLocked;
  List<SheetData>? sheets;
  String? activeSheetId;
  List<DocumentBlock>? docBlocks;
  List<HybridBlock>? hybridBlocks;

  SmartFile({
    required this.id,
    required this.name,
    this.folderId,
    required this.type,
    List<String>? tags,
    int? createdAt,
    int? updatedAt,
    this.isFavorite = false,
    this.isPinned = false,
    this.isLocked = false,
    this.sheets,
    this.activeSheetId,
    this.docBlocks,
    this.hybridBlocks,
  })  : tags = tags ?? [],
        createdAt = createdAt ??
            DateTime.now().millisecondsSinceEpoch,
        updatedAt =
            updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  void touch() => updatedAt = DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (folderId != null) 'folderId': folderId,
        'type': workspaceTypeToString(type),
        'tags': tags,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        if (isFavorite) 'isFavorite': true,
        if (isPinned) 'isPinned': true,
        if (isLocked) 'isLocked': true,
        if (sheets != null)
          'sheets': sheets!.map((s) => s.toJson()).toList(),
        if (activeSheetId != null) 'activeSheetId': activeSheetId,
        if (docBlocks != null)
          'docBlocks': docBlocks!.map((b) => b.toJson()).toList(),
        if (hybridBlocks != null)
          'hybridBlocks': hybridBlocks!.map((b) => b.toJson()).toList(),
      };

  factory SmartFile.fromJson(Map<String, dynamic> j) {
    List<SheetData>? sheets;
    if (j['sheets'] is List) {
      sheets = (j['sheets'] as List)
          .whereType<Map>()
          .map((e) => SheetData.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    List<DocumentBlock>? docs;
    if (j['docBlocks'] is List) {
      docs = (j['docBlocks'] as List)
          .whereType<Map>()
          .map((e) => DocumentBlock.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    List<HybridBlock>? hybrid;
    if (j['hybridBlocks'] is List) {
      hybrid = (j['hybridBlocks'] as List)
          .whereType<Map>()
          .map((e) => HybridBlock.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return SmartFile(
      id: '${j['id'] ?? ''}',
      name: '${j['name'] ?? 'Untitled'}',
      folderId: j['folderId'] as String?,
      type: workspaceTypeFromString('${j['type'] ?? 'spreadsheet'}'),
      tags: j['tags'] is List
          ? (j['tags'] as List).map((e) => '$e').toList()
          : [],
      createdAt: (j['createdAt'] as num? ??
              DateTime.now().millisecondsSinceEpoch)
          .toInt(),
      updatedAt: (j['updatedAt'] as num? ??
              DateTime.now().millisecondsSinceEpoch)
          .toInt(),
      isFavorite: j['isFavorite'] == true,
      isPinned: j['isPinned'] == true,
      isLocked: j['isLocked'] == true,
      sheets: sheets,
      activeSheetId: j['activeSheetId'] as String?,
      docBlocks: docs,
      hybridBlocks: hybrid,
    );
  }
}

class TrashItem {
  final String id;
  final String originalId;
  final String name;
  final String type; // file | folder
  final int deletedAt;
  final String? originalParentId;
  final Map<String, dynamic> payload;

  TrashItem({
    required this.id,
    required this.originalId,
    required this.name,
    required this.type,
    required this.deletedAt,
    this.originalParentId,
    required this.payload,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'originalId': originalId,
        'name': name,
        'type': type,
        'deletedAt': deletedAt,
        if (originalParentId != null) 'originalParentId': originalParentId,
        'payload': payload,
      };

  factory TrashItem.fromJson(Map<String, dynamic> j) => TrashItem(
        id: '${j['id'] ?? ''}',
        originalId: '${j['originalId'] ?? ''}',
        name: '${j['name'] ?? ''}',
        type: '${j['type'] ?? 'file'}',
        deletedAt: (j['deletedAt'] as num? ?? 0).toInt(),
        originalParentId: j['originalParentId'] as String?,
        payload: j['payload'] is Map
            ? Map<String, dynamic>.from(j['payload'])
            : {},
      );
}

class ActivityEntry {
  final String id;
  final int timestamp;
  final String? fileId;
  final String? fileName;
  final String type; // edit | delete | lock | unlock | paste | copy | restore
  final String details;

  ActivityEntry({
    required this.id,
    required this.timestamp,
    this.fileId,
    this.fileName,
    required this.type,
    required this.details,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp,
        if (fileId != null) 'fileId': fileId,
        if (fileName != null) 'fileName': fileName,
        'type': type,
        'details': details,
      };

  factory ActivityEntry.fromJson(Map<String, dynamic> j) => ActivityEntry(
        id: '${j['id'] ?? ''}',
        timestamp: (j['timestamp'] as num? ?? 0).toInt(),
        fileId: j['fileId'] as String?,
        fileName: j['fileName'] as String?,
        type: '${j['type'] ?? 'edit'}',
        details: '${j['details'] ?? ''}',
      );
}
