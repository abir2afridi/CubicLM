/// CubicDataSheet state owner: folders, files, trash, activity trail and
/// clipboard cache. Everything persists (2s debounced) into ONE vault
/// JSON file in public storage, so data survives app uninstall.
/// No database, no auth, no sharing — personal on-device space.
library;

import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'vault_store.dart';

class ClipboardEntry {
  final String id;
  final int timestamp;
  final String content;
  final String type;
  final String? cellAddress;
  final String? fileName;

  ClipboardEntry({
    required this.id,
    required this.timestamp,
    required this.content,
    required this.type,
    this.cellAddress,
    this.fileName,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp,
        'content': content,
        'type': type,
        if (cellAddress != null) 'cellAddress': cellAddress,
        if (fileName != null) 'fileName': fileName,
      };

  factory ClipboardEntry.fromJson(Map<String, dynamic> j) => ClipboardEntry(
        id: '${j['id'] ?? ''}',
        timestamp: (j['timestamp'] as num? ?? 0).toInt(),
        content: '${j['content'] ?? ''}',
        type: '${j['type'] ?? 'Plain Text'}',
        cellAddress: j['cellAddress'] as String?,
        fileName: j['fileName'] as String?,
      );
}

class CubicDataController extends GetxController {
  static const _uuid = Uuid();
  static String newId(String prefix) =>
      '$prefix${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${_uuid.v4().substring(0, 4)}';

  final folders = <Folder>[].obs;
  final files = <SmartFile>[].obs;
  final trash = <TrashItem>[].obs;
  final activity = <ActivityEntry>[].obs;
  final clipboard = <ClipboardEntry>[].obs;
  final loaded = false.obs;
  final saving = false.obs;
  final lastSavedAt = Rxn<DateTime>();
  final vaultPath = ''.obs;

  Timer? _saveTimer;
  bool _savingNow = false;

  @override
  void onInit() {
    super.onInit();
    unawaited(load());
  }

  @override
  void onClose() {
    _saveTimer?.cancel();
    super.onClose();
  }

  Future<void> load() async {
    try {
      final raw = await CubicVaultStore.load();
      if (raw != null) {
        _readVault(raw);
      }
    } catch (_) {}
    loaded.value = true;
  }

  void _readVault(Map<String, dynamic> raw) {
    try {
      if (raw['folders'] is List) {
        folders.assignAll((raw['folders'] as List)
            .whereType<Map>()
            .map((e) => Folder.fromJson(Map<String, dynamic>.from(e))));
      }
      if (raw['files'] is List) {
        files.assignAll((raw['files'] as List)
            .whereType<Map>()
            .map((e) => SmartFile.fromJson(Map<String, dynamic>.from(e))));
      }
      if (raw['trash'] is List) {
        trash.assignAll((raw['trash'] as List)
            .whereType<Map>()
            .map((e) => TrashItem.fromJson(Map<String, dynamic>.from(e))));
      }
      if (raw['activity'] is List) {
        activity.assignAll((raw['activity'] as List)
            .whereType<Map>()
            .map((e) => ActivityEntry.fromJson(Map<String, dynamic>.from(e))));
      }
      if (raw['clipboard'] is List) {
        clipboard.assignAll((raw['clipboard'] as List)
            .whereType<Map>()
            .map((e) => ClipboardEntry.fromJson(Map<String, dynamic>.from(e))));
      }
    } catch (_) {}
  }

  Map<String, dynamic> _writeVault() => {
        'version': 1,
        'app': 'CubicDataSheet',
        'folders': folders.map((f) => f.toJson()).toList(),
        'files': files.map((f) => f.toJson()).toList(),
        'trash': trash.map((t) => t.toJson()).toList(),
        'activity': activity.take(100).map((a) => a.toJson()).toList(),
        'clipboard': clipboard.take(20).map((c) => c.toJson()).toList(),
      };

  /// Debounced persist (2s, like the web autosave). Call after any mutation.
  void scheduleSave() {
    if (!loaded.value) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () async {
      if (_savingNow) {
        scheduleSave();
        return;
      }
      _savingNow = true;
      saving.value = true;
      try {
        final ok = await CubicVaultStore.save(_writeVault());
        if (ok) lastSavedAt.value = DateTime.now();
      } catch (_) {
      } finally {
        _savingNow = false;
        saving.value = false;
      }
    });
  }

  Future<bool> saveNow() async {
    _saveTimer?.cancel();
    try {
      final ok = await CubicVaultStore.save(_writeVault());
      if (ok) lastSavedAt.value = DateTime.now();
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Raw vault JSON string for manual backup export.
  String vaultJsonString() {
    try {
      return const JsonEncoder.withIndent('  ').convert(_writeVault());
    } catch (_) {
      return '{}';
    }
  }

  void log(String type, String details, {String? fileId, String? fileName}) {
    activity.insert(
      0,
      ActivityEntry(
        id: newId('log_'),
        timestamp: DateTime.now().millisecondsSinceEpoch,
        fileId: fileId,
        fileName: fileName,
        type: type,
        details: details,
      ),
    );
    if (activity.length > 100) activity.removeRange(100, activity.length);
    scheduleSave();
  }

  void pushClipboard({
    required String content,
    required String type,
    String? cellAddress,
    String? fileName,
  }) {
    clipboard.insert(
      0,
      ClipboardEntry(
        id: newId('cp_'),
        timestamp: DateTime.now().millisecondsSinceEpoch,
        content: content,
        type: type,
        cellAddress: cellAddress,
        fileName: fileName,
      ),
    );
    if (clipboard.length > 20) {
      clipboard.removeRange(20, clipboard.length);
    }
    scheduleSave();
  }

  // ── Files ──

  SmartFile createFile(WorkspaceType type, String name, {String? folderId}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final file = SmartFile(
      id: newId('f_'),
      name: name.trim().isEmpty ? 'Untitled' : name.trim(),
      folderId: folderId,
      type: type,
      createdAt: now,
      updatedAt: now,
    );
    switch (type) {
      case WorkspaceType.spreadsheet:
        final sheet = SheetData(id: newId('sh_'), name: 'Sheet1');
        file.sheets = [sheet];
        file.activeSheetId = sheet.id;
        break;
      case WorkspaceType.document:
        file.docBlocks = [
          DocumentBlock(id: newId('blk_'), type: 'paragraph')
        ];
        break;
      case WorkspaceType.hybrid:
        file.hybridBlocks = [];
        break;
    }
    files.insert(0, file);
    log('edit', 'Created ${file.name}', fileId: file.id, fileName: file.name);
    scheduleSave();
    return file;
  }

  SmartFile? byId(String id) {
    for (final f in files) {
      if (f.id == id) return f;
    }
    return null;
  }

  void renameFile(String id, String name) {
    final f = byId(id);
    if (f == null || name.trim().isEmpty) return;
    f.name = name.trim();
    f.touch();
    files.refresh();
    scheduleSave();
  }

  void toggleFavorite(String id) {
    final f = byId(id);
    if (f == null) return;
    f.isFavorite = !f.isFavorite;
    f.touch();
    files.refresh();
    scheduleSave();
  }

  void togglePin(String id) {
    final f = byId(id);
    if (f == null) return;
    f.isPinned = !f.isPinned;
    f.touch();
    files.refresh();
    scheduleSave();
  }

  void setTags(String id, List<String> tags) {
    final f = byId(id);
    if (f == null) return;
    f.tags = tags.map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
    f.touch();
    files.refresh();
    scheduleSave();
  }

  void moveFile(String id, String? folderId) {
    final f = byId(id);
    if (f == null) return;
    f.folderId = folderId;
    f.touch();
    files.refresh();
    scheduleSave();
  }

  /// Persist one file's content after an edit (marks touched + saves).
  void saveFile(SmartFile file, {String detail = 'Edited'}) {
    file.touch();
    files.refresh();
    log('edit', '$detail: ${file.name}', fileId: file.id, fileName: file.name);
    scheduleSave();
  }

  void deleteFile(String id) {
    final idx = files.indexWhere((f) => f.id == id);
    if (idx < 0) return;
    final f = files.removeAt(idx);
    trash.insert(
      0,
      TrashItem(
        id: newId('tr_'),
        originalId: f.id,
        name: f.name,
        type: 'file',
        deletedAt: DateTime.now().millisecondsSinceEpoch,
        originalParentId: f.folderId,
        payload: f.toJson(),
      ),
    );
    log('delete', 'Deleted ${f.name}', fileId: f.id, fileName: f.name);
    scheduleSave();
  }

  bool restoreTrash(String trashId) {
    final idx = trash.indexWhere((t) => t.id == trashId);
    if (idx < 0) return false;
    final item = trash.removeAt(idx);
    try {
      if (item.type == 'file') {
        final f =
            SmartFile.fromJson(Map<String, dynamic>.from(item.payload));
        // New id avoids collisions; keep the name.
        final restored = SmartFile(
          id: newId('f_'),
          name: f.name,
          folderId: item.originalParentId,
          type: f.type,
          tags: f.tags,
          isFavorite: f.isFavorite,
          isPinned: f.isPinned,
          sheets: f.sheets,
          activeSheetId: f.activeSheetId,
          docBlocks: f.docBlocks,
          hybridBlocks: f.hybridBlocks,
        );
        files.insert(0, restored);
      } else {
        final folder =
            Folder.fromJson(Map<String, dynamic>.from(item.payload));
        folders.insert(
          0,
          Folder(
            id: newId('fo_'),
            name: folder.name,
            parentId: item.originalParentId,
            color: folder.color,
            icon: folder.icon,
          ),
        );
      }
    } catch (_) {
      return false;
    }
    log('restore', 'Restored ${item.name}');
    scheduleSave();
    return true;
  }

  void purgeTrashItem(String trashId) {
    trash.removeWhere((t) => t.id == trashId);
    scheduleSave();
  }

  void purgeTrash() {
    if (trash.isEmpty) return;
    trash.clear();
    log('delete', 'Emptied trash');
    scheduleSave();
  }

  // ── Folders ──

  Folder createFolder(String name, {String? parentId}) {
    final folder = Folder(
      id: newId('fo_'),
      name: name.trim().isEmpty ? 'Folder' : name.trim(),
      parentId: parentId,
    );
    folders.insert(0, folder);
    scheduleSave();
    return folder;
  }

  void renameFolder(String id, String name) {
    for (final f in folders) {
      if (f.id == id && name.trim().isNotEmpty) {
        f.name = name.trim();
        break;
      }
    }
    folders.refresh();
    scheduleSave();
  }

  void deleteFolder(String id) {
    final idx = folders.indexWhere((f) => f.id == id);
    if (idx < 0) return;
    final folder = folders.removeAt(idx);
    // Files inside move back to root so nothing is lost silently.
    for (final f in files) {
      if (f.folderId == id) f.folderId = folder.parentId;
    }
    trash.insert(
      0,
      TrashItem(
        id: newId('tr_'),
        originalId: folder.id,
        name: folder.name,
        type: 'folder',
        deletedAt: DateTime.now().millisecondsSinceEpoch,
        originalParentId: folder.parentId,
        payload: folder.toJson(),
      ),
    );
    files.refresh();
    scheduleSave();
  }

  List<Folder> childFolders(String? parentId) =>
      folders.where((f) => f.parentId == parentId).toList();

  List<SmartFile> filesIn(String? folderId) =>
      files.where((f) => f.folderId == folderId).toList();

  String folderPath(String? folderId) {
    if (folderId == null) return 'Root';
    final byId = {for (final f in folders) f.id: f};
    final segs = <String>[];
    String? cur = folderId;
    var guard = 0;
    while (cur != null && guard < 10) {
      final f = byId[cur];
      if (f == null) break;
      segs.insert(0, f.name);
      cur = f.parentId;
      guard++;
    }
    return segs.join('/');
  }
}
