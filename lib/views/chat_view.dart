import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_markdown_latex/flutter_markdown_latex.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../controllers/chat_controller.dart';
import '../controllers/settings_controller.dart';
import '../services/inference_service.dart';
import '../services/local_image_service.dart';
import '../ffi/sd_ffi_bindings.dart';
import '../theme/design_tokens.dart';
import '../widgets/chat_bubble.dart';
import 'chat/chat_bars.dart';
import 'chat/chat_dialogs.dart';
import 'chat/chat_format.dart';
import 'chat/chat_sidebar.dart';
import 'chat/chat_widgets.dart';
import 'chat/empty_state.dart';
import 'chat/input_bar.dart';
import 'chat/selection_bar.dart';
import '../widgets/artifact_renderer.dart';
import '../widgets/thinking_orb.dart';
import '../widgets/thought_disclosure.dart';
import '../widgets/voice_overlay.dart';
import '../core/colors.dart';
import '../services/tts_service.dart';

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
      body: Stack(
        children: [
          Column(
            children: [
              modelLoadingBar(context, isDark),
              contextBar(context, isDark),
              Obx(() => controller.findActive.value
                  ? findBar(context, isDark)
                  : const SizedBox.shrink()),
              Expanded(
                child: RepaintBoundary(
                  child: Obx(() {
                    if (controller.currentSessionId.value.isEmpty ||
                        controller.messages.isEmpty) {
                      return emptyState(context, isDark);
                    }
                    final showArtifact = controller.showArtifactPanel.value;
                    final activeId = controller.activeArtifactId.value;
                    final artifact = activeId != null &&
                            controller.artifacts.containsKey(activeId)
                        ? controller.artifacts[activeId]
                        : null;

                    final streaming = controller.isStreaming.value;
                    final n = controller.messages.length;

                    Widget chatStack = Stack(
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
                            // ignore: deprecated_member_use
                            cacheExtent: 1000,
                            physics: const BouncingScrollPhysics(
                                parent: AlwaysScrollableScrollPhysics()),
                            addAutomaticKeepAlives: false,
                            addRepaintBoundaries: true,
                            itemCount: n + (streaming ? 1 : 0),
                            itemBuilder: (_, i) {
                              if (i == n && streaming) {
                                return _streamBubble(context, isDark);
                              }
                              final msg = controller.messages[i];
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

                              Widget content = dateHeader != null
                                  ? Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        dateHeader,
                                        selectableRow(context, msg, bubble, isDark)
                                      ],
                                    )
                                  : selectableRow(context, msg, bubble, isDark);

                              return RepaintBoundary(
                                key: controller.findKeyFor(msg.id),
                                child: _MessageEntrance(
                                  key: ValueKey('anim_${msg.id}'),
                                  messageId: msg.id,
                                  child: content,
                                ),
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

                    if (!showArtifact || artifact == null || artifact.isEmpty) {
                      return chatStack;
                    }

                    return LayoutBuilder(builder: (context, constraints) {
                      if (constraints.maxWidth > 900) {
                        return Row(
                          children: [
                            Expanded(flex: 1, child: chatStack),
                            Expanded(
                              flex: 1,
                              child: ArtifactRenderer(
                                id: controller.activeArtifactId.value!,
                                versions: artifact,
                                onClose: controller.closeArtifact,
                              ),
                            ),
                          ],
                        );
                      }
                      return Stack(
                        children: [
                          chatStack,
                          Positioned.fill(
                            child: ArtifactRenderer(
                              id: controller.activeArtifactId.value!,
                              versions: artifact,
                              onClose: controller.closeArtifact,
                            ),
                          ),
                        ],
                      );
                    });
                  }),
                ),
              ),
              Obx(() => controller.selectionMode.value
                  ? selectionBar(context, isDark)
                  : inputBar(context, isDark)),
            ],
          ),
          Obx(() {
            if (!controller.voiceMode.value) return const SizedBox.shrink();
            final tts = Get.isRegistered<TtsService>() ? Get.find<TtsService>() : null;
            return VoiceOverlay(
              isListening: controller.isListening.value,
              isSpeaking: tts?.isSpeaking.value ?? false,
              text: controller.inputText.value,
              onStop: () => controller.setVoiceMode(false),
            );
          }),
        ],
      ),
    );
  }

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

  static final md.ExtensionSet _eliteMdExtensionSet = md.ExtensionSet(
    [
      ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
      LatexBlockSyntax(),
    ],
    [
      ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
      LatexInlineSyntax(),
    ],
  );

  Widget _streamBubble(BuildContext context, bool isDark) {
    final attType = controller.streamingAttachmentType.value;
    final isImageGen = controller.imageGenTotal.value > 0;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: RepaintBoundary(
          child: Container(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.92),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isImageGen)
                  ImageGenIndicator(controller: controller, isDark: isDark)
                else
                  Obx(() {
                    final thought = controller.streamingThought.value;
                    final answer = controller.streamingAnswer.value;
                    final isThinking = controller.streamingIsThinking.value;
                    
                    final hasThought = thought.trim().isNotEmpty;
                    final hasAnswer = hasPrintable(answer);

                    if (!hasThought && !hasAnswer) {
                      return _typingHint(context, isDark, attachmentType: attType);
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (hasThought)
                          ThoughtDisclosure(
                              thought: thought,
                              isThinking: isThinking,
                              styleSheet: _thoughtMdCached(context, isDark)),
                        if (hasAnswer)
                          Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                    child: RepaintBoundary(
                                        child: answer.length > 1500
                                            ? SelectableText(answer,
                                                style: _streamMdCached(context, isDark)
                                                    .p)
                                            : MarkdownBody(
                                                data: answer,
                                                selectable: false,
                                                styleSheet:
                                                    _streamMdCached(context, isDark),
                                                builders: {
                                                  'latex': LatexElementBuilder(
                                                    textStyle:
                                                        _streamMdCached(context, isDark)
                                                            .p,
                                                  ),
                                                },
                                                extensionSet: _eliteMdExtensionSet,
                                              ))),
                                const BlinkingCursor(color: Dt.accent),
                              ]),
                      ],
                    );
                  }),
                if (!isImageGen)
                  RepaintBoundary(
                    child: Obx(() {
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
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

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

  Widget _typingHint(BuildContext context, bool isDark,
      {String? attachmentType}) {
    String? msg = attachmentType == 'image'
        ? 'chat_analyzing_image'.tr
        : attachmentType == 'audio'
            ? 'chat_processing_audio'.tr
            : null;

    if (controller.isSearchMode.value) {
      msg = 'Deep Searching...';
    }

    final settings = Get.find<SettingsController>();
    OrbState? fixed = orbStateFromName(settings.orbChatAnim.value);

    if (controller.isSearchMode.value) {
      fixed = OrbState.searching;
    }

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

  static final Set<String> _animatedMessageIds = {};
}

class _MessageEntrance extends StatefulWidget {
  final Widget child;
  final String messageId;
  const _MessageEntrance({super.key, required this.child, required this.messageId});

  @override
  State<_MessageEntrance> createState() => _MessageEntranceState();
}

class _MessageEntranceState extends State<_MessageEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _slide;
  late final Animation<double> _fade;
  bool _shouldAnimate = false;

  @override
  void initState() {
    super.initState();
    _shouldAnimate = !ChatView._animatedMessageIds.contains(widget.messageId);
    
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slide = Tween<double>(begin: 0.15, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.7, curve: Curves.easeIn)),
    );

    if (_shouldAnimate) {
      ChatView._animatedMessageIds.add(widget.messageId);
      _controller.forward();
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _fade.value,
          child: Transform.translate(
            offset: Offset(0, MediaQuery.of(context).size.height * _slide.value),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
