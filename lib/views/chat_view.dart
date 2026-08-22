import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../controllers/chat_controller.dart';
import '../controllers/settings_controller.dart';
import '../controllers/model_controller.dart';
import '../controllers/home_controller.dart';
import '../services/inference_service.dart';
import '../services/local_image_service.dart';
import '../ffi/sd_ffi_bindings.dart';
import '../utils/thought_parser.dart';
import '../widgets/attachment_preview.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/thought_disclosure.dart';
import '../core/colors.dart';

class ChatView extends GetView<ChatController> {
  const ChatView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.bg : AppColors.bgLight,
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
            return NotificationListener<ScrollUpdateNotification>(
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
                   return ChatBubble(
                     message: controller.messages[i],
                     onCopy: () {
                       Clipboard.setData(ClipboardData(text: controller.messages[i].content));
                     },
                     onRetry: () => controller.regenerateFromMessage(controller.messages[i]),
                     onBranch: () => controller.branchNewChat(controller.messages[i]),
                   );
                },
              ),
            );
          })),
          _inputBar(context, isDark),
        ],
      ),
    );
  }

  // ── AppBar ──
  PreferredSizeWidget _appBar(BuildContext context, bool isDark) {
    return AppBar(
      backgroundColor: isDark ? AppColors.bg : AppColors.bgLight,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleSpacing: 0,
      title: Obx(() {
        final sid = controller.currentSessionId.value;
        final settings = Get.find<SettingsController>();
        final inf = Get.find<InferenceService>();
        final isLocal = settings.inferenceMode.value == 'local';
        String model;
        if (isLocal) {
          final localImage = Get.find<LocalImageService>();
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
          final p = settings.cloudProvider.value;
          model = p == 'openai'
              ? settings.openaiModel.value
              : p == 'anthropic'
                  ? settings.anthropicModel.value
                  : p == 'google'
                      ? settings.googleModel.value
                      : p == 'stability'
                          ? settings.stabilityModel.value
                          : p == 'nvidia'
                              ? settings.nvidiaModel.value
                              : p == 'openrouter'
                                  ? settings.openRouterModel.value
                                  : p == 'custom'
                                      ? settings.customCloudModel.value
                                      : settings.kimiModel.value;
          if (p == 'custom' && model.isNotEmpty) {
            model = '${settings.customCloudName.value}: $model';
          }
        }
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
            Row(children: [
              Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (isLocal ? (inf.isModelLoaded.value ? AppColors.success : AppColors.warning) : AppColors.primary).withValues(alpha: 0.4),
                          blurRadius: 4,
                        )
                      ],
                      color: isLocal
                          ? (inf.isModelLoaded.value
                              ? AppColors.success
                              : AppColors.warning)
                          : AppColors.primary)),
              const SizedBox(width: 6),
              Flexible(
                  child: Text('$model · ${isLocal ? "Local" : "Cloud"}',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: Theme.of(context).hintColor,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis)),
            ]),
          ]),
        );
      }),
      actions: [
        IconButton(
            icon: Icon(Icons.history_rounded,
                size: 22, color: Theme.of(context).hintColor),
            onPressed: () => _showHistory(context)),
        const SizedBox(width: 4),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: IconButton(
              tooltip: 'New Chat',
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.add_rounded, size: 22, color: AppColors.primary),
              ),
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
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surface : const Color(0xFFF1F5F9),
          border: Border(bottom: BorderSide(color: isDark ? AppColors.border : AppColors.borderLightMode, width: 1)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.primary)),
            const SizedBox(width: 10),
            Text('Syncing model weights… $pct%',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: isDark ? AppColors.textPrimary : const Color(0xFF0F172A),
                    fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                  value: inf.modelLoadProgress.value,
                  backgroundColor: isDark ? AppColors.bg : const Color(0xFFE2E8F0),
                  color: AppColors.primary,
                  minHeight: 5)),
        ]),
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
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        decoration: BoxDecoration(
            color: isDark ? AppColors.bg.withValues(alpha: 0.5) : AppColors.bgLight.withValues(alpha: 0.5),
            border:
                Border(bottom: BorderSide(color: isDark ? AppColors.border : AppColors.borderLightMode, width: 0.5))),
        child: Row(children: [
          Icon(Icons.auto_graph_rounded, size: 14, color: accent),
          const SizedBox(width: 8),
          Text('${_fmtK(used)} / ${_fmtK(total)} tokens',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: Theme.of(context).hintColor,
                  fontWeight: FontWeight.w700)),
          const SizedBox(width: 12),
          Expanded(
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                      value: pct,
                      backgroundColor: isDark ? AppColors.surface : const Color(0xFFE2E8F0),
                      color: accent,
                      minHeight: 4))),
          const SizedBox(width: 10),
          Text('${(pct * 100).toStringAsFixed(0)}%',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11, color: accent, fontWeight: FontWeight.w800)),
        ]),
      );
    });
  }

  // ── Empty State ──
  Widget _emptyState(BuildContext context, bool isDark) {
    final suggestions = [
      'Explain quantum computing simply',
      'Write a short poem about time',
      'Help me debug my code',
      'Summarize a complex topic'
    ];
    return Center(
        child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Glowing Logo
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.1),
                blurRadius: 40,
                spreadRadius: 10,
              )
            ],
          ),
          child: Image.asset(
            'assets/icons/CubicLM.png',
            width: 100,
            height: 100,
          ),
        ),
        const SizedBox(height: 32),
        Text('Curious to learn?',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
                color: isDark ? AppColors.textPrimary : const Color(0xFF0F172A))),
        const SizedBox(height: 8),
        Text('Select a topic or start typing below.',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                color: Theme.of(context).hintColor,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 40),
        Obx(() {
          final settings = Get.find<SettingsController>();
          final models = Get.find<ModelController>();
          final isLocal = settings.inferenceMode.value == 'local';
          if (isLocal && models.downloadedCount == 0) {
            return Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.2)),
              ),
              child: Column(children: [
                const Icon(Icons.cloud_download_rounded,
                    color: AppColors.warning, size: 40),
                const SizedBox(height: 16),
                Text('No Local Models Found',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black)),
                const SizedBox(height: 8),
                Text(
                    'Download a model to enable offline AI processing on your device.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14, color: Theme.of(context).hintColor)),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => Get.find<HomeController>().changeTab(1),
                  icon: const Icon(Icons.arrow_right_alt_rounded, size: 20),
                  label: const Text('Go to Model Hub'),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.warning,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 14)),
                ),
              ]),
            );
          }
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: suggestions
                .map((s) => _suggestionChip(context, s, isDark))
                .toList(),
          );
        }),
      ]),
    ));
  }

  Widget _suggestionChip(BuildContext context, String text, bool isDark) {
    return InkWell(
      onTap: () {
        controller.createNewChat();
        controller.textController.text = text;
        controller.inputText.value = text;
        controller.sendMessage();
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        constraints: const BoxConstraints(maxWidth: 220),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surface : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? AppColors.border : AppColors.borderLightMode),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Text(text,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: isDark ? AppColors.textPrimary : const Color(0xFF0F172A),
                fontWeight: FontWeight.w600,
                height: 1.4)),
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
            color: isDark ? AppColors.surface : const Color(0xFFF1F5F9),
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(22),
                topRight: Radius.circular(22),
                bottomRight: Radius.circular(22),
                bottomLeft: Radius.circular(6)),
            border: Border.all(color: isDark ? AppColors.border : AppColors.borderLightMode, width: 0.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                blurRadius: 8,
                offset: const Offset(0, 4),
              )
            ],
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
                if (inf.tokensPerSecond.value <= 0) {
                  return const SizedBox.shrink();
                }
                return Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                          '${inf.tokensPerSecond.value.toStringAsFixed(1)} tok/s',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700)),
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
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg : AppColors.bgLight,
        border: Border(top: BorderSide(color: isDark ? AppColors.border : AppColors.borderLightMode, width: 1)),
      ),
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
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              // Attach button
              Obx(() {
                final s = Get.find<SettingsController>();
                final inf = Get.find<InferenceService>();
                final isCloud = s.inferenceMode.value == 'cloud';
                final isLocalVision = s.inferenceMode.value == 'local' &&
                    inf.loadedModelRuntime.value == 'litert' &&
                    inf.isVisionLoaded.value;
                if (!isCloud && !isLocalVision) return const SizedBox.shrink();
                return _AttachButton(
                  isDark: isDark,
                  isCloud: isCloud,
                  onCamera: controller.takePhoto,
                  onImage: controller.pickImage,
                  onFile: controller.pickFile,
                  context: context,
                );
              }),
              // Text field with floating container
              Expanded(
                  child: Container(
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surface : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: isDark ? AppColors.border : AppColors.borderLightMode),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: TextField(
                  controller: controller.textController,
                  onChanged: (v) => controller.inputText.value = v,
                  maxLines: 5,
                  minLines: 1,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      color: isDark ? AppColors.textPrimary : const Color(0xFF0F172A),
                      fontWeight: FontWeight.w500),
                  decoration: InputDecoration(
                    hintText: 'Enter your request…',
                    hintStyle: GoogleFonts.plusJakartaSans(
                        fontSize: 15, color: Theme.of(context).hintColor, fontWeight: FontWeight.w500),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    isDense: true,
                  ),
                  onSubmitted: (_) => controller.sendMessage(),
                ),
              )),
              const SizedBox(width: 8),
              // Main Action Button
              Obx(() {
                final loading = controller.isLoading.value;
                final listening = controller.isListening.value;
                final hasContent = controller.inputText.value.isNotEmpty ||
                    controller.selectedFileName.value != null ||
                    controller.selectedImagePath.value != null;

                final Color bgColor;
                final IconData iconData;
                final VoidCallback? onTap;

                if (loading) {
                  bgColor = AppColors.error;
                  iconData = Icons.stop_rounded;
                  onTap = controller.stopGenerating;
                } else if (listening) {
                  bgColor = AppColors.error;
                  iconData = Icons.stop_rounded;
                  onTap = controller.toggleListening;
                } else if (hasContent) {
                  bgColor = AppColors.primary;
                  iconData = Icons.arrow_upward_rounded;
                  onTap = controller.sendMessage;
                } else {
                  bgColor = isDark ? AppColors.surfaceLight : const Color(0xFFE2E8F0);
                  iconData = Icons.mic_rounded;
                  onTap = controller.toggleListening;
                }

                return GestureDetector(
                  onTap: onTap,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.elasticOut,
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: bgColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: bgColor.withValues(
                              alpha: (loading || listening || hasContent)
                                  ? 0.4
                                  : 0.0),
                          blurRadius:
                              (loading || listening || hasContent) ? 12 : 0,
                        ),
                      ],
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Icon(iconData,
                          key: ValueKey(iconData),
                          color: (loading || listening || hasContent)
                              ? Colors.white
                              : Theme.of(context).hintColor,
                          size: 22),
                    ),
                  ),
                );
              }),
            ]),
          ])),
    );
  }

  // ── Chat History ──
  void _showHistory(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.surface : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Container(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceLight : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2))),
          Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  Text('Chat History',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: isDark ? AppColors.textPrimary : const Color(0xFF0F172A))),
                  const Spacer(),
                ],
              )),
          Divider(height: 1, color: isDark ? AppColors.border : AppColors.borderLightMode),
          Flexible(child: Obx(() {
            if (controller.sessions.isEmpty) {
              return Padding(
                  padding: const EdgeInsets.all(48),
                  child: Text('No active sessions found.',
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).hintColor)));
            }
            return ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 20),
              itemCount: controller.sessions.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, indent: 72, color: isDark ? AppColors.border : AppColors.borderLightMode),
              itemBuilder: (ctx, i) {
                final s = controller.sessions[i];
                final active = controller.currentSessionId.value == s.id;
                return ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                          color: active
                              ? AppColors.primary.withValues(alpha: 0.1)
                              : (isDark ? AppColors.surfaceLight : const Color(0xFFF1F5F9)),
                          borderRadius: BorderRadius.circular(12)),
                      child: Icon(
                          active
                              ? Icons.chat_bubble_rounded
                              : Icons.chat_bubble_outline_rounded,
                          size: 18,
                          color: active
                              ? AppColors.primary
                              : Theme.of(ctx).hintColor)),
                  title: Text(s.title,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w600,
                          color: isDark ? AppColors.textPrimary : const Color(0xFF0F172A)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  subtitle: Text(_fmtDate(s.updatedAt),
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: Theme.of(ctx).hintColor, fontWeight: FontWeight.w500)),
                  trailing: IconButton(
                      icon: Icon(Icons.delete_outline_rounded,
                          size: 20, color: AppColors.error.withValues(alpha: 0.6)),
                      onPressed: () => controller.deleteChat(s.id)),
                  onTap: () {
                    controller.openChat(s.id);
                    Navigator.pop(ctx);
                  },
                );
              },
            );
          })),
        ]),
      ),
    );
  }

  // ── Markdown styles ──
  MarkdownStyleSheet _streamMd(BuildContext c, bool isDark) {
    final clr = isDark ? AppColors.textPrimary : const Color(0xFF0F172A);
    final base = GoogleFonts.plusJakartaSans(fontSize: 15, color: clr, height: 1.6, fontWeight: FontWeight.w500);
    final codeBg = isDark ? AppColors.surfaceLight : const Color(0xFFE2E8F0);
    return MarkdownStyleSheet.fromTheme(Theme.of(c)).copyWith(
        p: base,
        strong: base.copyWith(fontWeight: FontWeight.w800),
        em: base.copyWith(fontStyle: FontStyle.italic),
        listBullet: base,
        code: GoogleFonts.firaCode(
            fontSize: 13, color: clr, backgroundColor: codeBg),
        codeblockDecoration: BoxDecoration(
            color: codeBg, borderRadius: BorderRadius.circular(14)));
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

// ── Attach Button ──
class _AttachButton extends StatelessWidget {
  final bool isDark;
  final bool isCloud;
  final VoidCallback onCamera;
  final VoidCallback onImage;
  final VoidCallback onFile;
  final BuildContext context;

  const _AttachButton({
    required this.isDark,
    required this.isCloud,
    required this.onCamera,
    required this.onImage,
    required this.onFile,
    required this.context,
  });

  @override
  Widget build(BuildContext buildContext) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => _showSheet(buildContext),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceLight : const Color(0xFFE2E8F0),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.add_rounded,
              color: Theme.of(buildContext).hintColor, size: 24),
        ),
      ),
    );
  }

  void _showSheet(BuildContext ctx) {
    final isDarkSheet = Theme.of(ctx).brightness == Brightness.dark;
    showModalBottomSheet(
      context: ctx,
      backgroundColor: isDarkSheet ? AppColors.surface : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: isDarkSheet ? AppColors.surfaceLight : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 24),
              Text('Add Content',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: isDarkSheet ? AppColors.textPrimary : const Color(0xFF0F172A))),
              const SizedBox(height: 24),
              Row(children: [
                _SheetTile(
                  icon: Icons.camera_alt_rounded,
                  color: AppColors.warning,
                  label: 'Camera',
                  sub: 'Take a photo',
                  isDark: isDarkSheet,
                  onTap: () {
                    Navigator.pop(_);
                    onCamera();
                  },
                ),
                const SizedBox(width: 12),
                _SheetTile(
                  icon: Icons.photo_library_rounded,
                  color: AppColors.success,
                  label: 'Photos',
                  sub: 'Pick from gallery',
                  isDark: isDarkSheet,
                  onTap: () {
                    Navigator.pop(_);
                    onImage();
                  },
                ),
                const SizedBox(width: 12),
                _SheetTile(
                  icon: Icons.attach_file_rounded,
                  color: AppColors.primary,
                  label: 'Files',
                  sub: 'Documents & more',
                  isDark: isDarkSheet,
                  onTap: () {
                    Navigator.pop(_);
                    onFile();
                  },
                ),
              ]),
            ]),
          ),
        );
      },
    );
  }
}

class _SheetTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String sub;
  final bool isDark;
  final VoidCallback onTap;

  const _SheetTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.sub,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceLight : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? AppColors.border : AppColors.borderLightMode,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 14),
              Text(label,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppColors.textPrimary : const Color(0xFF0F172A))),
              const SizedBox(height: 2),
              Text(sub,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).hintColor)),
            ],
          ),
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
    return AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          return Row(
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
                                color: AppColors.primary.withValues(alpha: 0.7)))));
              }));
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
