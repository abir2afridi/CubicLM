import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../controllers/chat_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../services/inference_service.dart';
import '../../services/local_image_service.dart';
import '../../theme/design_tokens.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/model_switcher_sheet.dart';
import 'chat_widgets.dart';

/// Prompt template + add-to-chat sheets.
/// Extracted from views/chat_view.dart.

ChatController get _c => Get.find<ChatController>();

/// "+" sheet per reference spec §2.3: three equal tiles, then stacked
/// row-cards — including the Web-access toggle that used to sit in the
/// composer bar.
void showTemplateSheet(BuildContext context, bool isDark) {
  _c.ensureTemplatesLoaded();
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
                      itemCount: _c.promptTemplates.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final t = _c.promptTemplates[i];
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
                                  onPressed: () =>
                                      _c.deletePromptTemplate(t['id'] ?? ''),
                                ),
                          onTap: () {
                            Navigator.pop(sheetCtx);
                            _c.insertTemplate(t['body'] ?? '');
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
                    showTemplateEditor(context, isDark);
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

void showTemplateEditor(BuildContext context, bool isDark) {
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
              _c.addPromptTemplate(nameCtrl.text, bodyCtrl.text);
              Navigator.pop(dlgCtx);
            },
            child: const Text('Save')),
      ],
    ),
  );
}

void showAddToChatSheet(
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
                subtitle: composerModelLabel(),
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

/// Short label for the composer's model pill.
/// Pinned chats show the pinned model with 📌 (may differ from global).
String composerModelLabel() {
  if (_c.chatHasModelPin) {
    final pin = _c.chatPinnedModelLabel;
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
