import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../controllers/cloud_model_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../core/colors.dart';
import '../../theme/design_tokens.dart';
import 'local_model_card.dart';
import 'provider_theme.dart';

/// Provider key dialogs (add custom provider, save API key).
/// Extracted from views/model_view.dart.
void showCustomProviderDialog(
  BuildContext context,
  CloudModelController cloud,
) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final nameCtrl = TextEditingController();
  final baseUrlCtrl = TextEditingController();
  final apiKeyCtrl = TextEditingController();
  final modelCtrl = TextEditingController();
  final obscureKey = true.obs;
  final error = ''.obs;
  final isVerifying = false.obs;
  final verifiedCount = (-1).obs; // -1 = not verified yet

  Get.dialog(AlertDialog(
    backgroundColor: isDark ? AppColors.surface : Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    titlePadding: const EdgeInsets.fromLTRB(26, 26, 22, 0),
    contentPadding: const EdgeInsets.fromLTRB(26, 20, 26, 10),
    actionsPadding: const EdgeInsets.fromLTRB(22, 10, 22, 22),
    title: Row(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: AppColors.secondary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.tune, color: AppColors.secondary, size: 29),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Custom API',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 20, fontWeight: FontWeight.w800)),
              Text('OpenAI-compatible endpoint',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).hintColor)),
            ],
          ),
        ),
      ],
    ),
    content: SizedBox(
      width: double.maxFinite,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameCtrl,
              style: GoogleFonts.plusJakartaSans(fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Profile name (optional)',
                hintText: 'e.g. My Local Server',
                prefixIcon: Icon(LucideIcons.tag, size: 22),
                contentPadding:
                    EdgeInsets.symmetric(vertical: 18, horizontal: 18),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: baseUrlCtrl,
              style: GoogleFonts.firaCode(fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'http://192.168.1.100:8080',
                prefixIcon: Icon(LucideIcons.link, size: 22),
                contentPadding:
                    EdgeInsets.symmetric(vertical: 18, horizontal: 18),
              ),
            ),
            const SizedBox(height: 12),
            Obx(() => TextField(
                  controller: apiKeyCtrl,
                  obscureText: obscureKey.value,
                  style: GoogleFonts.firaCode(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'API key',
                    hintText: 'sk-... or leave empty for no auth',
                    prefixIcon: const Icon(Icons.key_outlined, size: 22),
                    suffixIcon: IconButton(
                      tooltip: obscureKey.value ? 'Show' : 'Hide',
                      onPressed: () => obscureKey.value = !obscureKey.value,
                      icon: Icon(
                          obscureKey.value
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 22),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 18, horizontal: 18),
                  ),
                )),
            const SizedBox(height: 12),
            TextField(
              controller: modelCtrl,
              style: GoogleFonts.firaCode(fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Model ID (fallback if fetch fails)',
                hintText: 'e.g. llama-3.1-8b-instruct',
                prefixIcon: Icon(Icons.smart_toy_outlined, size: 22),
                contentPadding:
                    EdgeInsets.symmetric(vertical: 18, horizontal: 18),
              ),
            ),
            const SizedBox(height: 14),
            // Verify button
            SizedBox(
              width: double.infinity,
              child: Obx(() => OutlinedButton.icon(
                    onPressed: isVerifying.value
                        ? null
                        : () async {
                            final baseUrl = baseUrlCtrl.text.trim();
                            if (baseUrl.isEmpty) {
                              error.value = 'Enter Base URL first.';
                              return;
                            }
                            final uri = Uri.tryParse(baseUrl);
                            if (uri == null ||
                                !uri.hasScheme ||
                                uri.host.isEmpty) {
                              error.value = 'Enter a valid URL.';
                              return;
                            }
                            error.value = '';
                            isVerifying.value = true;
                            final settings = Get.find<SettingsController>();
                            await settings.setCustomCloudConfig(
                              name: nameCtrl.text.trim(),
                              baseUrl: baseUrlCtrl.text.trim(),
                              apiKey: apiKeyCtrl.text.trim(),
                              model: modelCtrl.text.trim(),
                            );
                            await cloud.selectModel(
                                'custom', modelCtrl.text.trim(),
                                showSnackbar: false);
                            await cloud.refreshCustomModels();
                            isVerifying.value = false;
                            final models =
                                cloud.modelsByProvider['custom'] ?? [];
                            verifiedCount.value = models.length;
                            if (cloud.errorByProvider.containsKey('custom')) {
                              error.value = cloud.errorByProvider['custom']!;
                            }
                          },
                    icon: isVerifying.value
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(LucideIcons.wifi, size: 18),
                    label: Text(isVerifying.value
                        ? 'Verifying...'
                        : 'Verify & Load Models'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(
                          color: AppColors.secondary.withValues(alpha: 0.4)),
                    ),
                  )),
            ),
            // Verification result
            Obx(() {
              if (verifiedCount.value < 0) return const SizedBox.shrink();
              final models = cloud.modelsByProvider['custom'] ?? [];
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: models.isNotEmpty
                        ? AppColors.success.withValues(alpha: 0.08)
                        : AppColors.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: models.isNotEmpty
                          ? AppColors.success.withValues(alpha: 0.25)
                          : AppColors.warning.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            models.isNotEmpty
                                ? LucideIcons.checkCircle
                                : LucideIcons.info,
                            size: 16,
                            color: models.isNotEmpty
                                ? AppColors.success
                                : AppColors.warning,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            models.isNotEmpty
                                ? '${models.length} model${models.length == 1 ? '' : 's'} found'
                                : 'No models found — enter Model ID manually',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: models.isNotEmpty
                                  ? AppColors.success
                                  : AppColors.warning,
                            ),
                          ),
                        ],
                      ),
                      if (models.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: models.take(12).map((m) {
                            final isActive =
                                cloud.activeModelFor('custom') == m;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? Dt.accent.withValues(alpha: 0.15)
                                    : isDark
                                        ? Colors.white.withValues(alpha: 0.06)
                                        : Colors.black.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isActive
                                      ? Dt.accent.withValues(alpha: 0.4)
                                      : isDark
                                          ? Colors.white.withValues(alpha: 0.08)
                                          : Colors.black
                                              .withValues(alpha: 0.08),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(m,
                                      style: GoogleFonts.firaCode(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: isActive
                                            ? Dt.accent
                                            : (isDark
                                                ? Colors.white70
                                                : Colors.black54),
                                      )),
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: AppColors.success
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text('FREE',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 8,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.success,
                                        )),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                        if (models.length > 12)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('+ ${models.length - 12} more',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  color: Theme.of(context).hintColor,
                                )),
                          ),
                      ],
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            Obx(() {
              if (error.isEmpty) return const SizedBox.shrink();
              return buildErrorBox(context, error.value);
            }),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Get.back(closeOverlays: false),
        child: Text('common_cancel'.tr,
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
      ),
      ElevatedButton(
        onPressed: () async {
          final baseUrl = baseUrlCtrl.text.trim();
          final model = modelCtrl.text.trim();
          if (baseUrl.isEmpty) {
            error.value = 'Base URL is required.';
            return;
          }
          final uri = Uri.tryParse(baseUrl);
          if (uri == null ||
              !uri.hasScheme ||
              (uri.scheme != 'https' && uri.scheme != 'http') ||
              uri.host.isEmpty) {
            error.value = 'Enter a valid URL (http:// or https://).';
            return;
          }
          if (model.isEmpty &&
              (cloud.modelsByProvider['custom'] ?? []).isEmpty) {
            error.value = 'Enter a Model ID or verify endpoint first.';
            return;
          }
          error.value = '';
          await cloud.saveCustomProvider();
          final activeModel = model.isNotEmpty
              ? model
              : (cloud.modelsByProvider['custom'] ?? []).first;
          await cloud.selectModel('custom', activeModel, showSnackbar: false);
          Get.back(closeOverlays: false);
          Get.snackbar('Custom API Saved',
              '${nameCtrl.text.isEmpty ? "Custom API" : nameCtrl.text} · $activeModel',
              snackPosition: SnackPosition.BOTTOM);
        },
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        ),
        child: Text('Save',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
      ),
    ],
  ));
}

void showProviderKeyDialog(
  BuildContext context,
  CloudModelController cloud,
  CloudProviderInfo provider, {
  bool openModelsAfterSave = false,
}) {
  final keyController = cloud.apiKeyControllerFor(provider.id);
  final obscureKey = true.obs;
  final isVerifying = false.obs;
  // Verify-before-save: Save unlocks only for the exact text that
  // passed verification. Editing the field invalidates it.
  final draftKey = keyController.text.obs;
  final verifiedFor =
      (cloud.apiKeyFor(provider.id).isNotEmpty ? keyController.text : '').obs;
  void onDraftChanged(String v) {
    draftKey.value = v;
    if (v != verifiedFor.value) verifiedFor.value = '';
    cloud.errorByProvider.remove(provider.id);
  }

  final accent = providerAccent(provider.id);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final hasExistingKey = cloud.apiKeyFor(provider.id).isNotEmpty;
  Get.dialog(AlertDialog(
    backgroundColor: isDark ? AppColors.surface : Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    titlePadding: const EdgeInsets.fromLTRB(26, 26, 22, 0),
    contentPadding: const EdgeInsets.fromLTRB(26, 20, 26, 10),
    actionsPadding: const EdgeInsets.fromLTRB(22, 10, 22, 22),
    title: Row(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(provider.icon, color: accent, size: 29),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                provider.name,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                hasExistingKey ? 'Edit API key' : 'API key required',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).hintColor,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
    content: SizedBox(
      width: double.maxFinite,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Obx(
            () => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'API key',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                    const Spacer(),
                    if (draftKey.value.isNotEmpty)
                      InkWell(
                        onTap: () {
                          keyController.clear();
                          onDraftChanged('');
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Tooltip(
                          message: 'Clear',
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(
                              Icons.close_rounded,
                              size: 19,
                              color: Theme.of(context).hintColor,
                            ),
                          ),
                        ),
                      ),
                    InkWell(
                      onTap: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (data?.text != null) {
                          keyController.text = data!.text!;
                          keyController.selection = TextSelection.fromPosition(
                            TextPosition(offset: keyController.text.length),
                          );
                          onDraftChanged(keyController.text);
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Tooltip(
                        message: 'Paste from clipboard',
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            LucideIcons.clipboardPaste,
                            size: 19,
                            color: Theme.of(context).hintColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: keyController,
                  obscureText: obscureKey.value,
                  onChanged: onDraftChanged,
                  style: GoogleFonts.firaCode(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Paste ${provider.name} key',
                    prefixIcon: const Icon(Icons.key_outlined, size: 23),
                    suffixIcon: IconButton(
                      tooltip:
                          obscureKey.value ? 'Show API key' : 'Hide API key',
                      onPressed: () => obscureKey.value = !obscureKey.value,
                      icon: Icon(
                        obscureKey.value
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 20, horizontal: 18),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Obx(() {
            final error = cloud.errorByProvider[provider.id];
            if (error == null || error.isEmpty) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: buildErrorBox(context, error),
            );
          }),
          Obx(() {
            final ok = verifiedFor.value.isNotEmpty &&
                verifiedFor.value == draftKey.value;
            if (!ok) {
              return Text(
                'Paste the key, verify it, then save.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: Theme.of(context).hintColor,
                  height: 1.35,
                ),
              );
            }
            final count = cloud.verifiedModelCountByProvider[provider.id] ?? 0;
            return Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    size: 16, color: AppColors.success),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    count > 0
                        ? 'Verified — $count models found.'
                        : 'Verified — this key works.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.success,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            );
          }),
          const SizedBox(height: 14),
          // Full-width stacked actions: no cramped 3-button row.
          Obx(() => SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed:
                      (isVerifying.value || draftKey.value.trim().isEmpty)
                          ? null
                          : () async {
                              isVerifying.value = true;
                              final err = await cloud.verifyApiKey(
                                  provider.id, draftKey.value);
                              isVerifying.value = false;
                              if (err == null) {
                                verifiedFor.value = draftKey.value;
                                cloud.errorByProvider.remove(provider.id);
                              } else {
                                verifiedFor.value = '';
                                cloud.errorByProvider[provider.id] = err;
                              }
                            },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: isVerifying.value
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.verified_outlined, size: 18),
                            const SizedBox(width: 8),
                            Text('Verify Key',
                                style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w800, fontSize: 14)),
                          ],
                        ),
                ),
              )),
          const SizedBox(height: 8),
          Obx(() {
            final ok = verifiedFor.value.isNotEmpty &&
                verifiedFor.value == draftKey.value;
            return SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: !ok
                    ? null
                    : () async {
                        final value = keyController.text.trim();
                        await cloud.saveApiKey(provider.id, value);
                        await cloud.refreshModels(provider.id);
                        if ((cloud.errorByProvider[provider.id] ?? '')
                            .isNotEmpty) {
                          return;
                        }
                        Get.back(closeOverlays: false);
                      },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.save_outlined, size: 18),
                    const SizedBox(width: 8),
                    Text('Save Key',
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w800, fontSize: 14)),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    ),
    actions: [
      if (hasExistingKey)
        TextButton(
          onPressed: () async {
            await cloud.removeApiKey(provider.id);
            keyController.clear();
            Get.back(closeOverlays: false);
            Get.snackbar(
              'Key Removed',
              '${provider.name} API key deleted',
              snackPosition: SnackPosition.BOTTOM,
            );
          },
          style: TextButton.styleFrom(
            foregroundColor: Colors.red,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
          child: Text('Remove Key',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
        ),
      TextButton(
        onPressed: () => Get.back(closeOverlays: false),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
        child: Text('common_cancel'.tr,
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
      ),
    ],
  ));
}
