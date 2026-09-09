/// Shared inference types (engine-independent).
///
/// Lives outside the platform engines so the GGUF engine, the LiteRT
/// engine, the facade and the web stub all speak the same result type
/// without import cycles.
library;

/// Result from model loading.
class LoadResult {
  final bool success;
  final String message;
  final String gpuName;
  final int gpuLayers;
  final String runtime;
  final String backend;
  LoadResult({
    required this.success,
    required this.message,
    this.gpuName = '',
    this.gpuLayers = 0,
    this.runtime = '',
    this.backend = '',
  });
}
