import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/skill_model.dart';
import '../hive_service.dart';
import '../app_log_service.dart';

/// Threshold in bytes above which skill content is stored as a file
/// instead of inline in Hive (keeps Hive box lean).
const int _kLargeSkillThreshold = 100 * 1024;

class SkillRegistryService extends GetxService {
  final _uuid = const Uuid();
  late final HiveService _hive;

  final RxList<SkillModel> skills = <SkillModel>[].obs;

  Future<SkillRegistryService> init() async {
    _hive = Get.find<HiveService>();
    await _load();
    await installBuiltIns();
    return this;
  }

  Future<void> _load() async {
    final raw = _hive.skillsBox.values
        .map((v) => Map<dynamic, dynamic>.from(v as Map))
        .toList();
    final list = <SkillModel>[];
    for (final m in raw) {
      var skill = SkillModel.fromMap(m);
      // Resolve file-backed content.
      if (skill.content.startsWith('__file__:')) {
        final path = skill.content.substring('__file__:'.length);
        try {
          final content = await File(path).readAsString();
          skill = skill.copyWith(content: content);
        } catch (_) {
          // Keep placeholder content; log and continue.
          Get.find<AppLogService>().warning(
            'Failed to read skill file',
            details: path,
            category: LogCategory.system,
          );
        }
      }
      list.add(skill);
    }
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    skills.assignAll(list);
  }

  List<SkillModel> getAll() => skills.toList();
  List<SkillModel> getEnabled() => skills.where((s) => s.enabled).toList();

  Future<void> _persist(SkillModel skill) async {
    var toStore = skill;
    // If content is large, spill to file.
    if (skill.content.length > _kLargeSkillThreshold) {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/skills/${skill.id}.md');
      await file.parent.create(recursive: true);
      await file.writeAsString(skill.content);
      toStore = SkillModel(
        id: skill.id,
        name: skill.name,
        description: skill.description,
        author: skill.author,
        version: skill.version,
        content: '__file__:${file.path}',
        enabled: skill.enabled,
        isBuiltIn: skill.isBuiltIn,
        source: skill.source,
        createdAt: skill.createdAt,
      );
    }
    await _hive.skillsBox.put(skill.id, toStore.toMap());
  }

  Future<void> enable(String id) async {
    final idx = skills.indexWhere((s) => s.id == id);
    if (idx == -1) return;
    final updated = skills[idx].copyWith(enabled: true);
    skills[idx] = updated;
    await _persist(updated);
  }

  Future<void> disable(String id) async {
    final idx = skills.indexWhere((s) => s.id == id);
    if (idx == -1) return;
    final updated = skills[idx].copyWith(enabled: false);
    skills[idx] = updated;
    await _persist(updated);
  }

  Future<void> delete(String id) async {
    final skill = skills.firstWhereOrNull((s) => s.id == id);
    if (skill == null) return;
    // Built-ins can be disabled but not deleted? Spec says delete(id) for all;
    // we allow deleting built-ins but they will be re-seeded only if missing on next installBuiltIns.
    if (skill.content.startsWith('__file__:')) {
      // Also delete file if present.
      try {
        final path = skill.content.substring('__file__:'.length);
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    } else if (skill.content.length > _kLargeSkillThreshold) {
      // Check file-backed variant in Hive.
      final raw = _hive.skillsBox.get(id);
      if (raw is Map && (raw['content'] as String?)?.startsWith('__file__:') == true) {
        try {
          final path = (raw['content'] as String).substring('__file__:'.length);
          final f = File(path);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
    skills.removeWhere((s) => s.id == id);
    await _hive.skillsBox.delete(id);
  }

  /// Import a skill from raw markdown content. Caller provides metadata;
  /// YAML frontmatter in [content] is not auto-parsed here — the caller
  /// (GitHub/URL import) may pre-fill name/description from frontmatter.
  Future<SkillModel> importFromMarkdown(
    String content, {
    required String name,
    String description = '',
    String author = 'User',
    String version = '1.0.0',
    String source = 'file',
    bool enabled = true,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) throw Exception('Skill content is empty');
    if (trimmed.length > 500 * 1024) {
      throw Exception('Skill too large (max 500 KB)');
    }
    final id = _uuid.v4();
    final skill = SkillModel(
      id: id,
      name: name.trim().isEmpty ? 'Untitled Skill' : name.trim(),
      description: description.trim(),
      author: author.trim().isEmpty ? 'User' : author.trim(),
      version: version.trim().isEmpty ? '1.0.0' : version.trim(),
      content: trimmed,
      enabled: enabled,
      isBuiltIn: false,
      source: source,
      createdAt: DateTime.now(),
    );
    skills.add(skill);
    await _persist(skill);
    return skill;
  }

  /// Seeds bundled starter skills on first run. Idempotent — skips if a
  /// built-in with same id already exists.
  Future<void> installBuiltIns() async {
    const builtIns = [
      _BuiltInSkill(
        id: 'builtin-bn-en-translator',
        name: 'Bangla-English Translator',
        description: 'Bilingual helper that responds in the user\'s language mix and translates accurately between Bangla and English.',
        author: 'CubicLM',
        version: '1.0.0',
        assetPath: 'assets/skills/bn_en_translator.md',
        source: 'built-in',
      ),
      _BuiltInSkill(
        id: 'builtin-code-reviewer',
        name: 'Code Reviewer',
        description: 'Senior code reviewer for Flutter/Dart, Python, and JS — finds bugs, suggests idiomatic fixes, and scores readability.',
        author: 'CubicLM',
        version: '1.0.0',
        assetPath: 'assets/skills/code_reviewer.md',
        source: 'built-in',
      ),
      _BuiltInSkill(
        id: 'builtin-efficient-prompting',
        name: 'On-Device Efficient Prompting',
        description: 'Teaches the model to be concise and structured for small-context on-device models.',
        author: 'CubicLM',
        version: '1.0.0',
        assetPath: 'assets/skills/efficient_prompting.md',
        source: 'built-in',
      ),
      _BuiltInSkill(
        id: 'builtin-study-helper',
        name: 'Study Helper — Explain Like I\'m 12',
        description: 'Turns any topic into a clear, analogy-rich explanation with examples and a quick quiz.',
        author: 'CubicLM',
        version: '1.0.0',
        assetPath: 'assets/skills/study_helper.md',
        source: 'built-in',
      ),
      _BuiltInSkill(
        id: 'builtin-creative-writer',
        name: 'Creative Writer',
        description: 'Helps craft stories, poems, and scripts with vivid imagery and tight pacing.',
        author: 'CubicLM',
        version: '1.0.0',
        assetPath: 'assets/skills/creative_writer.md',
        source: 'built-in',
      ),
    ];

    for (final b in builtIns) {
      if (skills.any((s) => s.id == b.id)) continue;
      String content;
      try {
        content = await rootBundle.loadString(b.assetPath);
      } catch (e) {
        Get.find<AppLogService>().warning(
          'Built-in skill asset missing',
          details: '${b.assetPath}: $e',
          category: LogCategory.system,
        );
        continue;
      }
      final skill = SkillModel(
        id: b.id,
        name: b.name,
        description: b.description,
        author: b.author,
        version: b.version,
        content: content.trim(),
        enabled: false,
        isBuiltIn: true,
        source: b.source,
        createdAt: DateTime.now(),
      );
      skills.add(skill);
      await _persist(skill);
    }
  }
}

class _BuiltInSkill {
  const _BuiltInSkill({
    required this.id,
    required this.name,
    required this.description,
    required this.author,
    required this.version,
    required this.assetPath,
    required this.source,
  });
  final String id;
  final String name;
  final String description;
  final String author;
  final String version;
  final String assetPath;
  final String source;
}
