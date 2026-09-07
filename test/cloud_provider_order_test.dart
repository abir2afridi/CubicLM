import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:cubiclm/controllers/cloud_model_controller.dart';
import 'package:cubiclm/controllers/settings_controller.dart';
import 'package:cubiclm/services/hive_service.dart';
import 'package:cubiclm/services/secure_key_store.dart';

void main() {
  setUp(() {
    Get.testMode = true;
    Get.put(HiveService());
    Get.put(SecureKeyStore());
    Get.put(SettingsController());
  });

  tearDown(() {
    Get.reset();
  });

  CloudModelController makeController() {
    final c = CloudModelController();
    Get.put(c);
    return c;
  }

  CloudProviderInfo info(String id, String name) => CloudProviderInfo(
        id: id,
        name: name,
        description: 'd',
        icon: Icons.cloud_outlined,
      );

  group('provider ordering', () {
    test('custom API is always first', () {
      final c = makeController();
      c.allProviders.clear();
      c.allProviders.assignAll([
        info('openrouter', 'OpenRouter'),
        info('custom', 'Custom API'),
        info('openai', 'OpenAI'),
      ]);
      final ids = c.orderedProviders().map((p) => p.id).toList();
      expect(ids.first, 'custom');
    });

    test('keyed providers sort oldest-first in time mode', () {
      final c = makeController();
      final s = Get.find<SettingsController>();
      c.allProviders.clear();
      c.allProviders.assignAll([
        info('custom', 'Custom API'),
        info('openai', 'OpenAI'),
        info('groq', 'Groq'),
        info('mistral', 'Mistral'),
      ]);
      s.openaiKey.value = 'k1';
      s.groqKey.value = 'k2';
      // Both legacy (epoch timestamps) → alpha tiebreak.
      var ids = c.orderedProviders().map((p) => p.id).toList();
      expect(ids, ['custom', 'groq', 'openai', 'mistral']);
      // Name mode is pure A–Z among keyed.
      c.providerSortMode.value = 'name';
      ids = c.orderedProviders().map((p) => p.id).toList();
      expect(ids, ['custom', 'groq', 'openai', 'mistral']);
    });

    test('pinned providers outrank everything except custom', () async {
      final c = makeController();
      final s = Get.find<SettingsController>();
      c.allProviders.clear();
      c.allProviders.assignAll([
        info('custom', 'Custom API'),
        info('openai', 'OpenAI'),
        info('groq', 'Groq'),
      ]);
      s.openaiKey.value = 'k1';
      s.groqKey.value = 'k2';
      await c.togglePin('openai');
      expect(c.isPinned('openai'), isTrue);
      final ids = c.orderedProviders().map((p) => p.id).toList();
      expect(ids, ['custom', 'openai', 'groq']);
    });

    test('custom cannot be pinned; unkeyed cannot be pinned', () async {
      final c = makeController();
      c.allProviders.clear();
      c.allProviders.assignAll([
        info('custom', 'Custom API'),
        info('mistral', 'Mistral'),
      ]);
      await c.togglePin('custom');
      await c.togglePin('mistral');
      expect(c.pinnedProviders, isEmpty);
    });

    test('removing a key unpins it', () async {
      final c = makeController();
      final s = Get.find<SettingsController>();
      c.allProviders.clear();
      c.allProviders.assignAll([info('groq', 'Groq')]);
      s.groqKey.value = 'k2';
      await c.togglePin('groq');
      expect(c.isPinned('groq'), isTrue);
      s.groqKey.value = '';
      await c.removeApiKey('groq');
      expect(c.isPinned('groq'), isFalse);
    });

    test('providerOrderIndex follows display order', () {
      final c = makeController();
      final s = Get.find<SettingsController>();
      c.allProviders.clear();
      c.allProviders.assignAll([
        info('openai', 'OpenAI'),
        info('custom', 'Custom API'),
      ]);
      s.openaiKey.value = 'k1';
      expect(
          c.providerOrderIndex('custom') <
              c.providerOrderIndex('openai'),
          isTrue);
    });
  });
}
