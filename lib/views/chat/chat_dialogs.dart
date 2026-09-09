import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import '../../controllers/chat_controller.dart';
import '../../core/colors.dart';
import '../../models/chat_message.dart';
import '../../models/chat_session.dart';
import '../../services/hive_service.dart';
import '../../theme/design_tokens.dart';
import '../../utils/export_file.dart';
import '../../utils/prompt_export.dart';
import '../../utils/web_download.dart';
import '../../widgets/app_ui.dart';

/// Chat dialogs + session export helpers.
/// Extracted from views/chat_view.dart.

ChatController get _c => Get.find<ChatController>();

void confirmDeleteMessage(BuildContext context, ChatMessage msg, bool isDark) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: isDark ? Dt.cardDark : Dt.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('chat_delete_title'.tr,
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
      content: Text('chat_delete_desc'.tr,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: isDark ? AppColors.textSecondary : Dt.textSecondary)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('common_cancel'.tr,
              style: GoogleFonts.plusJakartaSans(
                  color: isDark ? AppColors.textMuted : Dt.textMuted)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: () {
            Navigator.pop(ctx);
            _c.deleteMessage(msg);
          },
          child: Text('common_delete'.tr,
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

void showEditDialog(BuildContext context, ChatMessage msg) {
  // Safety: Clear main input when starting an edit to prevent duplicate triggers
  _c.textController.clear();
  _c.inputText.value = '';

  final editController = TextEditingController(text: msg.content);
  final isDark = Theme.of(context).brightness == Brightness.dark;

  void submit() {
    final newContent = editController.text.trim();
    if (newContent.isNotEmpty && newContent != msg.content) {
      _c.editMessage(msg, newContent);
    }
    Navigator.pop(context);
  }

  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: isDark ? AppColors.surface : Colors.white,
      title: Text('chat_edit_title'.tr,
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
      content: TextField(
        controller: editController,
        maxLines: null,
        minLines: 3,
        autofocus: true,
        style: GoogleFonts.plusJakartaSans(fontSize: 15),
        decoration: InputDecoration(
          hintText: 'chat_edit_hint'.tr,
          hintStyle: GoogleFonts.plusJakartaSans(color: AppColors.textMuted),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary),
          ),
        ),
        onSubmitted: (_) => submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('common_cancel'.tr,
              style: GoogleFonts.plusJakartaSans(color: AppColors.textMuted)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Dt.accent),
          onPressed: submit,
          child: Text('Send',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

// ── Export helpers ──
String buildMarkdownForSession(ChatSession session, List<ChatMessage> msgs) {
  final buf = StringBuffer();
  buf.writeln('# ${session.title}');
  buf.writeln();
  for (final m in msgs) {
    final role = m.role == 'user'
        ? 'User'
        : m.role == 'assistant'
            ? 'Assistant'
            : m.role;
    buf.writeln('$role: ${m.content}');
    buf.writeln();
  }
  return buf.toString();
}

Future<void> exportSession(BuildContext context, ChatSession session) async {
  showAppBottomSheet(
    context,
    builder: (sheetCtx) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppSheetHeader(
                title: 'Export chat',
                onClose: () => Navigator.pop(sheetCtx)),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_rounded, color: AppColors.error),
              title: const Text('Export as PDF'),
              subtitle: const Text('Professional paginated document'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _doExport(context, session, asPdf: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.image_rounded, color: AppColors.success),
              title: const Text('Export as Image'),
              subtitle: const Text('High-resolution screenshot'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _doExport(context, session, asImage: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined, color: AppColors.primary),
              title: const Text('Export as Markdown'),
              subtitle: const Text('Perfect for documentation'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _doExport(context, session);
              },
            ),
            ListTile(
              leading: const Icon(Icons.text_fields_rounded, color: Dt.textSecondary),
              title: const Text('Export as Plain Text'),
              subtitle: const Text('Simple and lightweight'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _doExport(context, session, asTxt: true);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _doExport(BuildContext context, ChatSession session,
    {bool asTxt = false, bool asPdf = false, bool asImage = false}) async {
  try {
    final hive = Get.find<HiveService>();
    final raw = hive.getMessagesForChat(session.id);
    final msgs = raw.map((m) => ChatMessage.fromMap(m)).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (msgs.isEmpty) {
      Get.snackbar('Nothing to export', 'This chat has no messages.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    final safeTitle = session.title
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '_');
    final truncated = (safeTitle.isEmpty ? 'chat' : safeTitle)
        .substring(0, safeTitle.length > 40 ? 40 : safeTitle.length);
    final baseName = '${truncated}_${DateTime.now().millisecondsSinceEpoch}';

    if (asPdf) {
      // ... same as before ...
      try {
        final bytes = await PromptExport.buildPdfBytes(
            buildMarkdownForSession(session, msgs));
        if (kIsWeb) {
          try {
            if (await downloadWebFile(
                bytes, '$baseName.pdf', 'application/pdf')) {
              return;
            }
          } catch (_) {}
          await Share.share(buildMarkdownForSession(session, msgs),
              subject: session.title);
          return;
        }
        final saved = await ExportFile.saveBytes(
          bytes: bytes,
          fileName: '$baseName.pdf',
          dialogTitle: 'Save chat (.pdf)',
          mimeType: 'application/pdf',
        );
        if (saved == null) return; // user cancelled
        Get.snackbar('Chat saved', saved, snackPosition: SnackPosition.BOTTOM);
      } catch (_) {
        await Share.share(buildMarkdownForSession(session, msgs),
            subject: session.title);
      }
      return;
    }

    if (asImage) {
      try {
        await PromptExport.shareAsImage(
          buildMarkdownForSession(session, msgs),
          baseName: truncated,
        );
      } catch (e) {
        Get.snackbar('Image export failed', '$e',
            snackPosition: SnackPosition.BOTTOM);
      }
      return;
    }

    final String body;
    final String fileName;
    final String mimeType;
    if (asTxt) {
      body = buildPlainTextForSession(session, msgs);
      fileName = '$baseName.txt';
      mimeType = 'text/plain';
    } else {
      body = buildMarkdownForSession(session, msgs);
      fileName = '$baseName.md';
      mimeType = 'text/markdown';
    }

    if (kIsWeb) {
      try {
        // Note: the PDF branch returns earlier; this path handles .md/.txt.
        final name = asTxt ? '$baseName.txt' : '$baseName.md';
        if (await downloadWebFile(
            utf8.encode(body), name, asTxt ? 'text/plain' : 'text/markdown')) {
          return;
        }
      } catch (_) {}
      await Share.share(body, subject: session.title);
      return;
    }
    try {
      final saved = await ExportFile.saveText(
        text: body,
        fileName: fileName,
        dialogTitle: 'Save chat (.${asTxt ? 'txt' : 'md'})',
        mimeType: mimeType,
      );
      if (saved == null) return; // user cancelled
      Get.snackbar('Chat saved', saved, snackPosition: SnackPosition.BOTTOM);
    } catch (_) {
      await Share.share(body, subject: session.title);
    }
  } catch (e) {
    Get.snackbar('Export failed', '$e', snackPosition: SnackPosition.BOTTOM);
  }
}

/// Plain-text twin of [buildMarkdownForSession] (no markup).
String buildPlainTextForSession(ChatSession session, List<ChatMessage> msgs) {
  final buf = StringBuffer();
  buf.writeln(session.title);
  buf.writeln('=' * session.title.length);
  buf.writeln();
  for (final m in msgs) {
    final role = m.role == 'user' ? 'User' : 'Assistant';
    buf.writeln('$role:');
    buf.writeln(m.content);
    buf.writeln();
  }
  return buf.toString();
}

void showChatActionsSheet(
    BuildContext context, ChatSession session, bool isDark) {
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
          ListTile(
            leading: Icon(LucideIcons.share2,
                size: 22,
                color: isDark ? AppColors.textPrimary : Dt.textPrimary),
            title: Text('Export as Markdown',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(context);
              _doExport(context, session);
            },
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          ),
          ListTile(
            leading: Icon(LucideIcons.fileText,
                size: 22,
                color: isDark ? AppColors.textPrimary : Dt.textPrimary),
            title: Text('Export as Text (.txt)',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(context);
              _doExport(context, session, asTxt: true);
            },
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          ),
          ListTile(
            leading: Icon(LucideIcons.fileDown,
                size: 22,
                color: isDark ? AppColors.textPrimary : Dt.textPrimary),
            title: Text('Export as PDF',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(context);
              _doExport(context, session, asPdf: true);
            },
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          ),
          ListTile(
            leading: Icon(
              Icons.push_pin_outlined,
              size: 22,
              color: session.pinned
                  ? AppColors.primary
                  : (isDark ? AppColors.textPrimary : Dt.textPrimary),
            ),
            title: Text(session.pinned ? 'Unpin chat' : 'Pin to top',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(context);
              _c.togglePin(session.id);
            },
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          ),
          ListTile(
            leading: Icon(LucideIcons.userCog,
                size: 22,
                color: session.persona.isNotEmpty
                    ? AppColors.primary
                    : (isDark ? AppColors.textPrimary : Dt.textPrimary)),
            title: Text(
                session.persona.isNotEmpty ? 'Edit persona' : 'Set persona…',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            subtitle: session.persona.isNotEmpty
                ? Text(session.persona,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: AppColors.textMuted))
                : null,
            onTap: () {
              Navigator.pop(context);
              showPersonaDialog(context, session, isDark);
            },
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          ),
          ListTile(
            leading: Icon(
              session.archived
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined,
              size: 22,
              color: isDark ? AppColors.textPrimary : Dt.textPrimary,
            ),
            title: Text(session.archived ? 'Unarchive chat' : 'Archive chat',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(context);
              _c.toggleArchive(session.id);
            },
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          ),
          ListTile(
            leading: Icon(Icons.delete_outline_rounded,
                size: 22,
                color: isDark ? AppColors.textPrimary : Dt.textPrimary),
            title: Text('Delete chat',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(context);
              _c.deleteChat(session.id);
            },
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          ),
          const SizedBox(height: 4),
        ]),
      ),
    ),
  );
}

// ── Per-chat persona ──
void showLabelDialog(BuildContext context, ChatSession session, bool isDark) {
  final c = TextEditingController(text: session.label);
  final existing = _c.chatLabels.where((l) => l != session.label).toList();
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: isDark ? AppColors.surface : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Chat label',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: c,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            style: GoogleFonts.plusJakartaSans(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'e.g. work, study…',
              hintStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: AppColors.textMuted),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          if (existing.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final l in existing)
                  ActionChip(
                    label: Text(l,
                        style: GoogleFonts.plusJakartaSans(fontSize: 12)),
                    onPressed: () {
                      _c.setLabel(session.id, l);
                      Navigator.pop(ctx);
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            _c.setLabel(session.id, '');
            Navigator.pop(ctx);
          },
          child: Text('Clear',
              style: GoogleFonts.plusJakartaSans(color: AppColors.textMuted)),
        ),
        FilledButton(
          onPressed: () {
            _c.setLabel(session.id, c.text);
            Navigator.pop(ctx);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

void showPersonaDialog(BuildContext context, ChatSession session, bool isDark) {
  final c = TextEditingController(text: session.persona);
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: isDark ? AppColors.surface : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Chat persona',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Extra instructions for this chat only. Empty = global prompt.',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13, color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            autofocus: true,
            maxLines: 4,
            minLines: 2,
            style: GoogleFonts.plusJakartaSans(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'e.g. Reply like a strict Bengali teacher…',
              hintStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: AppColors.textMuted),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            _c.setPersona(session.id, '');
            Navigator.pop(ctx);
          },
          child: Text('Clear',
              style: GoogleFonts.plusJakartaSans(color: AppColors.textMuted)),
        ),
        FilledButton(
          onPressed: () {
            _c.setPersona(session.id, c.text);
            Navigator.pop(ctx);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  ).then((_) => c.dispose());
}
