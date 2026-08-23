import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../controllers/server_controller.dart';
import '../core/colors.dart';

class ServerView extends GetView<ServerController> {
  const ServerView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = AppColors.primary;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bg : AppColors.bgLight,
      appBar: AppBar(
        backgroundColor: (isDark ? AppColors.bg : AppColors.bgLight).withValues(alpha: 0.8),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(color: Colors.transparent),
          ),
        ),
        title: Text('API Node',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 24, letterSpacing: -0.5)),
      ),
      body: Obx(() {
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
                                  ? 'Compute Active'
                                  : 'Node Offline',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 16, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text(
                              isRunning
                                  ? controller.serverStatus.value
                                  : 'Bridge local models to OpenAI-compatible clients.',
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
            _sectionLabel(context, 'CURRENT PAYLOAD'),
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
                                ? Icons.verified_user_rounded
                                : Icons.help_outline_rounded,
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
                                  ? 'Active weighting engine'
                                  : 'Requires model initialization',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).hintColor)),
                        ])),
                  ])),
            ]),
            const SizedBox(height: 28),

            // Security
            _sectionLabel(context, 'GATEWAY SECURITY'),
            _groupedCard(isDark, children: [
              _switchTile(context, isDark,
                  title: 'Encrypted Handshake',
                  subtitle: 'Requires Bearer Token authentication',
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
                      decoration: const InputDecoration(
                          labelText: 'Access Token', hintText: 'Optional secure key'),
                    )),
                    const SizedBox(width: 8),
                    IconButton(
                        tooltip: 'Rotate Key',
                        onPressed: controller.generateApiKey,
                        icon: const Icon(Icons.refresh_rounded,
                            size: 22, color: accent)),
                    IconButton(
                        tooltip: 'Copy',
                        onPressed: hasKey
                            ? () => controller.copyText(
                                controller.apiKey.value, 'API key')
                            : null,
                        icon: Icon(Icons.copy_rounded,
                            size: 20, color: Theme.of(context).hintColor)),
                  ])),
            ]),
            const SizedBox(height: 24),

            if (isRunning) ...[
              _sectionLabel(context, 'ACTIVE ENDPOINTS'),
              _groupedCard(isDark, children: [
                Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _urlRow(context, isDark, 'Host',
                              controller.localUrl.value),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                              onPressed: controller.localUrl.value == null
                                  ? null
                                  : () =>
                                      _testHealth(controller.localUrl.value!),
                              icon: const Icon(Icons.sensors_rounded, size: 18),
                              label: const Text('Probe Connectivity'),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.success,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                              )),
                        ])),
              ]),
              const SizedBox(height: 24),
              _sectionLabel(context, 'IMPLEMENTATION SNIPPETS'),
              _groupedCard(isDark, children: [
                Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _codeBlock(context, isDark, 'REST: Model List',
                              'curl ${controller.baseUrl}/v1/models${_authHeader()}'),
                          _codeBlock(context, isDark, 'REST: Completions',
                              'curl ${controller.baseUrl}/v1/chat/completions \\\n  -H "Content-Type: application/json"${_authHeader()} \\\n  -d \'{"model":"${controller.inference.loadedModelName.value}","messages":[{"role":"user","content":"Hello"}]}\''),
                          _codeBlock(context, isDark, 'SDK: OpenAI Python',
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
                      const Icon(Icons.error_rounded,
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
    );
  }

  // ── Helpers ──

  Widget _groupedCard(bool isDark, {required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.02) : const Color(0xFFF1F5F9).withValues(alpha: 0.5),
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
              child: SelectableText(url ?? 'Detecting node...',
                  maxLines: 1,
                  style: GoogleFonts.firaCode(
                      fontSize: 12, fontWeight: FontWeight.w500, color: Theme.of(context).hintColor))),
          IconButton(
              tooltip: 'Copy',
              onPressed: url == null
                  ? null
                  : () => controller.copyText(url, '$label URL'),
              icon: Icon(Icons.copy_rounded,
                  size: 18, color: Theme.of(context).hintColor)),
        ]));
  }

  Widget _codeBlock(
      BuildContext context, bool isDark, String title, String code) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: isDark ? AppColors.bg : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isDark ? AppColors.border : AppColors.borderLightMode)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(title,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primary))),
          IconButton(
              tooltip: 'Copy',
              onPressed: () => controller.copyText(code, title),
              icon: Icon(Icons.content_copy_rounded,
                  size: 16, color: Theme.of(context).hintColor)),
        ]),
        const SizedBox(height: 8),
        SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(code,
                style: GoogleFonts.firaCode(
                    fontSize: 11, fontWeight: FontWeight.w500, color: isDark ? AppColors.textSecondary : const Color(0xFF475569)))),
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
            widget.isRunning ? Icons.dns_rounded : Icons.dns_outlined,
            size: 24,
            color: color,
          ),
        ),
      ],
    );
  }
}
