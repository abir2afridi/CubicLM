import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../controllers/chat_controller.dart';
import '../controllers/settings_controller.dart';
import '../controllers/home_controller.dart';
import '../services/inference_service.dart';
import '../services/local_image_service.dart';
import '../ffi/sd_ffi_bindings.dart';
import '../utils/thought_parser.dart';
import '../widgets/attachment_preview.dart';
import '../widgets/app_ui.dart';
import '../theme/design_tokens.dart';
import '../widgets/chat_bubble.dart';
import 'chat/chat_bars.dart';
import 'chat/chat_dialogs.dart';
import 'chat/chat_format.dart';
import 'chat/chat_sidebar.dart';
import 'chat/chat_widgets.dart';
import 'chat/empty_state.dart';
import 'chat/selection_bar.dart';
import '../widgets/model_switcher_sheet.dart';
import '../widgets/thinking_orb.dart';
import '../widgets/thought_disclosure.dart';
import '../core/colors.dart';

// ignore: must_be_immutable
class ChatView extends GetView<ChatController> {
  const ChatView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      key: controller.chatScaffoldKey,
      backgroundColor: isDark ? Dt.canvasDark : Dt.canvas,
      drawer: ChatSidebar(isDark: isDark),
      appBar: _appBar(context, isDark),
      body: Column(
        children: [
          modelLoadingBar(context, isDark),
          contextBar(context, isDark),
          Obx(() => controller.findActive.value
              ? findBar(context, isDark)
              : const SizedBox.shrink()),
          Expanded(child: Obx(() {
            if (controller.currentSessionId.value.isEmpty ||
                controller.messages.isEmpty) {
              return emptyState(context, isDark);
            }
            // NOTE: this observer deliberately does NOT read
            // streamingResponse — token flushes rebuild only the stream
            // bubble's own Obx below, not the whole list + every
            // MarkdownBody (was: full rebuild at ~25fps while streaming).
            final streaming = controller.isStreaming.value;
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
                    // Perf: bubbles rebuild on content change anyway — no
                    // need to keep every offscreen subtree alive.
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                    itemCount: n + (streaming ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == n && streaming) {
                        // Own observer: per-token rebuilds stay inside the
                        // streaming bubble instead of the whole list.
                        return Obx(() => _streamBubble(context,
                            controller.streamingResponse.value, isDark));
                      }
                      final msg = controller.messages[i];
                      // Date header: show when first message or different day than previous
                      Widget? dateHeader;
                      if (i == 0 ||
                          !isSameDay(controller.messages[i - 1].timestamp,
                              msg.timestamp)) {
                        dateHeader = dateChip(msg.timestamp, isDark);
                      }
                      final hasRevisions =
                          msg.revisions != null && msg.revisions!.isNotEmpty;
                      final bubble = ChatBubble(
                        message: msg,
                        onCopy: () {
                          Clipboard.setData(ClipboardData(text: msg.content));
                        },
                        onRetry: () => controller.regenerateFromMessage(msg),
                        onBranch: () => controller.branchNewChat(msg),
                        onEdit: msg.role == 'user'
                            ? () => showEditDialog(context, msg)
                            : null,
                        onDelete: () =>
                            confirmDeleteMessage(context, msg, isDark),
                        onPrevRevision: hasRevisions && msg.revisionIndex > 0
                            ? () => controller.navigateRevision(msg, -1)
                            : null,
                        onNextRevision: hasRevisions &&
                                msg.revisionIndex < msg.revisions!.length - 1
                            ? () => controller.navigateRevision(msg, 1)
                            : null,
                      );
                      if (dateHeader != null) {
                        return RepaintBoundary(
                          key: controller.findKeyFor(msg.id),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              dateHeader,
                              selectableRow(context, msg, bubble, isDark)
                            ],
                          ),
                        );
                      }
                      return RepaintBoundary(
                          key: controller.findKeyFor(msg.id),
                          child: selectableRow(context, msg, bubble, isDark));
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
                        child: Semantics(
                          label: 'Scroll to bottom',
                          button: true,
                          child: FloatingActionButton.small(
                            onPressed: controller.jumpToBottom,
                            backgroundColor: isDark ? Dt.cardDark : Dt.card,
                            foregroundColor: AppColors.primary,
                            elevation: 4,
                            child: const Icon(Icons.arrow_downward_rounded,
                                size: 20),
                          ),
                        ),
                      )),
                ),
              ],
            );
          })),
          Obx(() => controller.selectionMode.value
              ? selectionBar(context, isDark)
              : _inputBar(context, isDark)),
        ],
      ),
    );
  }

  // ── Multi-select ──

  /// Long-press enters selection mode; tap toggles while active.
  /// Normal taps pass through (bubble buttons keep working).

  PreferredSizeWidget _appBar(BuildContext context, bool isDark) {
    return AppBar(
      backgroundColor:
          (isDark ? Dt.canvasDark : Dt.canvas).withValues(alpha: 0.8),
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
            model = 'chat_no_model'.tr;
          }
          if (model.length > 20) model = '${model.substring(0, 20)}…';
        } else {
          // Single source of truth for the cloud label, shared with the model
          // switcher sheet so the two can't drift.
          model = settings.selectedCloudModelName;
          if (settings.cloudProvider.value == 'custom' && model.isNotEmpty) {
            model = '${settings.customCloudName.value}: $model';
          }
          if (model.length > 22) model = '${model.substring(0, 22)}…';
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
                    color: isDark ? AppColors.textPrimary : Dt.textPrimary),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Row(children: [
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
              Expanded(
                  child: Text(
                      '$model · ${isLocal ? 'chat_local'.tr : 'chat_cloud'.tr}',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: Theme.of(context).hintColor,
                          fontWeight: FontWeight.w600))),
            ]),
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
        notificationBell(context, isDark),
        Obx(() {
          // Always visible: Battle Arena needs no open chat. Session
          // items disable gracefully on the empty state instead of
          // hiding the whole menu (users couldn't find anything).
          final hasSession = controller.currentSessionId.value.isNotEmpty;
          final selecting = controller.selectionMode.value;
          final iconColor = isDark ? AppColors.textPrimary : Dt.iconDefault;
          final muted = Theme.of(context).hintColor;
          return PopupMenuButton<String>(
            tooltip: 'More options',
            icon: Icon(LucideIcons.moreVertical,
                size: Dt.iconSize - 2, color: iconColor),
            onSelected: (v) {
              if (v == 'find') controller.toggleFind(true);
              if (v == 'export') _exportCurrentSession(context);
              if (v == 'select') controller.toggleSelectionMode();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'find',
                enabled: hasSession,
                child: Row(children: [
                  Icon(LucideIcons.search,
                      size: 16, color: hasSession ? null : muted),
                  const SizedBox(width: 10),
                  Text('Find in chat',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14, color: hasSession ? null : muted)),
                ]),
              ),
              PopupMenuItem(
                value: 'export',
                enabled: hasSession,
                child: Row(children: [
                  Icon(LucideIcons.share2,
                      size: 16, color: hasSession ? null : muted),
                  const SizedBox(width: 10),
                  Text('Export chat',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14, color: hasSession ? null : muted)),
                ]),
              ),
              PopupMenuItem(
                value: 'select',
                enabled: hasSession,
                child: Row(children: [
                  Icon(
                      selecting
                          ? LucideIcons.checkSquare
                          : LucideIcons.listChecks,
                      size: 16,
                      color:
                          selecting ? Dt.accent : (hasSession ? null : muted)),
                  const SizedBox(width: 10),
                  Text(selecting ? 'Done selecting' : 'Select messages',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14, color: hasSession ? null : muted)),
                ]),
              ),
            ],
          );
        }),
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

  Future<void> _exportCurrentSession(BuildContext context) async {
    final sid = controller.currentSessionId.value;
    if (sid.isEmpty) return;
    final session = controller.sessions.firstWhereOrNull((s) => s.id == sid);
    if (session == null) return;
    await exportSession(context, session);
  }

  // ── Streaming Bubble ──
  Widget _streamBubble(BuildContext context, String text, bool isDark) {
    final attType = controller.streamingAttachmentType.value;
    final isImageGen = controller.imageGenTotal.value > 0;
    final clean = cleanStream(text).trimLeft();
    final parts = splitThoughtTags(clean);
    final answer = parts.answer.trimLeft();
    final hasText = parts.hasThought || hasPrintable(answer);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.92),
          padding: const EdgeInsets.symmetric(vertical: 4),
          // No card chrome — the response streams in place on the canvas,
          // identical to how the finished message renders (Claude-style).
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (isImageGen)
              ImageGenIndicator(controller: controller, isDark: isDark)
            else if (!hasText)
              _typingHint(context, isDark, attachmentType: attType)
            else ...[
              if (parts.hasThought)
                ThoughtDisclosure(
                    thought: parts.thought,
                    isThinking: parts.isThinking,
                    styleSheet: _thoughtMdCached(context, isDark)),
              if (hasPrintable(answer))
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                      // Perf: full MarkdownBody (selectable spans + gesture
                      // tree) rebuilt ~7x/sec while streaming is the main
                      // jank source. Short answers keep markdown; long ones
                      // (code dumps) stream as plain text in the same style
                      // and get full markdown once saved. Selectable off
                      // mid-stream — tap-hold selection works on the
                      // finished bubble.
                      child: RepaintBoundary(
                          child: answer.length > 4000
                              ? SelectableText(answer,
                                  style: _streamMdCached(context, isDark).p)
                              : MarkdownBody(
                                  data: answer,
                                  selectable: false,
                                  styleSheet:
                                      _streamMdCached(context, isDark)))),
                  const BlinkingCursor(color: Dt.accent),
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
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('${tps.toStringAsFixed(1)} tok/s',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700)),
                          ),
                        if (tps > 0 && duration > 0) const SizedBox(width: 8),
                        if (duration > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const PulsingTimerDot(),
                                const SizedBox(width: 4),
                                Text('${duration}s',
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
        ? 'chat_analyzing_image'.tr
        : attachmentType == 'audio'
            ? 'chat_processing_audio'.tr
            : null;
    // Thinking orbs — dotted orb cycling through random states with a
    // shimmering status label (Working / Searching / Solving / …).
    final settings = Get.find<SettingsController>();
    final fixed = orbStateFromName(settings.orbChatAnim.value);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (fixed != null)
        ThinkingOrb(size: 22, state: fixed, showLabel: true)
      else
        const ThinkingOrb(size: 22, autoCycle: true, showLabel: true),
      if (msg != null) ...[
        const SizedBox(width: 8),
        Flexible(
            child: Text(msg,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: Theme.of(context).hintColor,
                    fontWeight: FontWeight.w500))),
      ],
    ]);
  }

  // ── Input Bar ──
  Widget _inputBar(BuildContext context, bool isDark) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        color: Colors.transparent,
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
          // Web URL preview pills — shows chips for https:// links in input
          Obx(() {
            final text = controller.inputText.value;
            final urlRegExp = RegExp(r'https?://[^\s]+');
            final urls = urlRegExp
                .allMatches(text)
                .map((m) => m.group(0)!)
                .toSet()
                .toList();
            if (urls.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: urls.map((url) {
                  String domain;
                  try {
                    final cleanUrl =
                        url.replaceAll(RegExp(r'[.,;:!?\)\]]+$'), '');
                    domain = Uri.parse(cleanUrl).host.replaceFirst('www.', '');
                    if (domain.isEmpty) domain = cleanUrl;
                  } catch (_) {
                    domain = url;
                  }
                  final displayDomain = domain.length > 28
                      ? '${domain.substring(0, 28)}…'
                      : domain;
                  final faviconUrl =
                      'https://www.google.com/s2/favicons?domain=$domain&sz=32';
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.network(
                            faviconUrl,
                            width: 16,
                            height: 16,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: const Color(0xFF3B82F6)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Icon(LucideIcons.globe,
                                  size: 10, color: Color(0xFF3B82F6)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            displayDomain,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? AppColors.textPrimary
                                  : Dt.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () {
                            final current = controller.textController.text;
                            final updated = current
                                .replaceAll(url, '')
                                .replaceAll(RegExp(r'\s{2,}'), ' ')
                                .trim();
                            controller.textController.text = updated;
                            controller.textController.selection =
                                TextSelection.collapsed(offset: updated.length);
                            controller.inputText.value = updated;
                          },
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.06),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              LucideIcons.x,
                              size: 10,
                              color: isDark
                                  ? AppColors.textSecondary
                                  : Dt.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            );
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
                  border:
                      Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const PulsingDot(),
                  const SizedBox(width: 10),
                  Text('chat_listening_hint'.tr,
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
            final accent =
                backend == Backend.cpu ? AppColors.warning : AppColors.success;
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
                        border:
                            Border.all(color: accent.withValues(alpha: 0.2)),
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
                      border: Border.all(
                          color: isDark
                              ? AppColors.border
                              : AppColors.borderLightMode),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StepButton(
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
                        StepButton(
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
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                            child: Text('chat_unlock_models'.tr,
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
                            child: Text('chat_add_api_keys'.tr,
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: Dt.link)),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: s.dismissComposerUpsell,
                            child: const Icon(LucideIcons.x,
                                size: 14, color: Dt.textSecondary),
                          ),
                        ]),
                      ),
                    );
                  }),
                  // ── Text field: full-width, ABOVE the controls row (cursor starts here) ──
                  // Enter = send, Shift+Enter = newline
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
                    child: KeyboardListener(
                      focusNode: controller.composerKeyboardFocusNode,
                      onKeyEvent: (event) {
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.enter &&
                            !HardwareKeyboard.instance.isShiftPressed) {
                          // Prevent the newline from being inserted
                          final text = controller.textController.text.trim();
                          if (text.isNotEmpty ||
                              controller.selectedFileName.value != null) {
                            // Remove trailing newline that may have been inserted
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              final current = controller.textController.text;
                              if (current.endsWith('\n')) {
                                controller.textController.text =
                                    current.trimRight();
                                controller.inputText.value =
                                    controller.textController.text;
                              }
                              controller.sendMessage();
                            });
                          }
                        }
                      },
                      child: TextField(
                        focusNode: controller.composerFocusNode,
                        controller: controller.textController,
                        onChanged: (v) => controller.inputText.value = v,
                        maxLines: 6,
                        minLines: 1,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            height: 1.35,
                            color:
                                isDark ? AppColors.textPrimary : Dt.textPrimary,
                            fontWeight: FontWeight.w500),
                        decoration: InputDecoration(
                          hintText: 'chat_composer_hint'.tr,
                          hintStyle: GoogleFonts.plusJakartaSans(
                              fontSize: 16,
                              color: Dt.textPlaceholder,
                              fontWeight: FontWeight.w500),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 10),
                          isDense: true,
                          fillColor: Colors.transparent,
                        ),
                      ),
                    ),
                  ),
                  // ── Controls row: + / model pill … mic / send ──
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    // "+" opens the Add-to-Chat sheet (attachments, web access)
                    AppCircleButton(
                      icon: LucideIcons.plus,
                      tooltip: 'chat_add_to_chat'.tr,
                      onTap: () => _showAddToChatSheet(
                        context,
                        isDark: isDark,
                        onCamera: controller.takePhoto,
                        onImage: controller.pickImage,
                        onFile: controller.pickFile,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Model selector pill — fixed width so label change
                    // (Local → loaded model name) doesn't shift the
                    // right cluster. 125dp fits 14 chars at 12.5sp + chevron.
                    SizedBox(
                      width: 125,
                      child: Obx(() => AppModelPill(
                            label: _composerModelLabel(),
                            onTap: () => showModelSwitcherSheet(context),
                          )),
                    ),
                    const SizedBox(width: 6),
                    Obx(() {
                      final enabled =
                          Get.find<SettingsController>().webFetchEnabled.value;
                      return AppCircleButton(
                        icon: LucideIcons.globe,
                        tooltip: 'chat_web_access'.tr,
                        iconColor: enabled ? Dt.accent : null,
                        onTap: () => Get.find<SettingsController>()
                            .setWebFetchEnabled(!enabled),
                      );
                    }),
                    const SizedBox(width: 6),
                    AppCircleButton(
                      icon: LucideIcons.layoutTemplate,
                      tooltip: 'Prompt templates',
                      onTap: () => _showTemplateSheet(context, isDark),
                    ),
                    const Spacer(),
                    // Right cluster: mic (muted circle) + primary CTA (solid dark)
                    // Spacer pushes this cluster to the far right corner,
                    // and inner Row keeps mic + send at the same vertical level.
                    Obx(() {
                      final loading = controller.isLoading.value;
                      final listening = controller.isListening.value;
                      final hasContent =
                          controller.inputText.value.isNotEmpty ||
                              controller.selectedFileName.value != null ||
                              controller.selectedImagePath.value != null;
                      // Hide the mic when speech recognition is
                      // unavailable (e.g. permission denied, or a
                      // platform without an STT engine) instead of
                      // showing a dead button.
                      final micAvailable = controller.sttAvailable.value;
                      final voiceMode = controller.voiceMode.value;

                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Single voice button (like ChatGPT/Gemini):
                          // tap = push-to-talk, hold = hands-free mode.
                          if (!loading && !hasContent && micAvailable)
                            AppCircleButton(
                              icon: LucideIcons.mic,
                              tooltip: voiceMode
                                  ? 'Hands-free ON — tap to stop'
                                  : 'Voice input (hold for hands-free)',
                              iconColor: voiceMode
                                  ? Dt.accent
                                  : (listening ? AppColors.error : null),
                              onTap: () {
                                if (controller.voiceMode.value) {
                                  controller.setVoiceMode(false);
                                } else {
                                  controller.toggleListening();
                                }
                              },
                              onLongPress: () {
                                if (!controller.voiceMode.value) {
                                  controller.setVoiceMode(true);
                                }
                              },
                            ),
                          if (!loading && !hasContent && micAvailable)
                            const SizedBox(width: 8),
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
        ]),
      ),
    );
  }

  // ── Sidebar Drawer ──

  /// Short label for the composer's model pill.
  /// Pinned chats show the pinned model with 📌 (may differ from global).
  String _composerModelLabel() {
    if (controller.chatHasModelPin) {
      final pin = controller.chatPinnedModelLabel;
      if (pin.isNotEmpty) return '📌 $pin';
    }
    final s = Get.find<SettingsController>();
    if (s.inferenceMode.value == 'cloud') {
      final m = s.selectedCloudModelName;
      if (m.isEmpty) return 'chat_cloud'.tr;
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
    if (name.isEmpty) return 'chat_local'.tr;
    final stripped = name.replaceAll(
        RegExp(r'\.(gguf|litertlm|safetensors)$', caseSensitive: false), '');
    // 14 keeps the pill compact on 360dp screens (prevents 4-12px overflow).
    return stripped.length > 14 ? '${stripped.substring(0, 14)}…' : stripped;
  }

  /// "+" sheet per reference spec §2.3: three equal tiles, then stacked
  /// row-cards — including the Web-access toggle that used to sit in the
  /// composer bar.
  void _showTemplateSheet(BuildContext context, bool isDark) {
    controller.ensureTemplatesLoaded();
    showAppBottomSheet(
      context,
      builder: (sheetCtx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppSheetHeader(
                    title: 'Prompt templates',
                    onClose: () => Navigator.pop(sheetCtx)),
                const SizedBox(height: 6),
                Flexible(
                  child: Obx(() => ListView.separated(
                        shrinkWrap: true,
                        itemCount: controller.promptTemplates.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (_, i) {
                          final t = controller.promptTemplates[i];
                          final builtin = (t['builtin'] ?? '').isNotEmpty;
                          return ListTile(
                            dense: true,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            title: Text(t['name'] ?? '',
                                style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w700)),
                            subtitle: Text(
                                (t['body'] ?? '').replaceAll('\n', ' ').trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            trailing: builtin
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        size: 18),
                                    tooltip: 'Delete template',
                                    onPressed: () => controller
                                        .deletePromptTemplate(t['id'] ?? ''),
                                  ),
                            onTap: () {
                              Navigator.pop(sheetCtx);
                              controller.insertTemplate(t['body'] ?? '');
                            },
                          );
                        },
                      )),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New template'),
                    onPressed: () {
                      Navigator.pop(sheetCtx);
                      _showTemplateEditor(context, isDark);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showTemplateEditor(BuildContext context, bool isDark) {
    final nameCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('New template'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    labelText: 'Name', hintText: 'e.g. Debug SQL')),
            const SizedBox(height: 8),
            TextField(
                controller: bodyCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                    labelText: 'Prompt text',
                    hintText: 'Instructions… (your text goes after)')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dlgCtx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty ||
                    bodyCtrl.text.trim().isEmpty) {
                  return;
                }
                controller.addPromptTemplate(nameCtrl.text, bodyCtrl.text);
                Navigator.pop(dlgCtx);
              },
              child: const Text('Save')),
        ],
      ),
    );
  }

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
                AppSheetHeader(
                    title: 'chat_add_to_chat'.tr,
                    onClose: () => Navigator.pop(sheetCtx)),
                const SizedBox(height: 6),
                Row(children: [
                  AddTile(
                      icon: LucideIcons.camera,
                      label: 'chat_camera'.tr,
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        onCamera();
                      }),
                  const SizedBox(width: 8),
                  AddTile(
                      icon: LucideIcons.image,
                      label: 'chat_photos'.tr,
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        onImage();
                      }),
                  const SizedBox(width: 8),
                  AddTile(
                      icon: LucideIcons.fileUp,
                      label: 'chat_files'.tr,
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        onFile();
                      }),
                ]),
                const SizedBox(height: 12),
                // ── Choose model row (drills into the switcher) ──
                AppSheetRowCard(
                  leading: const AppIconCircle(icon: LucideIcons.box),
                  title: 'chat_choose_model'.tr,
                  subtitle: _composerModelLabel(),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    showModelSwitcherSheet(context);
                  },
                  trailing: const Icon(LucideIcons.chevronRight,
                      size: 18, color: Dt.textSecondary),
                ),
                const SizedBox(height: 10),
                Obx(() => AppSheetRowCard(
                      leading: const AppIconCircle(icon: LucideIcons.globe),
                      title: 'chat_web_access'.tr,
                      subtitle: 'chat_web_access_desc'.tr,
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

  // Stream-bubble stylesheets, memoized per (brightness, theme): the
  // stream Obx rebuilds ~7x/sec and must not pay fromTheme + GoogleFonts
  // per tick. Theme hash in the key self-invalidates on theme switch.
  static final Map<int, MarkdownStyleSheet> _streamMdCache = {};
  static final Map<int, MarkdownStyleSheet> _thoughtMdCache = {};

  MarkdownStyleSheet _streamMdCached(BuildContext c, bool isDark) {
    final key = Object.hash(isDark, Theme.of(c).hashCode);
    return _streamMdCache.putIfAbsent(key, () => _streamMd(c, isDark));
  }

  MarkdownStyleSheet _thoughtMdCached(BuildContext c, bool isDark) {
    final key = Object.hash(isDark, Theme.of(c).hashCode);
    return _thoughtMdCache.putIfAbsent(key, () => _thoughtMd(c, isDark));
  }

  MarkdownStyleSheet _streamMd(BuildContext c, bool isDark) {
    final clr = isDark ? AppColors.textPrimary : Dt.textPrimary;
    final muted = isDark ? AppColors.textSecondary : Dt.textSecondary;
    // Same serif voice as the finished message — no font swap on completion.
    final base =
        GoogleFonts.sourceSerif4(fontSize: 15.5, color: clr, height: 1.6);
    return MarkdownStyleSheet.fromTheme(Theme.of(c)).copyWith(
        p: base,
        pPadding: const EdgeInsets.only(bottom: 12),
        h1: base.copyWith(
            fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5),
        h2: base.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
        h3: base.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
        strong: base.copyWith(fontWeight: FontWeight.w700),
        em: base.copyWith(fontStyle: FontStyle.italic),
        listBullet: base,
        listIndent: 24,
        blockquote: base.copyWith(color: muted, fontSize: 14),
        blockquoteDecoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.03)
              : Colors.black.withValues(alpha: 0.03),
          border: const Border(
              left: BorderSide(color: AppColors.primary, width: 3)),
          borderRadius:
              const BorderRadius.horizontal(right: Radius.circular(8)),
        ),
        blockquotePadding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        code: GoogleFonts.firaCode(fontSize: 13, color: clr),
        codeblockDecoration: const BoxDecoration(),
        codeblockPadding: EdgeInsets.zero);
  }

  MarkdownStyleSheet _thoughtMd(BuildContext c, bool isDark) {
    final muted = Theme.of(c).hintColor;
    final base = GoogleFonts.plusJakartaSans(
        fontSize: 13, color: muted, height: 1.5, fontWeight: FontWeight.w500);
    final codeBg = isDark ? AppColors.surfaceLight : Dt.hairline;
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
}
