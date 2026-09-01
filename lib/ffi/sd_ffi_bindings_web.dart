// Stub for web — SD via FFI is not available on web.
// Provides the same public symbols so imports compile on web, but all
// operations are no-ops / unsupported.

// ignore_for_file: constant_identifier_names

enum QuantizationType {
  f32,
  f16,
  q4_0,
  q4_1,
  q5_0,
  q5_1,
  q8_0,
  q8_1,
  q2_k,
  q3_k,
  q4_k,
  q5_k,
  q6_k,
  q8_k,
}

extension QuantizationTypeExtension on QuantizationType {
  String get displayName {
    switch (this) {
      case QuantizationType.f32:
        return 'FP32';
      case QuantizationType.f16:
        return 'FP16';
      case QuantizationType.q4_0:
        return 'Q4_0 (fastest)';
      case QuantizationType.q4_1:
        return 'Q4_1';
      case QuantizationType.q5_0:
        return 'Q5_0';
      case QuantizationType.q5_1:
        return 'Q5_1';
      case QuantizationType.q8_0:
        return 'Q8_0 (balanced)';
      case QuantizationType.q8_1:
        return 'Q8_1';
      case QuantizationType.q2_k:
        return 'Q2_K (smallest)';
      case QuantizationType.q3_k:
        return 'Q3_K';
      case QuantizationType.q4_k:
        return 'Q4_K (recommended)';
      case QuantizationType.q5_k:
        return 'Q5_K';
      case QuantizationType.q6_k:
        return 'Q6_K (near-lossless)';
      case QuantizationType.q8_k:
        return 'Q8_K';
    }
  }

  int get nativeValue {
    switch (this) {
      case QuantizationType.f32:
        return 0;
      case QuantizationType.f16:
        return 1;
      case QuantizationType.q4_0:
        return 2;
      case QuantizationType.q4_1:
        return 3;
      case QuantizationType.q5_0:
        return 6;
      case QuantizationType.q5_1:
        return 7;
      case QuantizationType.q8_0:
        return 8;
      case QuantizationType.q8_1:
        return 9;
      case QuantizationType.q2_k:
        return 10;
      case QuantizationType.q3_k:
        return 11;
      case QuantizationType.q4_k:
        return 12;
      case QuantizationType.q5_k:
        return 13;
      case QuantizationType.q6_k:
        return 14;
      case QuantizationType.q8_k:
        return 15;
    }
  }
}

enum Backend {
  cpu,
  vulkan,
  opencl,
}

extension BackendExtension on Backend {
  String get displayName {
    switch (this) {
      case Backend.cpu:
        return 'CPU';
      case Backend.vulkan:
        return 'Vulkan (GPU)';
      case Backend.opencl:
        return 'OpenCL (GPU)';
    }
  }

  String get libraryName {
    switch (this) {
      case Backend.cpu:
        return 'libsd_jni.so';
      case Backend.vulkan:
        return 'libsd_jni_vulkan.so';
      case Backend.opencl:
        return 'libsd_jni_opencl.so';
    }
  }

  bool get isAvailable => false;
}

enum SampleMethod {
  euler,
  eulerA,
  heun,
  dpm2,
  dpmpp2sA,
  dpmpp2m,
  dpmpp2mv2,
  ipndm,
  ipndmV,
  lcm,
  ddimTrailing,
  tcd,
  resMultistep,
  res2s,
  erSde,
}

enum Schedule {
  discrete,
  karras,
  exponential,
  ays,
  gits,
  sgmUniform,
  simple,
  smoothstep,
  klOptimal,
  lcm,
  bongTangent,
}

class SdFfiBindings {
  static bool get isSupported => false;
  static Backend get currentBackend => Backend.cpu;
  static void initialize([Backend backend = Backend.cpu]) {}
  static void setupCallbacks(dynamic _) {}
  static void clearCallbacks() {}
  static dynamic initEx(
    dynamic modelPath,
    int nThreads,
    bool flashAttn,
    bool vaeTiling,
    dynamic taesdPath,
    dynamic vaePath,
    dynamic clipLPath,
    int wtype,
    int backend,
    bool offloadParamsToCpu,
    bool enableMmap,
    bool keepVaeOnCpu,
    double maxVram,
  ) =>
      throw UnsupportedError('FFI not supported on web');
  static void freeCtx(dynamic ctx) {}
  static dynamic generate(
    dynamic ctx,
    dynamic prompt,
    dynamic negativePrompt,
    int width,
    int height,
    int steps,
    int seed,
    double cfgScale,
    int sampleMethod,
    int schedule,
    bool vaeTiling,
    dynamic outSize,
  ) =>
      throw UnsupportedError('FFI not supported on web');
}

class GpuInfo {
  final bool vulkanSupported;
  final int deviceLocalMemoryBytes;
  final String deviceName;
  const GpuInfo(
      {this.vulkanSupported = false,
      this.deviceLocalMemoryBytes = 0,
      this.deviceName = ''});
  int get recommendedGpuLayers => 0;
}
