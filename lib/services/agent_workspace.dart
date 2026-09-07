import 'dart:io';

import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import 'hive_service.dart';

/// Agent-IDE project workspace (MVP: local-first).
///
/// - Metadata lives in Hive settings JSON (`agent_projects`): no new box.
/// - Files live under app documents `agent_projects/<id>/` (OS-sandboxed).
/// - Every path is jailed: absolute, `..`, and oversized writes rejected.
/// - Caps mirror the web-builder parser (30 files / 200KB / 5MB).
class AgentProject {
  final String id;
  String name;
  String framework;
  int updatedMs;

  AgentProject({
    required this.id,
    required this.name,
    required this.framework,
    required this.updatedMs,
  });

  factory AgentProject.fromMap(Map m) => AgentProject(
        id: (m['id'] ?? '').toString(),
        name: (m['name'] ?? 'Untitled').toString(),
        framework: (m['framework'] ?? 'Single HTML').toString(),
        updatedMs: (m['updatedMs'] is int)
            ? m['updatedMs'] as int
            : int.tryParse(m['updatedMs'].toString()) ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'framework': framework,
        'updatedMs': updatedMs,
      };
}

/// A snapshot of project files at a point in time.
class ProjectCheckpoint {
  final String id;
  final String label;
  final int timestampMs;
  final int fileCount;

  ProjectCheckpoint({
    required this.id,
    required this.label,
    required this.timestampMs,
    required this.fileCount,
  });

  factory ProjectCheckpoint.fromMap(Map m) => ProjectCheckpoint(
        id: (m['id'] ?? '').toString(),
        label: (m['label'] ?? '').toString(),
        timestampMs: m['timestampMs'] is int
            ? m['timestampMs'] as int
            : int.tryParse(m['timestampMs'].toString()) ?? 0,
        fileCount: m['fileCount'] is int
            ? m['fileCount'] as int
            : int.tryParse(m['fileCount'].toString()) ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'timestampMs': timestampMs,
        'fileCount': fileCount,
      };
}

class AgentWorkspaceService extends GetxService {
  static const _kProjects = 'agent_projects';
  static const maxFiles = 30;
  static const maxFileChars = 200000;
  static const maxTotalChars = 5000000;

  final projects = <AgentProject>[].obs;

  Future<Directory> get _root async {
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory('${docs.path}/agent_projects');
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  Future<AgentWorkspaceService> init() async {
    loadProjects();
    return this;
  }

  void loadProjects() {
    try {
      final raw = Get.find<HiveService>().getSetting<List>(_kProjects);
      final list = (raw ?? [])
          .whereType<Map>()
          .map(AgentProject.fromMap)
          .where((p) => p.id.isNotEmpty)
          .toList();
      list.sort((a, b) => b.updatedMs.compareTo(a.updatedMs));
      projects.assignAll(list);
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      await Get.find<HiveService>().setSetting(
          _kProjects, projects.map((p) => p.toMap()).toList());
    } catch (_) {}
  }

  /// Jail + normalize a project-relative path. '' = reject.
  static String sanitize(String raw) {
    var p = raw.trim().replaceAll('\\', '/');
    while (p.startsWith('/')) {
      p = p.substring(1);
    }
    final parts = <String>[];
    for (final seg in p.split('/')) {
      final s = seg.trim();
      if (s.isEmpty || s == '.' || s == '..') continue;
      parts.add(s);
    }
    if (parts.isEmpty) return '';
    final joined = parts.join('/');
    if (joined.length > 160) return '';
    return joined;
  }

  Future<Directory> dirFor(String projectId) async {
    final root = await _root;
    return Directory('${root.path}/$projectId');
  }

  Future<AgentProject> createProject(String name, String framework) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final p = AgentProject(
      id: id,
      name: name.trim().isEmpty ? 'Untitled project' : name.trim(),
      framework: framework,
      updatedMs: DateTime.now().millisecondsSinceEpoch,
    );
    await (await dirFor(id)).create(recursive: true);
    projects.insert(0, p);
    await _save();
    return p;
  }

  Future<void> touch(String projectId) async {
    final i = projects.indexWhere((p) => p.id == projectId);
    if (i < 0) return;
    projects[i].updatedMs = DateTime.now().millisecondsSinceEpoch;
    projects.sort((a, b) => b.updatedMs.compareTo(a.updatedMs));
    await _save();
  }

  Future<void> deleteProject(String projectId) async {
    projects.removeWhere((p) => p.id == projectId);
    await _save();
    try {
      final dir = await dirFor(projectId);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  Future<void> renameProject(String projectId, String name) async {
    final i = projects.indexWhere((p) => p.id == projectId);
    if (i < 0 || name.trim().isEmpty) return;
    projects[i].name = name.trim();
    await _save();
  }

  /// Write (create/overwrite) one file. Returns error string or null.
  Future<String?> writeFile(
      String projectId, String path, String content) async {
    final clean = sanitize(path);
    if (clean.isEmpty) return 'Rejected path.';
    if (content.length > maxFileChars) return 'File too large.';
    try {
      final dir = await dirFor(projectId);
      final files = await listFiles(projectId);
      var total = 0;
      for (final f in files) {
        if (f == clean) continue;
        total += await _fileLength(dir, f);
      }
      if (total + content.length > maxTotalChars) {
        return 'Project too large.';
      }
      final out = File('${dir.path}/$clean');
      await out.parent.create(recursive: true);
      // Atomic write: crash mid-write must never leave a truncated
      // file behind (same-dir rename is atomic on POSIX, near-atomic
      // on Windows with the delete fallback below).
      final tmp = File(
          '${out.path}.tmp-${DateTime.now().microsecondsSinceEpoch}');
      try {
        await tmp.writeAsString(content, flush: true);
        try {
          await tmp.rename(out.path);
        } catch (_) {
          try {
            if (await out.exists()) await out.delete();
          } catch (_) {}
          await tmp.rename(out.path);
        }
      } finally {
        try {
          if (await tmp.exists()) await tmp.delete();
        } catch (_) {}
      }
      await touch(projectId);
      return null;
    } catch (e) {
      return '$e';
    }
  }

  Future<int> _fileLength(Directory dir, String path) async {
    try {
      return await File('${dir.path}/$path').length();
    } catch (_) {
      return 0;
    }
  }

  Future<String?> readFile(String projectId, String path) async {
    final clean = sanitize(path);
    if (clean.isEmpty) return null;
    try {
      final dir = await dirFor(projectId);
      final f = File('${dir.path}/$clean');
      if (!await f.exists()) return null;
      return await f.readAsString();
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteFile(String projectId, String path) async {
    final clean = sanitize(path);
    if (clean.isEmpty) return;
    try {
      final dir = await dirFor(projectId);
      final f = File('${dir.path}/$clean');
      if (await f.exists()) await f.delete();
      await touch(projectId);
    } catch (_) {}
  }

  Future<void> renameFile(
      String projectId, String oldPath, String newPath) async {
    final o = sanitize(oldPath);
    final n = sanitize(newPath);
    if (o.isEmpty || n.isEmpty || o == n) return;
    try {
      final dir = await dirFor(projectId);
      final src = File('${dir.path}/$o');
      if (!await src.exists()) return;
      final dst = File('${dir.path}/$n');
      await dst.parent.create(recursive: true);
      await src.rename(dst.path);
      await touch(projectId);
    } catch (_) {}
  }

  /// Relative file paths, sorted, deepest last.
  Future<List<String>> listFiles(String projectId) async {
    try {
      final dir = await dirFor(projectId);
      if (!await dir.exists()) return [];
      final out = <String>[];
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File) {
          out.add(e.path.substring(dir.path.length + 1).replaceAll('\\', '/'));
        }
      }
      out.sort();
      return out;
    } catch (_) {
      return [];
    }
  }

  /// Grep file contents (case-insensitive). Returns path → line numbers.
  Future<Map<String, List<int>>> searchCode(
      String projectId, String query) async {
    final out = <String, List<int>>{};
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return {};
    try {
      final dir = await dirFor(projectId);
      for (final path in await listFiles(projectId)) {
        try {
          final text = await File('${dir.path}/$path').readAsString();
          final hits = <int>[];
          final lines = text.split('\n');
          for (var i = 0; i < lines.length && hits.length < 50; i++) {
            if (lines[i].toLowerCase().contains(q)) hits.add(i + 1);
          }
          if (hits.isNotEmpty) out[path] = hits;
        } catch (_) {}
      }
    } catch (_) {}
    return out;
  }

  /// Import generated files wholesale (bulk write, returns first error).
  Future<String?> importFiles(
      String projectId, Map<String, String> files) async {
    for (final e in files.entries.take(maxFiles)) {
      final err = await writeFile(projectId, e.key, e.value);
      if (err != null) return '${e.key}: $err';
    }
    return null;
  }

  // ── Checkpoints ──

  static const int maxCheckpoints = 20;
  static const _kCheckpoints = 'agent_checkpoints';

  Future<Directory> _checkpointDir(String projectId) async {
    final projectDir = await dirFor(projectId);
    final cpDir = Directory('${projectDir.path}/.checkpoints');
    if (!await cpDir.exists()) await cpDir.create(recursive: true);
    return cpDir;
  }

  Map<String, List<Map>> _allCheckpointMeta() {
    try {
      final raw = Get.find<HiveService>().getSetting<Map>(_kCheckpoints);
      if (raw == null) return {};
      return raw.map((k, v) => MapEntry(k.toString(), List<Map>.from(v as List)));
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveCheckpointMeta(
      String projectId, List<Map> list) async {
    try {
      final all = _allCheckpointMeta();
      all[projectId] = list;
      await Get.find<HiveService>().setSetting(_kCheckpoints, all);
    } catch (_) {}
  }

  /// Save a snapshot of all project files. Returns the checkpoint ID.
  Future<String> saveCheckpoint(String projectId, {String? label}) async {
    final cpId = DateTime.now().millisecondsSinceEpoch.toString();
    final cpDir = await _checkpointDir(projectId);
    final targetDir = Directory('${cpDir.path}/$cpId');
    await targetDir.create(recursive: true);

    // Copy all project files into the checkpoint directory.
    final projectDir = await dirFor(projectId);
    var fileCount = 0;
    for (final path in await listFiles(projectId)) {
      try {
        final src = File('${projectDir.path}/$path');
        final dst = File('${targetDir.path}/$path');
        await dst.parent.create(recursive: true);
        await src.copy(dst.path);
        fileCount++;
      } catch (_) {}
    }

    // Save metadata.
    final meta = _allCheckpointMeta();
    final list = meta[projectId] ?? [];
    list.insert(0, ProjectCheckpoint(
      id: cpId,
      label: label ?? 'Auto-save',
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      fileCount: fileCount,
    ).toMap());
    // Prune old checkpoints (keep maxCheckpoints).
    while (list.length > maxCheckpoints) {
      final oldest = list.removeLast();
      try {
        final oldDir = Directory('${cpDir.path}/${oldest['id']}');
        if (await oldDir.exists()) await oldDir.delete(recursive: true);
      } catch (_) {}
    }
    await _saveCheckpointMeta(projectId, list);
    return cpId;
  }

  /// List checkpoints for a project (newest first).
  Future<List<ProjectCheckpoint>> listCheckpoints(String projectId) async {
    final meta = _allCheckpointMeta();
    final list = meta[projectId] ?? [];
    return list.map(ProjectCheckpoint.fromMap).toList();
  }

  /// Rollback project files to a checkpoint. Returns the number of files restored.
  Future<int> rollbackToCheckpoint(String projectId, String checkpointId) async {
    final cpDir = await _checkpointDir(projectId);
    final srcDir = Directory('${cpDir.path}/$checkpointId');
    if (!await srcDir.exists()) return 0;

    // Clear current project files (except .checkpoints).
    final projectDir = await dirFor(projectId);
    await for (final e in projectDir.list(recursive: false)) {
      if (e is Directory && e.path.endsWith('.checkpoints')) continue;
      try {
        if (e is File) await e.delete();
        if (e is Directory) await e.delete(recursive: true);
      } catch (_) {}
    }

    // Copy checkpoint files back.
    var restored = 0;
    await for (final e in srcDir.list(recursive: true)) {
      if (e is File) {
        final rel = e.path.substring(srcDir.path.length + 1).replaceAll('\\', '/');
        final dst = File('${projectDir.path}/$rel');
        await dst.parent.create(recursive: true);
        await e.copy(dst.path);
        restored++;
      }
    }
    await touch(projectId);
    return restored;
  }

  /// Delete a specific checkpoint.
  Future<void> deleteCheckpoint(String projectId, String checkpointId) async {
    final cpDir = await _checkpointDir(projectId);
    final targetDir = Directory('${cpDir.path}/$checkpointId');
    if (await targetDir.exists()) await targetDir.delete(recursive: true);

    final meta = _allCheckpointMeta();
    final list = meta[projectId] ?? [];
    list.removeWhere((m) => m['id'] == checkpointId);
    await _saveCheckpointMeta(projectId, list);
  }
}
