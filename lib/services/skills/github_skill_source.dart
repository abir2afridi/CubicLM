import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:get/get.dart';

import '../hive_service.dart';

class GithubSkillEntry {
  final String path; // e.g. "skills/web-search"
  final String name;
  final String description;

  GithubSkillEntry({
    required this.path,
    required this.name,
    required this.description,
  });

  Map<String, dynamic> toMap() => {
        'path': path,
        'name': name,
        'description': description,
      };

  factory GithubSkillEntry.fromMap(Map<dynamic, dynamic> m) => GithubSkillEntry(
        path: m['path'] ?? '',
        name: m['name'] ?? '',
        description: m['description'] ?? '',
      );
}

class GithubSkillSource {
  static const String _apiBase = 'https://api.github.com/repos/anthropics/skills';
  static const String _rawBase = 'https://raw.githubusercontent.com/anthropics/skills/main';
  static const String _cacheKey = 'github_skills_cache';
  static const String _cacheTimeKey = 'github_skills_cache_time';
  static const int _cacheTtlMs = 6 * 60 * 60 * 1000; // 6 hours

  final Dio _dio;

  GithubSkillSource({Dio? dio}) : _dio = dio ?? Dio();

  /// Lists available skills by enumerating repo contents. Uses GitHub tree API
  /// in one call when possible, falls back to contents API.
  /// Cached in Hive, only refetched on explicit refresh.
  Future<List<GithubSkillEntry>> listAvailable({bool forceRefresh = false}) async {
    final hive = Get.find<HiveService>();
    if (!forceRefresh) {
      final cached = hive.getSetting<List>(_cacheKey);
      final cachedTime = hive.getSetting<int>(_cacheTimeKey) ?? 0;
      final age = DateTime.now().millisecondsSinceEpoch - cachedTime;
      if (cached != null && cached.isNotEmpty && age < _cacheTtlMs) {
        return cached
            .whereType<Map>()
            .map((m) => GithubSkillEntry.fromMap(Map<dynamic, dynamic>.from(m)))
            .toList();
      }
    }

    try {
      final entries = await _fetchViaTree();
      // Persist cache.
      await hive.setSetting(
          _cacheKey, entries.map((e) => e.toMap()).toList());
      await hive.setSetting(
          _cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
      return entries;
    } catch (e) {
      // Fall back to cached if available.
      final cached = hive.getSetting<List>(_cacheKey);
      if (cached != null && cached.isNotEmpty) {
        return cached
            .whereType<Map>()
            .map((m) => GithubSkillEntry.fromMap(Map<dynamic, dynamic>.from(m)))
            .toList();
      }
      rethrow;
    }
  }

  Future<List<GithubSkillEntry>> _fetchViaTree() async {
    // Use git/trees API to get all files in one request (avoids rate-limit per-folder).
    final resp = await _dio.get(
      '$_apiBase/git/trees/main?recursive=1',
      options: Options(headers: {
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'CubicLM',
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception('GitHub API ${resp.statusCode}');
    }
    final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
    final tree = (data['tree'] as List? ?? []);
    // Find all SKILL.md files.
    final skillPaths = <String>{};
    for (final item in tree) {
      if (item is! Map) continue;
      final path = item['path']?.toString() ?? '';
      if (path.endsWith('/SKILL.md') || path == 'SKILL.md') {
        final folder = path.contains('/')
            ? path.substring(0, path.lastIndexOf('/'))
            : '';
        if (folder.isNotEmpty) skillPaths.add(folder);
      }
    }

    // For each folder, fetch frontmatter for display (raw fetch per skill — limited to first 30 to stay under rate limit).
    final entries = <GithubSkillEntry>[];
    int fetched = 0;
    for (final folder in skillPaths) {
      if (fetched >= 30) break;
      try {
        final raw = await _dio.get<String>(
          '$_rawBase/$folder/SKILL.md',
          options: Options(responseType: ResponseType.plain),
        );
        final body = raw.data ?? '';
        final fm = _parseFrontmatter(body);
        final name = fm['name']?.isNotEmpty == true
            ? fm['name']!
            : folder.split('/').last.replaceAll('-', ' ');
        final desc = fm['description'] ?? '';
        entries.add(GithubSkillEntry(path: folder, name: name, description: desc));
        fetched++;
      } catch (_) {
        // Still add entry with folder name if frontmatter fetch fails.
        entries.add(GithubSkillEntry(
            path: folder,
            name: folder.split('/').last.replaceAll('-', ' '),
            description: ''));
      }
    }

    // If tree didn't yield SKILL.md (repo structure changed), fallback to contents API for top-level.
    if (entries.isEmpty) {
      return _fetchViaContents();
    }

    entries.sort((a, b) => a.name.compareTo(b.name));
    return entries;
  }

  Future<List<GithubSkillEntry>> _fetchViaContents() async {
    final resp = await _dio.get(
      '$_apiBase/contents',
      options: Options(headers: {
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'CubicLM',
      }),
    );
    if (resp.statusCode != 200) throw Exception('GitHub API ${resp.statusCode}');
    final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
    final list = data is List ? data : [];
    final entries = <GithubSkillEntry>[];
    for (final item in list) {
      if (item is! Map) continue;
      if (item['type'] != 'dir') continue;
      final name = item['name']?.toString() ?? '';
      if (name.isEmpty) continue;
      entries.add(GithubSkillEntry(path: name, name: name, description: ''));
    }
    return entries;
  }

  Future<String> fetchSkillContent(String path) async {
    final url = '$_rawBase/$path/SKILL.md';
    final resp = await _dio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    if (resp.statusCode != 200) throw Exception('Failed to fetch SKILL.md (${resp.statusCode})');
    final body = resp.data ?? '';
    if (body.trim().isEmpty) throw Exception('SKILL.md is empty');
    return body;
  }

  static Map<String, String> _parseFrontmatter(String content) {
    final result = <String, String>{};
    final trimmed = content.trimLeft();
    if (!trimmed.startsWith('---')) return result;
    final end = trimmed.indexOf('\n---', 3);
    if (end == -1) return result;
    final fm = trimmed.substring(3, end);
    for (final line in fm.split('\n')) {
      final idx = line.indexOf(':');
      if (idx == -1) continue;
      final key = line.substring(0, idx).trim().toLowerCase();
      var value = line.substring(idx + 1).trim();
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }
      if (key == 'name' || key == 'description') {
        result[key] = value;
      }
    }
    return result;
  }
}
