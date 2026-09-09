/// Shared token-text hygiene for both inference engines.
///
/// GGUF and LiteRT both surface SentencePiece/Gemma control garbage;
/// a single implementation here means a fix in one place heals both
/// engines (no drift). Pure functions — unit-testable.
library;

/// Strip Gemma garbage tokens that leak when Q4_K_M dequant is corrupt
/// on Google Tensor SoC. Harmless on devices that don't produce them.
/// NOTE: Do NOT trim() — SentencePiece tokens rely on leading spaces.
String sanitizeGemmaGarbage(String text) {
  return text
      .replaceAll(RegExp(r'<unused\d+>'), '')
      .replaceAll(RegExp(r'\[@BOS@\]'), '')
      .replaceAll('<bos>', '')
      .replaceAll('<mask>', '')
      .replaceAll('<pad>', '')
      .replaceAll('<unk>', '')
      .replaceAll('<s>', '')
      .replaceAll('</s>', '');
}

/// True when [text] contains at least one printable rune.
bool hasPrintableText(String text) {
  for (final rune in text.runes) {
    if (rune > 32 &&
        rune != 0x7F &&
        rune != 0x200B &&
        rune != 0x200C &&
        rune != 0x200D &&
        rune != 0xFEFF &&
        rune != 0xFFFD) {
      return true;
    }
  }
  return false;
}
