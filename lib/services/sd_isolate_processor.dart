import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../ffi/sd_ffi_bindings.dart';
import 'sd_isolate_worker.dart' as worker;

class ProgressUpdate {
  final int step;
  final int totalSteps;
  final double time;
  ProgressUpdate(this.step, this.totalSteps, this.time);
}

class LogMessage {
  final int level;
  final String message;
  LogMessage(this.level, this.message);
}

class GenerationResult {
  final Uint8List? rgbBytes;
  final int width;
  final int height;
  final String? error;
  GenerationResult(
      {this.rgbBytes, this.width = 0, this.height = 0, this.error});
}

/// Isolate-based Stable Diffusion processor.
/// Pattern adapted from Local-Diffusion (https://github.com/rmatif/Local-Diffusion)
class SdIsolateProcessor {
  final String modelPath;
  final int nThreads;
  final bool flashAttn;
  final bool vaeTiling;
  final String? taesdPath;
  final String? vaePath;
  final String? clipLPath;
  final Backend backend;
  final QuantizationType quantizationType;
  final bool offloadParamsToCpu;
  final bool enableMmap;
  final bool keepVaeOnCpu;
  final double maxVram;

  Isolate? _isolate;
  SendPort? _sendPort;
  final _receivePort = ReceivePort();
  final _initCompleter = Completer<void>();
  final _modelLoadedCompleter = Completer<bool>();
  bool _disposed = false;

  Future<bool> get modelLoaded => _modelLoadedCompleter.future;

  final _progressController = StreamController<ProgressUpdate>.broadcast();
  final _logController = StreamController<LogMessage>.broadcast();

  Stream<ProgressUpdate> get progressStream => _progressController.stream;
  Stream<LogMessage> get logStream => _logController.stream;

  SdIsolateProcessor({
    required this.modelPath,
    this.nThreads = 0,
    this.flashAttn = false,
    this.vaeTiling = false,
    this.taesdPath,
    this.vaePath,
    this.clipLPath,
    this.backend = Backend.cpu,
    this.quantizationType = QuantizationType.f16,
    this.offloadParamsToCpu = false,
    this.enableMmap = false,
    this.keepVaeOnCpu = false,
    this.maxVram = 0.0,
  }) {
    _spawnIsolate();
  }

  Future<void> _spawnIsolate() async {
    _isolate = await Isolate.spawn(
      worker.isolateEntryPoint,
      {
        'port': _receivePort.sendPort,
        'modelPath': modelPath,
        'nThreads': nThreads,
        'flashAttn': flashAttn,
        'vaeTiling': vaeTiling,
        'taesdPath': taesdPath,
        'vaePath': vaePath,
        'clipLPath': clipLPath,
        'backend': backend.index,
        'quantizationType': quantizationType.nativeValue,
        'offloadParamsToCpu': offloadParamsToCpu,
        'enableMmap': enableMmap,
        'keepVaeOnCpu': keepVaeOnCpu,
        'maxVram': maxVram,
      },
    );

    _receivePort.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        _initCompleter.complete();
        return;
      }
      if (message is Map) {
        switch (message['type']) {
          case 'progress':
            _progressController.add(ProgressUpdate(
              message['step'],
              message['steps'],
              (message['time'] as num).toDouble(),
            ));
            break;
          case 'log':
            _logController.add(LogMessage(
              message['level'],
              message['message'],
            ));
            break;
          case 'result':
            _handleResult(message);
            break;
          case 'modelLoaded':
            if (!_modelLoadedCompleter.isCompleted) {
              _modelLoadedCompleter.complete(true);
            }
            break;
          case 'error':
            _handleError(message['message']);
            break;
        }
      }
    });
  }

  void _handleResult(Map message) {
    final completer = _activeCompleter;
    if (completer == null || completer.isCompleted) {
      print('[MainIsolate] _handleResult: completer already completed or null');
      return;
    }

    final error = message['error'] as String?;
    if (error != null) {
      print('[MainIsolate] _handleResult: completing with error: $error');
      completer.complete(GenerationResult(error: error));
      return;
    }

    final bytes = message['bytes'] as Uint8List?;
    final width = (message['width'] as num?)?.toInt() ?? 0;
    final height = (message['height'] as num?)?.toInt() ?? 0;
    print(
        '[MainIsolate] _handleResult: completing with image ${width}x$height, ${bytes?.length} bytes');
    completer.complete(GenerationResult(
      rgbBytes: bytes,
      width: width,
      height: height,
    ));
  }

  void _handleError(String error) {
    if (!_modelLoadedCompleter.isCompleted) {
      _modelLoadedCompleter.complete(false);
    }
    final completer = _activeCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(GenerationResult(error: error));
    }
  }

  Completer<GenerationResult>? _activeCompleter;

  Future<GenerationResult> generate({
    required String prompt,
    String negativePrompt = '',
    int width = 384,
    int height = 384,
    int steps = 4,
    int seed = -1,
    double cfgScale = 7.0,
    SampleMethod sampleMethod = SampleMethod.eulerA,
    Schedule schedule = Schedule.discrete,
    bool vaeTiling = false,
  }) async {
    if (_disposed) {
      return GenerationResult(error: 'Processor is disposed');
    }
    await _initCompleter.future;

    final modelLoaded = await _modelLoadedCompleter.future;
    if (!modelLoaded) {
      return GenerationResult(error: 'Model failed to load');
    }

    if (_activeCompleter != null && !_activeCompleter!.isCompleted) {
      return GenerationResult(error: 'Generation already in progress');
    }

    _activeCompleter = Completer<GenerationResult>();

    _sendPort!.send({
      'command': 'generate',
      'prompt': prompt,
      'negativePrompt': negativePrompt,
      'width': width,
      'height': height,
      'steps': steps,
      'seed': seed,
      'cfgScale': cfgScale,
      'sampleMethod': sampleMethod.index,
      'schedule': schedule.index,
      'vaeTiling': vaeTiling,
    });

    return _activeCompleter!.future;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    await _initCompleter.future;
    _sendPort?.send({'command': 'dispose'});

    // Give isolate time to clean up
    await Future.delayed(const Duration(milliseconds: 200));

    _receivePort.close();
    _progressController.close();
    _logController.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }


}
