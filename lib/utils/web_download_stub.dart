/// No-op stub for non-web platforms (they use share sheets / dialogs).
Future<bool> downloadWebFile(
  List<int> bytes,
  String filename,
  String mime,
) async =>
    false;
