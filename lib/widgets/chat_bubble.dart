import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/chat_message.dart';
import '../utils/thought_parser.dart';
import '../core/colors.dart';
import 'attachment_preview.dart';
import 'code_block.dart';
import 'image_viewer.dart';
import 'thought_disclosure.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onCopy;
  final VoidCallback? onRetry;
  final VoidCallback? onBranch;
  final VoidCallback? onEdit;
  final VoidCallback? onPrevRevision;
  final VoidCallback? onNextRevision;

  const ChatBubble({
    super.key,
    required this.message,
    this.onCopy,
    this.onRetry,
    this.onBranch,
    this.onEdit,
    this.onPrevRevision,
    this.onNextRevision,
  });

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

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Align(
              alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
              child: GestureDetector(
                onLongPress: () => _showContextMenu(context, isUser),
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * (isUser ? 0.82 : 0.92),
                  ),
                  decoration: isUser ? BoxDecoration(
                    gradient: AppColors.userGradient,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(8),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ) : null,
                  child: Padding(
                    padding: isUser 
                        ? const EdgeInsets.symmetric(horizontal: 18, vertical: 14)
                        : const EdgeInsets.symmetric(vertical: 4),
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
                            builders: {
                              'code': CodeBlockBuilder(context),
                              'pre': CodeBlockBuilder(context),
                            },
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

            // Inline action bar
            _buildActionBar(context, isUser, isDark),
          ],
        ),
      ),
    );
  }

  // ── Inline action bar below message ──
  Widget _buildActionBar(BuildContext context, bool isUser, bool isDark) {
    final iconColor = isDark
        ? AppColors.textMuted.withValues(alpha: 0.6)
        : const Color(0xFF94A3B8);
    final mutedColor = isDark
        ? AppColors.textMuted.withValues(alpha: 0.3)
        : const Color(0xFFCBD5E1);
    const double iconSize = 16;
    final revisions = message.revisions;
    final hasRevisions = revisions != null && revisions.isNotEmpty;
    final canPrev = hasRevisions && message.revisionIndex > 0;
    final canNext = hasRevisions && message.revisionIndex < revisions.length - 1;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Revision navigation (prev/next) ──
          if (hasRevisions) ...[
            _actionButton(
              icon: Icons.chevron_left_rounded,
              tooltip: 'Previous version',
              onTap: canPrev ? onPrevRevision! : () {},
              color: canPrev ? iconColor : mutedColor,
              size: iconSize + 4,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                '${message.revisionIndex + 1}/${revisions.length + 1}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  color: iconColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _actionButton(
              icon: Icons.chevron_right_rounded,
              tooltip: 'Next version',
              onTap: canNext ? onNextRevision! : () {},
              color: canNext ? iconColor : mutedColor,
              size: iconSize + 4,
            ),
          ],

          if (isUser) ...[
            // User: Edit + Copy
            if (onEdit != null)
              _actionButton(
                icon: Icons.edit_outlined,
                tooltip: 'Edit',
                onTap: onEdit!,
                color: iconColor,
                size: iconSize,
              ),
            _actionButton(
              icon: Icons.copy_rounded,
              tooltip: 'Copy',
              onTap: () => Clipboard.setData(ClipboardData(text: message.content)),
              color: iconColor,
              size: iconSize,
            ),
          ] else ...[
            // Assistant: Copy + Regenerate + Branch
            _actionButton(
              icon: Icons.copy_rounded,
              tooltip: 'Copy',
              onTap: () => Clipboard.setData(ClipboardData(text: message.content)),
              color: iconColor,
              size: iconSize,
            ),
            if (onRetry != null)
              _actionButton(
                icon: Icons.refresh_rounded,
                tooltip: 'Regenerate',
                onTap: onRetry!,
                color: iconColor,
                size: iconSize,
              ),
            if (onBranch != null)
              _actionButton(
                icon: Icons.call_split_rounded,
                tooltip: 'Branch in new chat',
                onTap: onBranch!,
                color: iconColor,
                size: iconSize,
              ),
          ],
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required Color color,
    required double size,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Icon(icon, size: size, color: color),
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, bool isUser) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final content = message.content;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.surface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16, top: 4),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceLight : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _menuTile(
              icon: Icons.copy_rounded,
              label: 'Copy',
              isDark: isDark,
              onTap: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: content));
              },
            ),
            if (!isUser && onRetry != null)
              _menuTile(
                icon: Icons.refresh_rounded,
                label: 'Regenerate',
                isDark: isDark,
                onTap: () {
                  Navigator.pop(context);
                  onRetry!();
                },
              ),
            if (!isUser && onBranch != null)
              _menuTile(
                icon: Icons.call_split_rounded,
                label: 'Branch in new chat',
                isDark: isDark,
                onTap: () {
                  Navigator.pop(context);
                  onBranch!();
                },
              ),
            const SizedBox(height: 4),
          ]),
        ),
      ),
    );
  }

  Widget _menuTile({
    required IconData icon,
    required String label,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, size: 22, color: isDark ? AppColors.textPrimary : const Color(0xFF0F172A)),
      title: Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600)),
      onTap: onTap,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
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
