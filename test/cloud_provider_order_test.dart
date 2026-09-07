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
      // Only keyed + custom appear; mistral (unkeyed) is excluded.
      var ids = c.orderedProviders().map((p) => p.id).toList();
      expect(ids, ['custom', 'groq', 'openai']);
      // Name mode is pure A–Z among keyed.
      c.providerSortMode.value = 'name';
      ids = c.orderedProviders().map((p) => p.id).toList();
      expect(ids, ['custom', 'groq', 'openai']);
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

    test('unkeyedProviders returns only providers without keys', () {
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
      // Only groq and mistral have no key; openai has key, custom excluded.
      final unkeyed = c.unkeyedProviders.map((p) => p.id).toList();
      expect(unkeyed, containsAll(['groq', 'mistral']));
      expect(unkeyed, isNot(contains('openai')));
      expect(unkeyed, isNot(contains('custom')));
    });

    test('no ghost keys: stability mirrors nothing without its own key', () {
      final c = makeController();
      final s = Get.find<SettingsController>();
      c.allProviders.clear();
      c.allProviders.assignAll([
        info('custom', 'Custom API'),
        info('openai', 'OpenAI'),
        info('stability', 'Stability AI'),
      ]);
      // Only the OpenAI key is set — stability must stay unconfigured.
      s.openaiKey.value = 'k-openai';
      expect(c.apiKeyFor('stability'), isEmpty);
      expect(c.isConfigured('stability'), isFalse);
      expect(c.isConfigured('openai'), isTrue);
      final ids = c.orderedProviders().map((p) => p.id).toList();
      expect(ids, ['custom', 'openai']);
      expect(c.unkeyedProviders.map((p) => p.id), contains('stability'));
      // With its own key, stability joins the keyed list.
      s.stabilityKey.value = 'k-stability';
      expect(c.isConfigured('stability'), isTrue);
      expect(
          c.orderedProviders().map((p) => p.id),
          containsAll(['custom', 'openai', 'stability']));
    });

    test('routed vendors never flood the keyed top section', () async {
      final c = makeController();
      final s = Get.find<SettingsController>();
      c.allProviders.clear();
      c.allProviders.assignAll([
        info('custom', 'Custom API'),
        info('openrouter', 'OpenRouter'),
        info('groq', 'Groq'),
        info('xiaomi', 'Xiaomi'),
      ]);
      // Only OpenRouter key set: xiaomi borrows it (functional) but is
      // NOT explicitly keyed.
      s.openRouterKey.value = 'k-or';
      s.groqKey.value = 'k-groq';
      expect(c.isRouted('xiaomi'), isTrue);
      expect(c.isRouted('groq'), isFalse);
      expect(c.hasExplicitKey('xiaomi'), isFalse);
      expect(c.hasExplicitKey('groq'), isTrue);
      // Keyed top section: custom + explicitly-keyed only
      // (openrouter holds its own key; xiaomi borrows it).
      final ids = c.orderedProviders().map((p) => p.id).toList();
      expect(ids, ['custom', 'groq', 'openrouter']);
      // Routed bucket holds xiaomi; unkeyed bucket is empty.
      expect(c.routedProviders.map((p) => p.id), ['xiaomi']);
      expect(c.unkeyedProviders, isEmpty);
      // Routed cards cannot be pinned.
      await c.togglePin('xiaomi');
      expect(c.pinnedProviders, isEmpty);
    });

    test('unknown provider ids fail closed (no borrowed key)', () {
      final c = makeController();
      final s = Get.find<SettingsController>();
      s.openaiKey.value = 'k-openai';
      expect(c.apiKeyFor('no-such-provider'), isEmpty);
      expect(c.isConfigured('no-such-provider'), isFalse);
    });

    test('orderedProviders excludes unkeyed providers', () {
      final c = makeController();
      c.allProviders.clear();
      c.allProviders.assignAll([
        info('custom', 'Custom API'),
        info('openai', 'OpenAI'),
        info('mistral', 'Mistral'),
      ]);
      // No keys set → only custom appears.
      final ids = c.orderedProviders().map((p) => p.id).toList();
      expect(ids, ['custom']);
    });
  });
}
