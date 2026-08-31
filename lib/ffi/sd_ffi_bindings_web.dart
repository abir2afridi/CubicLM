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
  dpmPP2sA,
  dpmPP2m,
  dpmPP2mSde,
  dpmPP2mV3,
  ldpm,
  lms,
}

class SdFfiBindings {
  static bool get isSupported => false;
  static Backend get currentBackend => Backend.cpu;
  static void initialize([Backend backend = Backend.cpu]) {}
  static void setupCallbacks(dynamic _) {}
  static void clearCallbacks() {}
}

class GpuInfo {
  final bool vulkanSupported;
  final int deviceLocalMemoryBytes;
  final String deviceName;
  const GpuInfo({this.vulkanSupported = false, this.deviceLocalMemoryBytes = 0, this.deviceName = ''});
  int get recommendedGpuLayers => 0;
}
