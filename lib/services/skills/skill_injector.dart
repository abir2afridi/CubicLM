import 'package:get/get.dart';

import 'skill_registry_service.dart';

class SkillInjector {
  /// Builds the delimited block of all enabled skills.
  /// Stable order: by createdAt (install order), then name.
  static String buildInjectedContext() {
    if (!Get.isRegistered<SkillRegistryService>()) return '';
    final registry = Get.find<SkillRegistryService>();
    final enabled = registry.getEnabled();
    if (enabled.isEmpty) return '';
    enabled.sort((a, b) {
      final c = a.createdAt.compareTo(b.createdAt);
      if (c != 0) return c;
      return a.name.compareTo(b.name);
    });
    final buf = StringBuffer();
    buf.writeln('\n\n--- Enabled Skills ---');
    for (final s in enabled) {
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
}
