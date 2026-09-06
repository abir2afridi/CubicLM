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
      await out.writeAsString(content, flush: true);
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
}
