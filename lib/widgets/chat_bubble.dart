import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/chat_message.dart';
import '../utils/thought_parser.dart';
import '../core/colors.dart';
import 'attachment_preview.dart';
import 'image_viewer.dart';
import 'thought_disclosure.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final visibleContent = message.fileName == null
        ? message.content
        : message.content.split('\n\nAttached file:').first;
        
    final thoughtParts = isUser
        ? const ThoughtParts(thought: '', answer: '', isThinking: false)
        : splitThoughtTags(_cleanAssistantText(visibleContent));
        
    final answerContent = isUser ? visibleContent : thoughtParts.answer.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.82,
          ),
          decoration: BoxDecoration(
            gradient: isUser ? AppColors.userGradient : null,
            color: isUser ? null : (isDark ? AppColors.surface : const Color(0xFFF1F5F9)),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(22),
              topRight: const Radius.circular(22),
              bottomLeft: Radius.circular(isUser ? 22 : 6),
              bottomRight: Radius.circular(isUser ? 6 : 22),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
            border: isUser ? null : Border.all(
              color: isDark ? AppColors.border : AppColors.borderLightMode,
              width: 0.5,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(22),
              topRight: const Radius.circular(22),
              bottomLeft: Radius.circular(isUser ? 22 : 6),
              bottomRight: Radius.circular(isUser ? 6 : 22),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Image attachment
                  if (message.decodedImageBytes != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: GestureDetector(
                        onTap: () => ImageViewer.show(context, message.imageBase64!),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.memory(
                            message.decodedImageBytes!,
                            width: double.infinity,
                            height: 220,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            errorBuilder: (_, __, ___) => Container(
                              height: 100,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : Colors.black.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Center(child: Icon(Icons.broken_image_rounded, size: 28)),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Thought disclosure
                  if (!isUser && thoughtParts.hasThought)
                    ThoughtDisclosure(
                      thought: thoughtParts.thought,
                      durationSeconds: message.thoughtDurationSeconds,
                      styleSheet: _thoughtMarkdownStyle(context),
                    ),

                  // Message content
                  if (isUser)
                    SelectableText(
                      visibleContent,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        color: Colors.white,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  else if (answerContent.isNotEmpty)
                    MarkdownBody(
                      data: answerContent,
                      selectable: true,
                      styleSheet: _markdownStyle(context),
                    ),

                  // File attachment
                  if (message.fileName != null) ...[
                    const SizedBox(height: 12),
                    AttachmentPreview(
                      fileName: message.fileName!,
                      fileType: message.fileType,
                      fileSize: message.fileSize,
                      imageBase64: message.imageBase64,
                      imagePath: message.imagePath,
                      compact: true,
                    ),
                  ],

                  // Footer info
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.tokensPerSec != null && message.tokensPerSec! > 0)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: _infoBadge(
                            '${message.tokensPerSec!.toStringAsFixed(1)} tok/s',
                            isUser,
                            context,
                          ),
                        ),
                      if (message.imageGenDurationMs != null && message.imageGenDurationMs! > 0)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: _infoBadge(
                            _formatGenTime(message.imageGenDurationMs!),
                            isUser,
                            context,
                          ),
                        ),
                      Text(
                        _formatTime(message.timestamp),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          color: isUser
                              ? Colors.white.withValues(alpha: 0.6)
                              : AppColors.textMuted.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoBadge(String label, bool isUser, BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isUser 
            ? Colors.white.withValues(alpha: 0.15) 
            : AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 9,
          color: isUser ? Colors.white : AppColors.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  MarkdownStyleSheet _markdownStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? AppColors.textPrimary : const Color(0xFF0F172A);
    final muted = isDark ? AppColors.textSecondary : const Color(0xFF475569);
    final base = GoogleFonts.plusJakartaSans(fontSize: 15, color: color, height: 1.6);
    final codeBlockBg = isDark ? AppColors.surfaceLight : const Color(0xFFE2E8F0);

    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: base,
      strong: base.copyWith(fontWeight: FontWeight.w700),
      em: base.copyWith(fontStyle: FontStyle.italic),
      listBullet: base,
      code: GoogleFonts.firaCode(
        fontSize: 13,
        color: color,
        backgroundColor: codeBlockBg,
      ),
      codeblockDecoration: BoxDecoration(
        color: codeBlockBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.1), width: 0.5),
      ),
      codeblockPadding: const EdgeInsets.all(16),
      blockquote: base.copyWith(color: muted),
      blockquoteDecoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.03),
        border: const Border(
          left: BorderSide(
            color: AppColors.primary,
            width: 4,
          ),
        ),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
      ),
      blockquotePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  }

  MarkdownStyleSheet _thoughtMarkdownStyle(BuildContext context) {
    final muted = Theme.of(context).hintColor;
    final base = GoogleFonts.plusJakartaSans(fontSize: 13, color: muted, height: 1.5);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final codeBg = isDark ? AppColors.surfaceLight : const Color(0xFFE2E8F0);

    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: base,
      strong: base.copyWith(fontWeight: FontWeight.w700),
      em: base.copyWith(fontStyle: FontStyle.italic),
      listBullet: base,
      code: GoogleFonts.firaCode(
        fontSize: 11,
        color: muted,
        backgroundColor: codeBg,
      ),
      codeblockDecoration: BoxDecoration(
        color: codeBg,
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }

  String _formatTime(DateTime date) {
    final h = date.hour.toString().padLeft(2, '0');
    final m = date.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatGenTime(int ms) {
    if (ms < 1000) return '${ms}ms';
    if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)}s';
    final m = ms ~/ 60000;
    final s = (ms % 60000) ~/ 1000;
    return s > 0 ? '${m}m ${s}s' : '${m}m';
  }

  String _cleanAssistantText(String text) {
    return text
        .replaceAll('<|endoftext|>', '')
        .replaceAll('<|im_end|>', '')
        .replaceAll('<|end|>', '')
        .trim();
  }
}
