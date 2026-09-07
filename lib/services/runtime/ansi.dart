/// ANSI escape stripping for terminal display (pure Dart).
///
/// Interactive CLIs (claude, opencode, …) emit full-screen TUI control
/// sequences (colors, cursor moves, alternate screen). CubicLM's
/// terminal strip is a scrolling log, not a PTY emulator, so control
/// codes are stripped for readable output. Raw bytes are never needed
/// for the log view; nothing is faked — only display formatting.
library;

final _ansiRe = RegExp(
    r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~]|\][^\x07\x1B]*(?:\x07|\x1B\\))');

/// Remove ANSI/VT100 escape sequences (colors, cursor, screen modes).
String stripAnsi(String s) {
  if (!s.contains('\x1B')) return s;
  return s.replaceAll(_ansiRe, '');
}
