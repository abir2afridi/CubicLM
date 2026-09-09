import 'package:get/get.dart';
import 'app_log_service.dart';

/// A lightweight service for document chunking and retrieval (RAG).
/// Uses keyword density scoring as a proxy for vector similarity.
class VectorService extends GetxService {
  
  /// Splits a large text into overlapping chunks.
  List<String> chunkText(String text, {int chunkSize = 1500, int overlap = 300}) {
    if (text.length <= chunkSize) return [text];
    
    List<String> chunks = [];
    int start = 0;
    while (start < text.length) {
      int end = start + chunkSize;
      if (end > text.length) end = text.length;
      
      // Try to find a natural break point (newline or period) near the end
      if (end < text.length) {
        int lastNewline = text.lastIndexOf('\n', end);
        if (lastNewline > start + (chunkSize * 0.7)) {
          end = lastNewline + 1;
        } else {
          int lastPeriod = text.lastIndexOf('. ', end);
          if (lastPeriod > start + (chunkSize * 0.7)) {
            end = lastPeriod + 2;
          }
        }
      }
      
      chunks.add(text.substring(start, end).trim());
      start = end - overlap;
      if (start < 0) start = 0;
      
      // Avoid infinite loop if overlap >= chunkSize
      if (end >= text.length) break;
    }
    return chunks;
  }

  /// Retrieves the most relevant chunks based on keyword matching.
  List<String> retrieve(String query, List<String> chunks, {int topK = 4}) {
    if (chunks.isEmpty) return [];
    
    final queryTerms = query.toLowerCase()
        .split(RegExp(r'[\s.,!?;:()\[\]{}]+'))
        .where((t) => t.length > 2 && !_stopWords.contains(t))
        .toSet();
        
    if (queryTerms.isEmpty) {
      // If no meaningful terms, return the first few chunks
      return chunks.take(topK).toList();
    }

    List<({String chunk, double score})> scored = chunks.map((chunk) {
      double score = 0;
      final chunkLower = chunk.toLowerCase();
      
      for (var term in queryTerms) {
        // Simple occurrence counting
        final matches = term.allMatches(chunkLower);
        if (matches.isNotEmpty) {
          // Reward term frequency and term length (specificity)
          score += matches.length * term.length;
        }
      }
      return (chunk: chunk, score: score);
    }).toList();

    // Sort by score descending
    scored.sort((a, b) => b.score.compareTo(a.score));
    
    // Log for debugging
    try {
      Get.find<AppLogService>().info(
        'RAG Retrieval: ${queryTerms.length} terms, best score: ${scored.first.score}',
        category: LogCategory.chat
      );
    } catch (_) {}

    return scored
        .where((s) => s.score > 0)
        .take(topK)
        .map((s) => s.chunk)
        .toList();
  }

  static const _stopWords = {
    'the', 'and', 'for', 'that', 'this', 'with', 'from', 'have', 'what', 'where',
    'which', 'there', 'their', 'when', 'then', 'will', 'your', 'about', 'would'
  };
}
