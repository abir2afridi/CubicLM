import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../controllers/chat_controller.dart';
import '../../controllers/home_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../controllers/vision_live_controller.dart';
import '../../core/colors.dart';
import '../../ffi/sd_ffi_bindings.dart';
import '../../services/local_image_service.dart';
import '../../theme/design_tokens.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/attachment_preview.dart';
import '../../widgets/model_switcher_sheet.dart';
import 'chat_widgets.dart';
import 'template_sheets.dart';

/// Chat composer input bar + model label.
/// Extracted from views/chat_view.dart.

ChatController get _c => Get.find<ChatController>();

Widget inputBar(BuildContext context, bool isDark) {
  return SafeArea(
    top: false,
    child: DropTarget(
      onDragDone: (details) {
        if (details.files.isNotEmpty) {
          final file = details.files.first;
          _c.handleFile(file.path, file.name);
        }
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        color: Colors.transparent,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Attachment preview
        Obx(() {
          final name = _c.selectedFileName.value;
          if (name == null) return const SizedBox.shrink();
          return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AttachmentPreview(
                fileName: name,
                fileType: _c.selectedFileType.value,
                fileSize: _c.selectedFileSize.value > 0
                    ? _c.selectedFileSize.value
                    : null,
                imagePath: _c.selectedImagePath.value,
                imageBase64: _c.selectedImageBase64.value,
                onRemove: () {
                  _c.clearImage();
                  _c.clearFile();
                },
              ));
        }),
        // Web URL preview pills — shows chips for https:// links in input
        Obx(() {
          final text = _c.inputText.value;
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
                final displayDomain =
                    domain.length > 28 ? '${domain.substring(0, 28)}…' : domain;
                final faviconUrl =
                    'https://www.google.com/s2/favicons?domain=$domain&sz=32';
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.black.withValues(alpha: 0.05),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.network(
                            faviconUrl,
                            width: 14,
                            height: 14,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                                LucideIcons.globe,
                                size: 10,
                                color: Color(0xFF3B82F6)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          displayDomain,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Dt.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          final current = _c.textController.text;
                          final updated = current
                              .replaceAll(url, '')
                              .replaceAll(RegExp(r'\s{2,}'), ' ')
                              .trim();
                          _c.textController.text = updated;
                          _c.textController.selection =
                              TextSelection.collapsed(offset: updated.length);
                          _c.inputText.value = updated;
                        },
                        child: Icon(
                          LucideIcons.x,
                          size: 14,
                          color: isDark
                              ? AppColors.textSecondary
                              : Dt.textSecondary,
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
          if (!_c.isListening.value) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    focusNode: _c.composerKeyboardFocusNode,
                    onKeyEvent: (event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.enter &&
                          !HardwareKeyboard.instance.isShiftPressed) {
                        // Prevent the newline from being inserted
                        final text = _c.textController.text.trim();
                        if (text.isNotEmpty ||
                            _c.selectedFileName.value != null) {
                          // Remove trailing newline that may have been inserted
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            final current = _c.textController.text;
                            if (current.endsWith('\n')) {
                              _c.textController.text = current.trimRight();
                              _c.inputText.value = _c.textController.text;
                            }
                            _c.sendMessage();
                          });
                        }
                      }
                    },
                    child: TextField(
                      focusNode: _c.composerFocusNode,
                      controller: _c.textController,
                      onChanged: (v) => _c.inputText.value = v,
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
                    onTap: () => showAddToChatSheet(
                      context,
                      isDark: isDark,
                      onCamera: _c.takePhoto,
                      onImage: _c.pickImage,
                      onFile: _c.pickFile,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Model selector pill — fixed width so label change
                  // (Local → loaded model name) doesn't shift the
                  // right cluster. 125dp fits 14 chars at 12.5sp + chevron.
                  SizedBox(
                    width: 125,
                    child: Obx(() => AppModelPill(
                          label: composerModelLabel(),
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
                  Obx(() {
                    final enabled = _c.isSearchMode.value;
                    return AppCircleButton(
                      icon: LucideIcons.search,
                      tooltip: 'Deep Search (Perplexity-style)',
                      iconColor: enabled ? Dt.accent : null,
                      onTap: () => _c.isSearchMode.value = !enabled,
                    );
                  }),
                  const SizedBox(width: 6),
                  Obx(() {
                    final vision = Get.find<VisionLiveController>();
                    final enabled = vision.isLive.value;
                    return AppCircleButton(
                      icon: LucideIcons.video,
                      tooltip: 'Live Vision (Snapshot Loop)',
                      iconColor: enabled ? AppColors.error : null,
                      onTap: vision.toggleLive,
                    );
                  }),
                  const SizedBox(width: 6),
                  AppCircleButton(
                    icon: LucideIcons.layoutTemplate,
                    tooltip: 'Prompt templates',
                    onTap: () => showTemplateSheet(context, isDark),
                  ),
                  const Spacer(),
                  // Right cluster: mic (muted circle) + primary CTA (solid dark)
                  // Spacer pushes this cluster to the far right corner,
                  // and inner Row keeps mic + send at the same vertical level.
                  Obx(() {
                    final loading = _c.isLoading.value;
                    final listening = _c.isListening.value;
                    final hasContent = _c.inputText.value.isNotEmpty ||
                        _c.selectedFileName.value != null ||
                        _c.selectedImagePath.value != null;
                    // Hide the mic when speech recognition is
                    // unavailable (e.g. permission denied, or a
                    // platform without an STT engine) instead of
                    // showing a dead button.
                    final micAvailable = _c.sttAvailable.value;
                    final voiceMode = _c.voiceMode.value;

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
                              if (_c.voiceMode.value) {
                                _c.setVoiceMode(false);
                              } else {
                                _c.toggleListening();
                              }
                            },
                            onLongPress: () {
                              if (!_c.voiceMode.value) {
                                _c.setVoiceMode(true);
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
                              ? _c.stopGenerating
                              : (hasContent ? _c.sendMessage : null),
                        ),
                      ],
                    );
                  }),
                ]),
              ]),
            ),
          ],
        ),
      ),
    ),
  );
}
