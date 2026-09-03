import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/chat_message.dart';
import '../models/web_source.dart';
import '../utils/thought_parser.dart';
import '../core/colors.dart';
import '../theme/design_tokens.dart';
import '../services/tts_service.dart';
import 'attachment_preview.dart';
import 'code_block.dart';
import 'image_viewer.dart';
import 'thought_disclosure.dart';

class ChatBubble extends StatefulWidget {
  final ChatMessage message;
  final VoidCallback? onCopy;
  final VoidCallback? onRetry;
  final VoidCallback? onBranch;
  final VoidCallback? onEdit;
  final VoidCallback? onPrevRevision;
  final VoidCallback? onNextRevision;
  final VoidCallback? onDelete;

  const ChatBubble({
    super.key,
    required this.message,
    this.onCopy,
    this.onRetry,
    this.onBranch,
    this.onEdit,
    this.onPrevRevision,
    this.onNextRevision,
    this.onDelete,
  });

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.role == 'user';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final visibleContent = widget.message.fileName == null
        ? widget.message.content
        : widget.message.content.split('\n\nAttached file:').first;
        
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
                    // Claude: user message = soft warm surface pill, flat.
                    color: isDark ? Dt.pillMutedDark : Dt.pillMuted,
                    borderRadius: BorderRadius.circular(20),
                  ) : null,
                  child: Padding(
                    padding: isUser
                        ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
                        : const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Image attachment
                        if (widget.message.decodedImageBytes != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: GestureDetector(
                              onTap: () {
                                final b = widget.message.decodedImageBytes;
                                if (b != null) ImageViewer.showBytes(context, b);
                              },
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.memory(
                                  widget.message.decodedImageBytes!,
                                  width: double.infinity,
                                  height: 220,
                                  fit: BoxFit.cover,
                                  // Thumbnail only — decode at ~640px instead
                                  // of full resolution (viewer gets full bytes).
                                  cacheWidth: 640,
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
                            durationSeconds: widget.message.thoughtDurationSeconds,
                            styleSheet: _thoughtMarkdownStyle(context),
                          ),

                        // Message content
                        if (isUser)
                          SelectableText(
                            visibleContent,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              color: isDark ? Colors.white : Dt.textPrimary,
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

                        // Activated skills (intelligent per-prompt)
                        if (!isUser &&
                            widget.message.usedSkills != null &&
                            widget.message.usedSkills!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: _skillsUsedBar(
                                context, widget.message.usedSkills!, isDark),
                          ),

                        // Web sources fetched for this turn
                        if (!isUser &&
                            widget.message.webSources != null &&
                            widget.message.webSources!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: _webSourcesBar(
                                context, widget.message.webSources!, isDark),
                          ),

                        // File attachment
                        if (widget.message.fileName != null) ...[
                          const SizedBox(height: 12),
                          AttachmentPreview(
                            fileName: widget.message.fileName!,
                            fileType: widget.message.fileType,
                            fileSize: widget.message.fileSize,
                            imageBase64: widget.message.imageBase64,
                            imagePath: widget.message.imagePath,
                            compact: true,
                          ),
                        ],

                        // Footer info
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.message.tokensPerSec != null && widget.message.tokensPerSec! > 0)
                              Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: _infoBadge(
                                  '${widget.message.tokensPerSec!.toStringAsFixed(1)} tok/s',
                                  isUser,
                                  context,
                                ),
                              ),
                            if (widget.message.imageGenDurationMs != null && widget.message.imageGenDurationMs! > 0)
                              Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: _infoBadge(
                                  _formatGenTime(widget.message.imageGenDurationMs!),
                                  isUser,
                                  context,
                                ),
                              ),
                            if (widget.message.generationDurationMs != null && widget.message.generationDurationMs! > 0)
                              Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: _infoBadge(
                                  _formatGenTime(widget.message.generationDurationMs!),
                                  isUser,
                                  context,
                                  icon: Icons.timer_outlined,
                                ),
                              ),
                            Text(
                              _formatTime(widget.message.timestamp),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                color: isUser
                                    ? Dt.textMuted.withValues(alpha: 0.8)
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
        : Dt.textMuted;
    final mutedColor = isDark
        ? AppColors.textMuted.withValues(alpha: 0.3)
        : Dt.toggleTrackOff;
    const double iconSize = 16;
    final revisions = widget.message.revisions;
    final hasRevisions = revisions != null && revisions.isNotEmpty;
    final canPrev = hasRevisions && widget.message.revisionIndex > 0;
    final canNext = hasRevisions && widget.message.revisionIndex < revisions.length - 1;

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
              onTap: canPrev ? widget.onPrevRevision! : () {},
              color: canPrev ? iconColor : mutedColor,
              size: iconSize + 4,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                '${widget.message.revisionIndex + 1}/${revisions.length + 1}',
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
              onTap: canNext ? widget.onNextRevision! : () {},
              color: canNext ? iconColor : mutedColor,
              size: iconSize + 4,
            ),
          ],

          if (isUser) ...[
            // User: Edit + Copy + Share
            if (widget.onEdit != null)
              _actionButton(
                icon: Icons.edit_outlined,
                tooltip: 'Edit',
                onTap: widget.onEdit!,
                color: iconColor,
                size: iconSize,
              ),
            _actionButton(
              icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
              tooltip: _copied ? 'Copied!' : 'Copy',
              onTap: () {
                Clipboard.setData(ClipboardData(text: widget.message.content));
                HapticFeedback.selectionClick();
                setState(() => _copied = true);
                Future.delayed(const Duration(seconds: 2), () {
                  if (mounted) setState(() => _copied = false);
                });
              },
              color: iconColor,
              size: iconSize,
            ),
            _actionButton(
              icon: Icons.ios_share_rounded,
              tooltip: 'Share',
              onTap: () {
                final text = widget.message.content.trim();
                if (text.isNotEmpty) Share.share(text);
              },
              color: iconColor,
              size: iconSize,
            ),
          ] else ...[
            // Assistant: Copy + Read aloud + Share + Regenerate + Branch
            _actionButton(
              icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
              tooltip: _copied ? 'Copied!' : 'Copy',
              onTap: () {
                Clipboard.setData(ClipboardData(text: widget.message.content));
                HapticFeedback.selectionClick();
                setState(() => _copied = true);
                Future.delayed(const Duration(seconds: 2), () {
                  if (mounted) setState(() => _copied = false);
                });
              },
              color: iconColor,
              size: iconSize,
            ),
            if (!kIsWeb) _buildTtsButton(iconColor, iconSize),
            _actionButton(
              icon: Icons.ios_share_rounded,
              tooltip: 'Share',
              onTap: () {
                final text = widget.message.content.trim();
                if (text.isNotEmpty) Share.share(text);
              },
              color: iconColor,
              size: iconSize,
            ),
            if (widget.onRetry != null)
              _actionButton(
                icon: Icons.refresh_rounded,
                tooltip: 'Regenerate',
                onTap: widget.onRetry!,
                color: iconColor,
                size: iconSize,
              ),
            if (widget.onBranch != null)
              _actionButton(
                icon: Icons.call_split_rounded,
                tooltip: 'Branch in new chat',
                onTap: widget.onBranch!,
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
    return Semantics(
      label: tooltip,
      button: true,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Icon(icon, size: size, color: color),
          ),
        ),
      ),
    );
  }

  Widget _buildTtsButton(Color iconColor, double iconSize) {
    // Resolve the speakable text (answer without thinking tags / file footer).
    String resolveSpeakText() {
      final visible = widget.message.fileName == null
          ? widget.message.content
          : widget.message.content.split('\n\nAttached file:').first;
      final parts = splitThoughtTags(_cleanAssistantText(visible));
      final answer = parts.answer.trim();
      return answer.isEmpty ? widget.message.content : answer;
    }

    if (kIsWeb) return const SizedBox.shrink();
    if (!Get.isRegistered<TtsService>()) {
      return _actionButton(
        icon: Icons.volume_up_rounded,
        tooltip: 'Read aloud',
        onTap: () {
          if (Get.isRegistered<TtsService>()) {
            Get.find<TtsService>().speak(resolveSpeakText());
          }
        },
        color: iconColor,
        size: iconSize,
      );
    }
    return Obx(() {
      final tts = Get.find<TtsService>();
      final isSpeaking = tts.isSpeaking.value;
      return _actionButton(
        icon: isSpeaking ? Icons.stop_rounded : Icons.volume_up_rounded,
        tooltip: isSpeaking ? 'Stop' : 'Read aloud',
        onTap: () => tts.speak(resolveSpeakText()),
        color: iconColor,
        size: iconSize,
      );
    });
  }

  void _showContextMenu(BuildContext context, bool isUser) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final content = widget.message.content;
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
                color: isDark ? AppColors.surfaceLight : Dt.hairline,
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
                HapticFeedback.selectionClick();
              },
            ),
            _menuTile(
              icon: Icons.ios_share_rounded,
              label: 'Share',
              isDark: isDark,
              onTap: () {
                Navigator.pop(context);
                final text = content.trim();
                if (text.isNotEmpty) Share.share(text);
              },
            ),
            if (!isUser && !kIsWeb)
              _menuTile(
                icon: Icons.volume_up_rounded,
                label: 'Read aloud',
                isDark: isDark,
                onTap: () {
                  Navigator.pop(context);
                  if (Get.isRegistered<TtsService>()) {
                    final visible = widget.message.fileName == null
                        ? widget.message.content
                        : widget.message.content.split('\n\nAttached file:').first;
                    final parts = splitThoughtTags(_cleanAssistantText(visible));
                    final text = parts.answer.trim().isEmpty ? widget.message.content : parts.answer.trim();
                    Get.find<TtsService>().speak(text);
                  }
                },
              ),
            if (!isUser && widget.onRetry != null)
              _menuTile(
                icon: Icons.refresh_rounded,
                label: 'Regenerate',
                isDark: isDark,
                onTap: () {
                  Navigator.pop(context);
                  widget.onRetry!();
                },
              ),
            if (!isUser && widget.onBranch != null)
              _menuTile(
                icon: Icons.call_split_rounded,
                label: 'Branch in new chat',
                isDark: isDark,
                onTap: () {
                  Navigator.pop(context);
                  widget.onBranch!();
                },
              ),
            if (widget.onDelete != null)
              _menuTile(
                icon: Icons.delete_outline_rounded,
                label: 'Delete message',
                isDark: isDark,
                onTap: () {
                  Navigator.pop(context);
                  widget.onDelete!();
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
      leading: Icon(icon, size: 22, color: isDark ? AppColors.textPrimary : Dt.textPrimary),
      title: Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600)),
      onTap: onTap,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
    );
  }

  Widget _skillsUsedBar(
      BuildContext context, List<String> skills, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: Dt.accent.withValues(alpha: isDark ? 0.08 : 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Dt.accent.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Dt.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(LucideIcons.sparkles,
                  size: 12, color: Dt.accent),
            ),
            const SizedBox(width: 6),
            Text('Skills used',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    color: Dt.accent)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Dt.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('${skills.length}',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Dt.accent)),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: skills
                .map((name) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Dt.accent.withValues(alpha: 0.18)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.check,
                              size: 10, color: Dt.accent),
                          const SizedBox(width: 4),
                          Text(name,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? Colors.white
                                      : Dt.textPrimary)),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _webSourcesBar(
      BuildContext context, List<WebSource> sources, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(LucideIcons.link2,
                  size: 12, color: Color(0xFF3B82F6)),
            ),
            const SizedBox(width: 6),
            Text('Sources',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    color: const Color(0xFF3B82F6))),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('${sources.length}',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF3B82F6))),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: sources.map((src) {
              return InkWell(
                onTap: () async {
                  final uri = Uri.tryParse(src.url);
                  if (uri != null) {
                    try {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    } catch (_) {}
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.06)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.network(
                          src.faviconUrl,
                          width: 14,
                          height: 14,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: const Color(0xFF3B82F6)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Icon(LucideIcons.globe,
                                size: 8, color: Color(0xFF3B82F6)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(src.domain,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? Colors.white
                                        : Dt.textPrimary)),
                            if (src.title.isNotEmpty &&
                                src.title != src.domain)
                              Text(src.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 10,
                                      color: Theme.of(context).hintColor)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(LucideIcons.externalLink,
                          size: 10,
                          color: Theme.of(context).hintColor),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _infoBadge(String label, bool isUser, BuildContext context, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isUser
            ? Dt.textPrimary.withValues(alpha: 0.06)
            : Dt.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: isUser ? Dt.textSecondary : Dt.accent),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 9,
              color: isUser ? Dt.textSecondary : Dt.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  MarkdownStyleSheet _markdownStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? AppColors.textPrimary : Dt.textPrimary;
    final muted = isDark ? AppColors.textSecondary : Dt.textSecondary;
    // Assistant body reads in a serif — Claude's signature editorial voice.
    final base = GoogleFonts.sourceSerif4(fontSize: 15.5, color: color, height: 1.6);

    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: base,
      pPadding: const EdgeInsets.only(bottom: 12),
      h1: base.copyWith(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5),
      h2: base.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
      h3: base.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
      strong: base.copyWith(fontWeight: FontWeight.w700),
      em: base.copyWith(fontStyle: FontStyle.italic),
      listBullet: base,
      listIndent: 24,
      code: GoogleFonts.firaCode(
        fontSize: 13,
        color: color,
      ),
      codeblockDecoration: const BoxDecoration(),
      codeblockPadding: EdgeInsets.zero,
      blockquote: base.copyWith(color: muted, fontSize: 14),
      blockquoteDecoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.03),
        border: const Border(
          left: BorderSide(
            color: AppColors.primary,
            width: 3,
          ),
        ),
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
    );
  }

  MarkdownStyleSheet _thoughtMarkdownStyle(BuildContext context) {
    final muted = Theme.of(context).hintColor;
    final base = GoogleFonts.plusJakartaSans(fontSize: 13, color: muted, height: 1.5);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final codeBg = isDark ? AppColors.surfaceLight : Dt.hairline;

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
