import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../controllers/settings_controller.dart';
import '../controllers/home_controller.dart';
import '../core/colors.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/design_tokens.dart';
import '../core/constants.dart';
import '../services/mcp/mcp_registry_service.dart';
import '../services/mcp/mcp_config.dart';
import '../services/mcp/mcp_connection.dart';
import 'log_view.dart';
import 'settings/apple_widgets.dart';
import 'settings/device_card.dart';
import 'settings/model_params.dart';
import 'settings/skills_section.dart';

class SettingsView extends GetView<SettingsController> {
  /// When true, renders just the scrollable config sections without its
  /// own Scaffold — used inside the Nodes page's Config tab.
  final bool embedded;
  const SettingsView({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (embedded) return _configBody(context);
    return Scaffold(
      backgroundColor: isDark ? Dt.canvasDark : Dt.canvas,
      appBar: AppBar(
        backgroundColor:
            (isDark ? Dt.canvasDark : Dt.canvas).withValues(alpha: 0.8),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(color: Colors.transparent),
          ),
        ),
        title: Text('nodes_config'.tr,
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800, fontSize: 28, letterSpacing: -1)),
        toolbarHeight: 70,
        centerTitle: false,
      ),
      body: _configBody(context),
    );
  }

  Widget _configBody(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Obx(() => ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            const SizedBox(height: 16),
            sectionLabel(context, 'settings_section_diagnostics'.tr),
            appleGroupedCard(context, isDark, children: [
              appleListTile(
                context,
                isDark,
                leading: iconBox(AppColors.info, LucideIcons.terminal),
                title: 'settings_system_logs'.tr,
                subtitle: 'settings_system_logs_desc'.tr,
                trailing: const Icon(LucideIcons.chevronRight, size: 20),
                showDivider: false,
                onTap: () => Get.to(() => const LogView()),
              ),
            ]),
            const SizedBox(height: 28),
            sectionLabel(context, 'settings_section_hardware'.tr),
            buildDeviceCard(context, isDark),
            const SizedBox(height: 28),
            sectionLabel(context, 'settings_section_inference'.tr),
            appleGroupedCard(context, isDark, children: [
              appleListTile(
                context,
                isDark,
                leading: iconBox(AppColors.success, LucideIcons.zap),
                title: 'settings_local_privacy'.tr,
                subtitle: localSubtitle(),
                trailing: controller.inferenceMode.value == 'local'
                    ? const Icon(LucideIcons.check, size: 20, color: Dt.accent)
                    : null,
                showDivider: true,
                onTap: () => controller.setInferenceMode('local'),
              ),
              appleListTile(
                context,
                isDark,
                leading: iconBox(Dt.accent, LucideIcons.cloud),
                title: 'settings_cloud_assistant'.tr,
                subtitle: controller.cloudProvider.value.toUpperCase(),
                trailing: controller.inferenceMode.value == 'cloud'
                    ? const Icon(LucideIcons.check, size: 20, color: Dt.accent)
                    : null,
                showDivider: false,
                onTap: () => controller.setInferenceMode('cloud'),
              ),
            ]),
            const SizedBox(height: 28),
            sectionLabel(context, 'settings_section_system_prompt'.tr),
            appleGroupedCard(context, isDark, children: [
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('settings_prompt_desc'.tr,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).hintColor)),
                      const SizedBox(height: 12),
                      TextField(
                        controller: controller.globalSystemPromptController,
                        minLines: 3,
                        maxLines: 8,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 14, fontWeight: FontWeight.w500),
                        decoration: InputDecoration(
                          hintText: AppConstants.systemPrompt,
                          contentPadding: const EdgeInsets.all(16),
                          suffixIcon: IconButton(
                              icon: const Icon(LucideIcons.save, size: 22),
                              onPressed: () {
                                controller.setGlobalSystemPrompt(controller
                                    .globalSystemPromptController.text);
                                Get.snackbar('Saved',
                                    'System prompt updated successfully',
                                    snackPosition: SnackPosition.BOTTOM,
                                    backgroundColor: AppColors.success,
                                    colorText: Colors.white);
                              }),
                        ),
                        onSubmitted: (v) => controller.setGlobalSystemPrompt(v),
                      ),
                    ]),
              ),
            ]),
            const SizedBox(height: 28),
            sectionLabel(context, 'settings_section_skills'.tr),
            buildSkillsSection(context, isDark),
            const SizedBox(height: 28),
            sectionLabel(context, 'settings_section_mcp'.tr),
            const _McpSection(),
            const SizedBox(height: 28),
            sectionLabel(context, 'settings_section_local_params'.tr),
            buildLiteRtCard(context, isDark),
            const SizedBox(height: 12),
            buildModelParametersCard(context, isDark),
            const SizedBox(height: 28),
            sectionLabel(context, 'settings_section_image_params'.tr),
            buildImageGenerationCard(context, isDark),
            const SizedBox(height: 50),
          ],
        ));
  }
}

class _McpSection extends StatefulWidget {
  const _McpSection();

  @override
  State<_McpSection> createState() => _McpSectionState();
}

class _McpSectionState extends State<_McpSection> {
  McpRegistryService get _registry => Get.find<McpRegistryService>();

  /// Jump to Explore → MCP tab for full add/edit management.
  void _openManager() {
    try {
      Get.find<HomeController>().changeTab(1);
      Get.snackbar('MCP Servers', 'Open the MCP tab to add or edit servers.',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 3));
    } catch (_) {}
  }

  Future<void> _toggleEnable(
      BuildContext context, bool isDark, McpConfig cfg, bool v) async {
    if (!v) {
      await _registry.setEnabled(cfg.id, false);
      return;
    }
    await _registry.setEnabled(cfg.id, true);
    final mine = _registry.toolsFor(cfg.id);
    if (mine.isNotEmpty && context.mounted) {
      final ok = await _confirmEnableWithTools(context, isDark, mine);
      if (ok != true) await _registry.setEnabled(cfg.id, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Obx(() {
      final servers = _registry.configs.toList();
      final status = _registry.status.value;
      final tools = _registry.tools.toList();
      final error = _registry.lastError.value;

      return Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: isDark ? Dt.cardDark : Dt.card,
          border: Border.all(
              color:
                  isDark ? Colors.white.withValues(alpha: 0.07) : Dt.hairline),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Dt.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(LucideIcons.plug,
                          size: 18, color: Dt.accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('MCP Servers',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                            servers.isEmpty
                                ? 'Connect remote HTTP/SSE servers'
                                : '${servers.length} server${servers.length == 1 ? '' : 's'} · ${tools.length} tools',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: Theme.of(context).hintColor),
                          ),
                        ],
                      ),
                    ),
                    _statusDot(status),
                  ]),
                  const SizedBox(height: 14),
                  _statusBanner(status, error, tools, isDark),
                ],
              ),
            ),
            Divider(
                height: 1,
                indent: 20,
                endIndent: 20,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.06)),
            if (servers.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Text(
                  'No servers yet. Add one to give the model tools.',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, color: Theme.of(context).hintColor),
                ),
              ),
            for (final s in servers)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 12, 0),
                child: Row(children: [
                  _statusDot(_registry.statusOf(s.id)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.name.isEmpty ? 'MCP Server' : s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          s.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11, color: Theme.of(context).hintColor),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: s.enabled,
                    activeThumbColor: Dt.accent,
                    onChanged: (v) => _toggleEnable(context, isDark, s, v),
                  ),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openManager,
                  icon: const Icon(LucideIcons.settings2, size: 16),
                  label: Text(
                      servers.isEmpty ? 'Add MCP server' : 'Manage servers',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Dt.accent,
                    side: BorderSide(color: Dt.accent.withValues(alpha: 0.3)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            if (tools.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : Dt.pillMuted.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Exposed tools — model will see these',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).hintColor)),
                      const SizedBox(height: 8),
                      for (final t in tools.take(12))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: Dt.accent.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(LucideIcons.wrench,
                                    size: 14, color: Dt.accent),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(t.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                        ),
                      if (tools.length > 12)
                        Text('+${tools.length - 12} more',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                color: Theme.of(context).hintColor)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }

  Widget _statusDot(McpStatus s) {
    final color = switch (s) {
      McpStatus.connected => AppColors.success,
      McpStatus.connecting => AppColors.warning,
      McpStatus.error => AppColors.error,
      McpStatus.disconnected => Colors.grey,
    };
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: s == McpStatus.connected
            ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 6)]
            : null,
      ),
    );
  }

  Widget _statusBanner(
      McpStatus status, String error, List<McpTool> tools, bool isDark) {
    final text = switch (status) {
      McpStatus.connected => tools.isEmpty
          ? 'Connected — no tools exposed'
          : 'Connected — ${tools.length} tool(s) ready',
      McpStatus.connecting => 'Connecting…',
      McpStatus.error => error.isNotEmpty ? error : 'Connection error',
      McpStatus.disconnected => 'Not connected — save and test your server',
    };
    final color = switch (status) {
      McpStatus.connected => AppColors.success,
      McpStatus.connecting => AppColors.warning,
      McpStatus.error => AppColors.error,
      McpStatus.disconnected => Theme.of(Get.context!).hintColor,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(children: [
        Icon(
          switch (status) {
            McpStatus.connected => LucideIcons.checkCircle,
            McpStatus.connecting => LucideIcons.loader2,
            McpStatus.error => LucideIcons.alertTriangle,
            McpStatus.disconnected => LucideIcons.info,
          },
          size: 16,
          color: color,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ),
      ]),
    );
  }

  Future<bool?> _confirmEnableWithTools(
      BuildContext context, bool isDark, List<McpTool> tools) {
    return Get.dialog<bool>(
      AlertDialog(
        backgroundColor: isDark ? Dt.cardDark : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Enable MCP tools?',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'The model will be able to call these tools. Review them before enabling.',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: Theme.of(context).hintColor),
              ),
              const SizedBox(height: 12),
              for (final t in tools)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(LucideIcons.wrench,
                          size: 14, color: Dt.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.name,
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13, fontWeight: FontWeight.w700)),
                            if (t.description.isNotEmpty)
                              Text(t.description,
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      color: Theme.of(context).hintColor)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Get.back(result: false),
              child: Text('common_cancel'.tr)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Dt.accent),
            onPressed: () => Get.back(result: true),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
  }
}
