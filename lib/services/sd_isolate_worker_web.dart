import 'dart:isolate';

void isolateEntryPoint(Map<String, dynamic> args) {
  final mainSendPort = args['port'] as SendPort;
  mainSendPort.send({
    'type': 'error',
    'message': 'Stable Diffusion is not supported on web',
  });
}

void runGeneration(SendPort mainSendPort, dynamic ctx, Map message) {
  mainSendPort.send({
    'type': 'result',
    'error': 'Image generation is not supported on web',
  });
}
