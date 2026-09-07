import 'dart:async';

import 'package:get/get.dart';

import '../services/cloud_service.dart';
import '../services/inference_service.dart';
import '../controllers/cloud_model_controller.dart';
import '../controllers/settings_controller.dart';
import '../services/app_log_service.dart';
import '../utils/battle_scoring.dart';

/// One picked fighter: explicit provider + model.
/// [provider] is a cloud id, or `'local'` for the resident on-device model
/// (sequential mode only — local generation is serial).
class BattlePick {
  final String provider;
  final String model;

  const BattlePick({required this.provider, required this.model});

  String get id => '$provider::$model';
  bool get isLocal => provider == 'local';

  String get label {
    final m = model.contains('/') ? model.split('/').last : model;
    final short = m
        .replaceAll('.gguf', '')
        .replaceAll('.GGUF', '')
        .replaceAll('.litertlm', '');
    return isLocal ? 'On-device: $short' : '$provider: $short';
  }

  Map<String, dynamic> toMap() => {'provider': provider, 'model': model};
}

/// Live state of one contender during a battle.
class BattleEntry {
  final BattlePick pick;
  final status = 'running'.obs; // running | done | error | stopped
  final text = ''.obs;
  final elapsedMs = 0.obs;
  int? firstTokenMs;
  int? doneMs;
  String? error;

  BattleEntry(this.pick);

  int get chars => text.value.length;

  double get tokensPerSec {
    final ms = doneMs ?? elapsedMs.value;
    if (ms <= 0) return 0;
    return (chars / 4) / (ms / 1000);
  }
}

/// Battle Arena: race N cloud models on one prompt with a live monitor.
class BattleArenaController extends GetxController {
  static const maxContenders = 4;

  final picks = <BattlePick>[].obs;
  final prompt = ''.obs;
  final running = false.obs;
  final entries = <BattleEntry>[].obs;
  final verdict = Rxn<BattleVerdict>();
  final startedAt = Rxn<DateTime>();

  /// 'parallel' = same-time race (cloud only) · 'sequential' = one after
  /// another in pick order (local contender allowed).
  final mode = 'parallel'.obs;

  bool _stopped = false;
  Timer? _ticker;

  bool get canFight =>
      !running.value && picks.isNotEmpty && prompt.value.trim().isNotEmpty;

  void togglePick(String provider, String model) {
    final id = '$provider::$model';
    final idx = picks.indexWhere((p) => p.id == id);
    if (idx >= 0) {
      picks.removeAt(idx);
      return;
    }
    if (provider == 'local' && mode.value == 'parallel') {
      Get.snackbar(
        'Sequential only',
        'The on-device model races one-by-one — switch mode to Sequential.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 3),
      );
      return;
    }
    if (picks.length >= maxContenders) {
      Get.snackbar(
        'Max $maxContenders contenders',
        'Remove one to add another.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
      return;
    }
    picks.add(BattlePick(provider: provider, model: model));
  }

  /// Switch race mode. Local picks can't race same-time, so they drop
  /// when entering parallel (with a note).
  void setMode(String next) {
    if (running.value || mode.value == next) return;
    mode.value = next;
    if (next == 'parallel' && picks.any((p) => p.isLocal)) {
      picks.removeWhere((p) => p.isLocal);
      Get.snackbar(
        'On-device removed',
        'Local model races in Sequential mode only.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
    }
  }

  /// Display name of the resident local model, '' when none loaded.
  String get loadedLocalName {
    try {
      final inf = Get.find<InferenceService>();
      return inf.isModelLoaded.value ? inf.loadedModelName.value : '';
    } catch (_) {
      return '';
    }
  }

  bool isPicked(String provider, String model) =>
      picks.any((p) => p.provider == provider && p.model == model);

  void clearPicks() {
    if (!running.value) picks.clear();
  }

  /// Models grouped by provider id for the picker (configured
  /// providers with known models only).
  Map<String, List<String>> pickableModels() {
    final cmc = Get.find<CloudModelController>();
    final cloud = Get.find<CloudService>();
    final out = <String, List<String>>{};
    for (final p in cmc.orderedProviders()) {
      if (!cloud.isProviderConfigured(p.id)) continue;
      final models = (cmc.modelsByProvider[p.id] ?? [])
          .where((m) => m.trim().isNotEmpty)
          .toList();
      if (models.isNotEmpty) out[p.id] = models;
    }
    return out;
  }

  String providerName(String id) {
    try {
      final cmc = Get.find<CloudModelController>();
      return cmc.providers
          .firstWhere((p) => p.id == id,
              orElse: () => throw StateError(''))
          .name;
    } catch (_) {
      return id;
    }
  }

  Future<void> fight() async {
    if (!canFight) return;
    running.value = true;
    _stopped = false;
    verdict.value = null;
    entries.value =
        picks.map((p) => BattleEntry(p)).toList(growable: false);
    final t0 = DateTime.now();
    startedAt.value = t0;

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final now = DateTime.now().difference(t0).inMilliseconds;
      for (final e in entries) {
        if (e.status.value == 'running') e.elapsedMs.value = now;
      }
    });

    final settings = Get.find<SettingsController>();
    final temperature = settings.temperature.value;
    final maxTokens = settings.autoTuneParams.value
        ? null
        : settings.maxTokens.value;

    try {
      if (mode.value == 'sequential') {
        // One after another in pick order — each starts instantly when
        // the previous finishes. Local contender allowed here.
        for (final e in entries) {
          if (_stopped) {
            e.status.value = 'stopped';
            e.doneMs = DateTime.now().difference(t0).inMilliseconds;
            continue;
          }
          await _runOne(
            e,
            t0: t0,
            temperature: temperature,
            maxTokens: maxTokens,
            settings: settings,
          );
        }
      } else {
        await Future.wait(entries.map((e) => _runOne(
              e,
              t0: t0,
              temperature: temperature,
              maxTokens: maxTokens,
              settings: settings,
            )));
      }
    } finally {
      _ticker?.cancel();
      _ticker = null;
      for (final e in entries) {
        e.doneMs ??= DateTime.now().difference(t0).inMilliseconds;
        e.elapsedMs.value = e.doneMs!;
      }
      _score();
      running.value = false;
    }
  }

  Future<void> _runOne(
    BattleEntry e, {
    required DateTime t0,
    required double temperature,
    required int? maxTokens,
    required SettingsController settings,
  }) async {
    final system = _systemFor(e.pick.model, settings);
    try {
      if (e.pick.isLocal) {
        await _runLocal(e, t0: t0, system: system);
      } else {
        await _runCloud(
          e,
          t0: t0,
          system: system,
          temperature: temperature,
          maxTokens: maxTokens,
        );
      }
      if (_stopped) {
        e.status.value = 'stopped';
      } else {
        e.status.value = 'done';
      }
      e.doneMs = DateTime.now().difference(t0).inMilliseconds;
    } catch (err) {
      e.error = _shortError(err);
      e.status.value = 'error';
      e.doneMs = DateTime.now().difference(t0).inMilliseconds;
      try {
        Get.find<AppLogService>().warning(
          'Battle contender failed: ${e.pick.label}',
          details: '$err',
          category: LogCategory.cloud,
        );
      } catch (_) {}
    }
  }

  Future<void> _runCloud(
    BattleEntry e, {
    required DateTime t0,
    required String system,
    required double temperature,
    required int? maxTokens,
  }) async {
    final messages = [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': prompt.value.trim()},
    ];
    final cloud = Get.find<CloudService>();
    var first = true;
    await for (final chunk in cloud.streamMessageAs(
      providerId: e.pick.provider,
      model: e.pick.model,
      messages: messages,
      temperature: temperature,
      maxTokens: maxTokens,
    )) {
      if (_stopped) break;
      if (first) {
        first = false;
        e.firstTokenMs =
            DateTime.now().difference(t0).inMilliseconds;
      }
      e.text.value += chunk;
    }
  }

  /// Resident on-device model turn (sequential mode only — the local
  /// engine is serial). Uses the Hive sampling settings like chat.
  Future<void> _runLocal(
    BattleEntry e, {
    required DateTime t0,
    required String system,
  }) async {
    final inference = Get.find<InferenceService>();
    if (!inference.isModelLoaded.value) {
      throw Exception('No local model loaded.');
    }
    var first = true;
    await inference.generate(
      prompt: prompt.value.trim(),
      systemPrompt: system,
      source: 'battle',
      onToken: (chunk) {
        if (_stopped) return;
        if (first) {
          first = false;
          e.firstTokenMs =
              DateTime.now().difference(t0).inMilliseconds;
        }
        e.text.value += chunk;
      },
    );
  }

  String _systemFor(String model, SettingsController settings) {
    try {
      return settings.baseSystemPromptForModel(model);
    } catch (_) {
      return 'You are a helpful assistant.';
    }
  }

  String _shortError(Object e) {
    final s = e.toString();
    final flat = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length > 160 ? '${flat.substring(0, 160)}…' : flat;
  }

  void _score() {
    final inputs = entries
        .map((e) => BattleScoreInput(
              id: e.pick.id,
              failed:
                  e.status.value == 'error' || e.text.value.isEmpty,
              elapsedMs: e.doneMs ?? e.elapsedMs.value,
              chars: e.text.value.length,
            ))
        .toList();
    verdict.value = scoreContenders(inputs);
  }

  /// Rank (1-based) of an entry in the final verdict, 0 when unscored.
  int rankOf(String id, String axis) {
    final v = verdict.value;
    if (v == null) return 0;
    final row = v.rows[id];
    if (row == null) return 0;
    switch (axis) {
      case 'finish':
        return row.finishRank;
      case 'speed':
        return row.speedRank;
      case 'length':
        return row.lengthRank;
      default:
        return 0;
    }
  }

  /// 1-based overall place, 0 when unscored.
  int placeOf(String id) {
    final v = verdict.value;
    if (v == null) return 0;
    final i = v.order.indexOf(id);
    return i < 0 ? 0 : i + 1;
  }

  void stop() {
    _stopped = true;
    for (final e in entries) {
      if (e.status.value == 'running') e.status.value = 'stopped';
    }
    running.value = false;
  }

  @override
  void onClose() {
    _stopped = true;
    _ticker?.cancel();
    super.onClose();
  }
}
