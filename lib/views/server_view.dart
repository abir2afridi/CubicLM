import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../controllers/server_controller.dart';
import '../core/colors.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/design_tokens.dart';
import 'settings_view.dart';

class ServerView extends GetView<ServerController> {
  const ServerView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = Dt.accent;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
      backgroundColor: isDark ? Dt.canvasDark : Dt.canvas,
      appBar: AppBar(
        backgroundColor: (isDark ? Dt.canvasDark : Dt.canvas).withValues(alpha: 0.8),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(color: Colors.transparent),
          ),
        ),
        title: Text('nav_nodes'.tr,
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 24, letterSpacing: -0.5)),
        bottom: TabBar(
          indicatorColor: accent,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: accent,
          unselectedLabelColor: Theme.of(context).hintColor,
          dividerColor: Colors.transparent,
          labelStyle: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w800, fontSize: 13),
          unselectedLabelStyle: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700, fontSize: 13),
          tabs: [
            Tab(text: 'nodes_node'.tr),
            Tab(text: 'nodes_config'.tr),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          Obx(() {
        final isRunning = controller.isRunning.value;
        final hasKey = controller.apiKey.value.trim().isNotEmpty;

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
          children: [
            // Status
            _groupedCard(isDark, children: [
              Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(children: [
                    _StatusIcon(isRunning: isRunning),
                    const SizedBox(width: 16),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(
                              isRunning
                                  ? 'nodes_compute_active'.tr
                                  : 'nodes_node_offline'.tr,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 16, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text(
                              isRunning
                                  ? controller.serverStatus.value
                                  : 'nodes_bridge_desc'.tr,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(context).hintColor)),
                        ])),
                    Switch(
                        value: isRunning,
                        onChanged: controller.isStarting.value
                            ? null
                            : (v) => controller.toggleServer(v)),
                  ])),
            ]),
            const SizedBox(height: 28),

            // Model Information
            _sectionLabel(context, 'nodes_current_payload'.tr),
            _groupedCard(isDark, children: [
              Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(children: [
                    Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                            color: (controller.hasLocalModel
                                    ? AppColors.success
                                    : AppColors.warning)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10)),
                        child: Icon(
                            controller.hasLocalModel
                                ? LucideIcons.shieldCheck
                                : LucideIcons.helpCircle,
                            size: 18,
                            color: controller.hasLocalModel
                                ? AppColors.success
                                : AppColors.warning)),
                    const SizedBox(width: 16),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(controller.modelName,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 15, fontWeight: FontWeight.w700,
                                  color: isDark ? Colors.white : Colors.black)),
                          const SizedBox(height: 2),
                          Text(
                              controller.hasLocalModel
                                  ? 'nodes_active_engine'.tr
                                  : 'nodes_requires_init'.tr,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).hintColor)),
                        ])),
                  ])),
            ]),
            const SizedBox(height: 28),

            // Security
            _sectionLabel(context, 'nodes_gateway_security'.tr),
            _groupedCard(isDark, children: [
              _switchTile(context, isDark,
                  title: 'nodes_encrypted_handshake'.tr,
                  subtitle: 'nodes_bearer_desc'.tr,
                  value: controller.useApiKey.value, onChanged: (v) {
                controller.useApiKey.value = v;
                controller.saveSettings();
              }),
              Divider(
                  height: 1,
                  indent: 20,
                  color: isDark ? AppColors.border : AppColors.borderLightMode),
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Expanded(
                        child: TextField(
                      controller: controller.apiKeyCtrl,
                      onChanged: (v) => controller.apiKey.value = v,
                      onSubmitted: (_) => controller.saveSettings(),
                      style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                          labelText: 'nodes_access_token'.tr, hintText: 'nodes_optional_key'.tr),
                    )),
                    const SizedBox(width: 8),
                    IconButton(
                        tooltip: 'nodes_rotate_key'.tr,
                        onPressed: controller.generateApiKey,
                        icon: const Icon(LucideIcons.refreshCw,
                            size: 22, color: accent)),
                    IconButton(
                        tooltip: 'nodes_copy'.tr,
                        onPressed: hasKey
                            ? () => controller.copyText(
                                controller.apiKey.value, 'API key')
                            : null,
                        icon: Icon(LucideIcons.copy,
                            size: 20, color: Theme.of(context).hintColor)),
                  ])),
            ]),
            const SizedBox(height: 24),

            if (isRunning) ...[
              _sectionLabel(context, 'nodes_active_endpoints'.tr),
              _groupedCard(isDark, children: [
                Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _urlRow(context, isDark, 'nodes_host'.tr,
                              controller.localUrl.value),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                              onPressed: controller.localUrl.value == null
                                  ? null
                                  : () =>
                                      _testHealth(controller.localUrl.value!),
                              icon: const Icon(LucideIcons.activity, size: 18),
                              label: Text('nodes_probe_connectivity'.tr),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.success,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                              )),
                        ])),
              ]),
              const SizedBox(height: 24),
              _sectionLabel(context, 'nodes_implementation_snippets'.tr),
              _groupedCard(isDark, children: [
                Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _codeBlock(context, isDark, 'nodes_model_list'.tr,
                              'curl ${controller.baseUrl}/v1/models${_authHeader()}'),
                          _codeBlock(context, isDark, 'nodes_completions'.tr,
                              'curl ${controller.baseUrl}/v1/chat/completions \\\n  -H "Content-Type: application/json"${_authHeader()} \\\n  -d \'{"model":"${controller.inference.loadedModelName.value}","messages":[{"role":"user","content":"Hello"}]}\''),
                          _codeBlock(context, isDark, 'nodes_sdk_python'.tr,
                              'from openai import OpenAI\n\nclient = OpenAI(\n    base_url="${controller.baseUrl}/v1",\n    api_key="${controller.useApiKey.value ? controller.apiKey.value : "not-needed"}"\n)\n\nresponse = client.chat.completions.create(\n    model="${controller.inference.loadedModelName.value}",\n    messages=[{"role": "user", "content": "Hello"}],\n)\nprint(response.choices[0].message.content)'),
                        ])),
              ]),
            ],

            if (controller.lastError.value != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.2))),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(LucideIcons.alertCircle,
                          color: AppColors.error, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(controller.lastError.value!,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13, color: AppColors.error, fontWeight: FontWeight.w600))),
                    ]),
              ),
            ],
          ],
        );
          }),
          const SettingsView(embedded: true),
        ],
      ),
      ),
    );
  }

  // ── Helpers ──

  Widget _groupedCard(bool isDark, {required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.02) : Dt.pillMuted.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _sectionLabel(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, bottom: 8, top: 12),
      child: Text(title,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: Theme.of(context).hintColor)),
    );
  }

  Widget _switchTile(BuildContext context, bool isDark,
      {required String title,
      required String subtitle,
      required bool value,
      required ValueChanged<bool> onChanged}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).hintColor),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ])),
        Switch(value: value, onChanged: onChanged),
      ]),
    );
  }

  Widget _urlRow(BuildContext context, bool isDark, String label, String? url) {
    return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          SizedBox(
              width: 54,
              child: Text(label,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, fontWeight: FontWeight.w700))),
          Expanded(
              child: SelectableText(url ?? 'nodes_detecting'.tr,
                  maxLines: 1,
                  style: GoogleFonts.firaCode(
                      fontSize: 12, fontWeight: FontWeight.w500, color: Theme.of(context).hintColor))),
          IconButton(
              tooltip: 'nodes_copy'.tr,
              onPressed: url == null
                  ? null
                  : () => controller.copyText(url, '$label URL'),
              icon: Icon(LucideIcons.copy,
                  size: 18, color: Theme.of(context).hintColor)),
        ]));
  }

  Widget _codeBlock(
      BuildContext context, bool isDark, String title, String code) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Dt.pillMuted,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isDark ? AppColors.border : AppColors.borderLightMode)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(title,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, fontWeight: FontWeight.w800, color: Dt.accent))),
          IconButton(
              tooltip: 'nodes_copy'.tr,
              onPressed: () => controller.copyText(code, title),
              icon: Icon(LucideIcons.copy,
                  size: 16, color: Theme.of(context).hintColor)),
        ]),
        const SizedBox(height: 8),
        SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(code,
                style: GoogleFonts.firaCode(
                    fontSize: 11, fontWeight: FontWeight.w500, color: isDark ? AppColors.textSecondary : Dt.textSecondary))),
      ]),
    );
  }

  String _authHeader() {
    if (controller.useApiKey.value && controller.apiKey.value.isNotEmpty) {
      return ' \\\n  -H "Authorization: Bearer ${controller.apiKey.value}"';
    }
    return '';
  }

  Future<void> _testHealth(String baseUrl) async {
    try {
      final r = await http
          .get(Uri.parse('${baseUrl.replaceAll(RegExp(r'/$'), '')}/health'))
          .timeout(const Duration(seconds: 8));
      Get.snackbar('Node Signal', 'Engine responded with status ${r.statusCode}',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColors.success,
        colorText: Colors.white);
    } catch (e) {
      Get.snackbar('Connection Refused', 'Probe failed: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColors.error,
        colorText: Colors.white);
    }
  }
}

class _StatusIcon extends StatefulWidget {
  final bool isRunning;
  const _StatusIcon({required this.isRunning});

  @override
  State<_StatusIcon> createState() => _StatusIconState();
}

class _StatusIconState extends State<_StatusIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _animation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.isRunning) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_StatusIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRunning && !oldWidget.isRunning) {
      _controller.repeat(reverse: true);
    } else if (!widget.isRunning && oldWidget.isRunning) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isRunning ? AppColors.success : Theme.of(context).hintColor;
    return Stack(
      alignment: Alignment.center,
      children: [
        if (widget.isRunning)
          ScaleTransition(
            scale: _animation,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.2),
              ),
            ),
          ),
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            widget.isRunning ? LucideIcons.server : Icons.dns_outlined,
            size: 24,
            color: color,
          ),
        ),
      ],
    );
  }
}
