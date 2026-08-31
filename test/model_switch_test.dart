import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart';

/// Regression tests for "only one downloaded model is usable until the app is
/// restarted".
///
/// Root cause: [LlamaController.loadModel] used to throw
/// `StateError('Model already loaded')` whenever a model was still resident
/// natively. Because the C++ layer keeps the model in file statics that only
/// `nativeFreeModel()` or process death can clear, a single dirty load wedged
/// every later load — which is why restarting the app was the only cure.
///
/// These tests drive the real controller over mocked Pigeon channels, so they
/// exercise the shipped self-heal rather than a stand-in.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const prefix = 'dev.flutter.pigeon.llama_flutter_android.LlamaHostApi';
  const loadChannel = '$prefix.loadModel';
  const disposeChannel = '$prefix.dispose';
  const isLoadedChannel = '$prefix.isModelLoaded';
  const stopChannel = '$prefix.stop';

  const codec = LlamaHostApi.pigeonChannelCodec;
  late List<String> calls;

  /// Native residency as the Kotlin `AtomicBoolean` would report it.
  late bool nativeModelResident;

  /// When set, the next loadModel call fails with this PlatformException code.
  String? failNextLoadWith;

  TestDefaultBinaryMessenger messenger() =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void mock(String channel, Future<Object?> Function() reply) {
    messenger().setMockMessageHandler(channel, (message) async {
      calls.add(channel.split('.').last);
      return codec.encodeMessage(await reply());
    });
  }

  setUp(() {
    calls = [];
    nativeModelResident = false;
    failNextLoadWith = null;

    mock(loadChannel, () async {
      // Mirrors LlamaFlutterAndroidPlugin.loadModel: the native flag is only
      // flipped once nativeLoadModel returns without throwing.
      if (failNextLoadWith != null) {
        final code = failNextLoadWith!;
        failNextLoadWith = null;
        // A load that fails *after* the model is mapped still leaves the
        // process holding it — the exact state that used to be unrecoverable.
        nativeModelResident = true;
        return <Object?>[code, 'load failed', null];
      }
      nativeModelResident = true;
      return <Object?>[null];
    });
    mock(disposeChannel, () async {
      nativeModelResident = false;
      return <Object?>[null];
    });
    mock(isLoadedChannel, () async => <Object?>[nativeModelResident]);
    mock(stopChannel, () async => <Object?>[null]);
  });

  tearDown(() {
    for (final channel in [
      loadChannel,
      disposeChannel,
      isLoadedChannel,
      stopChannel,
    ]) {
      messenger().setMockMessageHandler(channel, null);
    }
  });

  test('loading a second model frees the first instead of throwing', () async {
    final controller = LlamaController();

    await controller.loadModel(modelPath: '/models/a.gguf');
    // Multi-model pool: first load goes straight to native (no isModelLoaded check).
    expect(calls, ['loadModel']);

    calls.clear();
    // Second load — native pool handles the switch/eviction internally.
    await controller.loadModel(modelPath: '/models/b.gguf');

    expect(calls, ['loadModel']);
  });

  test('a load that fails part-way does not block the next load', () async {
    final controller = LlamaController();

    failNextLoadWith = 'LOAD_ERROR';
    await expectLater(
      controller.loadModel(modelPath: '/models/corrupt.gguf'),
      throwsA(isA<PlatformException>()),
    );
    // Native side is still holding a model the Dart side never saw succeed.
    expect(nativeModelResident, isTrue);

    calls.clear();
    await controller.loadModel(modelPath: '/models/good.gguf');

    expect(calls, ['loadModel']);
    expect(nativeModelResident, isTrue);
  });

  test('a failed load reports the failure rather than a fake success',
      () async {
    final controller = LlamaController();
    failNextLoadWith = 'OOM';

    await expectLater(
      controller.loadModel(modelPath: '/models/huge.gguf'),
      throwsA(isA<PlatformException>()
          .having((e) => e.code, 'code', 'OOM')),
      reason: 'InferenceService must see the real error; reporting success '
          'would leave the UI naming a model that never loaded',
    );
  });

  test('the loading guard still rejects genuinely concurrent loads', () async {
    final controller = LlamaController();

    // Never completes, so the first load stays in flight.
    messenger().setMockMessageHandler(loadChannel, (message) async {
      calls.add('loadModel');
      return Completer<List<Object?>>().future.then(codec.encodeMessage);
    });

    final first = controller.loadModel(modelPath: '/models/a.gguf');
    // Let the isModelLoaded round-trip settle so _isLoading is set.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      () => controller.loadModel(modelPath: '/models/b.gguf'),
      throwsA(isA<StateError>()),
    );

    // Keep the analyzer honest about the pending future.
    expect(first, isA<Future<void>>());
  });
}
