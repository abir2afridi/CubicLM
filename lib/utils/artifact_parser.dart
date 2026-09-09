class ArtifactParts {
  final String? id;
  final String? type;
  final String? title;
  final String content;
  final String remainingText;

  ArtifactParts({
    this.id,
    this.type,
    this.title,
    required this.content,
    required this.remainingText,
  });
}

List<ArtifactParts> parseArtifacts(String text) {
  final artifacts = <ArtifactParts>[];
  final regExp = RegExp(
    r'<artifact\s+([^>]*?)>([\s\S]*?)<\/artifact>',
    caseSensitive: false,
  );

  final matches = regExp.allMatches(text).toList();

  // Process in reverse to not mess up indices if we were modifying, 
  // but here we just collect and provide the "clean" text.
  
  for (final match in matches) {
    final attrStr = match.group(1) ?? '';
    final content = match.group(2) ?? '';
    
    final idMatch = RegExp(r'id=["''](.*?)["'']').firstMatch(attrStr);
    final typeMatch = RegExp(r'type=["''](.*?)["'']').firstMatch(attrStr);
    final titleMatch = RegExp(r'title=["''](.*?)["'']').firstMatch(attrStr);
    
    artifacts.add(ArtifactParts(
      id: idMatch?.group(1),
      type: typeMatch?.group(1),
      title: titleMatch?.group(1),
      content: content.trim(),
      remainingText: '', // Will be calculated below
    ));
  }

  // Return the artifacts with the clean text attached to each (or just once)
  return artifacts;
}

String removeArtifacts(String text) {
  final regExp = RegExp(
    r'<artifact\s+([^>]*?)>([\s\S]*?)<\/artifact>',
    caseSensitive: false,
  );
  return text.replaceAll(regExp, '').trim();
}
