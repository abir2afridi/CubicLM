import 'package:get/get.dart';

import '../../models/skill_model.dart';
import 'skill_registry_service.dart';

class SkillInjector {
  /// Builds the delimited block of all enabled skills.
  /// Stable order: by createdAt (install order), then name.
  static String buildInjectedContext() {
    if (!Get.isRegistered<SkillRegistryService>()) return '';
    final registry = Get.find<SkillRegistryService>();
    final enabled = registry.getEnabled();
    return buildForSkills(enabled);
  }

  static String buildForSkills(List<SkillModel> skills) {
    if (skills.isEmpty) return '';
    final sorted = [...skills]..sort((a, b) {
        final c = a.createdAt.compareTo(b.createdAt);
        if (c != 0) return c;
        return a.name.compareTo(b.name);
      });
    final buf = StringBuffer();
    buf.writeln('\n\n--- Enabled Skills ---');
    for (final s in sorted) {
      buf.writeln('### Skill: ${s.name}');
      if (s.description.isNotEmpty) {
        buf.writeln('_${s.description}_');
      }
      buf.writeln(s.content.trim());
      buf.writeln();
    }
    buf.writeln('--- End Skills ---');
    return buf.toString();
  }

  /// Appends injected skills after [basePrompt] if any are enabled.
  static String injectInto(String basePrompt) {
    final block = buildInjectedContext();
    if (block.isEmpty) return basePrompt;
    return '$basePrompt$block';
  }

  /// Intelligent per-prompt selection — only the most relevant enabled
  /// skills are injected, and the caller can show which were used.
  static List<SkillModel> selectRelevantSkills(String userPrompt,
      {int maxSkills = 2}) {
    if (!Get.isRegistered<SkillRegistryService>()) return [];
    final enabled = Get.find<SkillRegistryService>().getEnabled();
    if (enabled.isEmpty) return [];
    final lower = userPrompt.toLowerCase();
    final hasBanglaScript = RegExp(r'[\u0980-\u09FF]').hasMatch(userPrompt);
    final hasCodeBlock = userPrompt.contains('```') ||
        RegExp(r'\b(code|flutter|dart|python|javascript|function|class|bug|fix|review|pr|pull request|refactor)\b',
                caseSensitive: false)
            .hasMatch(lower);

    final scored = <SkillModel, double>{};

    for (final s in enabled) {
      double score = 0;
      final id = s.id;
      final nameLower = s.name.toLowerCase();
      final descLower = s.description.toLowerCase();

      // Skill-specific heuristics.
      if (id == 'builtin-bn-en-translator') {
        if (hasBanglaScript) {
          score += 3.0;
        }
        if (lower.contains('translate') ||
            lower.contains('bangla') ||
            lower.contains('bengali') ||
            lower.contains('অনুবাদ') ||
            lower.contains('বাংলা')) {
          score += 2.0;
        }
        // If user wrote Bangla in Latin (common words) — lightweight check.
        if (RegExp(r'\b(kemon|valo|kothay|ki|korbo|hobe|achhi|korchi)\b')
            .hasMatch(lower)) {
          score += 1.0;
        }
      } else if (id == 'builtin-code-reviewer') {
        if (hasCodeBlock) {
          score += 3.0;
        }
        if (RegExp(r'\b(code|review|bug|flutter|dart|python|javascript|refactor|optimize|fix)\b')
            .hasMatch(lower)) {
          score += 1.5;
        }
        if (nameLower.contains('code') && lower.contains('code')) {
          score += 0.5;
        }
      } else if (id == 'builtin-efficient-prompting') {
        // This is a meta-skill: relevant for long prompts or when user wants concise.
        if (userPrompt.length > 800) {
          score += 1.0;
        }
        if (lower.contains('concise') ||
            lower.contains('short') ||
            lower.contains('brief')) {
          score += 1.0;
        }
        // Keep it low priority unless explicitly relevant — to avoid always-on.
        score *= 0.4;
      } else if (id == 'builtin-study-helper') {
        if (RegExp(r'\b(explain|what is|how does|why|teach|study|learn|understand|eli5|like i.*12)\b')
            .hasMatch(lower)) {
          score += 2.0;
        }
      } else if (id == 'builtin-creative-writer') {
        if (RegExp(r'\b(story|poem|poetry|fiction|tale|narrative|creative|write.*story|script)\b')
            .hasMatch(lower)) {
          score += 2.0;
        }
      } else {
        // Generic imported skill: match name/description keywords.
        final keywords = (nameLower.split(RegExp(r'\W+')) +
                descLower.split(RegExp(r'\W+')))
            .where((w) => w.length > 3)
            .toSet();
        for (final kw in keywords) {
          if (lower.contains(kw)) {
            score += 0.6;
          }
        }
        // Also check if prompt explicitly mentions the skill name.
        if (lower.contains(nameLower)) {
          score += 2.0;
        }
      }

      // Bonus if description words appear.
      for (final w in descLower.split(RegExp(r'\W+')).where((w) => w.length > 4)) {
        if (lower.contains(w)) {
          score += 0.2;
        }
      }

      if (score > 0) {
        scored[s] = score;
      }
    }

    if (scored.isEmpty) {
      return [];
    }
    final sorted = scored.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    // Only keep skills above threshold and top N.
    const threshold = 0.6;
    final filtered = sorted.where((e) => e.value >= threshold).take(maxSkills).map((e) => e.key).toList();
    return filtered;
  }

  /// Returns (injectedPrompt, usedSkillNames) for a given base + user prompt.
  static ({String injectedPrompt, List<String> usedSkillNames}) injectRelevant(
      String basePrompt, String userPrompt) {
    final relevant = selectRelevantSkills(userPrompt);
    if (relevant.isEmpty) return (injectedPrompt: basePrompt, usedSkillNames: <String>[]);
    final block = buildForSkills(relevant);
    return (
      injectedPrompt: '$basePrompt$block',
      usedSkillNames: relevant.map((s) => s.name).toList()
    );
  }
}
