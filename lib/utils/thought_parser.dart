class ThoughtParts {
  final String thought;
  final String answer;
  final bool isThinking;

  const ThoughtParts({
    required this.thought,
    required this.answer,
    required this.isThinking,
  });

  bool get hasThought => thought.trim().isNotEmpty;
  bool get hasAnswer => answer.trim().isNotEmpty;
}

ThoughtParts splitThoughtTags(String text) {
  final lower = text.toLowerCase();
  final startIdx = lower.indexOf('<think>');

  if (startIdx == -1) {
    return ThoughtParts(thought: '', answer: text, isThinking: false);
  }

  final before = text.substring(0, startIdx);
  final afterStartIdx = startIdx + 7; // Length of '<think>'
  final endIdx = lower.indexOf('</think>', afterStartIdx);

  if (endIdx == -1) {
    return ThoughtParts(
      thought: text.substring(afterStartIdx),
      answer: before,
      isThinking: true,
    );
  }

  final thought = text.substring(afterStartIdx, endIdx);
  final after = text.substring(endIdx + 8); // Length of '</think>'
  final answer = '$before$after'.trimLeft();

  return ThoughtParts(
    thought: thought,
    answer: answer,
    isThinking: false,
  );
}
