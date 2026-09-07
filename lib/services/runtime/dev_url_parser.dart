/// Dev-server URL extraction from process output (pure Dart).
///
/// Vite prints e.g.:
///   Local:   http://localhost:5173/
/// Next.js prints e.g.:
///   - Local:   http://localhost:3000
/// Never assume a fixed port — always parse the actual line.
library;

/// Extract the first localhost/127.0.0.1 dev URL from [output].
/// Returns null when no URL line is present yet.
String? parseDevServerUrl(String output) {
  final re = RegExp(
      r'https?://(?:localhost|127\.0\.0\.1)(?::\d+)?(?:/[^\s]*)?',
      caseSensitive: false);
  final m = re.firstMatch(output);
  return m?.group(0);
}

/// Extract the port from a dev URL. Returns null when absent/unparseable.
int? parseDevServerPort(String url) {
  final m = RegExp(r':(\d+)(?:/|$)').firstMatch(url);
  if (m == null) return null;
  return int.tryParse(m.group(1)!);
}
