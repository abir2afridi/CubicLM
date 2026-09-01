import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../ffi/sd_ffi_bindings.dart';

void isolateEntryPoint(Map<String, dynamic> args) {
  final mainSendPort = args['port'] as SendPort;
  final backendIndex = args['backend'] as int? ?? 0;
  final backend = Backend.values[backendIndex];

  // Initialize FFI inside the isolate with selected backend
  try {
    SdFfiBindings.initialize(backend);
  } catch (e) {
    mainSendPort.send({
      'type': 'error',
      'message': 'Failed to load ${backend.displayName}: $e',
    });
    return;
  }

  // Setup callbacks that post back to main isolate
  final isolateReceivePort = ReceivePort();
  mainSendPort.send(isolateReceivePort.sendPort);

  SdFfiBindings.setupCallbacks(mainSendPort);

  Pointer<Void>? ctx;

  isolateReceivePort.listen((message) {
    if (message is! Map) return;

    switch (message['command']) {
      case 'generate':
        runGeneration(mainSendPort, ctx, message);
        break;
      case 'dispose':
        final currentCtx = ctx;
        if (currentCtx != null && currentCtx.address != 0) {
          SdFfiBindings.freeCtx(currentCtx);
          ctx = null;
        }
        SdFfiBindings.clearCallbacks();
        isolateReceivePort.close();
        mainSendPort.send({'type': 'disposed'});
        break;
    }
  });

  // Initialize model
  final modelPath = args['modelPath'] as String;
  final nThreads = args['nThreads'] as int;
  final flashAttn = args['flashAttn'] as bool;
  final vaeTiling = args['vaeTiling'] as bool;
  final taesdPath = args['taesdPath'] as String?;
  final vaePath = args['vaePath'] as String?;
  final clipLPath = args['clipLPath'] as String?;
  final wtype = args['quantizationType'] as int? ?? 1; // default FP16
  final offloadParamsToCpu = args['offloadParamsToCpu'] as bool? ?? false;
  final enableMmap = args['enableMmap'] as bool? ?? false;
  final keepVaeOnCpu = args['keepVaeOnCpu'] as bool? ?? false;
  final maxVram = (args['maxVram'] as num?)?.toDouble() ?? 0.0;

  final pathPtr = modelPath.toNativeUtf8();
  final taesdPtr = (taesdPath != null && taesdPath.isNotEmpty)
      ? taesdPath.toNativeUtf8()
      : nullptr;
  final vaePtr = (vaePath != null && vaePath.isNotEmpty)
      ? vaePath.toNativeUtf8()
      : nullptr;
  final clipLPtr = (clipLPath != null && clipLPath.isNotEmpty)
      ? clipLPath.toNativeUtf8()
      : nullptr;
  try {
    final newCtx = SdFfiBindings.initEx(
      pathPtr,
      nThreads,
      flashAttn,
      vaeTiling,
      taesdPtr,
      vaePtr,
      clipLPtr,
      wtype,
      backendIndex,
      offloadParamsToCpu,
      enableMmap,
      keepVaeOnCpu,
      maxVram,
    );
    if (newCtx.address == 0) {
      ctx = null;
      mainSendPort.send({
        'type': 'error',
        'message': 'Failed to initialize model context',
      });
    } else {
      ctx = newCtx;
      mainSendPort.send({'type': 'modelLoaded'});
    }
  } catch (e) {
    ctx = null;
    mainSendPort.send({
      'type': 'error',
      'message': 'Failed to initialize ${backend.displayName}: $e',
    });
  } finally {
    calloc.free(pathPtr);
    if (taesdPtr != nullptr) calloc.free(taesdPtr);
    if (vaePtr != nullptr) calloc.free(vaePtr);
    if (clipLPtr != nullptr) calloc.free(clipLPtr);
  }
}

void runGeneration(
  SendPort mainSendPort,
  Pointer<Void>? ctx,
  Map message,
) {
  if (ctx == null || ctx.address == 0) {
    print('[Isolate] ERROR: Model not initialized');
    mainSendPort.send({
      'type': 'error',
      'message': 'Model not initialized',
    });
    return;
  }

  final prompt = message['prompt'] as String;
  final negativePrompt = message['negativePrompt'] as String;
  final width = message['width'] as int;
  final height = message['height'] as int;
  final steps = message['steps'] as int;
  final seed = message['seed'] as int;
  final cfgScale = (message['cfgScale'] as num).toDouble();
  final sampleMethod = message['sampleMethod'] as int;
  final schedule = message['schedule'] as int;
  final vaeTiling = message['vaeTiling'] as bool;

  print(
      '[Isolate] _runGeneration started: prompt="$prompt", ${width}x$height, steps=$steps, seed=$seed');

  final promptPtr = prompt.toNativeUtf8();
  final negPtr = negativePrompt.toNativeUtf8();
  final outSizePtr = calloc<IntPtr>(1);

  try {
    print('[Isolate] Calling FFI generate()...');
    final resultPtr = SdFfiBindings.generate(
      ctx,
      promptPtr,
      negPtr,
      width,
      height,
      steps,
      seed,
      cfgScale,
      sampleMethod,
      schedule,
      vaeTiling,
      outSizePtr,
    );
    print(
        '[Isolate] FFI generate() returned, resultPtr=${resultPtr.address}');

    final outSize = outSizePtr.value;
    print('[Isolate] outSize=$outSize');

    if (resultPtr.address == 0 || outSize == 0) {
      print('[Isolate] ERROR: null result or zero size');
      mainSendPort.send({
        'type': 'result',
        'error': 'Image generation failed (null result)',
      });
      return;
    }

    print('[Isolate] Copying $outSize bytes from native buffer...');
    // Copy native bytes into Dart-managed Uint8List
    final rgbBytes = Uint8List.fromList(
      resultPtr.asTypedList(outSize),
    );
    print('[Isolate] Copied ${rgbBytes.length} bytes');

    // Free native buffer
    calloc.free(resultPtr);

    print('[Isolate] Sending result to main isolate');
    mainSendPort.send({
      'type': 'result',
      'bytes': rgbBytes,
      'width': width,
      'height': height,
    });
    print('[Isolate] Result sent');
  } catch (e, stack) {
    print('[Isolate] EXCEPTION: $e');
    print('[Isolate] STACK: $stack');
    mainSendPort.send({
      'type': 'result',
      'error': 'Generation exception: $e',
    });
  } finally {
    calloc.free(promptPtr);
    calloc.free(negPtr);
    calloc.free(outSizePtr);
    print('[Isolate] _runGeneration finished');
  }
}
