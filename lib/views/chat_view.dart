import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../controllers/chat_controller.dart';
import '../models/chat_message.dart';
import '../controllers/settings_controller.dart';
import '../controllers/model_controller.dart';
import '../controllers/home_controller.dart';
import '../services/inference_service.dart';
import '../services/local_image_service.dart';
import '../ffi/sd_ffi_bindings.dart';
import '../utils/thought_parser.dart';
import '../widgets/attachment_preview.dart';
import '../widgets/app_ui.dart';
import '../theme/design_tokens.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/model_switcher_sheet.dart';
import '../widgets/thought_disclosure.dart';
import '../core/colors.dart';

class ChatView extends GetView<ChatController> {
  ChatView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? Dt.canvasDark : Dt.canvas,
      drawer: _buildSidebar(context, isDark),
      appBar: _appBar(context, isDark),
      body: Column(
        children: [
          _modelLoadingBar(context, isDark),
          _contextBar(context, isDark),
          Expanded(child: Obx(() {
            if (controller.currentSessionId.value.isEmpty ||
                controller.messages.isEmpty) {
              return _emptyState(context, isDark);
            }
            final streaming = controller.isStreaming.value;
            final text = controller.streamingResponse.value;
            final n = controller.messages.length;
            return Stack(
              children: [
                NotificationListener<ScrollUpdateNotification>(
                  onNotification: (note) {
                    if (note.dragDetails != null && streaming) {
                      if ((note.scrollDelta ?? 0) < 0) {
                        controller.pauseStreamingFollow();
                      } else {
                        controller.resumeStreamingFollowIfNearBottom();
                      }
                    }
                    return false;
                  },
                  child: ListView.builder(
                    controller: controller.scrollController,
                    padding: const EdgeInsets.only(top: 12, bottom: 12),
                    itemCount: n + (streaming ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == n && streaming) {
                        return _streamBubble(context, text, isDark);
                      }
                       final msg = controller.messages[i];
                       final hasRevisions = msg.revisions != null && msg.revisions!.isNotEmpty;
                       return ChatBubble(
                         message: msg,
                         onCopy: () {
                           Clipboard.setData(ClipboardData(text: msg.content));
                         },
                         onRetry: () => controller.regenerateFromMessage(msg),
                         onBranch: () => controller.branchNewChat(msg),
                         onEdit: msg.role == 'user'
                             ? () => _showEditDialog(context, msg)
                             : null,
                         onPrevRevision: hasRevisions && msg.revisionIndex > 0
                             ? () => controller.navigateRevision(msg, -1)
                             : null,
                         onNextRevision: hasRevisions && msg.revisionIndex < msg.revisions!.length - 1
                             ? () => controller.navigateRevision(msg, 1)
                             : null,
                       );
                    },
                  ),
                ),
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: Obx(() => AnimatedScale(
                        scale: controller.showScrollToBottom.value ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutBack,
                        child: FloatingActionButton.small(
                          onPressed: controller.jumpToBottom,
                          backgroundColor: isDark ? Dt.cardDark : Dt.card,
                          foregroundColor: AppColors.primary,
                          elevation: 4,
                          child: const Icon(Icons.arrow_downward_rounded, size: 20),
                        ),
                      )),
                ),
              ],
            );
          })),
          _inputBar(context, isDark),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, ChatMessage msg) {
    // Safety: Clear main input when starting an edit to prevent duplicate triggers
    controller.textController.clear();
    controller.inputText.value = '';
    
    final editController = TextEditingController(text: msg.content);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    void submit() {
      final newContent = editController.text.trim();
      if (newContent.isNotEmpty && newContent != msg.content) {
        controller.editMessage(msg, newContent);
      }
      Navigator.pop(context);
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? AppColors.surface : Colors.white,
        title: Text('Edit message',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: editController,
          maxLines: null,
          minLines: 3,
          autofocus: true,
          style: GoogleFonts.plusJakartaSans(fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Edit your message...',
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
            child: Text('Cancel',
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

  // ── AppBar ──
  PreferredSizeWidget _appBar(BuildContext context, bool isDark) {
    return AppBar(
      backgroundColor: (isDark ? Dt.canvasDark : Dt.canvas).withValues(alpha: 0.8),
      flexibleSpace: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(color: Colors.transparent),
        ),
      ),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleSpacing: 0,
      title: Obx(() {
        final sid = controller.currentSessionId.value;
        final settings = Get.find<SettingsController>();
        final inf = Get.find<InferenceService>();
        final isLocal = settings.inferenceMode.value == 'local';
        final localImage = Get.find<LocalImageService>();
        // A loaded image model counts as "ready" too — otherwise the dot shows
        // the warning colour while an image engine is happily resident.
        final isLocalReady =
            inf.isModelLoaded.value || localImage.isModelLoaded.value;
        String model;
        if (isLocal) {
          if (inf.isModelLoaded.value) {
            model = inf.loadedModelName.value
                .replaceAll('.gguf', '')
                .replaceAll('.GGUF', '');
          } else if (localImage.isModelLoaded.value) {
            final backend = localImage.currentBackend.value;
            final backendEmoji = backend == Backend.cpu ? '🖥' : '⚡';
            final backendName = backend.displayName.split(' ').first;
            model =
                '$backendEmoji $backendName · ${localImage.loadedModelName.value.replaceAll('.gguf', '').replaceAll('.GGUF', '')}';
          } else {
            model = 'No model loaded';
          }
          if (model.length > 24) model = '${model.substring(0, 24)}…';
        } else {
          // Single source of truth for the cloud label, shared with the model
          // switcher sheet so the two can't drift.
          model = settings.selectedCloudModelName;
          if (settings.cloudProvider.value == 'custom' && model.isNotEmpty) {
            model = '${settings.customCloudName.value}: $model';
          }
        }
        final statusColor = isLocal
            ? (isLocalReady ? AppColors.success : AppColors.warning)
            : AppColors.primary;
        final title = sid.isEmpty
            ? 'CubicLM'
            : controller.sessions.firstWhereOrNull((s) => s.id == sid)?.title ??
                'Chat';
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    letterSpacing: -0.5,
                    color: isDark ? AppColors.textPrimary : const Color(0xFF0F172A)),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            InkWell(
              onTap: () => showModelSwitcherSheet(context),
              borderRadius: BorderRadius.circular(8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: statusColor.withValues(alpha: 0.4),
                            blurRadius: 4,
                          )
                        ],
                        color: statusColor)),
                const SizedBox(width: 6),
                Flexible(
                    child: Text('$model · ${isLocal ? "Local" : "Cloud"}',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: Theme.of(context).hintColor,
                            fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 2),
                Icon(Icons.expand_more_rounded,
                    size: 16, color: Theme.of(context).hintColor),
              ]),
            ),
          ]),
        );
      }),
      leading: Builder(
        builder: (ctx) => IconButton(
          icon: Icon(LucideIcons.menu,
              size: Dt.iconSize - 2,
              color: isDark ? AppColors.textPrimary : Dt.iconDefault),
          onPressed: () => Scaffold.of(ctx).openDrawer(),
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: IconButton(
              tooltip: 'New Chat',
              icon: Icon(LucideIcons.messageSquarePlus,
                  size: Dt.iconSize - 2,
                  color: isDark ? AppColors.primary : Dt.accent),
              onPressed: () => controller.createNewChat()),
        ),
      ],
    );
  }

  // ── Model Loading ──
  Widget _modelLoadingBar(BuildContext context, bool isDark) {
    return Obx(() {
      final inf = Get.find<InferenceService>();
      if (!inf.isLoadingModel.value) return const SizedBox.shrink();
      final pct = (inf.modelLoadProgress.value * 100).toStringAsFixed(0);
      return ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
            decoration: BoxDecoration(
              color: (isDark ? AppColors.surface : Colors.white).withValues(alpha: 0.8),
              border: Border(bottom: BorderSide(color: isDark ? AppColors.border : AppColors.borderLightMode, width: 1)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: AppColors.primary)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Synchronizing Intelligence… $pct%',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          color: isDark ? AppColors.textPrimary : const Color(0xFF0F172A),
                          fontWeight: FontWeight.w800)),
                ),
              ]),
              const SizedBox(height: 14),
              Stack(
                children: [
                  ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                          value: inf.modelLoadProgress.value,
                          backgroundColor: isDark ? Dt.pillMutedDark : Dt.pillMuted,
                          color: AppColors.primary,
                          minHeight: 6)),
                  if (inf.modelLoadProgress.value > 0.05)
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: inf.modelLoadProgress.value,
                          child: Container(
                            decoration: BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(alpha: 0.4),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                )
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ]),
          ),
        ),
      );
    });
  }

  // ── Context Bar ──
  Widget _contextBar(BuildContext context, bool isDark) {
    return Obx(() {
      final settings = Get.find<SettingsController>();
      final inf = Get.find<InferenceService>();
      final active = controller.currentSessionId.value.isNotEmpty &&
          controller.messages.isNotEmpty;
      if (!active || settings.inferenceMode.value != 'local') {
        return const SizedBox.shrink();
      }
      final total = inf.contextTokensTotal.value > 0
          ? inf.contextTokensTotal.value
          : settings.contextSize.value;
      final est =
          controller.messages.fold<int>(0, (s, m) => s + m.content.length);
      final used = (inf.contextTokensUsed.value > 0
              ? inf.contextTokensUsed.value
              : (est / 4).ceil())
          .clamp(0, total)
          .toInt();
      final pct = total == 0 ? 0.0 : (used / total).clamp(0.0, 1.0).toDouble();
      final warn = pct >= 0.75;
      final accent = warn ? AppColors.warning : AppColors.primary;
      
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
          ),
        ),
        child: Row(children: [
          Icon(Icons.query_stats_rounded, size: 14, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Context Usage',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            color: Theme.of(context).hintColor,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2)),
                    Text('${_fmtK(used)} / ${_fmtK(total)} tokens',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            color: accent,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                        value: pct,
                        backgroundColor: isDark ? Dt.cardDark : Dt.card,
                        color: accent,
                        minHeight: 3)),
              ],
            ),
          ),
        ]),
      );
    });
  }

  // ── Empty State ──
  Widget _emptyState(BuildContext context, bool isDark) {
    final suggestions = [
      {'text': 'Explain quantum computing simply', 'icon': Icons.auto_awesome_rounded, 'color': Colors.blue},
      {'text': 'Write a short poem about time', 'icon': Icons.edit_note_rounded, 'color': Colors.purple},
      {'text': 'What makes the Northern Lights happen?', 'icon': Icons.light_mode_rounded, 'color': Colors.teal},
      {'text': 'Give me a 5-minute healthy breakfast recipe', 'icon': Icons.restaurant_rounded, 'color': Colors.orange},
    ];
    return Center(
        child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Small brand mark (reference: ~7% of screen width, no glow)
        Hero(
          tag: 'app_logo',
          child: Image.asset(
            'assets/icons/CubicLM.png',
            width: 64,
            height: 64,
          ),
        ),
        const SizedBox(height: 20),
        Text('What shall we explore?',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
                color: isDark ? AppColors.textPrimary : Dt.textPrimary)),
        const SizedBox(height: 8),
        Text('Start typing below or pick a topic.',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: Dt.textSecondary,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 28),
        Obx(() {
          final settings = Get.find<SettingsController>();
          final models = Get.find<ModelController>();
          final isLocal = settings.inferenceMode.value == 'local';
          if (isLocal && models.downloadedCount == 0) {
            return Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.2), width: 1.5),
              ),
              child: Column(children: [
                const Icon(Icons.cloud_download_rounded,
                    color: AppColors.warning, size: 48),
                const SizedBox(height: 16),
                Text('No Local Models Found',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black)),
                const SizedBox(height: 10),
                Text(
                    'Download a model to enable offline AI processing on your device.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14, color: Theme.of(context).hintColor, height: 1.5)),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: () => Get.find<HomeController>().changeTab(1),
                  icon: const Icon(Icons.arrow_right_alt_rounded, size: 22),
                  label: const Text('Go to Model Hub'),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.warning,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                ),
              ]),
            );
          }
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.5,
            ),
            itemCount: suggestions.length,
            itemBuilder: (ctx, i) {
              final s = suggestions[i];
              return _suggestionCard(
                context, 
                s['text'] as String, 
                s['icon'] as IconData, 
                s['color'] as Color,
                isDark
              );
            },
          );
        }),
      ]),
    ));
  }

  Widget _suggestionCard(BuildContext context, String text, IconData icon, Color color, bool isDark) {
    return InkWell(
      onTap: () {
        controller.createNewChat();
        controller.textController.text = text;
        controller.inputText.value = text;
        controller.sendMessage();
      },
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surface : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            Text(text,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: isDark ? AppColors.textPrimary : const Color(0xFF0F172A),
                    fontWeight: FontWeight.w700,
                    height: 1.3),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  // ── Streaming Bubble ──
  Widget _streamBubble(BuildContext context, String text, bool isDark) {
    final attType = controller.streamingAttachmentType.value;
    final isImageGen = controller.imageGenTotal.value > 0;
    final clean = _cleanStream(text).trimLeft();
    final parts = splitThoughtTags(clean);
    final answer = parts.answer.trimLeft();
    final hasText = parts.hasThought || _hasPrintable(answer);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.82),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: isDark ? Dt.cardDark : Dt.card,
            border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : Dt.hairline),
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
                bottomRight: Radius.circular(24),
                bottomLeft: Radius.circular(8)),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (isImageGen)
              _ImageGenIndicator(controller: controller, isDark: isDark)
            else if (!hasText)
              _typingHint(context, isDark, attachmentType: attType)
            else ...[
              if (parts.hasThought)
                ThoughtDisclosure(
                    thought: parts.thought,
                    isThinking: parts.isThinking,
                    styleSheet: _thoughtMd(context, isDark)),
              if (_hasPrintable(answer))
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                      child: MarkdownBody(
                          data: answer,
                          selectable: true,
                          styleSheet: _streamMd(context, isDark))),
                  const _BlinkingCursor(color: AppColors.primary),
                ]),
            ],
            if (hasText && !isImageGen)
              Obx(() {
                final inf = Get.find<InferenceService>();
                final tps = inf.tokensPerSecond.value;
                final duration = controller.generationLiveDurationSecs.value;
                if (tps <= 0 && duration <= 0) {
                  return const SizedBox.shrink();
                }
                return Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (tps > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                                '${tps.toStringAsFixed(1)} tok/s',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700)),
                          ),
                        if (tps > 0 && duration > 0) const SizedBox(width: 8),
                        if (duration > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const _PulsingTimerDot(),
                                const SizedBox(width: 4),
                                Text(
                                    '${duration}s',
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 10,
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w800)),
                              ],
                            ),
                          ),
                      ],
                    ));
              }),
          ]),
        ),
      ),
    );
  }

  Widget _typingHint(BuildContext context, bool isDark,
      {String? attachmentType}) {
    final msg = attachmentType == 'image'
        ? 'Analyzing image…'
        : attachmentType == 'audio'
            ? 'Processing audio…'
            : null;
    if (msg == null) return _TypingDots(isDark: isDark);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _TypingDots(isDark: isDark),
      const SizedBox(width: 12),
      Flexible(
          child: Text(msg,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: Theme.of(context).hintColor,
                  fontWeight: FontWeight.w600))),
    ]);
  }

  // ── Input Bar ──
  Widget _inputBar(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      color: Colors.transparent,
      child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Attachment preview
                Obx(() {
                  final name = controller.selectedFileName.value;
                  if (name == null) return const SizedBox.shrink();
                  return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AttachmentPreview(
                        fileName: name,
                        fileType: controller.selectedFileType.value,
                        fileSize: controller.selectedFileSize.value > 0
                            ? controller.selectedFileSize.value
                            : null,
                        imagePath: controller.selectedImagePath.value,
                        imageBase64: controller.selectedImageBase64.value,
                        onRemove: () {
                          controller.clearImage();
                          controller.clearFile();
                        },
                      ));
                }),
                // STT listening indicator
                Obx(() {
                  if (!controller.isListening.value) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const _PulsingDot(),
                        const SizedBox(width: 10),
                        Text('System listening… tap to end',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: AppColors.error,
                                fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  );
                }),
                // Image Gen Settings
                Obx(() {
                  final settings = Get.find<SettingsController>();
                  final localImage = Get.find<LocalImageService>();
                  if (settings.inferenceMode.value != 'local' ||
                      !localImage.isModelLoaded.value) {
                    return const SizedBox.shrink();
                  }
                  final steps = settings.imageSteps.value;
                  final size = settings.imageGenSize.value;
                  final sizeLabel = size == 0 ? 'Auto' : '${size}px';
                  final backend = localImage.currentBackend.value;
                  final backendLabel = backend == Backend.cpu
                      ? 'CPU'
                      : backend.displayName.split(' ').first.toUpperCase();
                  final accent = backend == Backend.cpu
                      ? AppColors.warning
                      : AppColors.success;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: accent.withValues(alpha: 0.2)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.auto_awesome_rounded,
                                    size: 14, color: accent),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'Generation Mode · $steps steps · $sizeLabel · $backendLabel',
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      color: accent,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          height: 34,
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.surface : Colors.white,
                            borderRadius: BorderRadius.circular(17),
                            border: Border.all(color: isDark ? AppColors.border : AppColors.borderLightMode),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _StepButton(
                                icon: Icons.remove_rounded,
                                enabled: steps > 1,
                                onTap: () => settings.setImageSteps(steps - 1),
                              ),
                              Text(
                                steps.toString(),
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: isDark ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              _StepButton(
                                icon: Icons.add_rounded,
                                enabled: steps < 20,
                                onTap: () => settings.setImageSteps(steps + 1),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surface : Dt.card,
                    borderRadius: BorderRadius.circular(Dt.rComposer),
                    border: isDark
                        ? Border.all(color: Colors.white.withValues(alpha: 0.08))
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                   child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // ── Dismissible upsell pill (inside card, per reference) ──
                    Obx(() {
                      final s = Get.find<SettingsController>();
                      if (s.composerUpsellDismissed.value) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                        child: Container(
                          height: 32,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Dt.pillMuted,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(children: [
                            Expanded(
                              child: Text('Unlock every cloud model',
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? AppColors.textSecondary
                                          : Dt.textSecondary)),
                            ),
                            GestureDetector(
                              onTap: () {
                                Get.find<HomeController>().changeTab(1);
                              },
                              child: Text('Add API keys',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: Dt.link)),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: s.dismissComposerUpsell,
                              child: Icon(LucideIcons.x,
                                  size: 14, color: Dt.textSecondary),
                            ),
                          ]),
                        ),
                      );
                    }),
                    // ── Text field: full-width, ABOVE the controls row (cursor starts here) ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
                      child: TextField(
                        controller: controller.textController,
                        onChanged: (v) => controller.inputText.value = v,
                        maxLines: 6,
                        minLines: 1,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            height: 1.35,
                            color: isDark ? AppColors.textPrimary : Dt.textPrimary,
                            fontWeight: FontWeight.w500),
                        decoration: InputDecoration(
                          hintText: 'Message CubicLM…',
                          hintStyle: GoogleFonts.plusJakartaSans(
                              fontSize: 16,
                              color: Dt.textPlaceholder,
                              fontWeight: FontWeight.w500),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                          isDense: true,
                          fillColor: Colors.transparent,
                        ),
                      ),
                    ),
                    // ── Controls row: + / model pill … mic / send ──
                    Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    // "+" opens the Add-to-Chat sheet (attachments, web access)
                    AppCircleButton(
                      icon: LucideIcons.plus,
                      tooltip: 'Add to chat',
                      onTap: () => _showAddToChatSheet(
                        context,
                        isDark: isDark,
                        onCamera: controller.takePhoto,
                        onImage: controller.pickImage,
                        onFile: controller.pickFile,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Model selector pill
                    AppModelPill(
                      label: _composerModelLabel(),
                      onTap: () => showModelSwitcherSheet(context),
                    ),
                    const Spacer(),
                    // Right cluster: mic (muted circle) + primary CTA (solid dark)
                    Obx(() {
                      final loading = controller.isLoading.value;
                      final listening = controller.isListening.value;
                      final hasContent = controller.inputText.value.isNotEmpty ||
                          controller.selectedFileName.value != null ||
                          controller.selectedImagePath.value != null;

                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!loading && !hasContent)
                            AppCircleButton(
                              icon: LucideIcons.mic,
                              tooltip: 'Voice input',
                              iconColor: listening ? AppColors.error : null,
                              onTap: controller.toggleListening,
                            ),
                          if (!loading && !hasContent) const SizedBox(width: 8),
                          AppCtaButton(
                            icon: loading
                                ? LucideIcons.square
                                : LucideIcons.arrowUp,
                            onTap: loading
                                ? controller.stopGenerating
                                : (hasContent ? controller.sendMessage : null),
                          ),
                        ],
                      );
                    }),
                    ]),
                  ]),
                ),
              ])),
    );
  }

  // ── Sidebar Drawer ──

  /// Short label for the composer's model pill.
  String _composerModelLabel() {
    final s = Get.find<SettingsController>();
    if (s.inferenceMode.value == 'cloud') {
      final m = s.selectedCloudModelName;
      if (m.isEmpty) return 'Cloud';
      final short = m.contains('/') ? m.split('/').last : m;
      return short.length > 18 ? '${short.substring(0, 18)}…' : short;
    }
    final inf = Get.find<InferenceService>();
    final img = Get.find<LocalImageService>();
    final name = inf.isModelLoaded.value
        ? inf.loadedModelName.value
        : img.isModelLoaded.value
            ? img.loadedModelName.value
            : '';
    if (name.isEmpty) return 'Local';
    final stripped = name.replaceAll(RegExp(r'\.(gguf|litertlm|safetensors)$', caseSensitive: false), '');
    return stripped.length > 18 ? '${stripped.substring(0, 18)}…' : stripped;
  }

  /// "+" sheet per reference spec §2.3: three equal tiles, then stacked
  /// row-cards — including the Web-access toggle that used to sit in the
  /// composer bar.
  void _showAddToChatSheet(
    BuildContext context, {
    required bool isDark,
    required VoidCallback onCamera,
    required VoidCallback onImage,
    required VoidCallback onFile,
  }) {
    showAppBottomSheet(
      context,
      builder: (sheetCtx) {
        final s = Get.find<SettingsController>();
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppSheetHeader(title: 'Add to chat', onClose: () => Navigator.pop(sheetCtx)),
                const SizedBox(height: 6),
                Row(children: [
                  _AddTile(icon: LucideIcons.camera, label: 'Camera', onTap: () { Navigator.pop(sheetCtx); onCamera(); }),
                  const SizedBox(width: 8),
                  _AddTile(icon: LucideIcons.image, label: 'Photos', onTap: () { Navigator.pop(sheetCtx); onImage(); }),
                  const SizedBox(width: 8),
                  _AddTile(icon: LucideIcons.fileUp, label: 'Files', onTap: () { Navigator.pop(sheetCtx); onFile(); }),
                ]),
                const SizedBox(height: 12),
                // ── Choose model row (drills into the switcher) ──
                AppSheetRowCard(
                  leading: const AppIconCircle(icon: LucideIcons.box),
                  title: 'Choose model',
                  subtitle: _composerModelLabel(),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    showModelSwitcherSheet(context);
                  },
                  trailing: Icon(LucideIcons.chevronRight,
                      size: 18, color: Dt.textSecondary),
                ),
                const SizedBox(height: 10),
                Obx(() => AppSheetRowCard(
                      leading: const AppIconCircle(icon: LucideIcons.globe),
                      title: 'Web access',
                      subtitle: 'Read links from your message into context',
                      trailing: Switch(
                        value: s.webFetchEnabled.value,
                        activeTrackColor:
                            Theme.of(sheetCtx).brightness == Brightness.dark
                                ? null
                                : Dt.toggleTrackOn,
                        onChanged: (v) => s.setWebFetchEnabled(v),
                      ),
                    )),
              ],
            ),
          ),
        );
      },
    );
  }

  final RxString _sidebarQuery = ''.obs;
  Widget _buildSidebar(BuildContext context, bool isDark) {
    return Drawer(
      backgroundColor: isDark ? AppColors.bg : Dt.sidebar,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.horizontal(right: Radius.circular(Dt.rDrawerEdge))),
      child: SafeArea(
        child: StatefulBuilder(
          builder: (context, setState) {
            return _sidebarContent(context, isDark, setState);
          },
        ),
      ),
    );
  }

  Widget _sidebarContent(BuildContext context, bool isDark, StateSetter setState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/icons/CubicLM.png',
                width: 32, height: 32, fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
            Text('CubicLM',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 20, fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: isDark ? AppColors.textPrimary : const Color(0xFF0F172A))),
          ]),
        ),
        const SizedBox(height: 8),
        // ── New chat — the only accent-colored row ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () { controller.createNewChat(); Navigator.pop(context); },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(children: [
                Icon(LucideIcons.messageSquarePlus,
                    size: 20, color: isDark ? AppColors.primary : Dt.accent),
                const SizedBox(width: 14),
                Text('New chat',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 15, fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.primary : Dt.accent)),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // ── Search ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
              onChanged: (v) => setState(() => _sidebarQuery.value = v.trim().toLowerCase()),
            style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: 'Search chats...',
              hintStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 14, color: AppColors.textMuted.withValues(alpha: 0.6)),
              prefixIcon: Icon(Icons.search_rounded, size: 20,
                  color: AppColors.textMuted.withValues(alpha: 0.6)),
              prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 0),
              suffixIcon: _sidebarQuery.value.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
                      onPressed: () => setState(() => _sidebarQuery.value = ''),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 0),
                    )
                  : null,
              filled: true,
              fillColor: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : const Color(0xFFF1F5F9),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text('Recents',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, fontWeight: FontWeight.w600,
                  color: AppColors.textMuted, letterSpacing: 0.3)),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Obx(() {
            final all = controller.sessions;
            final filtered = _sidebarQuery.value.isEmpty
                ? all
                : all.where((s) =>
                    s.title.toLowerCase().contains(_sidebarQuery.value) ||
                    (s.lastMessage?.toLowerCase().contains(_sidebarQuery.value) ?? false))
                .toList();
            if (filtered.isEmpty) {
              return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_sidebarQuery.value.isEmpty ? Icons.forum_outlined : Icons.search_off_rounded,
                      size: 40, color: AppColors.textMuted.withValues(alpha: 0.3)),
                  const SizedBox(height: 12),
                  Text(
                    _sidebarQuery.value.isEmpty ? 'No conversations yet' : 'No matches found',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                ]),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 2),
              itemBuilder: (ctx, i) {
                final s = filtered[i];
                final active = controller.currentSessionId.value == s.id;
                return _sidebarTile(context, s, active, isDark);
              },
            );
          }),
        ),
        const Divider(height: 1),
        // ── Pinned footer: identity + settings gear ──
        InkWell(
          onTap: () {
            Navigator.pop(context);
            Get.find<HomeController>().changeTab(3);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 14),
            child: Row(children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                    color: Dt.accent, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text('C',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('CubicLM',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14, fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.textPrimary : Dt.textPrimary)),
              ),
              IconButton(
                tooltip: 'App Settings',
                onPressed: () {
                  Navigator.pop(context);
                  Get.find<HomeController>().changeTab(3);
                },
                icon: Icon(LucideIcons.settings,
                    size: 20,
                    color: isDark ? AppColors.textPrimary : Dt.iconDefault),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _sidebarTile(BuildContext context, dynamic s, bool active, bool isDark) {
    return Dismissible(
      key: ValueKey(s.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: isDark ? AppColors.surface : Colors.white,
            title: Text('Delete chat?',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
            content: Text('This conversation will be permanently deleted.',
                style: GoogleFonts.plusJakartaSans(fontSize: 14)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('Cancel',
                      style: GoogleFonts.plusJakartaSans(color: AppColors.textMuted))),
              FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text('Delete',
                      style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600))),
            ],
          ),
        );
      },
      onDismissed: (_) => controller.deleteChat(s.id),
      child: Material(
        color: active ? AppColors.primary.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () { controller.openChat(s.id); Navigator.pop(context); },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : (isDark ? AppColors.surfaceLight : const Color(0xFFF1F5F9)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  active ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded,
                  size: 16,
                  color: active ? AppColors.primary : AppColors.textMuted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                            color: isDark ? AppColors.textPrimary : const Color(0xFF0F172A))),
                    const SizedBox(height: 2),
                    Text(_fmtDate(s.updatedAt),
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11, fontWeight: FontWeight.w500,
                            color: AppColors.textMuted)),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  MarkdownStyleSheet _streamMd(BuildContext c, bool isDark) {
    final clr = isDark ? AppColors.textPrimary : const Color(0xFF0F172A);
    final muted = isDark ? AppColors.textSecondary : const Color(0xFF475569);
    final base = GoogleFonts.plusJakartaSans(fontSize: 15, color: clr, height: 1.6, fontWeight: FontWeight.w500);
    return MarkdownStyleSheet.fromTheme(Theme.of(c)).copyWith(
        p: base,
        pPadding: const EdgeInsets.only(bottom: 12),
        h1: base.copyWith(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5),
        h2: base.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
        h3: base.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
        strong: base.copyWith(fontWeight: FontWeight.w800),
        em: base.copyWith(fontStyle: FontStyle.italic),
        listBullet: base,
        listIndent: 24,
        blockquote: base.copyWith(color: muted, fontSize: 14),
        blockquoteDecoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.03),
          border: const Border(left: BorderSide(color: AppColors.primary, width: 3)),
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
        ),
        blockquotePadding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        code: GoogleFonts.firaCode(
            fontSize: 13, color: clr),
        codeblockDecoration: const BoxDecoration(),
        codeblockPadding: EdgeInsets.zero);
  }

  MarkdownStyleSheet _thoughtMd(BuildContext c, bool isDark) {
    final muted = Theme.of(c).hintColor;
    final base = GoogleFonts.plusJakartaSans(fontSize: 13, color: muted, height: 1.5, fontWeight: FontWeight.w500);
    final codeBg = isDark ? AppColors.surfaceLight : const Color(0xFFE2E8F0);
    return MarkdownStyleSheet.fromTheme(Theme.of(c)).copyWith(
        p: base,
        strong: base.copyWith(fontWeight: FontWeight.w700),
        em: base.copyWith(fontStyle: FontStyle.italic),
        listBullet: base,
        code: GoogleFonts.firaCode(
            fontSize: 11, color: muted, backgroundColor: codeBg),
        codeblockDecoration: BoxDecoration(
            color: codeBg, borderRadius: BorderRadius.circular(10)));
  }

  // ── Helpers ──
  String _cleanStream(String t) => t
      .replaceAll(
          RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]'), '')
      .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
      .replaceAll('\uFFFD', '')
      .replaceAll('<|endoftext|>', '')
      .replaceAll('<|im_end|>', '')
      .replaceAll('<|end|>', '');

  bool _hasPrintable(String t) {
    for (final r in t.runes) {
      if (r > 32 &&
          r != 0x7F &&
          r != 0x200B &&
          r != 0x200C &&
          r != 0x200D &&
          r != 0xFEFF &&
          r != 0xFFFD) {
        return true;
      }
    }
    return false;
  }

  String _fmtDate(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${d.day}/${d.month}/${d.year}';
  }

  String _fmtK(int v) => v >= 1000000
      ? '${(v / 1000000).toStringAsFixed(1)}M'
      : v >= 1000
          ? '${(v / 1000).toStringAsFixed(1)}K'
          : v.toString();
}

// ── Add-to-chat tile (56dp muted circle + label) ──
class _AddTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AddTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? Theme.of(context).cardColor : Dt.card,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(children: [
            AppIconCircle(icon: icon, diameter: Dt.circleIconDiameter),
            const SizedBox(height: 8),
            Text(label,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Dt.textSecondary)),
          ]),
        ),
      ),
    );
  }
}


// ── Pulsing Dot ──
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.8, end: 1.2)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
            color: AppColors.error, shape: BoxShape.circle),
      ),
    );
  }
}

class _PulsingTimerDot extends StatefulWidget {
  const _PulsingTimerDot();

  @override
  State<_PulsingTimerDot> createState() => _PulsingTimerDotState();
}

class _PulsingTimerDotState extends State<_PulsingTimerDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _c,
      child: Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
            color: AppColors.primary, shape: BoxShape.circle),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _StepButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? AppColors.primary
        : Theme.of(context).hintColor.withValues(alpha: 0.3);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 34,
        height: 34,
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}

// ── Image Generation Indicator ──
class _ImageGenIndicator extends StatefulWidget {
  final ChatController controller;
  final bool isDark;
  const _ImageGenIndicator({required this.controller, required this.isDark});

  @override
  State<_ImageGenIndicator> createState() => _ImageGenIndicatorState();
}

class _ImageGenIndicatorState extends State<_ImageGenIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Timer _timer;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final start = widget.controller.imageGenStartTime.value;
      if (start != null) {
        setState(() {
          _elapsedSeconds = DateTime.now().difference(start).inSeconds;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _c.dispose();
    super.dispose();
  }

  String _fmtEta(int seconds) {
    if (seconds <= 0) return '';
    if (seconds < 60) return '~$seconds s remaining';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s > 0 ? '~$m m $s s remaining' : '~$m m remaining';
  }

  String _fmtElapsed(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s > 0 ? '${m}m ${s}s' : '${m}m';
  }

  Widget _backendChip(BuildContext context) {
    final localImage = Get.find<LocalImageService>();
    final backend = localImage.currentBackend.value;
    final isCpu = backend == Backend.cpu;
    final color = isCpu ? AppColors.warning : AppColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Text(
        isCpu
            ? 'CPU · Extended'
            : backend.displayName.split(' ').first.toUpperCase(),
        style: GoogleFonts.plusJakartaSans(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final dots = Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final t = ((_c.value - i * 0.15) % 1.0).clamp(0.0, 1.0);
            final pulse = math.sin(t * math.pi).clamp(0.0, 1.0);
            return Padding(
              padding: EdgeInsets.only(right: i < 2 ? 6 : 0),
              child: Opacity(
                opacity: 0.2 + 0.8 * pulse,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: 0.8),
                  ),
                ),
              ),
            );
          }),
        );

        return Obx(() {
          final step = widget.controller.imageGenStep.value;
          final total = widget.controller.imageGenTotal.value;
          final eta = widget.controller.imageGenEstimatedSecs.value;
          final decoding = widget.controller.imageGenDecoding.value;
          final hasProgress = total > 0;
          final pct = hasProgress ? (step / total).clamp(0.0, 1.0) : 0.0;
          final isDone = decoding || (hasProgress && step >= total);

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              dots,
              const SizedBox(height: 12),
              Text(
                isDone ? 'Decoding artifact…' : 'Synthesizing image…',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: widget.isDark ? Colors.white : Colors.black,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (hasProgress) ...[
                const SizedBox(height: 12),
                Container(
                  width: 180,
                  height: 6,
                  decoration: BoxDecoration(
                    color: (widget.isDark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: isDone ? 1.0 : pct,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: AppColors.userGradient,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  isDone
                      ? 'Reconstructing textures…'
                      : '${(pct * 100).toStringAsFixed(0)}% · Step $step / $total',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: Theme.of(context).hintColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                _backendChip(context),
                const SizedBox(height: 5),
                Text(
                  'Runtime: ${_fmtElapsed(_elapsedSeconds)}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    color: Theme.of(context).hintColor.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (eta > 0 && step >= 2 && !isDone) ...[
                  const SizedBox(height: 4),
                  Text(
                    _fmtEta(eta),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      color: AppColors.primary.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: widget.controller.stopGenerating,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.close_rounded,
                            size: 14, color: AppColors.error),
                        const SizedBox(width: 6),
                        Text(
                          'Abort',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: AppColors.error,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          );
        });
      },
    );
  }
}

// ── Typing Dots ──
class _TypingDots extends StatefulWidget {
  final bool isDark;
  const _TypingDots({required this.isDark});
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Claude-style thinking mark: an orange asterisk-star that gently
    // pulses (scale + fade) while the response is being prepared.
    return AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = (math.sin(_c.value * 2 * math.pi) + 1) / 2;
          return Transform.scale(
            scale: 0.82 + 0.28 * t,
            child: Opacity(
              opacity: 0.35 + 0.65 * t,
              child: const Icon(LucideIcons.asterisk,
                  size: 22, color: Dt.accent),
            ),
          );
        });
  }
}

// ── Blinking Cursor ──
class _BlinkingCursor extends StatefulWidget {
  final Color color;
  const _BlinkingCursor({required this.color});
  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Opacity(
            opacity: _c.value,
            child: Container(
                width: 3,
                height: 18,
                margin: const EdgeInsets.only(left: 4, bottom: 2),
                decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(2)))));
  }
}
