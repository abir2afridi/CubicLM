import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import '../controllers/chat_controller.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../controllers/settings_controller.dart';
import '../controllers/model_controller.dart';
import '../controllers/home_controller.dart';
import '../services/hive_service.dart';
import '../services/inference_service.dart';
import '../services/local_image_service.dart';
import '../ffi/sd_ffi_bindings.dart';
import '../utils/thought_parser.dart';
import '../widgets/attachment_preview.dart';
import '../widgets/app_ui.dart';
import '../theme/design_tokens.dart';
import '../widgets/chat_bubble.dart';
import 'chat/chat_dialogs.dart';
import 'chat/chat_format.dart';
import 'chat/chat_widgets.dart';
import '../widgets/model_switcher_sheet.dart';
import '../widgets/thinking_orb.dart';
import '../widgets/thought_disclosure.dart';
import '../core/colors.dart';
import '../services/notification_history_service.dart';
import 'notification_history_view.dart';

// ignore: must_be_immutable
class ChatView extends GetView<ChatController> {
  ChatView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      key: controller.chatScaffoldKey,
      backgroundColor: isDark ? Dt.canvasDark : Dt.canvas,
      drawer: _buildSidebar(context, isDark),
      appBar: _appBar(context, isDark),
      body: Column(
        children: [
          _modelLoadingBar(context, isDark),
          _contextBar(context, isDark),
          Obx(() => controller.findActive.value
              ? _findBar(context, isDark)
              : const SizedBox.shrink()),
          Expanded(child: Obx(() {
            if (controller.currentSessionId.value.isEmpty ||
                controller.messages.isEmpty) {
              return _emptyState(context, isDark);
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
                              _selectableRow(context, msg, bubble, isDark)
                            ],
                          ),
                        );
                      }
                      return RepaintBoundary(
                          key: controller.findKeyFor(msg.id),
                          child: _selectableRow(context, msg, bubble, isDark));
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
              ? _selectionBar(context, isDark)
              : _inputBar(context, isDark)),
        ],
      ),
    );
  }

  // ── Multi-select ──

  /// Long-press enters selection mode; tap toggles while active.
  /// Normal taps pass through (bubble buttons keep working).
  Widget _selectableRow(
      BuildContext context, ChatMessage msg, Widget child, bool isDark) {
    return GestureDetector(
      onLongPress: () {
        controller.toggleSelectionMode(true);
        controller.toggleSelected(msg.id);
      },
      onTap: () {
        if (controller.selectionMode.value) {
          controller.toggleSelected(msg.id);
        }
      },
      child: Obx(() {
        final selected = controller.selectionMode.value &&
            controller.selectedIds.contains(msg.id);
        if (!selected) return child;
        return Container(
          decoration: const BoxDecoration(
            color: Color(0x14D97757),
            border: Border(left: BorderSide(color: Dt.accent, width: 3)),
          ),
          child: child,
        );
      }),
    );
  }

  Widget _selectionBar(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: isDark ? Dt.cardDark : Dt.card,
        border: Border(
            top: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06))),
      ),
      child: SafeArea(
        top: false,
        child: Obx(() {
          final n = controller.selectedIds.length;
          return Row(
            children: [
              Text('$n selected',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w800, fontSize: 14)),
              const Spacer(),
              IconButton(
                tooltip: 'Copy selected',
                icon: const Icon(LucideIcons.copy, size: 20),
                onPressed: n == 0
                    ? null
                    : () => Clipboard.setData(
                        ClipboardData(text: controller.selectedAsMarkdown())),
              ),
              IconButton(
                tooltip: 'Share selected',
                icon: const Icon(LucideIcons.share2, size: 20),
                onPressed: n == 0
                    ? null
                    : () => Share.share(controller.selectedAsMarkdown()),
              ),
              IconButton(
                tooltip: 'Delete selected',
                icon: const Icon(LucideIcons.trash2,
                    size: 20, color: AppColors.error),
                onPressed: n == 0 ? null : () => controller.deleteSelected(),
              ),
              IconButton(
                tooltip: 'Done',
                icon: const Icon(LucideIcons.x, size: 20),
                onPressed: () => controller.toggleSelectionMode(false),
              ),
            ],
          );
        }),
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
        _notificationBell(context, isDark),
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

  Widget _findBar(BuildContext context, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Dt.cardDark : Dt.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.search,
              size: 18, color: isDark ? AppColors.textPrimary : Dt.iconDefault),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller.findController,
              autofocus: true,
              onChanged: controller.updateFind,
              onSubmitted: (_) => controller.stepFind(1),
              style: GoogleFonts.plusJakartaSans(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Find in this chat…',
                hintStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 14, color: Theme.of(context).hintColor),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          Obx(() {
            final n = controller.findMatches.length;
            final q = controller.findQuery.value;
            final label = q.isEmpty
                ? ''
                : n == 0
                    ? '0'
                    : '${controller.findIndex.value + 1}/$n';
            return Text(label,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).hintColor));
          }),
          IconButton(
            tooltip: 'Previous',
            icon: const Icon(LucideIcons.chevronUp, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () => controller.stepFind(-1),
          ),
          IconButton(
            tooltip: 'Next',
            icon: const Icon(LucideIcons.chevronDown, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () => controller.stepFind(1),
          ),
          IconButton(
            tooltip: 'Close find',
            icon: const Icon(LucideIcons.x, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () => controller.toggleFind(false),
          ),
        ],
      ),
    );
  }

  Widget _notificationBell(BuildContext context, bool isDark) {
    // Never throw if DI isn't ready yet (cold-start race) — bell just
    // shows no badge until the service lands.
    if (!Get.isRegistered<NotificationHistoryService>()) {
      return IconButton(
        tooltip: 'Notifications',
        icon: Icon(LucideIcons.bell,
            size: Dt.iconSize - 2,
            color: isDark ? AppColors.textPrimary : Dt.iconDefault),
        onPressed: () => Get.to(() => const NotificationHistoryView(),
            transition: Transition.rightToLeft,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic),
      );
    }
    final svc = Get.find<NotificationHistoryService>();
    return Obx(() {
      final unread = svc.unreadCount;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            tooltip: 'Notifications',
            icon: Icon(LucideIcons.bell,
                size: Dt.iconSize - 2,
                color: isDark ? AppColors.textPrimary : Dt.iconDefault),
            onPressed: () {
              svc.markAllRead();
              Get.to(() => const NotificationHistoryView(),
                  transition: Transition.rightToLeft,
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic);
            },
          ),
          if (unread > 0)
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                decoration: BoxDecoration(
                  color: Dt.accent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: isDark ? Dt.canvasDark : Dt.canvas, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1),
                  ),
                ),
              ),
            ),
        ],
      );
    });
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
              color: (isDark ? AppColors.surface : Colors.white)
                  .withValues(alpha: 0.8),
              border: Border(
                  bottom: BorderSide(
                      color:
                          isDark ? AppColors.border : AppColors.borderLightMode,
                      width: 1)),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: AppColors.primary)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text("${'chat_sync_intelligence'.tr} $pct%",
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          color:
                              isDark ? AppColors.textPrimary : Dt.textPrimary,
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
                          backgroundColor:
                              isDark ? Dt.pillMutedDark : Dt.pillMuted,
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
                                  color:
                                      AppColors.primary.withValues(alpha: 0.4),
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
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.05),
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
                    Text('chat_context_usage'.tr,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            color: Theme.of(context).hintColor,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2)),
                    Text('${fmtK(used)} / ${fmtK(total)} ${'chat_tokens'.tr}',
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
      {
        'text': 'Explain quantum computing simply',
        'icon': Icons.auto_awesome_rounded,
        'color': Colors.blue
      },
      {
        'text': 'Write a short poem about time',
        'icon': Icons.edit_note_rounded,
        'color': Colors.purple
      },
      {
        'text': 'What makes the Northern Lights happen?',
        'icon': Icons.light_mode_rounded,
        'color': Colors.teal
      },
      {
        'text': 'Give me a 5-minute healthy breakfast recipe',
        'icon': Icons.restaurant_rounded,
        'color': Colors.orange
      },
    ];
    return Center(
        child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Image.asset(
          'assets/icons/CubicLM.png',
          width: 64,
          height: 64,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 16),
        AnimatedAppName(isDark: isDark),
        const SizedBox(height: 20),
        Text('chat_empty_title'.tr,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
                color: isDark ? AppColors.textPrimary : Dt.textPrimary)),
        const SizedBox(height: 8),
        Text('chat_empty_subtitle'.tr,
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
                border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.2),
                    width: 1.5),
              ),
              child: Column(children: [
                const Icon(Icons.cloud_download_rounded,
                    color: AppColors.warning, size: 48),
                const SizedBox(height: 16),
                Text('chat_no_local_models_title'.tr,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black)),
                const SizedBox(height: 10),
                Text('chat_no_local_models_desc'.tr,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        color: Theme.of(context).hintColor,
                        height: 1.5)),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: () => Get.find<HomeController>().changeTab(1),
                  icon: const Icon(Icons.arrow_right_alt_rounded, size: 22),
                  label: Text('chat_go_to_hub'.tr),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.warning,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20))),
                ),
              ]),
            );
          }
          return LayoutBuilder(
            builder: (ctx, constraints) {
              final w = constraints.maxWidth;
              final cols = w >= 600 ? (w >= 900 ? 4 : 3) : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  // Fixed dp height (not width-derived) so wrapped text on
                  // narrow screens can never overflow the tile.
                  mainAxisExtent: 136,
                ),
                itemCount: suggestions.length,
                itemBuilder: (ctx, i) {
                  final s = suggestions[i];
                  return _suggestionCard(context, s['text'] as String,
                      s['icon'] as IconData, s['color'] as Color, isDark);
                },
              );
            },
          );
        }),
      ]),
    ));
  }

  Widget _suggestionCard(BuildContext context, String text, IconData icon,
      Color color, bool isDark) {
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
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.05),
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
                    color: isDark ? AppColors.textPrimary : Dt.textPrimary,
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

  final RxString _sidebarQuery = ''.obs;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  final RxSet<String> _searchHits = <String>{}.obs;
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

  Widget _sidebarContent(
      BuildContext context, bool isDark, StateSetter setState) {
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
                width: 32,
                height: 32,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
            Text('CubicLM',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: isDark ? AppColors.textPrimary : Dt.textPrimary)),
          ]),
        ),
        const SizedBox(height: 8),
        // ── New chat — the only accent-colored row ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              controller.createNewChat();
              Navigator.pop(context);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(children: [
                Icon(LucideIcons.messageSquarePlus,
                    size: 20, color: isDark ? AppColors.primary : Dt.accent),
                const SizedBox(width: 14),
                Text('chat_new_chat'.tr,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
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
            controller: _searchController,
            focusNode: controller.historySearchFocus,
            onChanged: (v) {
              final trimmed = v.trim().toLowerCase();
              setState(() => _sidebarQuery.value = trimmed);
              _searchDebounce?.cancel();
              if (trimmed.isEmpty) {
                _searchHits.clear();
                return;
              }
              _searchDebounce =
                  Timer(const Duration(milliseconds: 300), () async {
                // Guard against stale flights: only apply hits for the
                // query that is still current when the isolate returns.
                final snapshot = trimmed;
                try {
                  final hits =
                      await Get.find<HiveService>().searchMessages(snapshot);
                  if (snapshot == _sidebarQuery.value) {
                    _searchHits.assignAll(hits);
                  }
                } catch (_) {
                  if (snapshot == _sidebarQuery.value) _searchHits.clear();
                }
              });
            },
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: 'chat_search_hint'.tr,
              hintStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: AppColors.textMuted.withValues(alpha: 0.6)),
              prefixIcon: Icon(Icons.search_rounded,
                  size: 20, color: AppColors.textMuted.withValues(alpha: 0.6)),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 36, minHeight: 0),
              suffixIcon: _sidebarQuery.value.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded,
                          size: 18, color: AppColors.textMuted),
                      onPressed: () {
                        _searchController.clear();
                        _searchDebounce?.cancel();
                        _searchHits.clear();
                        setState(() => _sidebarQuery.value = '');
                      },
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 0),
                    )
                  : null,
              filled: true,
              fillColor:
                  isDark ? Colors.white.withValues(alpha: 0.06) : Dt.pillMuted,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text('chat_recents'.tr,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                  letterSpacing: 0.3)),
        ),
        const SizedBox(height: 8),
        // Archived toggle — only takes space when archives exist.
        // NOTE: read the Rx flag FIRST so this Obx always tracks an
        // observable even when the early return below is taken.
        Obx(() {
          final showing = controller.showArchived.value;
          final n = controller.archivedCount;
          if (n == 0 && !showing) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => controller.showArchived.value = !showing,
                icon: Icon(
                  showing
                      ? Icons.visibility_off_outlined
                      : Icons.archive_outlined,
                  size: 16,
                  color: AppColors.textMuted,
                ),
                label: Text(
                  showing ? 'Hide archived' : 'Show archived ($n)',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted),
                ),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          );
        }),
        // Hidden toggle — mirrors archived (read Rx first for tracking).
        Obx(() {
          final showing = controller.showHidden.value;
          final n = controller.hiddenCount;
          if (n == 0 && !showing) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => controller.showHidden.value = !showing,
                icon: Icon(
                  showing
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 16,
                  color: AppColors.textMuted,
                ),
                label: Text(
                  showing ? 'Hide hidden' : 'Show hidden ($n)',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted),
                ),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          );
        }),
        // Label/folder chips — only takes space when labels exist.
        Obx(() {
          final labels = controller.chatLabels;
          final active = controller.labelFilter.value;
          if (labels.isEmpty && active.isEmpty) {
            return const SizedBox.shrink();
          }
          return Container(
            height: 36,
            margin: const EdgeInsets.only(top: 4),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                if (active.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: const Text('All'),
                      selected: false,
                      onSelected: (_) => controller.labelFilter.value = '',
                    ),
                  ),
                for (final l in labels)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(l,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12, fontWeight: FontWeight.w700)),
                      selected: active == l,
                      selectedColor: Dt.accent.withValues(alpha: 0.2),
                      onSelected: (_) =>
                          controller.labelFilter.value = active == l ? '' : l,
                    ),
                  ),
              ],
            ),
          );
        }),
        Expanded(
          child: Obx(() {
            // Read Rx first so the list tracks them (see NOTE above).
            final showA = controller.showArchived.value;
            final showH = controller.showHidden.value;
            final activeLabel = controller.labelFilter.value;
            var all = showA
                ? controller.sessions.toList()
                : controller.sessions.where((s) => !s.archived).toList();
            if (!showH) all = all.where((s) => !s.hidden).toList();
            if (activeLabel.isNotEmpty) {
              all = all.where((s) => s.label == activeLabel).toList();
            }
            final q = _sidebarQuery.value;
            final messageHits = _searchHits.toSet();
            final filtered = q.isEmpty
                ? all
                : all
                    .where((s) =>
                        s.title.toLowerCase().contains(q) ||
                        (s.lastMessage?.toLowerCase().contains(q) ?? false) ||
                        messageHits.contains(s.id))
                    .toList();
            if (filtered.isEmpty) {
              return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                      _sidebarQuery.value.isEmpty
                          ? Icons.forum_outlined
                          : Icons.search_off_rounded,
                      size: 40,
                      color: AppColors.textMuted.withValues(alpha: 0.3)),
                  const SizedBox(height: 12),
                  Text(
                      _sidebarQuery.value.isEmpty
                          ? 'chat_no_conversations'.tr
                          : 'chat_no_matches'.tr,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted)),
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
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color:
                            isDark ? AppColors.textPrimary : Dt.textPrimary)),
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

  Widget _sidebarTile(
      BuildContext context, ChatSession s, bool active, bool isDark) {
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
        child: const Icon(Icons.delete_outline_rounded,
            color: AppColors.error, size: 20),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: isDark ? AppColors.surface : Colors.white,
            title: Text('chat_delete_chat_title'.tr,
                style:
                    GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
            content: Text('chat_delete_chat_desc'.tr,
                style: GoogleFonts.plusJakartaSans(fontSize: 14)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('common_cancel'.tr,
                      style: GoogleFonts.plusJakartaSans(
                          color: AppColors.textMuted))),
              FilledButton(
                  style:
                      FilledButton.styleFrom(backgroundColor: AppColors.error),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text('common_delete'.tr,
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w600))),
            ],
          ),
        );
      },
      onDismissed: (_) => controller.deleteChat(s.id),
      child: Material(
        color: active
            ? AppColors.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            controller.openChat(s.id);
            Navigator.pop(context);
          },
          onLongPress: () => showChatActionsSheet(context, s, isDark),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : (isDark ? AppColors.surfaceLight : Dt.pillMuted),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  s.pinned
                      ? Icons.push_pin_rounded
                      : (active
                          ? Icons.chat_bubble_rounded
                          : Icons.chat_bubble_outline_rounded),
                  size: 16,
                  color: s.pinned
                      ? AppColors.primary
                      : (active ? AppColors.primary : AppColors.textMuted),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight:
                                active ? FontWeight.w700 : FontWeight.w600,
                            color: isDark
                                ? AppColors.textPrimary
                                : Dt.textPrimary)),
                    const SizedBox(height: 2),
                    Text(fmtDate(s.updatedAt),
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textMuted)),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                icon: Icon(Icons.more_horiz_rounded,
                    size: 18,
                    color: AppColors.textMuted.withValues(alpha: 0.7)),
                tooltip: 'More',
                onSelected: (v) {
                  if (v == 'export') exportSession(context, s);
                  if (v == 'pin') controller.togglePin(s.id);
                  if (v == 'persona') showPersonaDialog(context, s, isDark);
                  if (v == 'archive') controller.toggleArchive(s.id);
                  if (v == 'hide') controller.toggleHidden(s.id);
                  if (v == 'lock') controller.toggleLocked(s.id);
                  if (v == 'label') showLabelDialog(context, s, isDark);
                  if (v == 'delete') controller.deleteChat(s.id);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'pin',
                    child: Row(children: [
                      Icon(
                        s.pinned
                            ? Icons.push_pin_outlined
                            : Icons.push_pin_rounded,
                        size: 16,
                        color: s.pinned ? AppColors.primary : null,
                      ),
                      const SizedBox(width: 10),
                      Text(s.pinned ? 'Unpin' : 'Pin to top',
                          style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'export',
                    child: Row(children: [
                      const Icon(LucideIcons.share2, size: 16),
                      const SizedBox(width: 10),
                      Text('Export',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'persona',
                    child: Row(children: [
                      Icon(LucideIcons.userCog,
                          size: 16,
                          color:
                              s.persona.isNotEmpty ? AppColors.primary : null),
                      const SizedBox(width: 10),
                      Text(
                          s.persona.isNotEmpty
                              ? 'Edit persona'
                              : 'Set persona…',
                          style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'archive',
                    child: Row(children: [
                      Icon(
                          s.archived
                              ? Icons.unarchive_outlined
                              : Icons.archive_outlined,
                          size: 16),
                      const SizedBox(width: 10),
                      Text(s.archived ? 'Unarchive' : 'Archive',
                          style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'hide',
                    child: Row(children: [
                      Icon(
                          s.hidden
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 16),
                      const SizedBox(width: 10),
                      Text(s.hidden ? 'Unhide' : 'Hide',
                          style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'label',
                    child: Row(children: [
                      const Icon(LucideIcons.tag, size: 16),
                      const SizedBox(width: 10),
                      Text(s.label.isEmpty ? 'Set label…' : 'Label: ${s.label}',
                          style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'lock',
                    child: Row(children: [
                      Icon(
                          s.locked
                              ? Icons.lock_open_outlined
                              : Icons.lock_outline_rounded,
                          size: 16),
                      const SizedBox(width: 10),
                      Text(s.locked ? 'Unlock chat' : 'Lock chat',
                          style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      const Icon(Icons.delete_outline_rounded,
                          size: 16, color: AppColors.error),
                      const SizedBox(width: 10),
                      Text('common_delete'.tr,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.error)),
                    ]),
                  ),
                ],
              ),
            ]),
          ),
        ),
      ),
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
